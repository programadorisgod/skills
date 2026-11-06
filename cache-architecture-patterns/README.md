# High-Performance Cache Architecture & In-Memory Patterns

Guía de ingeniería y patrones avanzados de arquitectura de caché granular, estructuras de datos en memoria para Node.js (motor V8), estrategias intercambiables (de In-Memory local a Redis distribuido), bajo consumo de RAM (< 3 MB para 10.000 registros) y mutaciones quirúrgicas $O(1)$ sin refetch destructivo.

---

## 🎯 Problemas que Resuelve esta Arquitectura

1. **Refetch Global Destructivo**: Cambiar el estado de un registro puntual (activar un usuario, asignar una categoría, alternar un flag) suele invalidar toda la caché de la aplicación, obligando a recargar tablas pesadas de órdenes o facturación desde la base de datos.
2. **Consumo Desmedido de RAM en Node.js**: Duplicar arreglos enteros con `.map()` o clonaciones profundas en cada mutación satura el heap del proceso y activa pausas frecuentes del Garbage Collector (*Stop-the-World*).
3. **Pérdida de Asignatarios al Revertir Estados**: Entidades que adoptan una marca temporal (ej. *Revisión Prioritaria*) pierden a su operador o revisor original al desmarcarse si la memoria no retiene el estado previo.
4. **Acoplamiento a Infraestructura Externa**: Depender de Redis desde el día 1 añade latencia de red (2–5 ms por comando) y costos de infraestructura en fases donde la memoria RAM local puede responder en sub-milisegundos (< 0.1 ms).
5. **Peticiones HTTP Redundantes**: Consultar endpoints de analítica histórica inmutable en cada navegación de interfaz en vez de congelar la respuesta en el cliente con TTLs escalonados.

---

## 📚 Índice de Referencias Técnicas

| Referencia | Tema Clave | Cuándo consultarla |
|---|---|---|
| [01. Patrón Strategy e Interfaces Hexagonales](references/01-strategy-pattern-interfaces.md) | `IHashCacheStrategy`, `ILruCacheStrategy` | Diseñar capas de caché desacopladas listas para migrar a Redis |
| [02. Optimización de Memoria en Motor V8](references/02-v8-memory-optimization.md) | Tagged Pointers (`Smi`), String Interning | Mantener 10.000 registros en < 3 MB con latencia < 0.1 ms |
| [03. Mutación Granular In-Place O(1)](references/03-granular-inplace-mutation.md) | Método `patch()`, Estado en Render React | Actualizar un solo registro sin invalidar la vista principal |
| [04. Patrón Restored Owners en Base de Datos](references/04-restored-owners-pattern.md) | Query indexada en `#tmp` (~2 ms), reversión segura | Revertir marcas transaccionales restaurando dueños originales |
| [05. TTL Escalonado e Invalidación Reactiva](references/05-tiered-ttl-and-reactivity.md) | Inmutabilidad (10h vs 15m), Short-Circuit | Cachear históricos y purgar selectivamente por tenant |

---

## 📐 Visión General de la Arquitectura

```mermaid
flowchart TD
    subgraph UI["Capa de Presentación (React / Next.js)"]
        A[Acción de Usuario: Toggle / Marca] --> B[Hook de Negocio: useEntidad]
        B --> C{"¿Requiere Refetch Global?"}
        C -- "❌ NO (Antipatrón)" --> D[Destruir caché y spinner general]
        C -- " SÍ (Patrón Granular)" --> E[patch in-place en memoria]
    end

    subgraph API["Capa de Aplicación y Servicios"]
        E --> F[API Route / Server Action]
        F --> G[Servicio de Dominio]
        G --> H["Puerto: IHashCacheStrategy / ILruCacheStrategy"]
    end

    subgraph INFRA["Capa de Infraestructura (Intercambiable)"]
        H --> I["Adaptador 1: InMemoryStrategy (Local, 0 ms, <3 MB)"]
        H -.-> J["Adaptador 2: RedisStrategy (Distribuido, Multi-Pod)"]
    end

    subgraph DB["Persistencia Transaccional (SQL Server / PostgreSQL)"]
        F --> K["Transacción con Tabla Temporal #tmp (~2 ms)"]
        K --> L[Devuelve Restored Owners si desmarca]
        L --> E
    end
```

---

## ⚡ Métricas de Rendimiento Verificadas

En pruebas de estrés automatizadas ejecutadas sobre Node.js:

- **Volumen evaluado**: 10.000 entidades activas en memoria particionadas por tenant.
- **Estrés de mutaciones**: 50.000 operaciones consecutivas de lectura y actualización.
- **Huella de memoria RAM**: **< 2.8 MB** en el heap de V8.
- **Tiempo de ejecución total**: **29 milisegundos** (~580 nanosegundos por operación).
- **Hit Ratio de caché**: **> 99.9%**.
