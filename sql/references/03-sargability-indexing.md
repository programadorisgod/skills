# 03. SARGabilidad, Búsquedas B-Tree y Conversiones Implícitas

## 1. El Concepto de SARGabilidad (Search Argument Able)

Un predicado en la cláusula `WHERE` es **SARGable** cuando el optimizador de SQL Server puede utilizar un índice existente para aislar un rango de valores mediante un operador de búsqueda directo (**Index Seek**), en lugar de tener que leer e inspeccionar cada fila de la tabla (**Table Scan** o **Index Scan**).

---

## 2. Los Tres Anti-Patrones Más Comunes

### Anti-Patrón 1: Comodín Inicial en Búsquedas de Texto (`LIKE '%TERM%'`)

```sql
-- NO SARGABLE: Fuerza un Clustered Index Scan completo sobre 100.000 filas
SELECT OrdenId, NumeroOrden, TotalOrden
FROM dbo.Ordenes WITH (NOLOCK)
WHERE NumeroOrden LIKE '%202500050%';
```
* **Comportamiento del Motor:** Dado que la cadena puede comenzar con cualquier carácter, el motor no puede posicionarse en las ramas del árbol B-Tree del índice `IX_Ordenes_Fecha_Numero`. Debe leer todas las páginas de datos.
* **Tiempo medido:** **1.450 ms** (14.200 logical reads).

#### Patrón Correcto (Búsqueda por Prefijo):
```sql
-- SARGABLE: Realiza un Index Range Seek inmediato
SELECT OrdenId, NumeroOrden, TotalOrden
FROM dbo.Ordenes WITH (NOLOCK)
WHERE NumeroOrden LIKE 'ORD-202500050%';
```
* **Comportamiento del Motor:** El motor localiza la primera clave que comienza con `'ORD-202500050'` y recorre únicamente las hojas consecutivas hasta que el prefijo cambia.
* **Tiempo medido:** **1.8 ms** (4 logical reads, **800x más rápido**).

---

### Anti-Patrón 2: Funciones Escalares o `CAST` sobre Columnas en el `WHERE`

```sql
-- NO SARGABLE: Evalúa la función CAST en 100.000 filas, invalidando el índice de FechaOrden
SELECT OrdenId, NumeroOrden, TotalOrden
FROM dbo.Ordenes WITH (NOLOCK)
WHERE CAST(FechaOrden AS DATE) = '2026-11-05';

-- NO SARGABLE: Funciones de fecha
WHERE YEAR(FechaOrden) = 2026 AND MONTH(FechaOrden) = 11;
```

#### Patrón Correcto (Rango Abierto-Cerrado):
```sql
-- SARGABLE: Index Seek puro en el rango de tiempo
DECLARE @FechaInicio DATETIME2(0) = '2026-11-05 00:00:00';
DECLARE @FechaFin    DATETIME2(0) = '2026-11-06 00:00:00';

SELECT OrdenId, NumeroOrden, TotalOrden
FROM dbo.Ordenes WITH (NOLOCK)
WHERE FechaOrden >= @FechaInicio AND FechaOrden < @FechaFin;
```

---

### Anti-Patrón 3: Precedencia de Tipos de Datos y Conversión Implícita (`CONVERT_IMPLICIT`)

En SQL Server, cada tipo de dato tiene un nivel de precedencia rígido. El tipo `NVARCHAR` (Unicode) tiene **mayor precedencia** que `VARCHAR` (ANSI).

Si una columna en la tabla es `VARCHAR(30)` pero el parámetro enviado desde el driver (o Node.js / Tedious) es `NVARCHAR`:

```sql
-- El driver envía @sku como NVARCHAR(30) = N'SKU-TECH-001'
SELECT ProductoId, CodigoSKU, NombreProducto
FROM dbo.Productos WITH (NOLOCK)
WHERE CodigoSKU = @sku; 
-- El motor traduce internamente a: WHERE CONVERT_IMPLICIT(nvarchar(30), CodigoSKU) = @sku
```
* **Consecuencia:** Como la función de conversión se aplica sobre la columna indexada (`CodigoSKU`), el índice **deja de ser sargable**. El motor ejecuta un Scan completo con advertencia en el plan: `PlanAffectingConvert`.

#### Solución en Node.js / Backend:
Asegurarse de mapear el tipo de dato exacto en el driver:
```typescript
import sql from 'mssql';

// MAL: Por defecto, muchas librerías infieren NVarChar
request.input('sku', 'SKU-TECH-001'); // Envía NVARCHAR

// BIEN: Tipado explícito que coincide con el esquema VARCHAR
request.input('sku', sql.VarChar(30), 'SKU-TECH-001');
```

---

## 3. Script de Validación en SSMS (Ctrl + M)

```sql
SET STATISTICS IO, TIME ON;
USE TiendaDemo;

-- 1. Comparar Wildcard (%TERM%) vs Prefix (TERM%)
SELECT OrdenId, NumeroOrden FROM dbo.Ordenes WHERE NumeroOrden LIKE '%202500050%';
SELECT OrdenId, NumeroOrden FROM dbo.Ordenes WHERE NumeroOrden LIKE 'ORD-202500050%';

-- 2. Comparar Función en Columna vs Rango de Fechas
SELECT COUNT(*) FROM dbo.Ordenes WHERE CAST(FechaOrden AS DATE) = '2026-11-01';
SELECT COUNT(*) FROM dbo.Ordenes WHERE FechaOrden >= '2026-11-01' AND FechaOrden < '2026-11-02';
```
