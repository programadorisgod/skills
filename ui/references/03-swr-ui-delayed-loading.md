# 03. Patrón SWR en Frontend y Umbral de Carga Diferida (160ms)

> **Módulo:** UI & UX Engineering Patterns  
> **Tema:** Experiencia de usuario no destructiva con Stale-While-Revalidate (SWR), eliminación del parpadeo de carga efímero y barras de progreso no intrusivas.

---

## 1. La Fatiga del "Fogonazo" de Carga (Loader Flickering)

En arquitecturas web convencionales, cada vez que el usuario cambia un filtro, selecciona una fecha o navega a una pestaña, suele ejecutarse un patrón destructivo:

```tsx
// ❌ Patrón destructivo: Forzar refetch reseteando el estado a null
function handleDateChange(newDate: string) {
  setDate(newDate);
  setData(null);      // <- Provoca desmontaje de la tabla existente
  setIsLoading(true); // <- Monta inmediatamente un esqueleto de carga
  fetchData(newDate).then(res => {
    setData(res);
    setIsLoading(false);
  });
}
```

### El problema de las respuestas rápidas (<160 ms):
En redes de alta velocidad o cuando las APIs consultan índices optimizados en memoria, la respuesta suele retornar entre **40 ms y 120 ms**.
1. En el **milisegundo 0**, la tabla previa desaparece y aparece un skeleton blanco pulsante.
2. En el **milisegundo 60**, llega la respuesta del servidor: el skeleton se destruye y la tabla vuelve a pintarse.
3. **Resultado:** El usuario percibe un "fogonazo" o parpadeo brillante molesto que fatiga la vista y hace que la aplicación se sienta inestable, a pesar de que el backend respondió con rapidez.

---

## 2. La Regla de los 160 ms de Nielsen Norman

Según los estudios fundamentales de usabilidad de Jakob Nielsen y los estándares de Material Design:
- **0 a 100 ms:** Se percibe como **instantáneo**. No debe mostrarse ningún indicador visual de carga.
- **100 a 300 ms:** Se percibe un breve retraso natural. Si se muestra un loader antes de 160 ms, se percibirá como un destello innecesario.
- **> 300 ms:** Es imperativo proporcionar retroalimentación visual continua para mantener la certeza del usuario.

```
0 ms               100 ms             160 ms                            1000 ms
├──────────────────┴──────────────────┼─────────────────────────────────┤
│    Zona Instantánea / Silenciosa    │  Aparición Suave de Barra UI    │
│  (Respuesta rápida -> Cero loaders) │  (Transición elegante fade-in)  │
```

---

## 3. Hook Universal: `useDelayedLoading`

Este hook aplaza la activación del indicador visual durante un umbral de gracia (*grace window*) de **160 ms**:

```tsx
// src/hooks/use-delayed-loading.ts
import { useState, useEffect } from "react";

/**
 * Retrasa la activación del estado de carga visual para evitar destellos
 * ante peticiones que resuelven en menos de `delayMs`.
 */
export function useDelayedLoading(isLoading: boolean, delayMs = 160): boolean {
  const [showLoading, setShowLoading] = useState(false);

  useEffect(() => {
    if (!isLoading) {
      setShowLoading(false);
      return;
    }

    const timer = setTimeout(() => {
      setShowLoading(true);
    }, delayMs);

    return () => clearTimeout(timer);
  }, [isLoading, delayMs]);

  return showLoading;
}
```

---

## 4. El Patrón SWR en Hooks de Datos de Cliente

Para evitar que la pantalla quede en blanco, los hooks de datos adoptan el principio **Stale-While-Revalidate**: **conservar en pantalla los datos de la consulta previa** mientras se valida la nueva petición en segundo plano.

```tsx
// src/hooks/use-dashboard-metrics.ts
import { useState, useEffect, useRef } from "react";
import { useDelayedLoading } from "./use-delayed-loading";

interface UseMetricsOptions {
  category: string;
  dateRange: string;
}

export function useDashboardMetrics({ category, dateRange }: UseMetricsOptions) {
  const [data, setData] = useState<MetricsData | null>(null);
  const [isFetching, setIsFetching] = useState(true);
  
  // Activa el feedback visual solo si la petición tarda más de 160ms
  const isPendingDelayed = useDelayedLoading(isFetching, 160);

  useEffect(() => {
    let active = true;
    setIsFetching(true);

    // 💡 IMPORTANTE: No borramos `data` a `null`.
    // Los datos de la fecha previa permanecen legibles en pantalla.

    fetchMetrics({ category, dateRange })
      .then((result) => {
        if (!active) return;
        setData(result);
        setIsFetching(false);
      })
      .catch((error) => {
        if (!active) return;
        setIsFetching(false);
      });

    return () => {
      active = false;
    };
  }, [category, dateRange]);

  return {
    data,
    isLoadingInitial: isFetching && data === null, // Skeleton solo en la primera carga en frío
    isRefreshing: isPendingDelayed,               // Barra superior suave tras 160ms
  };
}
```

---

## 5. Barra de Progreso No Intrusiva vs Fogonazos de Opacidad

En lugar de bajar la opacidad de la tabla (lo cual produce una oscilación de contraste molesta para los ojos al alternar entre 70% y 100%), la tabla **conserva el 100% de nitidez** y se acompaña de una barra de progreso lineal fijada al marco superior:

```tsx
// src/components/analytics/metrics-table.tsx
import React from "react";
import styles from "./analytics.module.css";

export function MetricsTable({ items, isRefreshing }: Props) {
  return (
    <div className={styles.tableCard}>
      {/* Barra de progreso de 2px en el borde superior */}
      {isRefreshing && (
        <div className={styles.topProgressBar} role="progressbar" />
      )}

      <table className={styles.table}>
        <thead>
          <tr>
            <th>Identificador</th>
            <th>Monto</th>
            <th>Estado</th>
          </tr>
        </thead>
        <tbody>
          {items.map((row) => (
            <tr key={row.id}>
              <td>{row.id}</td>
              <td>{row.amount}</td>
              <td>{row.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

```css
/* styles/analytics.module.css */
.tableCard {
  position: relative;
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  overflow: hidden;
}

/* Barra de progreso con gradiente continuo y animación fluida */
.topProgressBar {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 2px;
  background: linear-gradient(
    90deg,
    rgba(0, 87, 116, 0) 0%,
    rgba(0, 118, 158, 0.9) 50%,
    rgba(0, 87, 116, 0) 100%
  );
  background-size: 200% 100%;
  animation: progressFlow 1.2s ease-in-out infinite, progressFadeIn 180ms ease forwards;
  z-index: 20;
}

@keyframes progressFlow {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

@keyframes progressFadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
```

---

## 6. Cuadro Comparativo de Experiencia de Usuario

| Métrica | Enfoque Clásico Destructivo | Patrón SWR + Delayed Loading |
|---|---|---|
| **Respuesta en 80 ms** | Destello blanco de 80ms de un skeleton | **Cero loaders visibles (transición a 0 ms)** |
| **Respuesta en 450 ms** | Pantalla en blanco con spinner invasivo | Datos previos legibles + sutil barra superior |
| **Lectura durante carga** | Se interrumpe la lectura del usuario | **No se interrumpe**; el usuario sigue analizando filas |
| **Fatiga visual** | Alta (constantes cambios de luminancia) | Mínima (nitidez y contraste 100% estables) |
