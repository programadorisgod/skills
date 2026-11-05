# Patrones de Experiencia de Usuario (UX) para Aplicaciones Complejas

Este módulo compila estándares y patrones de interacción diseñados para eliminar la latencia percibida y mantener una navegación ágil en dashboards empresariales y tableros con alto volumen de datos.

---

## 1. Short-Circuit de Paginación (`skipCount`)

### El Problema:
Al paginar de la página 1 a la 2 dentro de la misma vista, el backend suele ejecutar dos consultas: los 25 registros y el `COUNT(*)` de toda la tabla. Como el conteo no varía entre páginas con los mismos filtros, se gasta entre 300 ms y 2.000 ms innecesarios en la base de datos.

### La Solución UX:
- El hook del frontend memoriza el `total` tras la primera búsqueda.
- Al cambiar de página, envía `skipCount=1` al servidor.
- La interfaz reutiliza el `total` previo en memoria y renderiza la nueva página en menos de 100 ms.

---

## 2. Cancelación Reactiva de Peticiones Previas (`AbortController`)

### El Problema:
Si un usuario hace clic rápidamente en la pestaña "Todas", luego en "Pendientes" y luego en "En Disputa", la petición más lenta (ej. "Todas") puede responder al final y sobreescribir la pantalla de "En Disputa".

### La Solución UX:
- Instanciar un `AbortController` al inicio de cada cambio de pestaña o filtro.
- Si existe una petición anterior en vuelo, llamar a `controller.abort()`.
- Propagar la señal al driver de base de datos para abortar la consulta en el motor y liberar la conexión de inmediato.

---

## 3. Micro-Animaciones Desbloqueadas en Paneles Laterales (Drawers)

### El Problema:
Al abrir un panel lateral detallado (slide-over / drawer), si el componente monta inmediatamente decenas de sub-componentes y gráficos pesados, la animación de entrada se entrecorta (jank / drop frames).

### La Solución UX:
- Abrir el contenedor del panel lateral instantáneamente en la capa de GPU (`transform: translateX()`).
- Aplazar el renderizado de gráficos y tablas pesadas mediante un micro-tick (`requestAnimationFrame` o `setTimeout(..., 100)`).
- Presentar skeletons de carga suaves mientras el contenido pesado finaliza su ciclo de montaje.
