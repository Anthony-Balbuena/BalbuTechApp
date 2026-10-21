# Módulo 13 — PERMISOS_EMPLEADOS

Solicitudes de permiso por empleado: tipo (`MEDICO`, `PERSONAL`, `ESTUDIO`,
`LICENCIA`, `SIN_SUELDO`), rango de fechas, descripción y estado
(`PENDIENTE`, `APROBADO`, `RECHAZADO`). No se cruzan con otro permiso no
rechazado del mismo empleado.

**Depende de:** `EMPLEADOS` (8).
**Es consultado por:** `ASISTENCIA_EMPLEADOS` (11) — un permiso `APROBADO`
bloquea el registro de asistencia.
**La usa la app:** `permisos.cpp` — `misPermisosUI()` para el historial y el
alta propia; `gestionarPermisosUI()` para que RRHH/ADMIN resuelva pendientes.

> **Pantallas:** "Mis permisos" en el menú principal (permiso
> `SOLICITAR_PERMISO`) y "16. Gestionar permisos" dentro del submenú de
> Empleados (gate `GESTIONAR_EMPLEADOS`).

Fuente: `modulos/13- PERMISOS_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 21/10/2026.

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

### `SP_LISTAR_PERMISOS_PENDIENTES()`

Sin parámetros. Devuelve `ID_PERMISO`, `ID_EMPLEADO`, `NOMBRE` (del empleado),
`TIPO_PERMISO`, `FECHA_INICIO`, `FECHA_FIN`,
`IFNULL(DESCRIPCION,'') AS DESCRIPCION` y `FECHA_SOLICITUD` de todo lo que está
`PENDIENTE`, ordenado por `FECHA_SOLICITUD ASC, ID_PERMISO ASC` (el ID
desempata solicitudes de la misma fecha). Es la lista que consume la
pantalla de gestión de RRHH.

### `SP_GESTIONAR_PERMISO(P_ID_PERMISO, P_NUEVO_ESTADO)`

Resuelve una solicitud **pendiente**. Validaciones en orden (`SIGNAL 45000`):

1. ID inexistente → `ERROR: PERMISO NO ENCONTRADO.`
2. estado actual distinto de `PENDIENTE` →
   `ERROR: SOLO SE PUEDEN GESTIONAR PERMISOS PENDIENTES.`
3. estado nuevo `NULL` o distinto de `APROBADO` o `RECHAZADO` →
   `ERROR: ESTADO NO VALIDO. SOLO SE PUEDE APROBAR O RECHAZAR.`

Si pasa, actualiza con `AND ESTADO = 'PENDIENTE'` y verifica
`ROW_COUNT()`: si otra gestión lo resolvió entre el `SELECT` y el `UPDATE`,
también falla con "solo pendientes". Devuelve
`EXITO: PERMISO ID <id> ACTUALIZADO A ESTADO: <estado>`.

> **Una sola resolución:** la app filtra los ya resueltos (la lista de
> `SP_LISTAR_PERMISOS_PENDIENTES` solo trae `PENDIENTE`) y el SP también los
> bloquea: el `SELECT` previo corta el caso normal y el `UPDATE ... AND
> ESTADO = 'PENDIENTE'` + `ROW_COUNT()` cubre la carrera entre dos gestiones.
> El parámetro sigue siendo `ENUM` (acepta `PENDIENTE` a nivel de tipo), pero
> el SP lo rechaza en la validación 3; un `NULL` también cae ahí con el
> mensaje amigable.
>
> **Quién gestiona:** el SP no sabe quién llama. El control lo hace la app con
> el gate `GESTIONAR_EMPLEADOS` del submenú de Empleados. El trigger del
> módulo 30 registra el antes/después, **no el actor**.

### `SP_HISTORIAL_PERMISOS_EMPLEADO(P_ID_EMPLEADO)`

Lista `TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, ESTADO, DESCRIPCION` del
empleado, del más reciente al más antiguo. La usa `misPermisosUI()` para
refrescar el historial propio después de cada alta.

## Flujo y UI

1. **Solicitud (empleado):** "Mis permisos" en el menú principal. La app
   obtiene el `ID_EMPLEADO` desde `USUARIOS.ID_EMPLEADO` usando el usuario de la
   sesión (si el usuario no está vinculado, avisa y no deja pedir). Muestra el
   historial con `SP_HISTORIAL_PERMISOS_EMPLEADO` y ofrece "Nueva solicitud":
   tipo (1 `MEDICO`, 2 `PERSONAL`, 3 `ESTUDIO`, 4 `LICENCIA`, 5 `SIN_SUELDO`),
   fecha inicio, fecha fin (`YYYY-MM-DD`) y descripción. Llama a
   `SP_SOLICITAR_PERMISO`, muestra `MENSAJE` o el error SQL y refresca el
   historial. No edita ni borra.
2. **Gestión (RRHH/ADMIN):** "Empleados" → "16. Gestionar permisos". Lista los
   pendientes con `SP_LISTAR_PERMISOS_PENDIENTES`, pide el ID y la acción
   (1 aprobar / 2 rechazar), llama a `SP_GESTIONAR_PERMISO` y muestra
   `MENSAJE` o el error SQL. Repite hasta que el usuario elige 0. Un permiso
   ya resuelto vuelve a fallar con "solo se pueden gestionar permisos
   pendientes": no hay doble resolución.
3. **Efecto:** un permiso `APROBADO` que cubre hoy bloquea el registro y la
   justificación de asistencia (módulo 11). Uno `RECHAZADO` no bloquea.

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
- **Una sola resolución**: solo un permiso `PENDIENTE` pasa a `APROBADO` o
  `RECHAZADO`; el SP no permite volver a gestionarlo.
- **Un permiso aprobado bloquea la asistencia** del día (módulo 11).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
