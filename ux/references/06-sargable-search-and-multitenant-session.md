# 06. Búsqueda Reactiva Sargable y Aislamiento de Sesión Multi-Tenant

> **Módulo:** UX Architecture & Interaction Patterns  
> **Tema:** Búsqueda adaptativa con debounce y disparo instantáneo por teclado (`Enter`), indexación sargable en base de datos, y aislamiento estricto de contexto multi-tenant en `sessionStorage`.

---

## 1. El Dilema de la Búsqueda en Vivo: Saturación vs Lentitud

Al diseñar campos de búsqueda en vivo en tablas con miles de registros:
- **Sin debounce**: Cada pulsación de tecla (`k-e-y-s-t-r-o-k-e`) dispara una petición HTTP y una consulta en la base de datos, saturando el servidor con 10 consultas por segundo por usuario.
- **Con debounce estático muy alto (ej. 600 ms)**: El usuario termina de escribir, presiona `Enter` o se detiene a mirar, y la pantalla tarda más de medio segundo en reaccionar, provocando sensación de pesadez.

### La Solución: Debounce Adaptativo con Disparo Inmediato por `Enter`:
1. **Al escribir normalmente**: Espera **300 ms** tras la última pulsación antes de disparar la búsqueda.
2. **Al presionar `Enter`**: Omite inmediatamente el temporizador y ejecuta la consulta en **0 ms**.
3. **Reseteo Inteligente de Paginación**: Devuelve la vista a la Página 1 **únicamente si el término de búsqueda ha variado**, evitando que el usuario quede atrapado en una página inexistente.

---

## 2. Búsquedas Sargables en Base de Datos (`LIKE @term + '%'`)

El diseño de la experiencia de búsqueda en el frontend depende directamente de la eficiencia de la consulta SQL subyacente.

```sql
-- ❌ No Sargable: Forzado a Table Scan / Index Scan completo (Lento: 850 ms)
SELECT * FROM Customers WHERE document_number LIKE '%' + @searchTerm + '%';

-- ✅ Sargable por Prefijo: Aprovecha B-Tree Index Seek (Ultrarrápido: < 5 ms)
SELECT * FROM Customers WHERE document_number LIKE @searchTerm + '%';
```

Al formatear la consulta con un prefijo sargable, el motor relacional navega por el árbol binario del índice en microsegundos, permitiendo que la respuesta viaje al cliente en menos de **20 ms**.

---

## 3. Implementación del Hook de Búsqueda Adaptativa

```tsx
// src/hooks/use-adaptive-search.ts
import { useState, useEffect, useRef, useCallback } from "react";

interface UseAdaptiveSearchProps {
  onSearch: (term: string) => void;
  debounceMs?: number;
}

export function useAdaptiveSearch({
  onSearch,
  debounceMs = 300,
}: UseAdaptiveSearchProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const timerRef = useRef<NodeJS.Timeout | null>(null);
  const lastExecutedTermRef = useRef("");

  // Ejecutar búsqueda inmediata
  const executeSearchNow = useCallback(
    (term: string) => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
      }
      if (term !== lastExecutedTermRef.current) {
        lastExecutedTermRef.current = term;
        onSearch(term.trim());
      }
    },
    [onSearch]
  );

  // Manejador del cambio de texto con debounce
  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const nextValue = e.target.value;
    setSearchTerm(nextValue);

    if (timerRef.current) {
      clearTimeout(timerRef.current);
    }

    timerRef.current = setTimeout(() => {
      executeSearchNow(nextValue);
    }, debounceMs);
  };

  // Disparo instantáneo al presionar Enter
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      executeSearchNow(searchTerm);
    }
  };

  const handleClear = () => {
    setSearchTerm("");
    executeSearchNow("");
  };

  return {
    searchTerm,
    handleInputChange,
    handleKeyDown,
    handleClear,
  };
}
```

---

## 4. Aislamiento de Contexto Multi-Tenant en `sessionStorage`

En sistemas corporativos donde un mismo usuario opera múltiples sucursales, sedes o cuentas empresariales simultáneamente (abriendo pestañas diferentes del navegador para cada una), guardar los filtros en una clave global única como `dashboard_filters` produce **contaminación cruzada**: los filtros de la Sede A sobrescriben los de la Sede B.

```
❌ Clave global única:
Pestaña 1 (Sucursal Norte): Guarda filtros en 'filters' -> status='PENDING'
Pestaña 2 (Sucursal Sur):   Sobrescribe 'filters'       -> status='APPROVED'
Al regresar a Pestaña 1 y refrescar, Norte muestra datos de Sur. (CORRUPCIÓN DE CONTEXTO)
```

```
✅ Claves Particionadas por Tenant / Sucursal:
Pestaña 1: sessionStorage.setItem('tenant_NORTE_filters', ...)
Pestaña 2: sessionStorage.setItem('tenant_SUR_filters', ...)
Ambas pestañas coexisten de forma 100% aislada e independiente.
```

### Implementación del Almacenamiento Aislado:

```typescript
// src/lib/tenant-storage.ts

export function getTenantStorageKey(tenantId: string, resourceKey: string): string {
  // Clave compuesta blindada contra contaminación entre sedes
  return `app_${tenantId}_${resourceKey}`;
}

export function saveTenantState<T>(tenantId: string, resourceKey: string, data: T): void {
  if (typeof window === "undefined") return;
  const key = getTenantStorageKey(tenantId, resourceKey);
  sessionStorage.setItem(key, JSON.stringify(data));
}

export function loadTenantState<T>(tenantId: string, resourceKey: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  const key = getTenantStorageKey(tenantId, resourceKey);
  const raw = sessionStorage.getItem(key);
  if (!raw) return fallback;

  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}
```

---

## 5. Normalización de URLs sin Recargas Destructivas

Al resolver el contexto de la sucursal activa o limpiar parámetros de búsqueda obsoletos, no debe ejecutarse `window.location.href = ...` (que recarga todo el bundle JavaScript y destruye la memoria de la aplicación).
Se debe utilizar la API nativa del navegador:

```typescript
export function normalizeCleanUrl(cleanParams: Record<string, string>) {
  if (typeof window === "undefined") return;

  const url = new URL(window.location.href);
  url.search = ""; // Limpiar parámetros previos

  Object.entries(cleanParams).forEach(([k, v]) => {
    if (v) url.searchParams.set(k, v);
  });

  // Reemplazar la URL en el historial sin recargar la página ni perder el estado
  window.history.replaceState({}, "", url.toString());
}
```
