# Módulo 13 — PERMISOS_EMPLEADOS

Solicitudes de permiso por empleado: tipo (`MEDICO`, `PERSONAL`, `ESTUDIO`,
`LICENCIA`, `SIN_SUELDO`), rango de fechas, descripción y estado
(`PENDIENTE`, `APROBADO`, `RECHAZADO`). No se cruzan con otro permiso no
rechazado del mismo empleado.

**Depende de:** `EMPLEADOS` (8).
**Es consultado por:** `ASISTENCIA_EMPLEADOS` (11) — un permiso `APROBADO`
bloquea el registro de asistencia.

> **La app todavía no consume este módulo**: no hay pantalla de permisos ni
> `CALL` en el C++. Los SP y la vista existen para el cliente actual/futuro y
> para las validaciones de asistencia.

Fuente: `modulos/13- PERMISOS_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### PERMISOS_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PERMISO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Empleado. |
| `TIPO_PERMISO` | `ENUM('MEDICO','PERSONAL','ESTUDIO','LICENCIA','SIN_SUELDO')` | NOT NULL | Tipo de permiso. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Primer día. |
| `FECHA_FIN` | `DATE` | NOT NULL | Último día (inclusive). |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Motivo. |
| `ESTADO` | `ENUM('PENDIENTE','APROBADO','RECHAZADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado de la solicitud. |
| `FECHA_SOLICITUD` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se pidió. |

**Restricción:** `CK_PERMISO_FECHAS` → `FECHA_FIN >= FECHA_INICIO`.

**Índices:** `IX_PERMISO_EMPLEADO` (historial por empleado),
`IX_PERMISO_ESTADO` (pendientes) e `IX_PERMISO_FECHAS`
(`FECHA_INICIO, FECHA_FIN`, calendarios de ausencias).

## Procedimientos almacenados

### `SP_SOLICITAR_PERMISO(P_ID_EMPLEADO, P_TIPO_PERMISO, P_FECHA_INICIO, P_FECHA_FIN, P_DESCRIPCION)`

**Validaciones en orden (`SIGNAL 45000`):**
1. empleado inexistente → `ERROR: EMPLEADO NO EXISTE.`
2. inicio anterior a hoy → `ERROR: NO PUEDES SOLICITAR PERMISOS RETROACTIVOS.`
3. solapamiento con otro permiso **no `RECHAZADO`** (tres cruces: inicio
   dentro, fin dentro, o el nuevo envuelve al viejo) →
   `ERROR: YA TIENES UNA SOLICITUD DE PERMISO PENDIENTE O APROBADA EN ESTAS FECHAS.`

Inserta con la descripción limpia (`TRIM` + colapso de espacios) y devuelve
`EXITO: SOLICITUD DE PERMISO CREADA PARA "<nombre>".`

> **Notas:** no valida que el empleado esté `ACTIVO`; y si `FECHA_FIN <
> FECHA_INICIO`, el SP **no** da un mensaje amigable: lo corta el CHECK de
> tabla con error técnico.
>
> La descripción se limpia con `REGEXP_REPLACE(TRIM(...))` **sin** `IFNULL`:
> si llega `NULL`, el resultado es `NULL` y la columna lo acepta (es
> nullable).

### `SP_GESTIONAR_PERMISO(P_ID_PERMISO, P_NUEVO_ESTADO)`

Cambia el estado a `PENDIENTE`, `APROBADO` o `RECHAZADO`. ID inexistente →
`ERROR: PERMISO NO ENCONTRADO.` Devuelve
`EXITO: PERMISO ID <id> ACTUALIZADO A ESTADO: <estado>`

> No hay validación de transiciones (se puede pasar de `RECHAZADO` a
> `APROBADO` sin problema) ni de quién gestiona: el control de permisos lo
> hace la app.

### `SP_HISTORIAL_PERMISOS_EMPLEADO(P_ID_EMPLEADO)`

Lista `TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, ESTADO, DESCRIPCION` del
empleado, del más reciente al más antiguo.

## Vistas

### `VISTA_PERMISOS_ACTIVOS`

Permisos **`APROBADO`** que cubren **hoy**
(`CURDATE() BETWEEN FECHA_INICIO AND FECHA_FIN`), con `NOMBRE` del empleado,
tipo, fechas y estado. Sirve para ver quién está ausente en este momento.

## Reglas de negocio

- **Sin retroactivos**: el alta exige `FECHA_INICIO >= CURDATE()`.
- **Sin solapamiento** con permisos pendientes o aprobados (los rechazados no
  bloquean).
- **Rango válido** (`FECHA_FIN >= FECHA_INICIO`) por CHECK.
- **Estados**: `PENDIENTE` (default), `APROBADO`, `RECHAZADO`.
- **Un permiso aprobado bloquea la asistencia** del día (módulo 11).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
