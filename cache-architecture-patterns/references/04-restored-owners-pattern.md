# Patrón Restored Owners: Reversión Atómica sin Refetch Destructivo

## 1. El Dilema del Estado Transitorio y la Pérdida de Linaje

En sistemas de distribución de trabajo, logística y flujos de revisión (tickets, órdenes de compra, auditorías), es común que ciertos registros sean asignados **temporalmente** a un rol o usuario supervisor (por ejemplo, para una revisión especial o contingencia).

### El Problema
Al desmarcar o liberar los registros de esa condición especial:
1. ¿Quién era el operador o asignatario original de cada registro?
2. Si el sistema simplemente borra el registro de la tabla de marcas temporales, la interfaz de usuario en el cliente y la caché en memoria quedan con el nombre del supervisor temporal o vacías.
3. El enfoque ingenuo es forzar un `refetch()` global de toda la tabla (miles de filas) para averiguar los dueños originales, lo cual reintroduce latencia, consumo de red y parpadeo visual.

---

## 2. La Solución Arquitectónica: Patrón Restored Owners

El patrón consiste en un flujo atómico coordinado entre SQL, el servicio de backend y la caché del cliente:

```
[Cliente: Desmarca K registros]
           │
           ▼
[POST /api/ordenes/desmarcar]
           │
           ├─► 1. SQL: Carga K IDs en tabla temporal #tmp_ids (indexada)
           │          Hace JOIN con la tabla de asignaciones base (~2 ms)
           │          Captura los "dueños originales" (restoredOwners)
           │
           ├─► 2. SQL: Borra las marcas en la tabla transitoria
           │
           ├─► 3. Backend: Parchea in-place la caché en memoria del servidor
           │
           ▼
[Respuesta JSON: { procesadas: K, restoredOwners: { [id]: "Operador A", ... } }]
           │
           ▼
[Cliente: Muta in-place su tabla y contadores de pestañas en 0 ms sin refetch]
```

---

## 3. Implementación T-SQL de Alto Rendimiento (~2 ms)

En Microsoft SQL Server o motores relacionales modernos, consultar miles de registros individuales con un `WHERE id IN (...)` dinámico puede fragmentar la caché de planes o causar *Row Goal* ineficiente.

El patrón óptimo utiliza una **tabla temporal local `#tmp` con índice agrupado**:

```sql
-- Procedimiento o bloque T-SQL ejecutado por el servicio
CREATE TABLE #tmp_ids (
    orden_id INT NOT NULL PRIMARY KEY CLUSTERED
);

-- Inserción en bloque de los K IDs desmarcados
INSERT INTO #tmp_ids (orden_id)
VALUES (101), (102), (105);

-- 1. Captura atómica de los asignatarios originales antes del borrado
SELECT 
    t.orden_id AS ordenId,
    ISNULL(a.nombre_operador, 'SIN ASIGNAR') AS operadorOriginal
FROM #tmp_ids t
INNER JOIN ORDENES_ASIGNACION a WITH (NOLOCK)
    ON a.orden_id = t.orden_id
WHERE a.tenant_id = @tenantId;

-- 2. Eliminación de las marcas transitorias de revisión especial
DELETE m
FROM ORDENES_MARCAS_TEMPORALES m
INNER JOIN #tmp_ids t
    ON m.orden_id = t.orden_id
WHERE m.tenant_id = @tenantId;

DROP TABLE #tmp_ids;
```

> **Métricas:** En bases de datos con más de 2 millones de órdenes, esta consulta toma **entre 1 y 3 milisegundos**, utilizando únicamente lecturas lógicas puntuales (*Index Clustered Seek*).

---

## 4. Orquestación en el Servicio Backend (TypeScript)

El backend mapea los resultados en un diccionario indexado `Record<string, string>` y lo devuelve en la misma respuesta:

```typescript
// servicio-marcado-especial.ts
export interface DesmarcarResult {
  procesadas: number;
  restoredOwners: Record<string, string>; // { "ORD-101": "Carlos Mendoza", ... }
}

export async function desmarcarOrdenes(
  tenantId: string,
  ordenesIds: string[]
): Promise<DesmarcarResult> {
  const result = await db.transaction(async (tx) => {
    // 1. Obtener dueños originales mediante JOIN indexado
    const queryOwners = await tx.query(`
      SELECT o.id, a.operador_nombre
      FROM OPENJSON(@ids) WITH (id VARCHAR(50) '$') o
      LEFT JOIN ORDENES_ASIGNACION a ON a.orden_id = o.id AND a.tenant_id = @tenantId
    `, { ids: JSON.stringify(ordenesIds), tenantId });

    const restoredOwners: Record<string, string> = {};
    for (const row of queryOwners.recordset) {
      restoredOwners[row.id] = row.operador_nombre ?? 'SIN ASIGNAR';
    }

    // 2. Borrar marcas temporales
    await tx.query(`
      DELETE FROM ORDENES_MARCAS_TEMPORALES
      WHERE tenant_id = @tenantId AND orden_id IN (SELECT value FROM STRING_SPLIT(@idsList, ','))
    `, { tenantId, idsList: ordenesIds.join(',') });

    return { procesadas: ordenesIds.length, restoredOwners };
  });

  // 3. Parche in-place en la caché en memoria del servidor
  ordenesCacheStrategy.patch(
    (key) => key.startsWith(`ordenes:${tenantId}:`),
    (dataset) => dataset.map((item) => {
      if (result.restoredOwners[item.id]) {
        return {
          ...item,
          marcaEspecial: false,
          operadorAsignado: result.restoredOwners[item.id]
        };
      }
      return item;
    })
  );

  return result;
}
```

---

## 5. Aplicación In-Place en el Cliente (Frontend)

En el frontend, el hook o componente recibe `restoredOwners` y actualiza inmediatamente las colecciones de las pestañas ("Todas", "Marcadas", "Sin Marcar") sin invocar a `refetch()`:

```typescript
// En el componente de UI o hook
const handleDesmarcar = async (idsSeleccionados: string[]) => {
  const res = await api.post<DesmarcarResult>('/api/ordenes/desmarcar', {
    ids: idsSeleccionados,
  });

  const { restoredOwners } = res.data;

  // Parcheamos la lista principal en memoria
  setOrdenes((prevOrdenes) =>
    prevOrdenes.map((orden) => {
      if (restoredOwners[orden.id] !== undefined) {
        return {
          ...orden,
          marcaEspecial: false,
          operadorAsignado: restoredOwners[orden.id], // Dueño original restaurado
        };
      }
      return orden;
    })
  );

  // Actualizamos contadores de pestañas en memoria (O(1))
  setPestanasContadores((prev) => ({
    ...prev,
    marcadas: prev.marcadas - idsSeleccionados.length,
    sinMarcar: prev.sinMarcar + idsSeleccionados.length,
  }));
};
```

---

## 6. Ventajas del Enfoque

1. **Fidelidad Absoluta de Datos:** Ningún registro queda con datos residuales del supervisor temporal.
2. **Resiliencia ante Fallos de Conexión:** Si el servicio se reinicia o el cliente recarga con F5, la base de datos ya fue actualizada limpiamente y el estado devuelto siempre será exacto.
3. **Cero Parpadeo:** La tabla en la pantalla del usuario actualiza los nombres en el mismo frame de renderizado, brindando una sensación nativa y fluida.
