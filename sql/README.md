# SQL Server High-Performance & Concurrency Handbook

Guía de ingeniería, patrones arquitectónicos y técnicas avanzadas de optimización de consultas en **Microsoft SQL Server (MSSQL)** para cargas de trabajo analíticas, dashboards web y transacciones concurrentes de alto volumen.

Este compendio reúne lecciones de bajo nivel aprendidas en producción, traduciendo diagnósticos de planes de ejecución reales a patrones de código directamente aplicables en tus proyectos.

---

## Índice de Referencias Técnicas

| Módulo | Tema Central | Problema de Motor Mitigado |
|---|---|---|
| [01. Row Goal Trap y Hints](./references/01-row-goal-optimizer.md) | `DISABLE_OPTIMIZER_ROWGOAL` | Paginación degradada por filtros selectivos o derivados |
| [02. Two-Stage Pagination](./references/02-two-stage-pagination.md) | Selección Ligera + Enriquecimiento Tardío | Consultas con múltiples CTEs analíticos y agregaciones costosas |
| [03. SARGabilidad e Indexación](./references/03-sargability-indexing.md) | `Index Range Seek` vs `Table Scan` | Búsquedas de texto, funciones en `WHERE` y conversiones de tipo |
| [04. Concurrencia y Deadlocks](./references/04-concurrency-deadlocks.md) | Error 1205, `UPDLOCK, HOLDLOCK`, Attention Signal | Deadlocks en procesos concurrentes y contención de buffers de red |
| [05. TempDB y Collation](./references/05-tempdb-and-collation.md) | Error 468, `COLLATE database_default` | Incompatibilidad de intercalación en `#tmp` y desbordes a disco |
| [06. Poda de Conteos (Count Pruning)](./references/06-count-pruning.md) | `buildFastCountSql`, `skipCount` | `SELECT COUNT(*)` masivos que saturan CPU al paginar en web |

---

## Entorno de Pruebas Reproducible

El repositorio incluye un script T-SQL completo en [`scripts/00-schema-and-seed.sql`](./scripts/00-schema-and-seed.sql) para crear una base de datos de pruebas (`TiendaDemo`) con 100.000 órdenes y relaciones maestras.

Puedes ejecutarlo en **SQL Server Management Studio (SSMS)** o **Azure Data Studio** para comparar métricas con `SET STATISTICS IO, TIME ON` y analizar los planes gráficos de ejecución (**Ctrl + M**).

---

## Checklist Rápido de Validación para Desarrolladores

Antes de desplegar una consulta a producción en SQL Server:

- [ ] **Paginación Web (`OFFSET ... FETCH NEXT`):**
  - ¿El filtro del `WHERE` descarta más del 90% del universo de datos? Si es así, evalúa `OPTION (MAXDOP 2, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'))` para evitar que el optimizador recorra millones de filas buscando 25 coincidencias.
  - Si el filtro es amplio (> 80% coincide), **NO** uses el hint; permite que el motor se detenga de forma anticipada.
- [ ] **Enriquecimiento de Filas (JOINs y Agregaciones):**
  - ¿La consulta une 5 o más tablas y calcula sumatorias para mostrar solo una página de 25 filas? Aplica la arquitectura **Two-Stage Pagination**: filtra y ordena solo los IDs clave en el Stage 1, y enriquece únicamente esas 25 filas en el Stage 2.
- [ ] **SARGabilidad:**
  - ¿Hay filtros `LIKE '%VALOR%'`? Asegura búsqueda por prefijo (`LIKE 'VALOR%'`) para aprovechar el árbol B-Tree del índice.
  - ¿Hay funciones sobre columnas indexadas (`CAST(Fecha AS DATE) = @f`)? Conviértelas a rangos de fechas sargables (`Fecha >= @f AND Fecha < @fSig`).
- [ ] **Aislamiento y Concurrencia:**
  - En dashboards de solo lectura, usa `WITH (NOLOCK)` para evitar bloqueos compartidos (`S`).
  - En asignaciones y actualización de inventario concurrente, utiliza `WITH (UPDLOCK, HOLDLOCK)` para forzar serialización atómica y evitar deadlocks (Error 1205).
- [ ] **Tablas Temporales (`#tmp`):**
  - En toda columna de texto (`VARCHAR`, `NVARCHAR`), declara explícitamente `COLLATE database_default` para evitar el Error 468 ante discrepancias con `tempdb`.
- [ ] **Cálculo de Totales (`COUNT`):**
  - Al consultar el total de registros para la paginación, retira todos los CTEs analíticos y JOINs que no modifiquen el número de filas (`Count Pruning`).
