# 05. Tablas Temporales (`#tmp`), TempDB y Conflictos de Intercalación (Error 468)

## 1. El Problema de Motor: Conflicto de Intercalación (Error 468)

En entornos de producción con SQL Server, es habitual encontrarse con este error al cruzar tablas temporales con tablas físicas:

```text
Mens. 468, Nivel 16, Estado 9, Línea 24
No se puede resolver el conflicto de intercalación entre 'Modern_Spanish_CI_AS' y 'Latin1_General_CI_AS' de la operación equal to.
```

### Causa Raíz a Bajo Nivel:
1. Las bases de datos de la aplicación se crean con una intercalación específica (por ejemplo, `Modern_Spanish_CI_AS`).
2. La base de datos del sistema **`tempdb`** hereda automáticamente la intercalación de la instancia del servidor SQL Server (habitualmente `Latin1_General_CI_AS`).
3. Cuando un procedimiento o script crea una tabla temporal:
   ```sql
   -- MAL: Las columnas heredan la intercalación de tempdb (Latin1_General_CI_AS)
   CREATE TABLE #tmp_ordenes (
       NumeroOrden VARCHAR(30) NOT NULL
   );
   ```
4. Al cruzar la tabla `#tmp_ordenes` con la tabla física `dbo.Ordenes`:
   ```sql
   SELECT O.OrdenId, O.TotalOrden
   FROM dbo.Ordenes O
   INNER JOIN #tmp_ordenes tmp ON tmp.NumeroOrden = O.NumeroOrden;
   ```
   SQL Server evalúa la comparación entre dos expresiones de intercalación explícita con el mismo nivel de precedencia (**Coercibility Level 1**). Al no haber una regla que prevalezca, el compilador aborta inmediatamente con el **Error 468**.

---

## 2. La Solución Canónica: `COLLATE database_default`

En toda creación de tabla temporal (`#tmp`) o variable tipo tabla (`@tabla`), es **obligatorio** especificar la cláusula `COLLATE database_default` en todas las columnas de tipo texto (`VARCHAR`, `NVARCHAR`, `CHAR`):

```sql
-- BIEN: Fuerza a que las columnas de la tabla temporal adopten la intercalación de la BD actual
CREATE TABLE #tmp_ordenes (
    NumeroOrden VARCHAR(30) COLLATE database_default NOT NULL,
    EstadoOrden VARCHAR(20) COLLATE database_default NULL,
    CONSTRAINT PK_tmp_ordenes PRIMARY KEY CLUSTERED (NumeroOrden)
);
```

### ¿Por qué funciona?
`database_default` le indica a SQL Server que resuelva la intercalación contra la base de datos de usuario en la que se ejecuta la sesión activa, garantizando coincidencia total con las tablas del esquema.

---

## 3. Mejores Prácticas de Rendimiento con Tablas Temporales

### A. Clave Primaria Clustered en Tablas Temporales
Si la tabla temporal contendrá más de 100 registros que luego serán consultados mediante JOIN:
```sql
-- Siempre define PK Clustered en la creación para evitar un Table Scan en tempdb
CREATE TABLE #tmp_pedidos_seleccionados (
    OrdenId BIGINT NOT NULL,
    CONSTRAINT PK_tmp_pedidos PRIMARY KEY CLUSTERED (OrdenId)
);
```

### B. ¿Tabla Temporal (`#tmp`) o Variable de Tabla (`@tabla`)?
- **Variable de tabla (`@tabla`):** Solo recomendada para menos de 50–100 filas. SQL Server no mantiene estadísticas de distribución en variables tipo tabla (asume históricamente que tienen 1 fila), lo que puede generar planes de ejecución desastrosos en volúmenes mayores.
- **Tabla temporal (`#tmp`):** Recomendada para volúmenes medianos y grandes. Permite índices secundarios, genera estadísticas automáticas y participa en re-compilaciones inteligentes del optimizador.

---

## 4. Script de Validación en SSMS

```sql
SET STATISTICS IO, TIME ON;
USE TiendaDemo;

-- 1. Crear tabla temporal con collation seguro
CREATE TABLE #tmp_batch (
    NumeroOrden VARCHAR(30) COLLATE database_default NOT NULL PRIMARY KEY
);

INSERT INTO #tmp_batch (NumeroOrden)
VALUES ('ORD-2025000001'), ('ORD-2025000002'), ('ORD-2025000003');

-- 2. Ejecutar cruce sin riesgo de Error 468
SELECT O.OrdenId, O.NumeroOrden, O.TotalOrden, O.EstadoOrden
FROM dbo.Ordenes O WITH (NOLOCK)
INNER JOIN #tmp_batch b ON b.NumeroOrden = O.NumeroOrden;

-- 3. Limpieza
DROP TABLE #tmp_batch;
```
