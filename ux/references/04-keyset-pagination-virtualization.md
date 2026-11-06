# 04. Paginación Keyset (Cursor-Based), Virtualización y Resiliencia F5

> **Módulo:** UX Architecture & Interaction Patterns  
> **Tema:** Paginación de alto rendimiento basada en cursor determinista $O(1)$ frente al costo degradante de `OFFSET`, soporte para virtualización de listas masivas y persistencia de posición ante recargas F5 (*F5 reload resilience*).

---

## 1. El Costo Degradante de la Paginación con `OFFSET`

La paginación estándar con `OFFSET N ROWS FETCH NEXT 25 ROWS` sufre de una degradación matemática inevitable: **a mayor profundidad de página, más lenta es la consulta**.

```
Página 1:   OFFSET 0      -> El motor lee 25 filas. Tiempo: 10 ms
Página 100: OFFSET 2.500  -> El motor escanea y descarta 2.500 filas en disco. Tiempo: 120 ms
Página 500: OFFSET 12.500 -> El motor escanea y descarta 12.500 filas en disco. Tiempo: 850 ms
Página 2000: OFFSET 50.000 -> El motor escanea y descarta 50.000 filas en disco. Tiempo: 3.200 ms
```

### Síntoma UX:
El usuario percibe que la aplicación es rápida al principio, pero conforme navega hacia atrás o inspecciona históricos profundos, la interfaz comienza a congelarse y los tiempos de carga se multiplican exponencialmente.

---

## 2. La Solución: Paginación Keyset (Cursor-Based) en $O(1)$

En lugar de saltar filas por conteo relativo (`OFFSET`), la paginación keyset busca el siguiente bloque mediante una **clave compuesta determinista e indexada** (por ejemplo, `created_at` + `id`):

```sql
-- ⚡ Búsqueda directa por B-Tree Seek en O(1) constante (10 ms en cualquier página)
SELECT TOP 25 id, created_at, customer_name, total_amount
FROM Orders WITH (NOLOCK)
WHERE 
    -- Clave compuesta: fecha menor a la última vista O misma fecha con id menor
    (created_at < @lastCreatedAt)
    OR (created_at = @lastCreatedAt AND id < @lastId)
ORDER BY created_at DESC, id DESC;
```

```mermaid
flowchart TD
    subgraph OffsetModel [OFFSET Paginación O(N)]
        O1["Página 500: Leer 12.500 filas en disco"] --> O2["Descartar 12.475 filas"] --> O3["Retornar 25 filas (Lento: 850ms)"]
    end

    subgraph KeysetModel [Keyset Cursor O(1)]
        K1["Cursor: lastDate=2026-11-01, lastId=9402"] --> K2["Seek directo en Índice B-Tree"] --> K3["Retornar 25 filas inmediatamente (Rápido: 10ms)"]
    end
```

---

## 3. Implementación del Cursor Keyset en TypeScript / React

```tsx
// src/hooks/use-keyset-pagination.ts
import { useState, useCallback, useRef } from "react";

export interface KeysetCursor {
  lastDate: string;
  lastId: string;
}

export function useKeysetPagination<T extends { id: string; createdAt: string }>() {
  const [items, setItems] = useState<T[]>([]);
  const [nextCursor, setNextCursor] = useState<KeysetCursor | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [isLoading, setIsLoading] = useState(false);

  const fetchNextPage = useCallback(async () => {
    if (isLoading || !hasMore) return;
    setIsLoading(true);

    const query = new URLSearchParams({
      pageSize: "25",
      ...(nextCursor && {
        cursorDate: nextCursor.lastDate,
        cursorId: nextCursor.lastId,
      }),
    });

    try {
      const res = await fetch(`/api/orders/keyset?${query.toString()}`);
      const data = await res.json();

      setItems((prev) => [...prev, ...data.items]);
      setHasMore(data.hasMore);

      if (data.items.length > 0) {
        const lastItem = data.items[data.items.length - 1];
        setNextCursor({
          lastDate: lastItem.createdAt,
          lastId: lastItem.id,
        });
      } else {
        setNextCursor(null);
      }
    } finally {
      setIsLoading(false);
    }
  }, [isLoading, hasMore, nextCursor]);

  return { items, hasMore, isLoading, fetchNextPage };
}
```

---

## 4. Resiliencia ante Recargas F5 (*F5 Reload Resilience*)

### El Problema de la Pérdida de Posición:
Al trabajar en un panel denso, si el usuario navega hasta la página 8 o se desplaza por un scroll infinito y presiona accidentalmente **F5** (o recarga la pestaña), la aplicación tradicionalmente resetea el estado a la página 1. El usuario pierde su contexto de trabajo y debe buscar nuevamente su lugar.

### La Solución: Sincronización en `sessionStorage` y URL:

```tsx
// Guardar el cursor y los filtros activos en la sesión del navegador
export function persistNavigationState(cursor: KeysetCursor | null, filters: object) {
  if (typeof window === "undefined") return;
  const statePayload = {
    cursor,
    filters,
    timestamp: Date.now(),
  };
  sessionStorage.setItem("orders_nav_state", JSON.stringify(statePayload));
}

// Recuperar el cursor al montarse la pantalla tras un refresco F5
export function recoverNavigationState(): KeysetCursor | null {
  if (typeof window === "undefined") return null;
  const raw = sessionStorage.getItem("orders_nav_state");
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw);
    // Expirar la posición tras 30 minutos de inactividad
    if (Date.now() - parsed.timestamp > 30 * 60 * 1000) {
      sessionStorage.removeItem("orders_nav_state");
      return null;
    }
    return parsed.cursor;
  } catch {
    return null;
  }
}
```

Al inicializar el hook, se lee `recoverNavigationState()` para reconstruir el cursor y evitar reiniciar desde cero.

---

## 5. Tabla Comparativa: OFFSET vs Keyset

| Característica | Paginación con OFFSET | Paginación Keyset (Cursor) |
|---|---|---|
| **Complejidad Temporal** | $O(N)$ (Empeora con cada página) | **$O(1)$ Constante** en cualquier profundidad |
| **Resistencia a Inserciones** | Puede repetir u omitir filas si se inserta un registro arriba | **Determinista**: No repite filas gracias al cursor por ID |
| **Consumo de I/O en Motor** | Creciente (lee miles de páginas en disco) | Mínimo (seek directo por índice B-Tree) |
| **Ideal para** | Saltos directos arbitrarios (ej. "Ir a página 40") | **Scrolls infinitos, virtualización y navegación continua** |
