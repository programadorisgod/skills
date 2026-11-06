# Skills — Full-Stack, Database & Cache Engineering Patterns

Repositorio centralizado de estándares de ingeniería, patrones arquitectónicos, optimizaciones de bases de datos de alto volumen (SQL Server / MSSQL), diseño de interfaces (UI), experiencia de usuario (UX) y arquitecturas de caché granular de alto rendimiento para aplicaciones modernas y analíticas.

Este repositorio documenta lecciones reales aprendidas en entornos de producción de alta exigencia, estructuradas de forma modular y con ejemplos genéricos para su rápida adopción en nuevos proyectos.

---

## Estructura del Repositorio

```text
skills/
├── sql/                           # Base de datos, rendimiento del motor, concurrencia y optimizaciones
│   ├── README.md                  # Guía general de SQL Server Performance
│   ├── scripts/                   # Esquemas DDL reproducibles y semillas de prueba (TiendaDemo)
│   └── references/                # Documentos técnicos a bajo nivel (01 a 06)
├── cache-architecture-patterns/   # Arquitectura de caché granular, estrategias intercambiables y bajo consumo RAM
│   ├── README.md                  # Visión general, benchmark (<2.8 MB para 10.000 filas) y patrones
│   └── references/                # Guías a bajo nivel (01 a 05: Estrategias, V8, Mutación In-Place, etc.)
├── ux/                            # Experiencia de usuario, patrones de interacción y reactividad
│   └── README.md                  # Guía de patrones UX para dashboards y tablas complejas
└── ui/                            # Componentes visuales, diseño atómico y layout
    └── README.md                  # Principios de diseño visual, densidad y estilos
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

## 2. ⚡ Cache Architecture Patterns (`cache-architecture-patterns/`)

Diseño e implementación de sistemas de almacenamiento en caché en memoria y distribuidos, optimizados para ultra-baja huella de RAM y latencia en microsegundos:

- **[01. Strategy Pattern & Interfaces](cache-architecture-patterns/references/01-strategy-pattern-interfaces.md)**: Contrato desacoplado `ICacheStrategy<T>` que permite alternar sin costo entre `MemoryCacheStrategy` y `RedisCacheStrategy`.
- **[02. Optimización de Memoria en V8](cache-architecture-patterns/references/02-v8-memory-optimization.md)**: Hidden Classes monomórficas, punteros *Smi*, *String Interning* y reducción de consumo (< 2.8 MB para 10.000 registros).
- **[03. Mutación Granular In-Place](cache-architecture-patterns/references/03-granular-inplace-mutation.md)**: Eliminación del refetch destructivo mediante `patch()`, sincronización bidireccional y patrón React 19 en render.
- **[04. Patrón Restored Owners](cache-architecture-patterns/references/04-restored-owners-pattern.md)**: Reversión atómica de marcas transitorias en SQL con `#tmp` indexada (~2 ms) preservando asignatarios originales sin refetch.
- **[05. TTL Escalonado y Reactividad Multi-Tenant](cache-architecture-patterns/references/05-tiered-ttl-and-reactivity.md)**: Clasificación de datos por grado de inmutabilidad (10h históricos vs 15m transaccionales), deduplicación de promesas e invalidación push por SSE.

---

## 3. 🎨 User Experience Patterns (`ux/`)

Técnicas y estándares de interacción para interfaces analíticas ultra-fluidas, reactivas y sin fricción:

- **[01. Paginación con Memoria de Conteo](ux/references/01-skipcount-pagination-shortcircuit.md)**: Reducción del 98% en latencia entre páginas mediante `skipCount=1`, memoria de total en cliente y poda de subconsultas analíticas (`buildFastCountSql`).
- **[02. Cancelación Reactiva y Race Conditions](ux/references/02-abortcontroller-race-conditions.md)**: Prevención de inconsistencias al alternar filtros con `AbortController`, guarda contra el flash de "No se encontraron registros", y emisión de paquetes TDS Attention en MSSQL.
- **[03. Arquitectura Two-Tier (Carga Progresiva)](ux/references/03-two-tier-progressive-loading.md)**: Desacople en Tier 1 (Resumen en 30ms para pintar métricas en frame 0) + Tier 2 (Detalle paginado), eliminando bloqueos de pantalla de 3 a 5 segundos.
- **[04. Paginación Keyset y Resiliencia F5](ux/references/04-keyset-pagination-virtualization.md)**: Búsqueda determinista por cursor $O(1)$ en índice B-Tree, soporte para virtualización de listas masivas y persistencia de posición en `sessionStorage` ante recargas accidentales.
- **[05. Mutaciones Optimistas en 0 ms](ux/references/05-optimistic-ui-rollback-patterns.md)**: Interfaz reactiva en 0 ms para reasignaciones y cambios de estado con rollback automático transparente y notificaciones toast ante errores de red.
- **[06. Búsqueda Reactiva Sargable y Multi-Tenant](ux/references/06-sargable-search-and-multitenant-session.md)**: Debounce adaptativo con disparo instantáneo por `Enter`, búsquedas por prefijo sargable (`LIKE @q + '%'`) en <5 ms y claves aisladas en `sessionStorage` por sucursal.
- **[07. Micro-Interacciones y Latencia Percibida](ux/references/07-micro-interactions-and-perceived-latency.md)**: Paneles laterales (drawers) deslizantes en GPU sin caída de frames (*jank = 0*), confirmaciones en línea compactas y la regla de los 1.5s para estados de éxito efímeros.

---

## 4. 📐 Interface & UX Engineering (`ui/`)

Patrones de diseño visual, estabilidad geométrica y renderizado fluido para dashboards analíticos y tablas de alta densidad:

- **[01. Estabilización Geométrica y Cero Layout Shift](ui/references/01-zero-layout-shift-geometry.md)**: Paridad de huella en skeletons (`rows={PAGE_SIZE}`), eliminación del tirón de 17px con `scrollbar-gutter: stable`, y estabilización de View Transitions (`object-fit: none`).
- **[02. Transiciones de Altura y Colapso Asimétrico](ui/references/02-fluid-height-and-asymmetric-collapse.md)**: Contenedor `SmoothHeight` con sincronización pre-paint (`useLayoutEffect`), compensación de bordes y el patrón de retención temporal de filas salientes (`data-exiting="true"`) para erradicar huecos blancos.
- **[03. SWR en Frontend y Umbral de Carga Diferida](ui/references/03-swr-ui-delayed-loading.md)**: Experiencia no destructiva conservando datos previos montados, regla de los 160ms de Nielsen Norman (`useDelayedLoading`) y barras de progreso continuas.
- **[04. Arquitectura de Modales y Ciclo de Salida](ui/references/04-modal-architecture-portals-lifecycle.md)**: Desacoplamiento del DOM con `createPortal` para cubrir sidebars fijos con `backdrop-filter: blur()`, ciclo de vida con `useModalAnimation` (220ms), tecla Escape y precarga predictiva en hover.
- **[05. Data Tables de Alta Densidad y NumberFlow](ui/references/05-high-density-data-tables-design.md)**: Encabezados sticky corporativos de alto contraste (`#005774`), alineación contable con `tabular-nums`, componente nativo `NumberFlow` en React 19 y contención de botones con CSS Grid Stacking.
- **[06. Micro-Animaciones y Tokens de Movimiento](ui/references/06-micro-animations-and-motion-tokens.md)**: Sistema canónico de movimiento, aceleración GPU (`translateZ(0)`), prevención del bloqueo por `animation: ... both`, segmented controls elásticos y rebote táctil (*spring pop*).

---

## Licencia

MIT License — Libre para uso personal, profesional y en equipos de ingeniería.
