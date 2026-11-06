# Patrones de Experiencia de Usuario (UX) e Interacción de Alto Rendimiento

Este módulo compila estándares y patrones de interacción diseñados para eliminar la latencia percibida, garantizar la coherencia en interfaces reactivas y mantener una navegación ágil en dashboards empresariales y tableros con alto volumen de datos.

---

## Índice de Referencias Técnicas

| Referencia | Tema Clave | Cuándo consultarla |
|---|---|---|
| [01. Paginación con Memoria de Conteo (`skipCount`)](references/01-skipcount-pagination-shortcircuit.md) | Memoria de total en cliente, poda de subconsultas analíticas | Al detectar que cambiar de página tarda entre 500ms y 2s por culpa del `COUNT(*)` |
| [02. Cancelación Reactiva y Race Conditions](references/02-abortcontroller-race-conditions.md) | `AbortController`, guard contra flash de estado vacío, TDS Attention | Al cambiar rápidamente entre pestañas o filtros y evitar sobreescritura de datos viejos |
| [03. Arquitectura Two-Tier (Carga Progresiva)](references/03-two-tier-progressive-loading.md) | Resumen en 30ms + Detalle paginado desacoplado | Al diseñar tableros pesados para evitar congelar la pantalla durante 3 a 5 segundos |
| [04. Paginación Keyset y Resiliencia F5](references/04-keyset-pagination-virtualization.md) | Cursor determinista $O(1)$, virtualización y persistencia `sessionStorage` | Al navegar históricos profundos donde `OFFSET` se vuelve intolerable o al recargar la vista |
| [05. Mutaciones Optimistas en 0 ms](references/05-optimistic-ui-rollback-patterns.md) | Optimistic UI, snapshot previo, rollback atómico y reconcialización | Al realizar reasignaciones, cambios de estado o toggles con respuesta inmediata |
| [06. Búsqueda Reactiva Sargable y Multi-Tenant](references/06-sargable-search-and-multitenant-session.md) | Debounce adaptativo con `Enter`, prefijo B-Tree y claves aisladas | Al implementar búsquedas en vivo y evitar contaminación entre pestañas del navegador |
| [07. Micro-Interacciones y Latencia Percibida](references/07-micro-interactions-and-perceived-latency.md) | Drawers en GPU (60 FPS sin jank), confirmaciones en línea, regla 1.5s | Al abrir paneles laterales detallados sin tirones o confirmar acciones sin modales |

---

## Matriz Rápida de Diagnóstico de UX

| Síntoma en la Interfaz | Causa Raíz | Solución Recomendada |
|---|---|---|
| **Al paginar de la página 1 a la 2 tarda casi un segundo** | Re-ejecución innecesaria de `SELECT COUNT(*)` | Enviar `skipCount=1` y reusar el total en memoria ([Ref 01](references/01-skipcount-pagination-shortcircuit.md)) |
| **Al hacer clics rápidos entre pestañas, la pantalla muestra datos viejos** | Condición de carrera (*race condition* de respuestas lentas) | Cancelar petición previa con `AbortController` ([Ref 02](references/02-abortcontroller-race-conditions.md)) |
| **Aparece un cartel fugaz de "No se encontraron registros" al filtrar** | El manejador de `AbortError` apaga `isLoading` antes de tiempo | Ignorar silenciosamente cancelaciones en el bloque catch ([Ref 02](references/02-abortcontroller-race-conditions.md)) |
| **El dashboard tarda 4 segundos en mostrar cualquier elemento** | Consulta SQL monolítica que junta KPIs y 25 filas | Separar en Two-Tier: Resumen (30ms) y Detalle ([Ref 03](references/03-two-tier-progressive-loading.md)) |
| **La página 200 tarda 5 veces más en cargar que la página 1** | Escaneo secuencial en disco de `OFFSET 5000` | Cambiar a paginación Keyset por cursor $O(1)$ ([Ref 04](references/04-keyset-pagination-virtualization.md)) |
| **Al presionar F5, el usuario pierde su lugar en la tabla** | Estado volátil únicamente en memoria de React | Sincronizar cursor y filtros en `sessionStorage` ([Ref 04](references/04-keyset-pagination-virtualization.md)) |
| **Al reasignar un registro, la pantalla se congela esperando confirmación** | Enfoque pesimista que bloquea la UI | Aplicar mutación optimista en 0 ms con rollback ([Ref 05](references/05-optimistic-ui-rollback-patterns.md)) |
| **Al abrir un panel lateral detallado, la animación entra a tirones** | Montaje de gráficos y tablas pesadas en el frame 0 | Abrir en GPU y aplazar render pesado 100ms ([Ref 07](references/07-micro-interactions-and-perceived-latency.md)) |

---

## Checklist de Calidad para Experiencia de Usuario

- [ ] **Paginación Ágil**: ¿Los saltos de página con filtros idénticos omiten el cálculo de total con `skipCount`?
- [ ] **Cancelación Segura**: ¿Las peticiones anteriores son canceladas sin causar destellos de estado vacío en la UI?
- [ ] **Sensación de 0 ms**: ¿Las acciones cotidianas de reasignación y cambio de estado se reflejan de inmediato en la pantalla?
- [ ] **Resiliencia F5**: ¿El usuario puede refrescar el navegador y conservar su contexto de filtrado y navegación?
- [ ] **Movimiento Fluido**: ¿Los paneles laterales deslizantes entran a 60 FPS estables gracias a la aceleración por hardware y al renderizado diferido?
