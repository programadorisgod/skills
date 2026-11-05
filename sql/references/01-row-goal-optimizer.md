# 01. La Heurística y Trampa del Row Goal (`Optimizer Row Goal Trap`)

## 1. El Problema de Motor

Cuando una consulta incluye `OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY` o `TOP 25` combinado con una cláusula `ORDER BY` sobre un índice (por ejemplo, `FechaOrden DESC, NumeroOrden DESC`), el optimizador de costos de SQL Server activa una heurística interna denominada **Row Goal**.

El optimizador asume lo siguiente:
> *"Dado que solo se necesitan 25 filas y existe un índice ordenado por fecha, recorreré el índice de forma descendente. Asumo que encontraré rápidamente 25 filas que cumplan los predicados del WHERE, por lo que no requiero escanear toda la tabla ni ordenar en memoria (evito un Sort Operator)."*

### Cuándo se convierte en una Trampa de Rendimiento (Row Goal Trap):
Si los filtros del `WHERE` son **altamente selectivos o derivados** (por ejemplo: `EstadoOrden = 'EN_DISPUTA'` o `ClienteId IN (VIP_PLATINUM)` donde solo el 1% o 2% del universo histórico cumple la condición):
1. SQL Server lee miles o millones de páginas de datos descartando pedidos que no están en disputa.
2. Por cada fila candidata leída del índice de fechas, realiza un **Nested Loop** con **Key Lookup** hacia la tabla Clustered (`PK`).
3. **Resultado:** Millones de lecturas lógicas (`logical reads`), uso del 100% de CPU y tiempos de respuesta que escalan de 150 ms a más de **5.000 ms – 12.000 ms**.

---

## 2. El Remedio: `DISABLE_OPTIMIZER_ROWGOAL`

La directiva de consulta:
```sql
OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'))
```
Instruye al motor a deshabilitar la suposición del Row Goal. El optimizador calcula el plan estimando el costo sobre todo el universo filtrado: realiza un escaneo eficiente o un **Hash Match / Merge Join** con filtros de mapa de bits (**Bitmap Filters**), reúne las filas coincidentes y solo entonces aplica el ordenamiento y el corte de las 25 filas.

---

## 3. La Regla de Oro: Condicionamiento Dinámico (Cuándo SÍ y Cuándo NO)

Inyectar `DISABLE_OPTIMIZER_ROWGOAL` de forma indiscriminada en todas las consultas de la aplicación es un **grave error de arquitectura**.

### Matriz de Decisión:

| Escenario | Condición del `WHERE` | ¿Usar `DISABLE_OPTIMIZER_ROWGOAL`? | Comportamiento del Motor |
|---|---|:---:|---|
| **Filtro selectivo / derivado** (ej. pedidos en disputa, clientes morosos) | Descarta > 90% de las filas activas | **SÍ** | Evita el Row Goal Trap. Filtra primero mediante Hash Joins y luego recorta las 25 filas. |
| **Filtro general / amplio** (ej. todas las órdenes del mes, vista general) | El 80%–100% de las filas cumplen el criterio | **NO** | Permite al optimizador usar el índice ordenado y **detenerse inmediatamente** tras encontrar 25 filas (Early Exit). |

### Anti-Patrón (Hint Incondicional en Backend):
```typescript
// MAL: Forzar el hint en todas las consultas de paginación
const query = `
  SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden
  FROM dbo.Ordenes
  WHERE EstadoOrden IN ('PAGADA', 'PENDIENTE', 'EN_DISPUTA')
  ORDER BY FechaOrden DESC
  OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
  OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'));
`;
```
*Efecto secundario negativo:* En la pestaña de órdenes generales, el motor es forzado a leer las 100.000 órdenes completas, volcarlas a `tempdb` en un `Sort Operator` masivo y luego devolver las primeras 25. La consulta pasa de 80 ms a más de 1.800 ms.

### Patrón Correcto (Inyección Dinámica Condicionada):
```typescript
// BIEN: Solo inyectar el hint cuando existe un filtro selectivo aplicado
const isSelectiveFilter = Boolean(filters.estado && filters.estado === 'EN_DISPUTA');

const query = `
  SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden
  FROM dbo.Ordenes
  WHERE (${buildWhereClause(filters)})
  ORDER BY FechaOrden DESC
  OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
  ${isSelectiveFilter ? "OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'))" : "OPTION (MAXDOP 2)"};
`;
```

---

## 4. Script de Validación en SSMS (Ctrl + M)

Ejecuta el siguiente script en la base de datos `TiendaDemo` con el plan de ejecución gráfico activado:

```sql
SET STATISTICS IO, TIME ON;
USE TiendaDemo;

-- =========================================================================
-- PRUEBA 1: Filtro Selectivo (2% del universo: 'EN_DISPUTA')
-- =========================================================================

-- A. Con Row Goal activo (Plan ingenuo: sufre Row Goal Trap)
SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden, SaldoPendiente
FROM dbo.Ordenes WITH (NOLOCK)
WHERE EstadoOrden = 'EN_DISPUTA' AND SaldoPendiente > 0
ORDER BY FechaOrden DESC, NumeroOrden DESC
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
OPTION (MAXDOP 2);

-- B. Con Row Goal desactivado (Plan optimizado para selectividad)
SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden, SaldoPendiente
FROM dbo.Ordenes WITH (NOLOCK)
WHERE EstadoOrden = 'EN_DISPUTA' AND SaldoPendiente > 0
ORDER BY FechaOrden DESC, NumeroOrden DESC
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'));

-- =========================================================================
-- PRUEBA 2: Filtro Amplio (Vista general de órdenes recientes)
-- =========================================================================

-- A. Sin Hint: Permite salida anticipada (Early Exit en < 5 ms)
SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden, SaldoPendiente
FROM dbo.Ordenes WITH (NOLOCK)
ORDER BY FechaOrden DESC, NumeroOrden DESC
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
OPTION (MAXDOP 2);

-- B. Con Hint innecesario: Fuerza escaneo completo y ordenamiento en TempDB
SELECT OrdenId, NumeroOrden, FechaOrden, TotalOrden, SaldoPendiente
FROM dbo.Ordenes WITH (NOLOCK)
ORDER BY FechaOrden DESC, NumeroOrden DESC
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'));
```

### Qué observar en el Plan de Ejecución:
- **En la Prueba 1:** Observa en la consulta (A) cómo el operador de lectura lee decenas de miles de filas antes de encontrar 25. En la consulta (B), el operador realiza un `Index Seek` o un filtro directo con lecturas lógicas mínimas.
- **En la Prueba 2:** Compara el operador `Top` / `Stream Aggregate` de la consulta (A) con el operador `Sort` costoso (con advertencia de memory grant) de la consulta (B).
