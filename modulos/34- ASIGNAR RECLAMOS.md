# Módulo 34 — ASIGNAR RECLAMOS

A qué técnico se le asignó cada reclamo de garantía, con prioridad, estado de la
asignación y fechas. Un reclamo puede pasar por varias asignaciones a lo largo
del tiempo; el avance del trabajo vive **acá**, no en el reclamo.

**Depende de:** `RECLAMOS_GARANTIAS` (27) y `EMPLEADOS` (8).
**Es usado por:** **nadie**. La app **no** llama a ninguno de los dos `SP`; cierra
reclamos con `27_SP_FINALIZAR_RECLAMO_TOTAL` (27), que **no toca esta tabla**.

Fuente: `modulos/34- ASIGNAR RECLAMOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### ASIGNACIONES_RECLAMOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_ASIGNACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_RECLAMO_GARAN` | `INT` | NOT NULL, FK → `RECLAMOS_GARANTIAS` **ON DELETE CASCADE** | Reclamo. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Técnico asignado. |
| `FECHA_ASIGNACION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo se asignó. |
| `FECHA_FINALIZACION` | `DATETIME` | NULL, CHECK `>= FECHA_ASIGNACION` | Cuándo se cerró. |
| `PRIORIDAD` | `ENUM('BAJA','MEDIA','ALTA','URGENTE')` | DEFAULT `'MEDIA'` | Prioridad. |
| `ESTADO_ASIGNACION` | `ENUM('PENDIENTE','EN_PROCESO','COMPLETADO','CANCELADO')` | DEFAULT `'PENDIENTE'` | Estado del trabajo. |
| `OBSERVACIONES` | `VARCHAR(255)` | NULL | Notas. |

**Índices:** `IDX_EMPLEADO_FECHA` **y** `IDX_ASIGNACIONES_EMPLEADO_FECHA`, los dos
sobre `(ID_EMPLEADO, FECHA_ASIGNACION)`.

> **Dos índices idénticos.** El primero se declara dentro del `CREATE TABLE` y el
> segundo con un `CREATE INDEX` más abajo, con otro nombre: MySQL los acepta
> como dos estructuras separadas sobre las mismas columnas. Uno sobra.
>
> **La FK del reclamo borra en cascada**: borrar un reclamo se lleva sus
> asignaciones. La FK del empleado **no** tiene `ON DELETE`, así que un técnico
> con asignaciones no se puede borrar.
>
> **`PENDIENTE` nunca se usa**: el `SP` inserta directo en `EN_PROCESO`, así que
> ese estado del `ENUM` es decorativo. Y el `CHECK` de fechas solo compara contra
> la fecha de asignación por defecto, no contra la del reclamo.

**Migración incluida:** `ALTER TABLE ... ADD CONSTRAINT IF NOT EXISTS
CHK_FECHAS_VALIDAS CHECK (FECHA_FINALIZACION >= FECHA_ASIGNACION)`, idempotente.

## Procedimientos almacenados

### `SP_ASIGNAR_TECNICO_RECLAMO(P_ID_RECLAMO, P_ID_EMPLEADO, P_PRIORIDAD, P_OBSERVACIONES)`

1. reclamo inexistente → `ERROR: RECLAMO NO ENCONTRADO.`
2. reclamo que no está `PENDIENTE` → `ERROR: SOLO SE PUEDEN ASIGNAR TÉCNICOS A RECLAMOS PENDIENTES.`
3. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
4. reclamo con otra asignación `PENDIENTE`/`EN_PROCESO` →
   `ERROR: EL RECLAMO YA TIENE UNA ASIGNACION EN CURSO.`
5. inserta la asignación en `EN_PROCESO` y devuelve
   `EXITO: TÉCNICO ASIGNADO CORRECTAMENTE.`

> **No valida que el empleado sea técnico ni que esté activo**: cualquier
> empleado —o uno despedido— se puede asignar.
>
> **El reclamo se queda en `PENDIENTE`** a propósito: su `ENUM` no admite
> `EN_PROCESO` (antes el `SP` intentaba ese `UPDATE` y fallaba con `1265`).
>
> **La verificación "una sola asignación en curso" no está protegida por la
> base**: no hay índice único, así que dos llamadas simultáneas pueden crear dos
> filas `EN_PROCESO` para el mismo reclamo.
>
> **El `LEAVE proc_label` después de cada `SIGNAL` nunca se ejecuta**: `SIGNAL`
> ya aborta el bloque. Es ruido, no un error.

### `SP_FINALIZAR_RECLAMO(P_ID_ASIGNACION, P_OBSERVACIONES_FINALES)`

Cierra la **asignación** y el **reclamo** en una transacción (propia solo si
`@@in_transaction = 0`, con `EXIT HANDLER` que hace `ROLLBACK` + `RESIGNAL`).

1. asignación inexistente → `ERROR: ASIGNACION NO ENCONTRADA.`
2. asignación ya `COMPLETADO` → `ERROR: ESTA ASIGNACION YA FUE FINALIZADA.`
3. marca la asignación `COMPLETADO`, con `FECHA_FINALIZACION = NOW()` y la nota
   final agregada a `OBSERVACIONES`.
4. deja el reclamo en `CERRADO` y devuelve
   `EXITO: RECLAMO FINALIZADO Y CERRADO.`

> **Una asignación `CANCELADO` sí se puede finalizar**: el `SP` solo bloquea
> `COMPLETADO`. Un trabajo cancelado termina marcado como completado.
>
> **La nota final puede borrar todas las notas previas**: si `OBSERVACIONES` es
> `NULL`, `CONCAT(NULL, ' | Nota final: ', …)` da `NULL` y el `UPDATE` deja la
> columna vacía. Las observaciones anteriores se pierden sin aviso.
>
> **Cierra el reclamo entero**, aunque tenga otras asignaciones abiertas (solo
> hay una por la validación del otro `SP`, pero nada lo garantiza en la base).
>
> **La app no lo llama**: el cierre real pasa por `27_SP_FINALIZAR_RECLAMO_TOTAL`,
> que deja la asignación en `EN_PROCESO` para siempre. Hoy, en la práctica, la
> tabla es un registro de asignaciones que nunca se completan.

## Reglas de negocio

- **Un reclamo tiene, como mucho, una asignación en curso** (validado en el `SP`,
  no en la base).
- **Solo se asigna sobre un reclamo `PENDIENTE`.**
- **El avance vive en `ESTADO_ASIGNACION`**, no en el estado del reclamo.
- **Finalizar la asignación cierra el reclamo.**
- **Borrar el reclamo borra sus asignaciones.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
