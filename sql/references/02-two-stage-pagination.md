# 02. Arquitectura Two-Stage Pagination (Selección Ligera + Enriquecimiento Tardío)

## 1. El Problema de la Consulta Monolítica

En dashboards operativos y portales de comercio electrónico, la grilla de órdenes no solo muestra campos básicos, sino que requiere datos enriquecidos provenientes de múltiples tablas relacionadas:
- Nombre y categoría del cliente (`dbo.Clientes`).
- Sumatoria de ítems y total de productos (`dbo.DetalleOrden`).
- Sumatoria de pagos aplicados y último método de pago (`dbo.PagosOrden`).
- Estado del despacho y guía de transporte (`dbo.Envios`).

### El Anti-Patrón (JOIN Masivo Prematuro):
Unir todas estas tablas y calcular agregaciones (`SUM`, `COUNT`) sobre el universo completo de pedidos **antes** de paginar:

```sql
-- MAL: Realiza agregaciones costosas sobre 50.000 pedidos para luego descartar el 99.9%
WITH TOTAL_ITEMS AS (
    SELECT OrdenId, SUM(Cantidad) AS TotalArticulos, SUM(Subtotal) AS SubtotalCalculado
    FROM dbo.DetalleOrden WITH (NOLOCK)
    GROUP BY OrdenId
),
TOTAL_PAGOS AS (
    SELECT OrdenId, SUM(MontoPagado) AS TotalPagado
    FROM dbo.PagosOrden WITH (NOLOCK)
    WHERE EstadoPago = 'APROBADO'
    GROUP BY OrdenId
)
SELECT TOP 25 
    O.NumeroOrden,
    C.RazonSocial AS Cliente,
    O.FechaOrden,
    O.TotalOrden,
    TI.TotalArticulos,
    TP.TotalPagado,
    E.EstadoEnvio
FROM dbo.Ordenes O WITH (NOLOCK)
INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId
LEFT JOIN TOTAL_ITEMS TI ON TI.OrdenId = O.OrdenId
LEFT JOIN TOTAL_PAGOS TP ON TP.OrdenId = O.OrdenId
LEFT JOIN dbo.Envios E WITH (NOLOCK) ON E.OrdenId = O.OrdenId
WHERE O.EstadoOrden = 'PENDIENTE'
ORDER BY O.FechaOrden DESC;
```

### Síntoma en el Servidor:
- El motor calcula la suma de millones de líneas de detalle en `dbo.DetalleOrden` y pagos en `dbo.PagosOrden`.
- Consumo masivo de memoria (`Memory Grant`) para realizar Hash Matches previos al recorte `TOP 25`.
- La consulta tarda entre **2.500 ms y 4.500 ms**, bloqueando hilos de trabajo.

---

## 2. La Solución: Two-Stage Pagination

Desacoplar la consulta en **dos etapas independientes**:

```
[Cliente Web / Frontend]
        │
        ▼ (Petición: Página 1, 25 filas)
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Selección Ligera (50 ms – 180 ms)                 │
│ - Aplica filtros WHERE y ordenamiento.                     │
│ - SOLO consulta dbo.Ordenes (y JOINs esenciales de filtro). │
│ - Retorna únicamente los 25 IDs: [101, 102, ..., 125].     │
└─────────────────────────────────────────────────────────────┘
        │
        ▼ Array de 25 IDs
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: Enriquecimiento Tardío (15 ms – 30 ms)            │
│ - WHERE OrdenId IN (101, 102, ..., 125).                   │
│ - Une Detalle, Clientes, Pagos y Envíos SOLO para los 25.   │
│ - Clustered Index Seek directo por clave primaria.         │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
[Respuesta combinada: 25 registros en < 200 ms]
```

---

## 3. Implementación de los Dos Stages

### Stage 1: Consulta de Selección Ligera (Solo IDs)
```sql
SELECT O.OrdenId
FROM dbo.Ordenes O WITH (NOLOCK)
WHERE O.EstadoOrden = 'PENDIENTE'
ORDER BY O.FechaOrden DESC, O.NumeroOrden DESC
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
OPTION (MAXDOP 2);
```
*Tiempo de ejecución:* **40 ms**. El motor utiliza directamente el índice `IX_Ordenes_Estado_Saldo` sin tocar tablas secundarias.

### Stage 2: Enriquecimiento Tardío por PK
Con los 25 `OrdenId` obtenidos (`1001, 1002, ..., 1025`):

```sql
SELECT 
    O.OrdenId,
    O.NumeroOrden,
    C.RazonSocial AS Cliente,
    O.FechaOrden,
    O.TotalOrden,
    O.SaldoPendiente,
    ISNULL(TI.TotalArticulos, 0) AS TotalArticulos,
    ISNULL(TP.TotalPagado, 0) AS TotalPagado,
    E.EstadoEnvio,
    E.GuiaDespacho
FROM dbo.Ordenes O WITH (NOLOCK)
INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId
LEFT JOIN (
    SELECT OrdenId, SUM(Cantidad) AS TotalArticulos
    FROM dbo.DetalleOrden WITH (NOLOCK)
    WHERE OrdenId IN (1001, 1002, 1003, /* ... 25 IDs */)
    GROUP BY OrdenId
) TI ON TI.OrdenId = O.OrdenId
LEFT JOIN (
    SELECT OrdenId, SUM(MontoPagado) AS TotalPagado
    FROM dbo.PagosOrden WITH (NOLOCK)
    WHERE OrdenId IN (1001, 1002, 1003, /* ... 25 IDs */)
      AND EstadoPago = 'APROBADO'
    GROUP BY OrdenId
) TP ON TP.OrdenId = O.OrdenId
LEFT JOIN dbo.Envios E WITH (NOLOCK) ON E.OrdenId = O.OrdenId
WHERE O.OrdenId IN (1001, 1002, 1003, /* ... 25 IDs */)
ORDER BY O.FechaOrden DESC;
```
*Tiempo de ejecución:* **12 ms**. Solo se procesan los ítems y pagos de esas 25 órdenes.

---

## 4. Patrón en TypeScript / Node.js

```typescript
export async function getOrdersPaginated(filters: OrderFilters, page: number, pageSize: number) {
  // 1. Stage 1: Obtener únicamente los IDs de la página actual
  const stage1Sql = `
    SELECT OrdenId
    FROM dbo.Ordenes WITH (NOLOCK)
    WHERE (${buildWhereClause(filters)})
    ORDER BY FechaOrden DESC, NumeroOrden DESC
    OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
    OPTION (MAXDOP 2);
  `;
  
  const idRows = await db.query<{ OrdenId: number }>(stage1Sql, {
    offset: (page - 1) * pageSize,
    pageSize
  });

  if (idRows.length === 0) {
    return { data: [], total: 0 };
  }

  const orderIds = idRows.map(r => r.OrdenId);

  // 2. Stage 2: Enriquecer exactamente los 25 IDs por Clustered Index Seek
  const stage2Sql = `
    SELECT 
      O.OrdenId, O.NumeroOrden, C.RazonSocial AS Cliente,
      O.FechaOrden, O.TotalOrden,
      ISNULL(TI.TotalArticulos, 0) AS TotalArticulos,
      ISNULL(TP.TotalPagado, 0) AS TotalPagado
    FROM dbo.Ordenes O WITH (NOLOCK)
    INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId
    LEFT JOIN (
      SELECT OrdenId, SUM(Cantidad) AS TotalArticulos 
      FROM dbo.DetalleOrden WITH (NOLOCK)
      WHERE OrdenId IN (${orderIds.join(',')})
      GROUP BY OrdenId
    ) TI ON TI.OrdenId = O.OrdenId
    LEFT JOIN (
      SELECT OrdenId, SUM(MontoPagado) AS TotalPagado 
      FROM dbo.PagosOrden WITH (NOLOCK)
      WHERE OrdenId IN (${orderIds.join(',')}) AND EstadoPago = 'APROBADO'
      GROUP BY OrdenId
    ) TP ON TP.OrdenId = O.OrdenId
    WHERE O.OrdenId IN (${orderIds.join(',')})
    ORDER BY O.FechaOrden DESC;
  `;

  const enrichedData = await db.query(stage2Sql);
  return { data: enrichedData };
}
```

---

## 5. Script de Validación en SSMS (Ctrl + M)

```sql
SET STATISTICS IO, TIME ON;
USE TiendaDemo;

-- Simulación Monolítica vs Two-Stage:
-- Ejecuta ambas consultas y compara:
-- 1. Table 'DetalleOrden'. Scan count y logical reads.
-- 2. CPU time y Elapsed time en la pestaña Messages.
```
