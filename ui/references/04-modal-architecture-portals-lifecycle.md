# 04. Arquitectura de Modales: Portals, Backdrop Global y Ciclo de Salida

> **Módulo:** UI & UX Engineering Patterns  
> **Tema:** Desacoplamiento del DOM con React Portals, desenfoque sobre barras laterales fijas, ciclo de vida de animación de salida (`useModalAnimation`) y precarga en hover.

---

## 1. Problemas Frecuentes en la Implementación de Diálogos Modales

Al construir modales en paneles de administración o dashboards analíticos con menús laterales (*sidebars*), suelen presentarse 3 fallas críticas de diseño e ingeniería:

```
❌ Fallas comunes en modales tradicionales:
1. El backdrop NO cubre el sidebar fijo (queda atrapado en el <main> con z-index inferior).
2. Al cerrar el modal, este desaparece instantáneamente en 0 ms sin reproducir la animación de salida.
3. El usuario debe esperar 300 ms con un spinner después de hacer clic en "Ver Detalle".
4. Tablas interiores desbordan horizontalmente en monitores estándar (1366x768 o 1080p escalado).
```

```
✅ Arquitectura Moderna con Portales y Ciclo de Vida:
┌────────────────────────────────────────────────────────┐
│ document.body (createPortal)                           │
│ ┌────────────────────────────────────────────────────┐ │
│ │ Backdrop desenfocado 100% viewport                 │ │
│ │ (cubre sidebar fijo, cabecera y contenido principal) │
│ │                     ┌───────────────┐              │ │
│ │                     │ Modal Centrado│              │ │
│ │                     │ (Scale/Fade)  │              │ │
│ │                     └───────────────┘              │ │
│ └────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

---

## 2. Teleportación al Raíz con React Portals

Para evitar que un modal herede restricciones de su componente padre (`overflow: hidden`, `contain: paint` o contextos de apilamiento `transform`), el diálogo debe teletransportarse a la raíz del documento:

```tsx
// src/components/ui/modal-portal.tsx
import React, { useSyncExternalStore } from "react";
import { createPortal } from "react-dom";

// Guarda de hidratación segura para Server-Side Rendering (SSR)
const emptySubscribe = () => () => {};
function useIsClient() {
  return useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false
  );
}

interface ModalPortalProps {
  children: React.ReactNode;
}

export function ModalPortal({ children }: ModalPortalProps) {
  const isClient = useIsClient();
  if (!isClient) return null;

  return createPortal(children, document.body);
}
```

---

## 3. El Dilema del Desmontaje en React y el Hook `useModalAnimation`

En React, el renderizado condicional clásico `{isOpen && <Modal />}` tiene un defecto insalvable: en cuanto `isOpen` pasa a `false`, **React desmonta el nodo del DOM en el mismo frame**. Como consecuencia, cualquier clase CSS o `@keyframes` de salida (`scaleOut`, `fadeOut`) se anula y el modal se esfuma bruscamente.

### El Ciclo de Vida en Tres Estados:
1. **Montado y Abierto (`isOpen = true`):** El modal se inserta en el DOM con `@keyframes modalEnter`.
2. **Cierre en Transición (`isClosing = true`):** Al presionar `Esc`, hacer clic en el backdrop o pulsar la `✕`, se activan las clases de salida (`@keyframes modalExit`) durante **220 ms**.
3. **Desmontaje Limpio (`isMounted = false`):** Una vez concluido el temporizador de 220 ms, se desmonta el componente del DOM sin cortes perceptibles.

```tsx
// src/hooks/use-modal-animation.ts
import { useState, useEffect, useCallback } from "react";

interface UseModalAnimationOptions {
  isOpen: boolean;
  durationMs?: number;
  onClose: () => void;
}

export function useModalAnimation({
  isOpen,
  durationMs = 220,
  onClose,
}: UseModalAnimationOptions) {
  const [isMounted, setIsMounted] = useState(isOpen);
  const [isClosing, setIsClosing] = useState(false);

  // Sincronizar apertura
  useEffect(() => {
    if (isOpen) {
      setIsMounted(true);
      setIsClosing(false);
    } else if (isMounted && !isClosing) {
      setIsClosing(true);
      const timer = setTimeout(() => {
        setIsMounted(false);
        setIsClosing(false);
      }, durationMs);
      return () => clearTimeout(timer);
    }
  }, [isOpen, isMounted, isClosing, durationMs]);

  // Cierre ordenado disparando la animación de salida
  const triggerClose = useCallback(() => {
    if (isClosing) return;
    setIsClosing(true);
    setTimeout(() => {
      setIsMounted(false);
      setIsClosing(false);
      onClose();
    }, durationMs);
  }, [isClosing, durationMs, onClose]);

  // Soporte de tecla Escape
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        triggerClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, triggerClose]);

  return { isMounted, isClosing, triggerClose };
}
```

---

## 4. Estilos y Keyframes Desacoplados

Para garantizar que el desenfoque cubra todos los elementos de la interfaz sin colisionar con variables globales:

```css
/* styles/modal.module.css */
.overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: flex;
  align-items: center;
  justify-content: center;
  background-color: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
  padding: 1.5rem;
  animation: overlayFadeIn 220ms cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

.overlayClosing {
  animation: overlayFadeOut 220ms cubic-bezier(0.4, 0, 1, 1) forwards;
}

.content {
  position: relative;
  background: #ffffff;
  border-radius: 12px;
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
  width: 100%;
  max-width: 860px;
  max-height: 85vh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  animation: contentScaleIn 220ms cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

.contentClosing {
  animation: contentScaleOut 220ms cubic-bezier(0.4, 0, 1, 1) forwards;
}

@keyframes overlayFadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes overlayFadeOut {
  from { opacity: 1; }
  to { opacity: 0; }
}

@keyframes contentScaleIn {
  from { opacity: 0; transform: scale(0.96) translateY(8px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}

@keyframes contentScaleOut {
  from { opacity: 1; transform: scale(1) translateY(0); }
  to { opacity: 0; transform: scale(0.96) translateY(8px); }
}
```

---

## 5. Precarga Predictiva en Hover (Latencia Percibida a 0 ms)

El tiempo que transcurre entre que el cursor del usuario se posiciona sobre el botón (`mouseenter` / `focus`) y el momento físico en que presiona el ratón (`click`) es de aproximadamente **150 ms a 250 ms**.

Aprovechar esta ventana biológica permite solicitar los datos del diálogo por anticipado:

```tsx
export function AuditHistoryTriggerButton({ recordId }: { recordId: string }) {
  const [isOpen, setIsOpen] = useState(false);

  // Iniciar la consulta HTTP en el hover
  const handlePreload = () => {
    prefetchAuditDetails(recordId);
  };

  return (
    <>
      <button
        onClick={() => setIsOpen(true)}
        onMouseEnter={handlePreload}
        onFocus={handlePreload}
        className={styles.triggerButton}
      >
        Ver Historial
      </button>

      {isOpen && (
        <AuditHistoryModal
          recordId={recordId}
          isOpen={isOpen}
          onClose={() => setIsOpen(false)}
        />
      )}
    </>
  );
}
```

---

## 6. Presupuesto Geométrico sin Scroll Horizontal

En tablas densas ubicadas dentro de modales, el ancho disponible suele estar restringido a ~800px - 1000px.
Para evitar que aparezca una barra de scroll horizontal en resoluciones de 1366x768 o pantallas escaladas al 125%:

| Columna | Ancho Recomendado | Justificación |
|---|---|---|
| **Fecha / Hora** | `115px` | Suficiente para formato estándar `DD/MM/YYYY, HH:MM` |
| **Identificador / Código** | `115px` | Textos de 12-14 caracteres con números tabulares |
| **Entidad / Actor** | `160px` | Texto con `text-overflow: ellipsis` y tooltip |
| **Badge / Estado** | `140px` | Píldora de estado con padding compacto |
| **Acción / Botón** | `120px` | Botón compacto secundario |

**Ancho Total Proyectado:** `~650px` a `~850px` → Encaja al 100% sin generar barras de desplazamiento horizontal.
