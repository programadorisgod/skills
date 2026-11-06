# Patrones de Diseño de Interfaces (UI) y Experiencia de Usuario (UX)

Este módulo recopila principios de arquitectura de interfaz, interacción visual de alto rendimiento y patrones para tableros analíticos y sistemas con alta densidad de datos. Su propósito es erradicar defectos comunes como el *Cumulative Layout Shift* (CLS), parpadeos por loaders efímeros, colapsos de tablas y modales que no se integran de forma natural con layouts complejos.

---

## Índice de Referencias Técnicas

| Referencia | Tema Clave | Cuándo consultarla |
|---|---|---|
| [01. Estabilización Geométrica y Cero Layout Shift](references/01-zero-layout-shift-geometry.md) | Paridad de skeletons, `scrollbar-gutter: stable`, View Transitions | Al detectar brincos de altura o tirones horizontales al navegar entre páginas |
| [02. Transiciones de Altura y Colapso Asimétrico](references/02-fluid-height-and-asymmetric-collapse.md) | `SmoothHeight`, sincronización pre-paint, retención `data-exiting` | Al cambiar filtros o fechas donde el número de filas de la tabla varía drásticamente |
| [03. SWR en Frontend y Umbral de Carga Diferida](references/03-swr-ui-delayed-loading.md) | Patrón SWR, regla de los 160ms (`useDelayedLoading`), barras sutiles | Al eliminar fogonazos de spinners y parpadeos molestos en consultas rápidas |
| [04. Arquitectura de Modales y Ciclo de Salida](references/04-modal-architecture-portals-lifecycle.md) | `createPortal`, backdrop global desenfocado, `useModalAnimation` | Al crear diálogos que deben cubrir barras laterales fijas y cerrar con fluidez |
| [05. Data Tables de Alta Densidad y NumberFlow](references/05-high-density-data-tables-design.md) | Sticky contrast headers, números tabulares, stacking en CSS Grid | Al diseñar tablas contables masivas, cifras animadas continuas o botones sin CLS |

---

## Matriz Rápida de Diagnóstico

| Síntoma en la Interfaz | Causa Raíz | Solución Recomendada |
|---|---|---|
| **La página da un salto vertical de +800px tras cargar los datos** | Disparidad entre las filas del skeleton y la paginación real | Igualar `TableSkeleton rows={PAGE_SIZE}` ([Ref 01](references/01-zero-layout-shift-geometry.md)) |
| **La pantalla se desplaza 17px a la izquierda al cambiar de pestaña** | La barra de scroll nativa aparece/desaparece | Añadir `scrollbar-gutter: stable` en `html` ([Ref 01](references/01-zero-layout-shift-geometry.md)) |
| **Al filtrar pocos registros, la tabla deja un hueco blanco y parpadea** | Colapso asimétrico: el contenido cae en 0ms y el contenedor tarda 280ms | Retener filas salientes temporalmente con `data-exiting` ([Ref 02](references/02-fluid-height-and-asymmetric-collapse.md)) |
| **La tabla da un destello rápido cada vez que se hace clic en una fecha** | Se muestra un loader para una respuesta que tardó menos de 100ms | Aplicar `useDelayedLoading` con umbral de 160ms ([Ref 03](references/03-swr-ui-delayed-loading.md)) |
| **El fondo desenfocado del modal no cubre el menú lateral fijo** | El modal se renderiza dentro del contenedor `<main>` | Teletransportar a `document.body` mediante `createPortal` ([Ref 04](references/04-modal-architecture-portals-lifecycle.md)) |
| **Al presionar 'Cerrar', el modal desaparece de golpe sin animación** | Desmontaje inmediato de React (`isOpen = false`) | Separar el estado de desmontaje con `useModalAnimation` ([Ref 04](references/04-modal-architecture-portals-lifecycle.md)) |
| **Al presionar 'Exportar', los botones vecinos se mueven de lugar** | El texto "Generando..." ensancha el ancho del botón | Contener el botón con CSS Grid Stacking (`grid-area: stack`) ([Ref 05](references/05-high-density-data-tables-design.md)) |

---

## Checklist de Calidad para Interfaces de Alta Densidad

Antes de promover un componente visual o pantalla analítica a producción:

- [ ] **Geometría Predictiva**: ¿El estado de carga (`Skeleton`) ocupa la misma superficie que la vista con datos reales?
- [ ] **Scrollbar Inmóvil**: ¿El layout horizontal permanece fijo gracias a `scrollbar-gutter: stable`?
- [ ] **Cero Fogonazos**: ¿Las peticiones sub-160ms se resuelven de forma invisible sin mostrar spinners fugaces?
- [ ] **Tablas No Destructivas**: ¿Se mantiene montada la tabla previa con una barra superior sutil en lugar de destruirla en cada filtro?
- [ ] **Modales Globales**: ¿Los diálogos cubren el 100% del viewport (incluyendo sidebars fijos) y se desvanecen suavemente al pulsar Escape?
- [ ] **Números Alineados**: ¿Todas las cifras contables utilizan `font-variant-numeric: tabular-nums` para alinear comas y decimales?
