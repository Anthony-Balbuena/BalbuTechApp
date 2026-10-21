# Módulo 41 — TURNO_CAJA

Apertura y cierre de caja por turno. Un turno va desde que un empleado abre la
caja hasta que la cierra; guarda quién abrió, quién cerró, el monto inicial y
el **cuadre**: el saldo esperado (apertura + lo cobrado en `PAGOS` dentro de
la ventana del turno), el saldo real que cuenta el empleado y la diferencia.

**Depende de:** `EMPLEADOS` (8) y `PAGOS` (26) — a `PAGOS` solo la lee, no la
toca.
**Es usado por:** `caja.cpp` (apertura, estado y cierre de turno).

Fuente: `modulos/41- TURNO_CAJA.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### TURNO_CAJA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_TURNO` | `INT` | PK, AUTO_INCREMENT | Identificador del turno. |
| `CAJA` | `VARCHAR(20)` | NOT NULL | Nombre/identificador de la caja física. |
| `ID_EMPLEADO_APERTURA` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quién abrió. |
| `MONTO_INICIAL` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00`, CHECK `>= 0` | Fondo con el que arranca la caja. |
| `FECHA_APERTURA` | `DATETIME` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Inicio del turno (marca el comienzo de la ventana de cobros). |
| `ID_EMPLEADO_CIERRE` | `INT` | NULL, FK → `EMPLEADOS` | Quién cerró. |
| `FECHA_CIERRE` | `DATETIME` | NULL | Fin del turno. |
| `SALDO_ESPERADO` | `DECIMAL(10,2)` | NULL | `MONTO_INICIAL` + cobrado en la ventana; se congela al cerrar. |
| `SALDO_REAL` | `DECIMAL(10,2)` | NULL | Lo contado por el empleado al cerrar. |
| `DIFERENCIA` | `DECIMAL(10,2)` | NULL | `SALDO_REAL - SALDO_ESPERADO` (0 = cuadra). |
| `ESTADO` | `VARCHAR(10)` | NOT NULL, DEFAULT `'ABIERTO'`, CHECK `IN ('ABIERTO','CERRADO')` | Estado del turno. |

> **Nota de diseño:** `ESTADO` es `VARCHAR(10)` con `CHECK`, no `ENUM` como el
> resto del esquema. Funciona igual, pero es el único caso así.
>
> El `CREATE` usa `IF NOT EXISTS` (el único del esquema), así que reimportar no
> falla.

## Procedimientos almacenados

### `SP_ABRIR_TURNO(P_CAJA, P_ID_EMPLEADO, P_MONTO_INICIAL)`

**Usada por la app** (`caja.cpp`).

- Caja nula o vacía → `ERROR: INGRESE EL NOMBRE DE LA CAJA.`
- Monto inicial nulo o negativo → `ERROR: EL MONTO INICIAL NO PUEDE SER NEGATIVO.`
- Ya hay un turno `ABIERTO` en esa caja →
  `ERROR: YA HAY UN TURNO ABIERTO EN ESTA CAJA. CIERRELO ANTES DE ABRIR OTRO.`
- Inserta el turno y devuelve
  `EXITO: TURNO #<id> ABIERTO EN <caja>.`

> **Regla clave: una caja = un turno abierto a la vez.** El control es lógico
> (no hay índice único parcial que lo garantice); dos aperturas simultáneas
> podrían colarse. No valida que el empleado exista (FK, error técnico `1452`).

### `SP_ESTADO_TURNO(P_CAJA)`

**Usada por la app.** Solo lectura.

- Sin turno abierto → una fila
  `ESTADO_TURNO = 'SIN TURNO'`, `CAJA = <caja>`.
- Con turno abierto → `ID_TURNO`, `CAJA`, `ESTADO_TURNO = 'ABIERTO'`,
  `FECHA_APERTURA`, `MONTO_INICIAL`, `EMPLEADO_APERTURA`, y dos cálculos vivos
  sobre `PAGOS` entre `FECHA_APERTURA` y `NOW()`:
  `COBRADO_HASTA_AHORA` y `SALDO_ESPERADO_VIVO` (`monto inicial + cobrado`,
  con `IFNULL(..., 0)`).

> El cobrado se calcula **sobre todos los pagos del período**, no sobre los de
> esa caja ni los de ese empleado: `PAGOS` no tiene columna de caja ni de turno.
> Con una sola caja operando es correcto; **con dos cajas abiertas a la vez,
> cada turno suma los cobros de la otra**. Es la limitación estructural del
> diseño (el comentario del archivo lo asume: "los pagos se anotan al turno por
> su fecha/hora").

### `SP_CERRAR_TURNO(P_ID_TURNO, P_SALDO_REAL, P_ID_EMPLEADO_CIERRE)`

**Usada por la app.** Cierra y cuadra.

- Turno inexistente → `ERROR: NO EXISTE ESE TURNO.`
- Ya cerrado → `ERROR: ESE TURNO YA ESTA CERRADO.`
- Saldo real nulo o negativo → `ERROR: EL CIERRE REAL NO PUEDE SER NEGATIVO.`
- Calcula `SALDO_ESPERADO = MONTO_INICIAL + IFNULL(SUM(PAGOS en ventana), 0)`,
  actualiza `ID_EMPLEADO_CIERRE`, `FECHA_CIERRE`, `SALDO_ESPERADO`,
  `SALDO_REAL`, `DIFERENCIA = real - esperado` y `ESTADO = 'CERRADO'`.

Devuelve **2 result sets**:
1. `MENSAJE` con el cuadre: `EXITO: TURNO #<id> CERRADO. CUADRA.` /
   `... FALTA $<n>.` / `... SOBRA $<n>.` (la app lee este primero).
2. Resumen: `ID_TURNO`, `CAJA`, `FECHA_APERTURA`, `FECHA_CIERRE`,
   `EMPLEADO_APERTURA`, `EMPLEADO_CIERRE`, `MONTO_INICIAL`, `SALDO_ESPERADO`,
   `SALDO_REAL`, `DIFERENCIA`.

> No valida que el empleado de cierre exista (FK) ni que sea distinto del de
> apertura. Tampoco abre transacción explícita: el `UPDATE` es una sola
> sentencia, así que el cierre es atómico por sí mismo.

## Reglas de negocio

- **Una caja, un turno abierto** (control lógico en el SP de apertura).
- **Monto inicial y saldo real nunca negativos.**
- **El esperado lo calcula la base:** apertura + cobros de `PAGOS` en la
  ventana `FECHA_APERTURA → NOW()`.
- **`DIFERENCIA = SALDO_REAL - SALDO_ESPERADO`**: 0 cuadra, negativa falta
  plata, positiva sobra.
- **El turno cerrado no se reabre ni se modifica**: los estados solo van
  `ABIERTO → CERRADO`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
