# TTL Escalonado por Volatilidad y Reactividad Multi-Tenant

## 1. El Concepto de TTL Escalonado (*Tiered TTL*)

No todos los datos de una aplicación cambian con la misma frecuencia ni tienen el mismo valor de frescura. Aplicar un TTL plano (por ejemplo, 5 minutos a todo) produce dos fallas graves:
- **Sub-aprovechamiento:** Consultas analíticas pesadas sobre datos históricos cerrados se recalculan innecesariamente.
- **Inconsistencia:** Datos operativos críticos muestran estados obsoletos a los usuarios.

La estrategia de **TTL Escalonado** clasifica los datos según su grado intrínseco de inmutabilidad:

| Nivel de Inmutabilidad | Tipo de Datos | Frecuencia de Cambio | TTL Recomendado | Estrategia de Invalidación |
|---|---|---|---|---|
| **Tier 1: Histórico / Consolidado** | Cierres contables, KPIs diarios pasados, auditorías archivadas | Inmutable una vez cerrado el día | **10 a 24 horas** | Desalojo natural por tiempo o recálculo explícito |
| **Tier 2: Semi-Estático** | Listados de usuarios, operadores, catálogos, configuraciones | Días o semanas | **1 a 4 horas** | Mutación in-place (`patch`) ante eventos del usuario |
| **Tier 3: Transaccional Activo** | Órdenes en tránsito, colas de trabajo activas, inventario | Minutos o segundos | **5 a 15 minutos** | Eventos en tiempo real (SSE / WebSockets) |

---

## 2. Aislamiento Estricto por Tenant en la Nomenclatura de Claves

En entornos multi-tenant o multi-sede, **nunca** se deben mezclar claves globales sin prefijo. Cada clave debe seguir un esquema jerárquico determinista:

```
[dominio]:[tenantId]:[entidad]:[parámetros_hasheados_o_normalizados]
```

### Ejemplos
- `kpi:tenant-alpha:historico:2026-11-05`
- `operadores:tenant-beta:activos`
- `ordenes:tenant-gamma:pagina:1:size:50`

Esto permite invalidar de forma selectiva todo un tenant sin tocar la memoria de los demás:

```typescript
export function invalidarTenant(cache: ICacheStrategy<any>, tenantId: string): void {
  const prefix = `:${tenantId}:`;
  // Si la estrategia implementa deletePrefix o patch
  if ('deletePrefix' in cache && typeof cache.deletePrefix === 'function') {
    cache.deletePrefix(prefix);
  }
}
```

---

## 3. Short-Circuit y Deduplicación de Peticiones en el Cliente

Un error común en el frontend es disparar múltiples peticiones idénticas si dos componentes en la misma pantalla solicitan los mismos datos al montarse.

### Patrón: Deduplicación de Promesas en Vuelo
Si una petición ya está en curso hacia el servidor, las llamadas subsiguientes deben suscribirse a la misma promesa sin disparar un segundo `fetch`:

```typescript
// cliente-cache-reactivo.ts
class ReactiveClientCache {
  private cache = new Map<string, { data: any; expiresAt: number }>();
  private inFlight = new Map<string, Promise<any>>();

  async fetchWithCache<T>(key: string, ttlMs: number, fetcher: () => Promise<T>): Promise<T> {
    // 1. Short-circuit: ¿Está en memoria y vigente?
    const cached = this.cache.get(key);
    if (cached && Date.now() < cached.expiresAt) {
      return cached.data as T;
    }

    // 2. Deduplicación: ¿Hay una petición idéntica en vuelo?
    if (this.inFlight.has(key)) {
      return this.inFlight.get(key) as Promise<T>;
    }

    // 3. Ejecutar y registrar la promesa activa
    const promise = (async () => {
      try {
        const data = await fetcher();
        this.cache.set(key, { data, expiresAt: Date.now() + ttlMs });
        return data;
      } finally {
        this.inFlight.delete(key);
      }
    })();

    this.inFlight.set(key, promise);
    return promise;
  }
}
```

---

## 4. Reactividad Push: Integración con Server-Sent Events (SSE)

Para datos transaccionales (Tier 3) o cuando ocurre un cierre diario mayor, el servidor puede emitir un evento liviano SSE notificando a los clientes que un tenant específico ha cambiado de versión:

```typescript
// En el backend (Publicador de eventos)
sseManager.broadcast('tenant_invalidated', {
  tenantId: 'tenant-alpha',
  module: 'kpi_diario',
  timestamp: Date.now(),
});
```

```typescript
// En el frontend (Hook de escucha)
useEffect(() => {
  const eventSource = new EventSource('/api/events');

  eventSource.addEventListener('tenant_invalidated', (event) => {
    const payload = JSON.parse(event.data);
    if (payload.tenantId === currentTenantId) {
      // Invalida solo la caché del módulo correspondiente
      clientCache.deletePrefix(`${payload.module}:${currentTenantId}`);
      // Actualiza la UI limpiamente
      triggerRefresh();
    }
  });

  return () => eventSource.close();
}, [currentTenantId]);
```

---

## 5. Caso de Estudio: Rendimiento con 10 Horas de TTL

En reportes diarios consolidados de seguimiento:
- **Sin TTL largo:** 120 usuarios consultando la pantalla durante el día generan ~4.800 ejecuciones de agregaciones complejas en la base de datos (con `GROUP BY`, `SUM`, cálculos de desviación estándar).
- **Con TTL de 10 Horas:**
  - 1ª consulta del día: 320 ms (cálculo en SQL y guardado en caché).
  - Siguientes 4.799 consultas: **< 1 ms** (servidas directo de memoria V8).
  - **Reducción de carga en el motor de base de datos:** **99.98%**.
  - **Uso de memoria adicional en el servidor:** menos de 150 KB para todo el día.
