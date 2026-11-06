# 07. Micro-Interacciones, Drawers en GPU y Latencia Percibida

> **Módulo:** UX Architecture & Interaction Patterns  
> **Tema:** Reducción de la latencia percibida, apertura de paneles laterales (drawers) sin caídas de frames (*jank = 0*), confirmaciones en línea y la regla de los 1.5 segundos para estados de éxito efímeros.

---

## 1. Latencia Real vs Latencia Percibida

La velocidad de una aplicación no se mide únicamente en los milisegundos que tarda la base de datos en devolver un paquete TCP, sino en **cómo experimenta el cerebro humano el flujo de interacción**:
- Una operación que tarda 200 ms pero bloquea la pantalla con un parpadeo se siente **lenta e inestable**.
- Una operación que tarda 350 ms pero responde con una micro-interacción instantánea, fluida y predecible se siente **rápida y agradable**.

---

## 2. Paneles Laterales (Drawers) sin Caída de Frames (*Jank = 0*)

### El Problema del Montaje Sincrónico Pesado:
Al abrir un panel lateral deslizante (*slide-over / drawer*) con información detallada, si el componente intenta montar en el mismo frame gráficos de resumen, 30 campos de formulario y una tabla de auditoría, el navegador debe calcular el layout y pintar todo simultáneamente.
**Resultado:** La animación de entrada se entrecorta, saltándose frames (*frame drops* de 60 FPS a 18 FPS) y luciendo tosca.

```mermaid
flowchart TD
    subgraph JankModel [Montaje Sincrónico Tradicional (Lag)]
        J1["Usuario pulsa 'Ver Detalle'"] --> J2["Montar Drawer + Gráficos + Tabla pesada en Frame 0"]
        J2 --> J3["CPU al 100% calculando DOM masivo"]
        J3 --> J4["Animación de deslizamiento se congela y salta (Jank)"]
    end

    subgraph SmoothModel [Arquitectura Desacoplada (60/120 FPS)]
        S1["Usuario pulsa 'Ver Detalle'"] --> S2["Apertura INMEDIATA del contenedor en GPU (transform: translateX)"]
        S2 --> S3["Mostrar Skeleton ligero mientras la cortina entra fluida a 60 FPS"]
        S3 --> S4["Micro-tick (100ms): Montar componentes pesados tras finalizar el movimiento"]
        S4 --> S5["Transición 100% suave sin saltos de fotogramas"]
    end
```

### Implementación del Desplazamiento Diferido:

```tsx
// src/components/ui/fluid-drawer.tsx
import React, { useState, useEffect } from "react";
import styles from "./drawer.module.css";

interface DrawerProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
}

export function FluidDrawer({ isOpen, onClose, children }: DrawerProps) {
  const [isReadyToRenderHeavyContent, setIsReady] = useState(false);

  useEffect(() => {
    if (isOpen) {
      // Aplazar el montaje pesado hasta que la animación de entrada esté avanzada
      const timer = setTimeout(() => {
        setIsReady(true);
      }, 120);
      return () => clearTimeout(timer);
    } else {
      setIsReady(false);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <aside
        className={styles.drawerPanel}
        onClick={(e) => e.stopPropagation()}
      >
        {isReadyToRenderHeavyContent ? (
          children
        ) : (
          <div className={styles.lightSkeleton}>
            <div className={styles.skeletonBar} style={{ width: "60%" }} />
            <div className={styles.skeletonBar} style={{ width: "90%" }} />
            <div className={styles.skeletonBox} />
          </div>
        )}
      </aside>
    </div>
  );
}
```

```css
/* styles/drawer.module.css */
.drawerPanel {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  max-width: 480px;
  background-color: #ffffff;
  box-shadow: -4px 0 20px rgba(0, 0, 0, 0.15);
  transform: translateX(100%);
  animation: drawerSlideIn 240ms cubic-bezier(0.16, 1, 0.3, 1) forwards;
  will-change: transform; /* Promovido a capa independiente de GPU */
  z-index: 1000;
}

@keyframes drawerSlideIn {
  from { transform: translateX(100%); }
  to { transform: translateX(0); }
}
```

---

## 3. Confirmaciones en Línea sin Saltos de Scroll

### La Molestia de los Modales Invasivos:
Para acciones reversibles o de impacto medio (como desmarcar un registro o deshacer una asignación), disparar un modal emergente que bloquea toda la pantalla interrumpe el ritmo del usuario.

### El Patrón de Confirmación en Línea (*Inline Action Stack*):
La confirmación ocurre dentro de la misma celda de la tabla, con un ancho fijo y animación horizontal suave que no altera el ancho de las demás columnas:

```tsx
// src/components/ui/inline-confirm-button.tsx
import React, { useState } from "react";
import styles from "./inline-confirm.module.css";

interface InlineConfirmProps {
  onConfirm: () => void;
  label?: string;
  confirmPrompt?: string;
}

export function InlineConfirmButton({
  onConfirm,
  label = "Deshacer",
  confirmPrompt = "¿Seguro?",
}: InlineConfirmProps) {
  const [isAsking, setIsAsking] = useState(false);

  if (!isAsking) {
    return (
      <button
        onClick={() => setIsAsking(true)}
        className={styles.triggerBtn}
      >
        {label}
      </button>
    );
  }

  return (
    <div className={styles.confirmBox}>
      <span className={styles.promptText}>{confirmPrompt}</span>
      <button
        onClick={() => {
          setIsAsking(false);
          onConfirm();
        }}
        className={styles.yesBtn}
      >
        Sí
      </button>
      <button
        onClick={() => setIsAsking(false)}
        className={styles.noBtn}
      >
        No
      </button>
    </div>
  );
}
```

```css
/* styles/inline-confirm.module.css */
.confirmBox {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  background-color: #fef2f2;
  border: 1px solid #fecaca;
  padding: 2px 6px;
  border-radius: 4px;
  animation: popIn 150ms cubic-bezier(0.34, 1.56, 0.64, 1);
}

.promptText {
  font-size: 0.6875rem;
  font-weight: 600;
  color: #991b1b;
}

.yesBtn {
  background-color: #dc2626;
  color: #ffffff;
  border: none;
  border-radius: 3px;
  font-size: 0.6875rem;
  font-weight: 600;
  padding: 1px 6px;
  cursor: pointer;
}

.noBtn {
  background: transparent;
  color: #64748b;
  border: none;
  font-size: 0.6875rem;
  padding: 1px 4px;
  cursor: pointer;
}

@keyframes popIn {
  from { opacity: 0; transform: scale(0.92); }
  to { opacity: 1; transform: scale(1); }
}
```

---

## 4. La Regla de los 1.5 Segundos para Estados de Éxito Efímeros

Cuando un usuario presiona un botón de acción como *"Descargar Excel"* o *"Guardar Cambios"*, la retroalimentación no debe exigir un nuevo clic en un botón de *"Aceptar"*.

### Ciclo de Tres Fases Automático:
1. **Fase 1: En progreso (0 a N ms):** Spinner sutil o texto *"Procesando..."*.
2. **Fase 2: Éxito efímero (1.5 segundos exactos):** El botón se ilumina suavemente en verde con un icono de verificación (`✓`) y el texto *"¡Completado!"*.
3. **Fase 3: Retorno neutral silencioso:** El botón vuelve a su estado original sin recargar la página.

```tsx
export function useEphemeralSuccess(durationMs = 1500) {
  const [isSuccess, setIsSuccess] = useState(false);

  const triggerSuccess = () => {
    setIsSuccess(true);
    setTimeout(() => {
      setIsSuccess(false);
    }, durationMs);
  };

  return { isSuccess, triggerSuccess };
}
```

---

## 5. Resumen de Directrices de Latencia Percibida

- [ ] ¿Los paneles laterales (*drawers*) usan `will-change: transform` y aplazan el renderizado de gráficos pesados durante la animación de entrada?
- [ ] ¿Las confirmaciones secundarias se resuelven en línea sin recurrir a modales invasivos de pantalla completa?
- [ ] ¿Los botones de acción exitosa regresan automáticamente a su estado neutral tras **1.5 segundos** de confirmación visual?
- [ ] ¿Los estados de carga táctiles responden en menos de **100 ms** para confirmar la recepción física del clic?
