# 06. Poda Dinámica de Conteos (`Count Pruning`) y Short-Circuit con `skipCount`

## 1. El Problema del Conteo en Dashboards Web

Para alimentar la barra de paginación de un portal web (`"Mostrando 1–25 de 48.210 órdenes"`), el backend necesita calcular el total de registros coincidentes.

### El Anti-Patrón (Conteo Espejo Monolítico):
Copiar la misma consulta de selección de datos y envolverla en un `SELECT COUNT(*)`:

```sql
-- MAL: Arrastra CTEs analíticos, detalles de productos y pagos solo para contar
WITH DETALLES AS (
    SELECT OrdenId, SUM(Cantidad) AS Items FROM dbo.DetalleOrden GROUP BY OrdenId
),
PAGOS AS (
    SELECT OrdenId, SUM(MontoPagado) AS Pagado FROM dbo.PagosOrden GROUP BY OrdenId
),
ULTIMO_ENVIO AS (
    SELECT OrdenId, ROW_NUMBER() OVER (PARTITION BY OrdenId ORDER BY EnvioId DESC) AS rn
    FROM dbo.Envios
)
SELECT COUNT(*) AS TotalCount
FROM dbo.Ordenes O
INNER JOIN dbo.Clientes C ON C.ClienteId = O.ClienteId
LEFT JOIN DETALLES D ON D.OrdenId = O.OrdenId
LEFT JOIN PAGOS P ON P.OrdenId = O.OrdenId
LEFT JOIN ULTIMO_ENVIO UE ON UE.OrdenId = O.OrdenId AND UE.rn = 1
WHERE O.EstadoOrden = 'PENDIENTE';
```
* **Consecuencia:** SQL Server computa la función de ventana `ROW_NUMBER()` sobre toda la tabla de envíos y agrega millones de detalles de órdenes, únicamente para descartar las columnas al final y contar filas.
* **Tiempo medido:** **2.800 ms – 3.900 ms**.

---

## 2. La Solución: Poda Dinámica de Conteos (`Count Pruning`)

Si el filtro del usuario **no depende** de los campos calculados en los CTEs o tablas secundarias:
**Ninguno de los CTEs ni tablas anexas es necesario para determinar la cantidad de filas.**

### Consulta Podada (`buildFastCountSql`):
```sql
-- BIEN: Poda todos los JOINs innecesarios. Cuenta directamente sobre la tabla maestra
SELECT COUNT_BIG(*) AS TotalCount
FROM dbo.Ordenes O WITH (NOLOCK)
WHERE O.EstadoOrden = 'PENDIENTE'
OPTION (MAXDOP 2);
```
* **Tiempo medido:** **35 ms** (**100x más rápido**). El motor realiza un conteo estrecho utilizando únicamente las páginas del índice de estado.

---

## 3. Patrón de Implementación en Backend

```typescript
export function buildCountQuery(filters: OrderFilters): string {
  // Si el filtro involucra búsqueda por nombre de cliente, conservamos solo ese JOIN
  const needsClienteJoin = Boolean(filters.nombreCliente);

  return `
    SELECT COUNT_BIG(1) AS total
    FROM dbo.Ordenes O WITH (NOLOCK)
    ${needsClienteJoin ? 'INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId' : ''}
    WHERE (${buildWhereClause(filters)})
    OPTION (MAXDOP 2);
  `;
}
```

---

## 4. Optimización Frontend: Short-Circuit con `skipCount`

Cuando un usuario navega entre las páginas de un listado (ej. pasa de la Página 1 a la Página 2, o a la Página 3) **sin modificar los filtros**:
- El total de registros ya fue calculado en la primera petición y se encuentra en la memoria del cliente.
- Recalcular `COUNT(*)` en cada cambio de página representa un desperdicio absoluto de CPU en la base de datos.

### Patrón de Short-Circuit en Frontend / Hook:
```typescript
// Si ya conocemos el total de la consulta previa y los filtros no cambiaron, omitimos el conteo
const skipCount = previousFiltersKey === currentFiltersKey && previousTotal > 0;

const response = await fetch(`/api/orders?page=${page}&skipCount=${skipCount ? 1 : 0}`);
const data = await response.json();

const totalRecords = skipCount ? previousTotal : data.total;
```

---

## 5. Script de Validación en SSMS (Ctrl + M)

```sql
SET STATISTICS IO, TIME ON;
USE TiendaDemo;

-- 1. Conteo Monolítico con JOINs innecesarios
SELECT COUNT(*) 
FROM dbo.Ordenes O WITH (NOLOCK)
INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId
LEFT JOIN dbo.DetalleOrden D WITH (NOLOCK) ON D.OrdenId = O.OrdenId
WHERE O.EstadoOrden = 'PENDIENTE';

-- 2. Conteo Podado (Count Pruned)
SELECT COUNT_BIG(1) 
FROM dbo.Ordenes O WITH (NOLOCK)
WHERE O.EstadoOrden = 'PENDIENTE'
OPTION (MAXDOP 2);
```
