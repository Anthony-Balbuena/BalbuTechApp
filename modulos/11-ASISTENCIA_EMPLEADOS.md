# Módulo 11 — ASISTENCIA_EMPLEADOS

Asistencia diaria por empleado: un registro por día con hora de entrada,
hora de salida, horas trabajadas (calculadas solas) y estado
(`PRESENTE`, `AUSENTE`, `TARDE`, `PERMISO`).

**Depende de:** `EMPLEADOS` (8), `VACACIONES_EMPLEADOS` (12) y
`PERMISOS_EMPLEADOS` (13) — estas dos últimas solo se consultan dentro de los
SP y del trigger.
**Es usado por:** liquidaciones (16) y reportes de RRHH.

Fuente: `modulos/11-ASISTENCIA_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### ASISTENCIA_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_ASISTENCIA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Empleado. |
| `FECHA` | `DATE` | NOT NULL | Día de la marcación. |
| `HORA_ENTRADA` | `TIME` | NOT NULL | Hora de entrada. |
| `HORA_SALIDA` | `TIME` | NULL | Hora de salida; `NULL` mientras no cierra. |
| `HORAS_TRABAJADAS` | `DECIMAL(5,2)` | **GENERATED ALWAYS ... STORED** | `TIMESTAMPDIFF(MINUTE, entrada, salida) / 60`; `NULL` si no hay salida. |
| `ESTADO` | `ENUM('PRESENTE','AUSENTE','TARDE','PERMISO')` | NOT NULL, DEFAULT `'PRESENTE'` | Estado del día. |
| `OBSERVACION` | `VARCHAR(200)` | NULL | Motivo de justificación. |

**Restricción:** `UQ_ASISTENCIA_DIA` UNIQUE (`ID_EMPLEADO`, `FECHA`): un
registro por empleado por día.

**Índices:** `IX_ASISTENCIA_FECHA`, `IX_ASISTENCIA_ESTADO` e
`IX_ASISTENCIA_EMPLEADO`.

> `IX_ASISTENCIA_EMPLEADO` es redundante: el `UNIQUE (ID_EMPLEADO, FECHA)` ya
> cubre los accesos por `ID_EMPLEADO` como prefijo. No molesta; candidato a
> limpieza.

> `HORAS_TRABAJADAS` es columna generada `STORED`: no se escribe a mano; se
> recalcula al setear `HORA_SALIDA`. Si la salida es anterior a la entrada,
> el resultado queda negativo (no hay validación de orden).

## Procedimientos almacenados

### `SP_REGISTRAR_ASISTENCIA(P_ID_EMPLEADO, P_TIPO_MOVIMIENTO)`

**Usada por la app** (`empleados.cpp`). `P_TIPO_MOVIMIENTO` es
`ENUM('ENTRADA','SALIDA')`.

**Bloqueos previos (para ambos movimientos):**
- permiso `APROBADO` que cubra hoy →
  `ERROR: EMPLEADO CON PERMISO APROBADO. NO REQUIERE REGISTRO DE ASISTENCIA.`
- vacaciones que cubran hoy →
  `ERROR: EMPLEADO DE VACACIONES. NO REQUIERE REGISTRO DE ASISTENCIA.`

**Entrada:**
- ya hay registro hoy → `ERROR: YA TIENE REGISTRO DE ENTRADA HOY.`
- inserta con `CURDATE()/CURTIME()` y estado **`TARDE` si la hora es mayor a
  `08:30:00`**, si no `PRESENTE`. **La hora tope está hardcodeada en el SP.**

**Salida:**
- sin registro hoy → `ERROR: NO TIENE REGISTRO DE ENTRADA HOY.`
- ya tiene salida → `ERROR: YA TIENE SALIDA REGISTRADA HOY.` (la segunda
  salida no pisa la primera).
- setea `HORA_SALIDA = CURTIME()`.

Devuelve `EXITO: ASISTENCIA REGISTRADA.`

> No valida que el empleado exista: un ID inválido cae en la FK con error
> técnico `1452`.

### `11_SP_REGISTRAR_SALIDA(P_ID_EMPLEADO)`

**La app no la llama** (usa `SP_REGISTRAR_ASISTENCIA` con `'SALIDA'`).
Cierra la jornada de hoy. Mismos errores de "sin entrada" y "ya tiene
salida", pero **sin** los chequeos de vacaciones/permiso.

### `11_SP_JUSTIFICAR_ASISTENCIA(P_ID_EMPLEADO, P_FECHA, P_NUEVO_ESTADO, P_JUSTIFICACION)`

**Usada por la app.** Cambia el estado del día y guarda
`OBSERVACION = 'JUSTIFICACIÓN: <texto>'`. Si no hay registro para esa
fecha → `ERROR: NO EXISTE REGISTRO PARA ESTE EMPLEADO EN LA FECHA.`
Devuelve `EXITO: ASISTENCIA DE ID <id> JUSTIFICADA COMO <estado>`

> **Ojo:** si el día no tiene fila (p. ej. un ausente que nunca marcó), este
> SP no puede justificarlo; habría que insertar la fila primero.

### `11_SP_REPORTE_ASISTENCIA_INDIVIDUAL(P_ID_EMPLEADO, P_FECHA_INICIO, P_FECHA_FIN)`

**Usada por la app.** Devuelve `FECHA, HORA_ENTRADA, HORA_SALIDA,
HORAS_TRABAJADAS, ESTADO` del período, del día más reciente al más antiguo.

### `11_SP_BLOQUEAR_EDICION_ANTIGUA(P_ID_EMPLEADO, P_FECHA)`

**Usada por la app** antes de editar asistencia. Si la fecha es anterior a
`CURRENT_DATE - 7 DAY` →
`ERROR: SEGURIDAD BLOQUEA LA EDICIÓN DE FECHAS SUPERIORES A 7 DÍAS.`
Si está dentro del período devuelve `ACCESO PERMITIDO`.

### `11_SP_RESUMEN_ASISTENCIA_MES(P_ID_EMPLEADO, P_MES)`

**Usada por la app** (asistencia v2, 17/10/2026). `P_MES` es `'AAAA-MM'`
(se compara con `DATE_FORMAT(FECHA, '%Y-%m')`). Devuelve una fila con
`DIAS_MARCADOS`, `HORAS_TOTALES`, `TARDANZAS`, `AUSENCIAS`, `PERMISOS`,
`PRESENCIAS` (0 si no marcó ese mes).

### `11_SP_ASISTENCIA_HOY(P_FECHA)`

**Usada por la app** (asistencia v2). `NULL` = hoy. Lista **todos los
empleados activos** con su estado del día; si no hay fila de asistencia, los
marca **`AUSENTE`** (`LEFT JOIN` + `IFNULL`). Devuelve
`ID_EMPLEADO, NOMBRE, CARGO, ESTADO, HORA_ENTRADA, HORA_SALIDA, HORAS`.

## Triggers

### `TR_BLOQUEAR_ASISTENCIA_INAPROPIADA`

`BEFORE INSERT ON ASISTENCIA_EMPLEADOS`. Bloquea el insert si el empleado
está de vacaciones o tiene permiso `APROBADO` que cubra **`NEW.FECHA`**:
- `ERROR: REGISTRO DENEGADO. EL EMPLEADO SE ENCUENTRA DE VACACIONES.`
- `ERROR: REGISTRO DENEGADO. EL EMPLEADO TIENE UN PERMISO APROBADO.`

> Usa `NEW.FECHA` (no `CURDATE()`): así también bloquea altas retroactivas o
> de otra fecha. Es la red de seguridad para inserts que no pasan por el SP.

## Reglas de negocio

- **Un registro por empleado y día** (UNIQUE).
- **Las horas trabajadas se calculan solas** (columna generada `STORED`).
- **Entrada después de las 08:30 = `TARDE`** (hora tope hardcodeada).
- **No se puede marcar si está de vacaciones o con permiso aprobado.**
- **Segunda entrada/salida del día se rechaza** (no se sobrescribe).
- **Edición limitada a los últimos 7 días** (control de seguridad).
- **Un día sin marcación se reporta como `AUSENTE`** en el listado diario.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
