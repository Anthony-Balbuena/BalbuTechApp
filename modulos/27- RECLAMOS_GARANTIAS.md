# Módulo 27 — RECLAMOS_GARANTIAS

Los reclamos que se abren sobre una garantía: qué pasó, cuándo y en qué estado
quedó. Es la **puerta de entrada** al uso de una garantía (módulo 25).

**Depende de:** `GARANTIAS` (25) y `AUDITORIA_SISTEMA` (3).
**Es usado por:** `ventas.cpp` (alta y cierre del reclamo).

Fuente: `modulos/27- RECLAMOS_GARANTIAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### RECLAMOS_GARANTIAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_RECLAMO_GARAN` | `INT` | PK, AUTO_INCREMENT | Identificador (el nombre va truncado). |
| `ID_GARANTIA` | `INT` | NOT NULL, FK → `GARANTIAS` **ON DELETE CASCADE** | Garantía reclamada. |
| `FECHA_RECLAMO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se abrió. |
| `DESCRIPCION` | `VARCHAR(255)` | NOT NULL | Qué pasó. |
| `ESTADO` | `ENUM('PENDIENTE','APROBADO','RECHAZADO','CERRADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |

**Índice:** `IX_RECLAMO_GARANTIA_FECHA` (`FECHA_RECLAMO`), para listar del más
reciente al más viejo.

> La FK `ON DELETE CASCADE` es letra muerta: las garantías no se borran.

### Máquina de estados

```
PENDIENTE ──> APROBADO ──> CERRADO
    └──────> RECHAZADO
```

`RECHAZADO` y `CERRADO` son **terminales**; nadie vuelve a `PENDIENTE`.

## Procedimientos almacenados

### `27_SP_REGISTRAR_RECLAMO_GARANTIA(P_ID_GARANTIA, P_DESCRIPCION)`

**Usada por la app** (`ventas.cpp`).

1. garantía inexistente → `ERROR: LA GARANTÍA NO EXISTE.`
2. garantía no `ACTIVA` →
   `ERROR: ESTA GARANTÍA NO ESTÁ ACTIVA Y NO SE PUEDE RECLAMAR.`
3. Inserta el reclamo en `PENDIENTE` y devuelve
   `EXITO: RECLAMO REGISTRADO CORRECTAMENTE.`

> **La garantía vencida por fecha sigue aceptando reclamos.** El SP solo mira
> `ESTADO`, y ningún módulo pasa una garantía a `VENCIDA` (ver módulo 25): una
> garantía con `FECHA_FIN` en el pasado sigue figurando `ACTIVA` y el reclamo
> entra sin chistar. **No se compara `FECHA_FIN` con la fecha de hoy en ningún
> lado del flujo.**
>
> **`P_DESCRIPCION` no se valida**: la columna es `NOT NULL`, pero una cadena
> vacía o de solo espacios pasa.

### `27_SP_FINALIZAR_RECLAMO_TOTAL(P_ID_RECLAMO)`

**Usada por la app** (`ventas.cpp`). Cierra el caso.

1. reclamo inexistente → `ERROR: RECLAMO NO ENCONTRADO.`
2. `UPDATE` a `CERRADO`.
3. Inserta en `AUDITORIA_SISTEMA`
   (`TABLA_AFECTADA = 'RECLAMOS_GARANTIAS'`, `ACCION = 'UPDATE'`,
   `USUARIO_SISTEMA = USER()`, `VALOR_ANTERIOR = <estado previo>`,
   `VALOR_NUEVO = 'CERRADO'`).

> **Transacción propia:** abre solo si `@@in_transaction = 0`; si viene de otra,
> no la cierra. El `EXIT HANDLER` hace `ROLLBACK` solo en el caso propio, con
> `RESIGNAL`. Antes hacía `START`/`COMMIT`/`ROLLBACK` incondicionales y rompía
> la transacción del llamador (corregido el 09/10/2026).
>
> **No devuelve mensaje**: el cierre se confirma por el resultado vacío.
>
> **Cerrar un `RECHAZADO` falla**: el trigger de cambio de estado trata
> `RECHAZADO` como terminal y rechaza el paso a `CERRADO`.

## Triggers

### `TR_VALIDAR_CAMBIO_RECLAMO` (`BEFORE UPDATE`)

- el reclamo **no cambia de garantía** →
  `ERROR: EL RECLAMO NO CAMBIA DE GARANTIA.`
- desde `CERRADO` o `RECHAZADO`, cualquier cambio de estado →
  `ERROR: EL RECLAMO YA ESTA CERRADO O RECHAZADO; ESE ESTADO NO CAMBIA.`
- volver a `PENDIENTE` desde otro estado →
  `ERROR: EL RECLAMO NO SE REABRE.`

> **No protege el flujo `APROBADO → PENDIENTE`… pero sí:** la tercera regla lo
> corta. Lo que **no** valida es el salto directo `PENDIENTE → CERRADO` sin
> pasar por `APROBADO`; el SP de cierre lo permite y se usa para cerrar casos
> que no llegaron a aprobarse.
>
> **`DESCRIPCION` es editable para siempre**, incluso con el reclamo cerrado:
> no hay candado sobre el texto.

### `TR_FINALIZAR_RECLAMO_APROBADO` (`AFTER UPDATE`)

En `PENDIENTE → APROBADO`, pasa la **garantía** a `CANCELADA`.

> **Una aprobación quema la garantía entera**, incluso si el reclamo cubría una
> sola unidad de una línea con varias. No hay devolución de stock ni reemplazo:
> la base registra el caso, la reposición se resuelve afuera.
>
> **No escribe auditoría**; solo `27_SP_FINALIZAR_RECLAMO_TOTAL` lo hace.

### `TR_BLOQUEAR_BORRADO_RECLAMO` (`BEFORE DELETE`)

Solo se borra un reclamo `PENDIENTE`:
`ERROR: EL RECLAMO PROCESADO NO SE BORRA; USE LOS SPS DE CIERRE.`

## Reglas de negocio

- **Solo se reclama sobre una garantía `ACTIVA`** — que no es lo mismo que
  vigente por fecha.
- **Un reclamo aprobado cancela la garantía** completa.
- **`RECHAZADO` y `CERRADO` son terminales**; no se reabren.
- **Un reclamo procesado no se borra** (auditoría).
- **El cierre deja rastro** en `AUDITORIA_SISTEMA` con el usuario de la sesión.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
