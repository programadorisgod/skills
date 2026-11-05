# Skills — Full-Stack & Database Engineering Patterns

Repositorio centralizado de estándares de ingeniería, patrones arquitectónicos, optimizaciones de bases de datos de alto volumen (SQL Server / MSSQL), diseño de interfaces (UI) y experiencia de usuario (UX) para aplicaciones modernas y analíticas.

Este repositorio documenta lecciones reales aprendidas en entornos de producción de alta exigencia, estructuradas de forma modular y con ejemplos genéricos para su rápida adopción en nuevos proyectos.

---

## Estructura del Repositorio

```text
skills/
├── sql/                   # Base de datos, rendimiento del motor, concurrencia y optimizaciones
│   ├── README.md          # Guía general de SQL Server Performance
│   ├── scripts/           # Esquemas DDL reproducibles y semillas de prueba (TiendaDemo)
│   └── references/        # Documentos técnicos a bajo nivel (01 a 06)
├── ux/                    # Experiencia de usuario, patrones de interacción y reactividad
│   └── README.md          # Guía de patrones UX para dashboards y tablas complejas
└── ui/                    # Componentes visuales, diseño atómico y layout
    └── README.md          # Principios de diseño visual, densidad y estilos
```

---

## 1. 🗄️ SQL Engineering (`sql/`)

Optimización de motores relacionales Microsoft SQL Server (MSSQL), análisis de planes de ejecución y reducción drástica de tiempos de respuesta:

- **[01. Row Goal Trap y Hints](sql/references/01-row-goal-optimizer.md)**: Matriz de decisión para aplicar dinámicamente `USE HINT('DISABLE_OPTIMIZER_ROWGOAL')` ante filtros selectivos vs generales.
- **[02. Two-Stage Pagination](sql/references/02-two-stage-pagination.md)**: Desacople de consultas pesadas en dos fases (Selección Ligera de IDs + Enriquecimiento Tardío por PK).
- **[03. SARGabilidad e Indexación](sql/references/03-sargability-indexing.md)**: Búsquedas por prefijo B-Tree en < 5 ms vs Table Scans, rangos de fechas y mitigación de conversiones implícitas (`NVARCHAR` vs `VARCHAR`).
- **[04. Concurrencia y Deadlocks (1205)](sql/references/04-concurrency-deadlocks.md)**: Aislamiento con `WITH (NOLOCK)`, bloqueos atómicos preventivos con `WITH (UPDLOCK, HOLDLOCK)` y cancelación de queries huérfanas mediante paquetes TDS Attention.
- **[05. TempDB y Collation (468)](sql/references/05-tempdb-and-collation.md)**: Prevención de errores de intercalación entre bases de usuario y `tempdb` usando `COLLATE database_default`.
- **[06. Poda de Conteos y Short-Circuit](sql/references/06-count-pruning.md)**: Optimización de `SELECT COUNT(*)` mediante poda de CTEs analíticos (`buildFastCountSql`) y parámetro `skipCount`.

👉 *Incluye entorno reproducible con 100.000 filas sintéticas en [`sql/scripts/00-schema-and-seed.sql`](sql/scripts/00-schema-and-seed.sql).*

---

## 2. 🎨 User Experience Patterns (`ux/`)

Técnicas para interfaces analíticas ultra-fluidas y sin fricción:

- **Optimistic UI & Transiciones Inmediatas**: Actualización visual reactiva antes de esperar confirmación del servidor.
- **Paginación con Memoria de Conteo**: Prevención de re-consultas del total de registros (`skipCount`) cuando los filtros no cambian.
- **Prevención de Condiciones de Carrera (Race Conditions)**: Cancelación de peticiones previas con `AbortController` al alternar entre pestañas.
- **Micro-Animaciones Desbloqueadas**: Separación de capas CSS para apertura instantánea de paneles laterales y modales (sin bloqueo por renderizado de tablas masivas).

---

## 3. 📐 Interface Design (`ui/`)

Patrones de diseño visual orientados a densidad de datos y legibilidad:

- **Data Tables de Alta Densidad**: Tipografía monoespaciada para cifras monetarias, alineaciones contables y truncamiento inteligente de texto con tooltips.
- **Layouts con Sticky Headers y Scroll Virtualizado**: Navegación de grandes volúmenes de filas manteniendo cabeceras visibles.
- **Feedback de Estados**: Skeletons adaptativos en lugar de spinners invasivos, toasts no intrusivos y badges de estado con alto contraste accesible.

---

## Licencia

MIT License — Libre para uso personal, profesional y en equipos de ingeniería.
