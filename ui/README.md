# Patrones de Diseño de Interfaces (UI) para Dashboards Analíticos

Este módulo recopila principios de diseño visual, componentes atómicos y estructuras de layout orientadas a la visualización clara de información masiva.

---

## 1. Diseño de Data Tables de Alta Densidad

- **Tipografía Numérica Contable**: Uso de fuentes con números tabulares (`font-feature-settings: 'tnum'`, o familias como Inter / JetBrains Mono) para alinear decimales y cifras financieras de manera uniforme.
- **Alineación Semántica**:
  - Textos, códigos y nombres: alineados a la **izquierda**.
  - Fechas, estados y categorías: **centrados**.
  - Montos, saldos, porcentajes y cantidades: alineados a la **derecha**.
- **Truncamiento Inteligente**: Celdas con textos largos (ej. observaciones o nombres de cliente extensos) usan `truncate` con un tooltip informativo nativo (`title` o componente Radix UI) para no distorsionar el alto de las filas.

---

## 2. Sticky Headers y Scroll Virtualizado

- **Cabecera Fija (`position: sticky; top: 0; z-index: 10`)**: Permite que el usuario haga scroll hacia abajo en tablas largas sin perder de vista a qué columna corresponde cada valor.
- **Contraste de Separación**: Sombra sutil o borde inferior acentuado en la cabecera fija para delimitarla claramente del contenido que se desplaza por debajo.

---

## 3. Feedback Visual con Skeletons

- En lugar de spinners circulares centrales que ocultan toda la pantalla, utilizar **skeletons pulsantes** con la misma geometría de las filas y cards que se van a cargar.
- Reduce la fatiga visual y prepara al cerebro del usuario para la estructura de la información que aparecerá en pantalla.
