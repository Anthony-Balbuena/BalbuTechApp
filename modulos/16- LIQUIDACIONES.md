# Módulo 16 — LIQUIDACIONES

Liquidaciones de salida de empleados: fecha, años trabajados, salario base,
monto, motivo (`RENUNCIA`, `DESPIDO`, `FIN_CONTRATO`, `DESAHUCIO`) y
observación. Registrar una liquidación **inactiva al empleado** en la misma
transacción.

**Depende de:** `EMPLEADOS` (8).
**Dispara:** al pasar el empleado a `INACTIVO`, los triggers de los módulos 10
(bloqueo de usuario) y 15 (historial laboral) se ejecutan en la misma
transacción.

> **La app no consume este módulo todavía** (no hay `CALL` en el C++).

Fuente: `modulos/16- LIQUIDACIONES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### LIQUIDACIONES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LIQUIDACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` **ON DELETE CASCADE** | Empleado. |
| `FECHA_LIQUIDACION` | `DATE` | NOT NULL | Fecha de salida. |
| `ANIOS_TRABAJADOS` | `INT` | NULL | Años computados (el trigger exige > 0 al insertar). |
| `SALARIO_BASE` | `DECIMAL(10,2)` | NOT NULL | Salario sobre el que se calcula. |
| `MONTO_LIQUIDACION` | `DECIMAL(10,2)` | NOT NULL | Monto calculado. |
| `MOTIVO` | `ENUM('RENUNCIA','DESPIDO','FIN_CONTRATO','DESAHUCIO')` | NOT NULL | Motivo de salida. |
| `OBSERVACION` | `VARCHAR(200)` | NULL | Nota; **el único campo editable** después del alta. |

**Índices:** `IX_LIQUIDACION_EMPLEADO`, `IX_LIQUIDACION_FECHA`,
`IX_LIQUIDACION_MOTIVO`.

## Procedimientos almacenados

### `SP_REGISTRAR_LIQUIDACION(P_ID_EMPLEADO, P_FECHA, P_ANIOS, P_SALARIO, P_MOTIVO, P_OBSERVACION)`

**Manejo transaccional:** si no hay transacción abierta (`@@in_transaction =
0`) abre una propia y la cierra con `COMMIT`; si hay una externa, no la
cierra. Un `EXIT HANDLER FOR SQLEXCEPTION` hace `ROLLBACK` solo si la
transacción es propia y re-lanza el error (`RESIGNAL`).

**Validaciones:**
- empleado inexistente o **no `ACTIVO`** →
  `ERROR: EL EMPLEADO NO ESTA ACTIVO O NO EXISTE.`
- motivo fuera del ENUM → `ERROR: MOTIVO DE LIQUIDACION DESCONOCIDO.`

**Cálculo:** `MONTO_LIQUIDACION = SALARIO * ANIOS`.

**Efectos:** inserta la liquidación y actualiza `EMPLEADOS.ESTADO =
'INACTIVO'` (lo que dispara, en la misma transacción, el bloqueo de usuario y
el historial laboral). Devuelve
`EXITO: LIQUIDACION DE $<monto> PROCESADA.`

> **El cálculo es un placeholder:** un mes de salario por año trabajado,
> **no** la Ley 16-92. El comentario del archivo lo dice explícitamente
> ("puedes ajustarla"). Antes de usar esto en producción hay que reemplazar la
> fórmula.
>
> No valida `P_ANIOS` ni `P_SALARIO`: lo hace el trigger de inserción
> (`> 0`), con mensajes propios.

## Triggers

### `TR_VALIDAR_LIQUIDACION`

`BEFORE INSERT`. Exige, con `IFNULL` (un `NULL` también se rechaza):
- `ANIOS_TRABAJADOS > 0` →
  `ERROR: LOS ANIOS TRABAJADOS DEBEN SER MAYORES A CERO.`
- `SALARIO_BASE > 0` → `ERROR: EL SALARIO BASE DEBE SER MAYOR A CERO.`
- `MONTO_LIQUIDACION > 0` →
  `ERROR: EL MONTO DE LA LIQUIDACION DEBE SER MAYOR A CERO.`

### `TR_BLOQUEAR_CAMBIO_LIQUIDACION`

`BEFORE UPDATE`. Una liquidación guardada **no cambia** en empleado, fecha,
años, salario, monto ni motivo:
`ERROR: LA LIQUIDACION GUARDADA NO CAMBIA (SOLO LA OBSERVACION).`
Solo se puede editar `OBSERVACION`.

### `16_TR_BLOQUEAR_BORRADO_LIQUIDACION`

`BEFORE DELETE`. Bloquea cualquier borrado:
`ERROR: PROHIBIDO BORRAR LIQUIDACIONES. POR AUDITORIA LEGAL, SOLO SE PUEDEN ANULAR O MODIFICAR MEDIANTE SP.`

> Es un bloqueo duro: ni siquiera `ON DELETE CASCADE` puede borrar
> liquidaciones al borrar un empleado (el `DELETE` del empleado fallaría si
> tiene liquidaciones). Es intencional por auditoría legal.

## Vistas

### `VISTA_ESTADISTICAS_SALIDAS`

Agrupa por `MOTIVO`: `TOTAL_SALIDAS` y `COSTO_TOTAL_PRESTACIONES`
(`SUM(MONTO_LIQUIDACION)`).

### `VISTA_LIQUIDACIONES_RECIENTES`

Liquidaciones de los **últimos 30 días**: `ID_LIQUIDACION`, `EMPLEADO`,
`FECHA_LIQUIDACION`, `MONTO_LIQUIDACION`, `MOTIVO` y
`DIAS_DESDE_LIQUIDACION`, de la más reciente a la más antigua.

## Reglas de negocio

- **Solo se liquida a un empleado `ACTIVO`.**
- **Registrar liquidación lo deja `INACTIVO`** (transacción atómica con el
  insert).
- **Años, salario y monto deben ser > 0** (trigger).
- **La liquidación es inmutable** salvo la observación; **no se borra**.
- **Cálculo actual = salario × años** (placeholder, no ley laboral).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
