# Mutación Granular In-Place: Eliminando el Refetch Destructivo

## 1. El Problema del Refetch Global

En arquitecturas tradicionales de aplicaciones web (SPAs y SSR interactivo), el ciclo típico ante una actualización de estado es:

```
[Usuario cambia 1 registro]
       │
       ▼
[POST/PUT a la API] ──► [UPDATE en DB]
       │
       ▼
[Cliente llama a refetch()] ──► [SELECT de miles de registros]
                                      │
                                      ▼
                        [Serialización JSON pesada]
                        [Parpadeo en la UI / Layout Shift]
                        [Pérdida de scroll y foco del usuario]
```

### Por qué esto degrada el rendimiento
1. **Sobrecarga de Red y Base de Datos:** Para actualizar un valor booleano o un estado de una fila (ej. cambiar un usuario de `"ACTIVO"` a `"INACTIVO"`), se descargan megabytes de datos innecesarios.
2. **Degradación de UX:** El usuario experimenta un salto visual, barras de carga (*spinners*) y pérdida del cursor o selección activa.
3. **Invalidación Torpe de Caché:** Invalidar toda la clave de caché del tenant obliga a reconstruir datos que siguen siendo 99.9% idénticos.

---

## 2. El Método `patch()` en el Patrón de Estrategias

Para resolver esto en el servidor (backend), la interfaz de caché debe soportar mutación localizada:

```typescript
export interface ICacheStrategy<T> {
  get(key: string): Promise<T | null> | (T | null);
  set(key: string, value: T, ttlMs?: number): Promise<void> | void;
  delete(key: string): Promise<boolean> | boolean;
  clear(): Promise<void> | void;
  /**
   * Muta selectivamente las entradas que coincidan con un predicado
   * sin invalidar ni alterar las demás claves del almacenamiento.
   */
  patch?(predicate: (key: string) => boolean, updater: (value: T, key: string) => T): Promise<void> | void;
}
```

### Implementación en Memoria ($O(K)$ donde $K$ es el subconjunto evaluado)

```typescript
export class MemoryCacheStrategy<T> implements ICacheStrategy<T> {
  private readonly storage = new Map<string, { value: T; expiresAt: number }>();

  // ... métodos get, set, delete ...

  patch(predicate: (key: string) => boolean, updater: (value: T, key: string) => T): void {
    for (const [key, entry] of this.storage.entries()) {
      // Filtramos únicamente las claves del tenant o módulo afectado
      if (predicate(key)) {
        if (Date.now() <= entry.expiresAt) {
          const updatedValue = updater(entry.value, key);
          // Mutación directa preservando el tiempo de expiración
          entry.value = updatedValue;
        } else {
          // Desalojo perezoso de expirados
          this.storage.delete(key);
        }
      }
    }
  }
}
```

---

## 3. Ejemplo Concreto: Actualización de Estado de Operador en SaaS

Supongamos un módulo donde se gestionan los operadores de una plataforma de comercio y logística.

### 3.1 En el Servidor (Controlador / Servicio)
Al recibir la petición de cambio de estado:
1. Ejecuta el `UPDATE` en SQL en una transacción corta.
2. Parchea la entrada de caché del tenant correspondiente en memoria.
3. Devuelve al cliente una respuesta compacta con el registro mutado.

```typescript
// servicio-operadores.ts
export async function actualizarEstadoOperador(
  tenantId: string,
  operadorId: string,
  nuevoEstado: 'ACTIVO' | 'INACTIVO'
): Promise<OperadorResumen> {
  // 1. Persistencia transaccional en base de datos
  await db.query(
    `UPDATE OPERADORES SET estado = @estado WHERE tenant_id = @tenantId AND id = @operadorId`,
    { estado: nuevoEstado, tenantId, operadorId }
  );

  // 2. Parche granular in-place en la caché en memoria del servidor
  operadoresCacheStrategy.patch(
    (key) => key.startsWith(`operadores:${tenantId}:`),
    (listaOperadores) => {
      return listaOperadores.map((op) =>
        op.id === operadorId ? { ...op, estado: nuevoEstado } : op
      );
    }
  );

  return { id: operadorId, estado: nuevoEstado };
}
```

---

## 4. Mutación In-Place en el Cliente (Frontend)

En el frontend, el hook o almacén de datos no ejecuta `refetch()`. En su lugar, aplica la actualización directamente sobre las estructuras en memoria:

```typescript
// use-operadores.ts (React)
const cambiarEstado = useCallback(async (id: string, nuevoEstado: 'ACTIVO' | 'INACTIVO') => {
  // 1. Mutación optimista en el estado local de React
  setOperadores((prev) =>
    prev.map((op) => (op.id === id ? { ...op, estado: nuevoEstado } : op))
  );

  try {
    const res = await fetch(`/api/operadores/${id}/estado`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nuevoEstado }),
    });

    if (!res.ok) throw new Error('Error al actualizar estado');

    // 2. Muta la caché de páginas / filtros del cliente sin refetch
    operadoresPageCache.forEach((pagina, cacheKey) => {
      operadoresPageCache.set(
        cacheKey,
        pagina.map((op) => (op.id === id ? { ...op, estado: nuevoEstado } : op))
      );
    });
  } catch (error) {
    // Rollback en caso de falla
    setOperadores((prev) =>
      prev.map((op) => (op.id === id ? { ...op, estado: op.estado === 'ACTIVO' ? 'INACTIVO' : 'ACTIVO' } : op))
    );
  }
}, []);
```

---

## 5. Patrón React 19: Sincronización de Estado en Render

Un antipatrón muy extendido en React es usar `useEffect` para sincronizar el estado local cuando cambia una prop o dato de caché:

```typescript
// ❌ ANTIPATRÓN: Dispara re-renders redundantes y advertencias en React 19
useEffect(() => {
  setLocalState(props.initialData);
}, [props.initialData]);
```

### La Alternativa Idiomática en React 19
Sincronizar directamente durante la fase de render rastreando la versión de los datos recibidos:

```typescript
// ✅ IDIOMÁTICO REACT 19: Sin efectos secundarios, 0 re-renders en cascada
export function useOperadoresGranular(dataInicial: Operador[], keyCache: string) {
  const [operadores, setOperadores] = useState(dataInicial);
  const [prevKey, setPrevKey] = useState(keyCache);

  // Si la clave del tenant o dataset cambió, sincronizamos inmediatamente en render
  if (prevKey !== keyCache) {
    setPrevKey(keyCache);
    setOperadores(dataInicial);
  }

  return { operadores, setOperadores };
}
```

### Beneficios Obtenidos
- **0 milisegundos de latencia visual:** La UI responde de forma inmediata al clic del usuario.
- **Reducción del 98% en tráfico de red:** La respuesta de la API pasa de ~450 KB (listado completo) a ~120 bytes (confirmación JSON compacta).
- **Cero contención en DB:** SQL solo procesa un `UPDATE` puntual por clave primaria indexada.
