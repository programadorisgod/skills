# 05. Data Tables de Alta Densidad, NumberFlow y Micro-Animaciones Desbloqueadas

> **Módulo:** UI & UX Engineering Patterns  
> **Tema:** Estándares de diseño visual para visualización de datos masivos, alineación contable tabular, animación nativa de dígitos rodantes (`NumberFlow`) y contención de layout en botones con CSS Grid.

---

## 1. Fundamentos de Data Tables de Alta Densidad

En plataformas empresariales y analíticas que manejan miles de registros, la interfaz debe priorizar la **densidad de información, la legibilidad instantánea y el anclaje visual** sobre espacios en blanco excesivos.

```
┌────────────────────────────────────────────────────────────────────────┐
│ THEAD STICKY CORPORATIVO (Fondo Azul Marino Oscuro #005774, Texto Blanco)│
├───────────────┬───────────────────────────────┬────────────────────────┤
│ IDENTIFICADOR │ DESCRIPCIÓN                   │ MONTO TOTAL (USD)      │
│ (0.6875rem)   │ (Alineado a la Izquierda)     │ (tabular-nums, Derecha)│
├───────────────┼───────────────────────────────┼────────────────────────┤
│ TX-109283     │ Suscripción Plan Pro Mensual  │            $ 12,450.00 │
│ TX-109284     │ Renovación Licencia Anual     │             $ 3,200.50 │
├───────────────┼───────────────────────────────┼────────────────────────┤
│ TFOOT TOTALES │ 2 Transacciones               │            $ 15,650.50 │
└───────────────┴───────────────────────────────┴────────────────────────┘
```

### Reglas de Diseño Canónico:
1. **Encabezados Sticky de Alto Contraste:**
   - Fondo contrastado corporativo (ej. `#005774`), texto en mayúsculas pequeñas (`0.6875rem` / `11px`), `font-weight: 600`, `letter-spacing: 0.05em`.
   - Permite que el ojo humano mantenga el anclaje de columnas incluso al desplazarse verticalmente por cientos de filas.
2. **Tipografía Numérica Contable (`tabular-nums`):**
   - El uso de `font-feature-settings: "tnum"` o `font-variant-numeric: tabular-nums` asigna el mismo ancho a todos los dígitos (`0` a `9`).
   - Evita que los decimales y los separadores de miles bailen o se desalineen al comparar filas verticalmente.
3. **Alineación Semántica Estricta:**
   - **Izquierda:** Textos, identificadores alfanuméricos y descripciones.
   - **Centro:** Fechas, badges de estado y categorías cortas.
   - **Derecha:** Montos monetarios, porcentajes y conteos numéricos.

```css
/* styles/table-density.module.css */
.denseTable {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  font-size: 0.8125rem;
  color: #1e293b;
}

.denseTable th {
  position: sticky;
  top: 0;
  z-index: 10;
  background-color: #005774;
  color: #ffffff;
  font-size: 0.6875rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.65rem 0.85rem;
  border-bottom: 2px solid #00769e;
}

.numberCell {
  text-align: right;
  font-variant-numeric: tabular-nums;
  font-feature-settings: "tnum";
  font-weight: 500;
}

.denseTable tfoot td {
  background-color: #f8fafc;
  font-weight: 700;
  border-top: 2px solid #cbd5e1;
  padding: 0.75rem 0.85rem;
}
```

---

## 2. Componente Nativo: `NumberFlow` en React 19

Para animar cifras en tarjetas de KPIs, balances y contadores de armadores o analistas sin recurrir a bibliotecas pesadas de 50 KB, se implementa un componente nativo de dígitos rodantes verticales (*rolling spring digits*):

```tsx
// src/components/ui/number-flow.tsx
import React, { useId } from "react";
import styles from "./number-flow.module.css";

interface NumberFlowProps {
  value: number;
  prefix?: string;
  suffix?: string;
  formatFn?: (val: number) => string;
  className?: string;
}

const DIGITS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

function DigitColumn({ digit }: { digit: string }) {
  const num = parseInt(digit, 10);
  if (isNaN(num)) {
    return <span className={styles.symbol}>{digit}</span>;
  }

  // Desplazamiento vertical calculado: cada dígito ocupa el 10% de la columna
  const translateY = -(num * 10);

  return (
    <span className={styles.digitWindow}>
      <span
        className={styles.digitTrack}
        style={{ transform: `translateY(${translateY}%)` }}
      >
        {DIGITS.map((d) => (
          <span key={d} className={styles.digitItem}>
            {d}
          </span>
        ))}
      </span>
    </span>
  );
}

export function NumberFlow({
  value,
  prefix = "",
  suffix = "",
  formatFn,
  className = "",
}: NumberFlowProps) {
  const formattedText = formatFn ? formatFn(value) : value.toLocaleString("es-CO");
  const characters = formattedText.split("");

  return (
    <span className={`${styles.numberFlowContainer} ${className}`}>
      {prefix && <span className={styles.prefix}>{prefix}</span>}
      <span className={styles.digitsRow}>
        {characters.map((char, index) => (
          <DigitColumn key={`${index}-${char}`} digit={char} />
        ))}
      </span>
      {suffix && <span className={styles.suffix}>{suffix}</span>}
    </span>
  );
}
```

```css
/* styles/number-flow.module.css */
.numberFlowContainer {
  display: inline-flex;
  align-items: baseline;
  font-variant-numeric: tabular-nums;
  font-feature-settings: "tnum";
}

.digitsRow {
  display: inline-flex;
  overflow: hidden;
  height: 1.25em;
  line-height: 1.25em;
}

.digitWindow {
  position: relative;
  display: inline-block;
  height: 1.25em;
  overflow: hidden;
  vertical-align: top;
}

.digitTrack {
  display: flex;
  flex-direction: column;
  transition: transform 380ms cubic-bezier(0.16, 1, 0.3, 1);
  will-change: transform;
}

.digitItem {
  height: 1.25em;
  line-height: 1.25em;
  text-align: center;
}

.symbol {
  display: inline-block;
  padding: 0 1px;
}

/* Respeta usuarios con preferencias de movimiento reducido */
@media (prefers-reduced-motion: reduce) {
  .digitTrack {
    transition: none !important;
  }
}
```

---

## 3. Contención de Layout en Botones de Acción (CSS Grid Stacking)

### El Problema:
Al presionar un botón de "Exportar a Excel", el texto cambia a "Generando archivo...". Como las cadenas tienen diferentes longitudes, el botón ensancha bruscamente el menú de herramientas o la cabecera de la tabla, provocando un salto lateral de todos los botones vecinos (*layout shift*).

### La Solución: Apilamiento en la Misma Celda de CSS Grid
Ambos estados coexisten en la misma celda de grid (`grid-area: stack`). El botón adopta naturalmente el ancho del texto más largo y no se mueve ni 1 px durante la transición:

```tsx
// src/components/ui/export-action-button.tsx
import React from "react";
import styles from "./action-button.module.css";

interface ExportButtonProps {
  isLoading: boolean;
  onExport: () => void;
}

export function ExportActionButton({ isLoading, onExport }: ExportButtonProps) {
  return (
    <button
      onClick={onExport}
      disabled={isLoading}
      className={styles.button}
      aria-busy={isLoading}
    >
      <div className={styles.stackGrid}>
        {/* Estado Normal */}
        <span className={`${styles.layer} ${isLoading ? styles.hidden : styles.visible}`}>
          <svg className={styles.icon} viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          Exportar a Excel
        </span>

        {/* Estado Cargando */}
        <span className={`${styles.layer} ${isLoading ? styles.visible : styles.hidden}`}>
          <span className={styles.spinner} />
          Generando archivo...
        </span>
      </div>
    </button>
  );
}
```

```css
/* styles/action-button.module.css */
.button {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  background-color: #005774;
  color: #ffffff;
  font-weight: 500;
  border: none;
  cursor: pointer;
  transition: background-color 150ms ease;
}

.button:hover:not(:disabled) {
  background-color: #00465d;
}

.stackGrid {
  display: grid;
  grid-template-areas: "stack";
  place-items: center;
}

.layer {
  grid-area: stack;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: opacity 160ms ease, transform 160ms ease;
}

.visible {
  opacity: 1;
  transform: translateY(0);
}

.hidden {
  opacity: 0;
  transform: translateY(4px);
  pointer-events: none;
}

.spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #ffffff;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
```

---

## 4. Desbloqueo de Micro-Animaciones en Tarjetas Interactivas

### La Trampa del `animation: ... both`:
Al declarar `@keyframes cardEntrance { ... }` con la directiva `both` (que aplica `forwards` y `backwards` en la cascada CSS), la regla de animación se sitúa en una capa de prioridad que **bloquea las transiciones CSS de `:hover`, `:active` y `:focus`** en el componente.

```css
/* ❌ Bloquea transiciones interactivas posteriores */
.metricCard {
  animation: cardEntrance 300ms ease both;
  transition: transform 150ms ease, box-shadow 150ms ease;
}
.metricCard:hover {
  transform: translateY(-2px); /* <- IGNORADO por culpa del 'both' de la animación */
}

/* ✅ Desbloqueado y fluido */
.metricCard {
  animation: cardFadeIn 200ms ease-out forwards;
  transition: transform 150ms cubic-bezier(0.4, 0, 0.2, 1), box-shadow 150ms cubic-bezier(0.4, 0, 0.2, 1);
}
.metricCard:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}
```
