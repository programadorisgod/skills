# 04. Concurrencia, Prevención de Deadlocks (Error 1205) y Señales de Atención

## 1. Naturaleza de los Deadlocks en SQL Server

Un **Deadlock (Error 1205)** ocurre cuando dos o más transacciones concurrentes mantienen bloqueos sobre recursos que la otra necesita para continuar, formando un ciclo circular cerrado:

```
Transacción 1 (Dashboard)                     Transacción 2 (Proceso de Cierre / Asignación)
┌───────────────────────────┐                 ┌───────────────────────────┐
│ Mantiene Lock S en        │                 │ Mantiene Lock X en        │
│ Tabla Ordenes             │                 │ Tabla DetalleOrden        │
└─────────────┬─────────────┘                 └─────────────┬─────────────┘
              │                                             │
              ▼ Espera Lock en DetalleOrden                 ▼ Espera Lock en Ordenes
        [BLOQUEO CIRCULAR: El Deadlock Monitor elige a una víctima y emite el Error 1205]
```

### Tipos de Deadlocks Frecuentes:
1. **Key Lock / Page Lock Deadlock**: Escaneos de lectura masiva de dashboards chocan con procesos en segundo plano que ejecutan `INSERT` o `UPDATE`.
2. **Communication Buffer Deadlock (`CXPACKET`)**: En consultas paralelizadas (`MAXDOP > 1`), múltiples hilos secundarios intercambian paquetes en memoria interna y se bloquean mutuamente ante contención de I/O.

---

## 2. Técnicas de Prevención y Patrones Probados

### Patrón 1: Aislamiento de Lecturas con `WITH (NOLOCK)`
En consultas analíticas de reportes o dashboards donde no se requiere consistencia transaccional serializable:

```sql
SELECT O.OrdenId, O.NumeroOrden, O.TotalOrden, C.RazonSocial
FROM dbo.Ordenes O WITH (NOLOCK)
INNER JOIN dbo.Clientes C WITH (NOLOCK) ON C.ClienteId = O.ClienteId
WHERE O.EstadoOrden = 'PENDIENTE';
```
* **Ventaja:** Emite lecturas no comprometidas (`READ UNCOMMITTED`), lo que **no solicita Shared Locks (`S`)** y permite que las escrituras concurrentes avancen sin bloquearse.

---

### Patrón 2: Serialización Transaccional con `WITH (UPDLOCK, HOLDLOCK)`
Cuando dos procesos intentan descontar stock o asignar un pedido de forma concurrente, el patrón `SELECT ... THEN UPDATE` común produce deadlocks si ambos adquieren lock compartido `S` y luego intentan convertirlo a exclusivo `X`.

#### Anti-Patrón (Deadlock Inminente):
```sql
-- Dos procesos concurrentes leen simultáneamente
SELECT StockActual FROM dbo.Productos WHERE ProductoId = 1; -- Adquiere Lock S

-- Ambos intentan actualizar al mismo tiempo -> Deadlock 1205
UPDATE dbo.Productos SET StockActual = StockActual - 1 WHERE ProductoId = 1;
```

#### Patrón Correcto (Bloqueo Atómico Preventivo):
```sql
BEGIN TRANSACTION;

-- Adquiere un lock de actualización (U) que impide que otra transacción lea con intención de modificar
SELECT StockActual
FROM dbo.Productos WITH (UPDLOCK, HOLDLOCK)
WHERE ProductoId = 1;

-- Actualización segura y serializada
UPDATE dbo.Productos 
SET StockActual = StockActual - 1 
WHERE ProductoId = 1;

COMMIT TRANSACTION;
```
* `UPDLOCK`: Adquiere bloqueo de actualización de inmediato en lugar de bloqueo compartido.
* `HOLDLOCK`: Mantiene el bloqueo hasta que finalice la transacción (`SERIALIZABLE`), evitando lecturas sucias y condiciones de carrera.

---

### Patrón 3: Prioridad de Víctima (`SET DEADLOCK_PRIORITY`)
Para procesos en segundo plano o tareas batch (ej. cierres diarios o sincronizaciones nocturnas):

```sql
-- Si ocurre un deadlock, este proceso prefiere ser sacrificado antes que bloquear a los usuarios web
SET DEADLOCK_PRIORITY LOW;

BEGIN TRANSACTION;
    -- Operaciones masivas de sincronización...
COMMIT TRANSACTION;
```

---

### Patrón 4: Cancelación de Consultas Huérfanas (TDS Attention Signal)

Cuando un usuario navega rápidamente entre pestañas o cancela una petición web en el frontend, el servidor HTTP desconecta el socket, pero **SQL Server continúa ejecutando la consulta pesada en segundo plano**, consumiendo CPU y reteniendo bloqueos.

En el driver de Node.js / Tedious, se debe propagar el `AbortSignal`:

```typescript
export async function executeCancellableQuery(sqlText: string, signal?: AbortSignal) {
  const request = new sql.Request();

  if (signal) {
    signal.addEventListener('abort', () => {
      // Envía un paquete TDS Attention al motor SQL Server para abortar la consulta en el engine
      request.cancel();
    });
  }

  return await request.query(sqlText);
}
```

---

## 3. Script de Simulación en SSMS

Abre dos pestañas en SSMS para simular contención con `UPDLOCK`:

```sql
-- Pestaña 1:
USE TiendaDemo;
BEGIN TRAN;
SELECT StockActual FROM dbo.Productos WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = 1;
-- (No ejecutes COMMIT todavía)

-- Pestaña 2:
USE TiendaDemo;
BEGIN TRAN;
-- Esta consulta esperará pacientemente a la Pestaña 1 sin generar deadlock
SELECT StockActual FROM dbo.Productos WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = 1;

-- En Pestaña 1:
COMMIT TRAN;
-- Verás que la Pestaña 2 se desbloquea de inmediato.
```
