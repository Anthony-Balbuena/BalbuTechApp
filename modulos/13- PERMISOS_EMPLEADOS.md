# Módulo 13 — PERMISOS_EMPLEADOS

Solicitudes de permiso por empleado: tipo (`MEDICO`, `PERSONAL`, `ESTUDIO`,
`LICENCIA`, `SIN_SUELDO`), rango de fechas, descripción y estado
(`PENDIENTE`, `APROBADO`, `RECHAZADO`). No se cruzan con otro permiso no
rechazado del mismo empleado.

**Depende de:** `EMPLEADOS` (8).
**Es consultado por:** `ASISTENCIA_EMPLEADOS` (11) — un permiso `APROBADO`
bloquea el registro de asistencia.
**La usa la app:** `permisos.cpp` — `misPermisosUI()` para el historial y el
alta propia; `gestionarPermisosUI()` para que RRHH/ADMIN resuelva pendientes;
`verAuditoriaPermisosUI()` para leer la bitácora de cambios.

> **Pantallas:** "Mis permisos" en el menú principal (permiso
> `SOLICITAR_PERMISO`) y "Gestionar permisos" + "Ver auditoría de permisos"
> dentro del submenú de Empleados (las dos con `GESTIONAR_PERMISOS_EMPLEADO`).

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
> el gate `GESTIONAR_PERMISOS_EMPLEADO` del submenú de Empleados. Quién resolvió
> la solicitud queda en `LOG_AUDITORIA_PERMISOS` (`TR_LOG_PERMISO_CAMBIO_ESTADO`,
> más abajo).

### `SP_HISTORIAL_PERMISOS_EMPLEADO(P_ID_EMPLEADO)`

Lista `TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, ESTADO, DESCRIPCION` del
empleado, del más reciente al más antiguo. La usa `misPermisosUI()` para
refrescar el historial propio después de cada alta.

## Auditoría: `LOG_AUDITORIA_PERMISOS`

Bitácora de todo lo que pasa con un permiso de empleado: `ALTA`,
`CAMBIO_ESTADO` o `BAJA`, con el estado anterior y el nuevo, cuándo y quién.
Vive en este módulo porque es la bitácora de `PERMISOS_EMPLEADOS`.

### Tabla

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LOG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PERMISO` | `INT` | NULL, FK → `PERMISOS_EMPLEADOS` **ON DELETE SET NULL** | Permiso afectado. |
| `ID_EMPLEADO` | `INT` | NULL | Dueño del permiso. Sobrevive al borrado. |
| `TIPO_PERMISO` | `VARCHAR(20)` | NULL | `MEDICO`, `PERSONAL`, … Idem. |
| `ACCION` | `VARCHAR(20)` | NOT NULL | `ALTA`, `CAMBIO_ESTADO`, `BAJA`. |
| `ESTADO_ANTERIOR` | `VARCHAR(20)` | NULL | Estado previo (`NULL` en un alta). |
| `ESTADO_NUEVO` | `VARCHAR(20)` | NULL | Estado nuevo (`NULL` en una baja). |
| `FECHA_CAMBIO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ID_USUARIO_ADMIN` | `INT` | NULL, FK → `USUARIOS` **ON DELETE SET NULL** | Quién lo hizo. |

> **`ON DELETE SET NULL` a propósito**: borrar un permiso **no** destruye su
> bitácora (antes era `CASCADE`).
>
> **Por qué `ID_EMPLEADO` y `TIPO_PERMISO` están acá** si se pueden sacar del
> permiso: porque `ID_PERMISO` pasa a `NULL` cuando se borra el permiso. Esas
> dos columnas son lo único que después sigue diciendo de quién era.
>
> **`VARCHAR(20)` en vez del `ENUM` de origen**: si mañana el estado se alarga,
> acá no rompe, pero tampoco hay validación.

### Cómo se actualiza una base que ya tenía la tabla vieja

El módulo trae un bloque idempotente que pregunta cada cambio a
`INFORMATION_SCHEMA` antes de hacerlo: agrega `ID_EMPLEADO`, `TIPO_PERMISO`,
`ACCION` e `ID_USUARIO_ADMIN` si faltan, rellena `ACCION` con
`'CAMBIO_ESTADO'` (las filas viejas solo podían venir de un `UPDATE`), recupera
`ID_EMPLEADO`/`TIPO_PERMISO` por `JOIN` donde el permiso todavía existe, y recién
después pasa `ACCION` a `NOT NULL`. Las filas que ya perdieron su permiso no se
pueden reconstruir: quedan en `NULL`.

### Triggers

| Trigger | Evento | Qué escribe |
|---|---|---|
| `TR_LOG_PERMISO_ALTA` | `AFTER INSERT` | `ALTA`, estado anterior `NULL` |
| `TR_LOG_PERMISO_CAMBIO_ESTADO` | `AFTER UPDATE` | solo si cambia `ESTADO`; antes y después |
| `TR_LOG_PERMISO_BAJA` | `AFTER DELETE` | `BAJA`, estado nuevo `NULL` |

El `DELETE` inserta con `ID_PERMISO = NULL` a propósito: la fila del permiso ya
no existe y la FK rechazaría la escritura —y con ella abortaría el `DELETE`.

**El actor** sale de `@ID_USUARIO_ACTUAL`, resuelto con
`SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL)`.
Si no hay sesión, el `SELECT` no devuelve fila y queda `NULL` (es el mismo
patrón de `LOG_USUARIOS`, módulo 29).

**Los triggers nunca abortan el cambio.** Corren dentro del `INSERT`/`UPDATE`/
`DELETE` de `PERMISOS_EMPLEADOS`: si fallaran, se caería la escritura del
permiso. Por eso el actor es `NULL` y no un `SIGNAL`.

### Vista

`VIEW_HISTORIAL_PERMISOS` traduce ids a nombres: empleado afectado, tipo,
acción, antes/después, fecha y usuario que lo hizo. `LEFT JOIN` en todo, para
que el registro se siga leyendo aunque el permiso, el empleado o el usuario ya
no existan.

### Lectores paginados

| `SP` | Qué hace | Permiso |
|---|---|---|
| `SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO(P_PAGINA, P_POR_PAGINA)` | una página del historial, de lo más reciente a lo más viejo | `GESTIONAR_PERMISOS_EMPLEADO` |
| `SP_CONTAR_AUDITORIA_PERMISOS()` | total, para el "Página 1 de N" | `GESTIONAR_PERMISOS_EMPLEADO` |

Los dos llevan la guarda `CALL SP_EXIGIR_PERMISO(...)` escrita a mano (como el
21 y el 63): `db/injectar-guardas.py` la saltea si ya está. `EXIGIR = 1`,
igual que el resto de las rutinas mapeadas.

El mapeo rutina → permiso vive en `db/mapear-permisos.sql`, no en este módulo:
`PERMISO_POR_RUTINA` la crea el módulo 66, que se importa después, así que un
`INSERT` acá fallaría en una instalación nueva.

**No hay permiso nuevo**: la pantalla se abre con `GESTIONAR_PERMISOS_EMPLEADO`,
el mismo con el que se aprueba y rechaza (ADMIN, GERENTE, RRHH). Separar
"aprobar" de "auditar" es aditivo y se puede hacer después sin migrar datos.

### Pantalla

"Empleados" → "Ver auditoría de permisos". Lista paginada de 10 en 10 con
`FECHA · ACCIÓN · EMPLEADO · TIPO · ESTADO (antes > después) · QUIÉN`. Es de
solo lectura: la app no edita ni borra la bitácora. `(sin sesión)` marca los
cambios hechos por SQL a mano y `(empleado borrado)` los que perdieron el
empleado.

## Flujo y UI

1. **Solicitud (empleado):** "Mis permisos" en el menú principal. La app
   obtiene el `ID_EMPLEADO` desde `USUARIOS.ID_EMPLEADO` usando el usuario de la
   sesión (si el usuario no está vinculado, avisa y no deja pedir). Muestra el
   historial con `SP_HISTORIAL_PERMISOS_EMPLEADO` y ofrece "Nueva solicitud":
   tipo (1 `MEDICO`, 2 `PERSONAL`, 3 `ESTUDIO`, 4 `LICENCIA`, 5 `SIN_SUELDO`),
   fecha inicio, fecha fin (`YYYY-MM-DD`) y descripción. Llama a
   `SP_SOLICITAR_PERMISO`, muestra `MENSAJE` o el error SQL y refresca el
   historial. No edita ni borra.
2. **Gestión (RRHH/ADMIN):** "Empleados" → "Gestionar permisos". Lista los
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
- **Los tres eventos dejan fila** en la bitácora, con el actor cuando hay
  sesión; cambiar algo que no es el estado no registra nada.
- **La bitácora sobrevive** al borrado del permiso, del empleado y del usuario.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
