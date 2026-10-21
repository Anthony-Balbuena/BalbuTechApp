# Módulo 12 — VACACIONES_EMPLEADOS

Solicitudes de vacaciones por empleado: rango de fechas y estado
(`PENDIENTE`, `APROBADO`, `RECHAZADO`), con tope de **15 días por año**. No
se solapan con otra solicitud no rechazada del mismo empleado y, si se borra
el empleado, se borran sus vacaciones (`ON DELETE CASCADE`).

**Depende de:** `EMPLEADOS` (8).
**Es consultado por:** `ASISTENCIA_EMPLEADOS` (11) — solo una vacación
`APROBADO` bloquea el registro y la justificación de asistencia.
**La usa la app:** `vacaciones.cpp` — `misVacacionesUI()` para el historial y
la solicitud propia; `gestionarVacacionesUI()` para que RRHH/ADMIN apruebe o
rechace pendientes.

> **Pantallas:** "Mis vacaciones" en el menú principal (permiso
> `SOLICITAR_PERMISO`, el mismo de "Mis permisos") y "17. Gestionar
> vacaciones" dentro del submenú de Empleados (gate `GESTIONAR_EMPLEADOS`).

Fuente: `modulos/12- VACACIONES_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 21/10/2026.

## Tablas

### VACACIONES_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_VACACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` **ON DELETE CASCADE** | Empleado. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Primer día. |
| `FECHA_FIN` | `DATE` | NOT NULL | Último día (inclusive). |
| `ESTADO` | `ENUM('PENDIENTE','APROBADO','RECHAZADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado de la solicitud. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta del registro. |

**Restricción:** `CK_FECHAS_VACACIONES` → `FECHA_FIN >= FECHA_INICIO`.

> **Ojo con el borrado:** la FK es `ON DELETE CASCADE`. Borrar un empleado
> borra su historial de vacaciones; la app no borra empleados (los
> desactiva), pero un `DELETE` manual se lleva todo.

## Procedimientos almacenados

### `SP_SOLICITAR_VACACIONES(P_ID_EMPLEADO, P_FECHA_INICIO, P_FECHA_FIN)`

Único camino de alta. Reemplaza al viejo `SP_INSERTAR_VACACIONES`, que ya no
existe. Toda solicitud nace **`PENDIENTE`**.

**Validaciones en orden (`SIGNAL 45000`):**
1. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
2. inicio anterior a hoy → `ERROR: NO PUEDES SOLICITAR VACACIONES EN EL PASADO.`
3. fin menor que inicio →
   `ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.`
4. solapamiento con otra solicitud **no `RECHAZADO`** (tres cruces: inicio
   dentro, fin dentro, o la nueva envuelve a la vieja) →
   `ERROR: EL EMPLEADO YA TIENE VACACIONES PENDIENTES O APROBADAS EN ESE RANGO.`
5. límite anual: días **no rechazados** del año de `FECHA_INICIO` + días
   pedidos (`DATEDIFF + 1`, extremos inclusive) > 15 →
   `ERROR: EL EMPLEADO SUPERA EL LÍMITE DE 15 DÍAS POR AÑO.`

Inserta `PENDIENTE` y devuelve
`EXITO: SOLICITUD DE VACACIONES CREADA PARA "<nombre>" (ID: <id>) DEL <inicio> AL <fin>. QUEDA PENDIENTE DE APROBACION.`

> No valida que el empleado esté `ACTIVO` (se pueden cargar vacaciones a un
> inactivo).

### `SP_GESTIONAR_VACACION(P_ID_VACACION, P_NUEVO_ESTADO)`

Aprueba o rechaza una solicitud **pendiente**. `P_NUEVO_ESTADO` es
`ENUM('APROBADO','RECHAZADO')`.

Validaciones en orden (`SIGNAL 45000`):

1. ID inexistente → `ERROR: VACACION NO ENCONTRADA.`
2. estado actual distinto de `PENDIENTE` →
   `ERROR: SOLO SE PUEDEN GESTIONAR VACACIONES PENDIENTES.`
3. estado nuevo `NULL` →
   `ERROR: ESTADO NO VALIDO. SOLO SE PUEDE APROBAR O RECHAZAR.`

Si pasa, actualiza con `AND ESTADO = 'PENDIENTE'` y verifica `ROW_COUNT()`: si
otra gestión la resolvió entre el `SELECT` y el `UPDATE`, también falla con
"solo pendientes". Devuelve
`EXITO: VACACION ID <id> ACTUALIZADA A ESTADO: <estado>`.

> **Una sola resolución:** la app lista solo pendientes y el SP también las
> bloquea; el `UPDATE ... AND ESTADO = 'PENDIENTE'` + `ROW_COUNT()` cubre la
> carrera entre dos gestiones.
>
> **Quién gestiona:** el SP no sabe quién llama. El control lo hace la app con
> el gate `GESTIONAR_EMPLEADOS` del submenú de Empleados.

### `SP_LISTAR_VACACIONES_PENDIENTES()`

Sin parámetros. Devuelve `ID_VACACION`, `ID_EMPLEADO`, `NOMBRE` (del
empleado), `FECHA_INICIO`, `FECHA_FIN` y `FECHA_REGISTRO` de todo lo que está
`PENDIENTE`, ordenado por `FECHA_REGISTRO ASC, ID_VACACION ASC` (la primera
que llegó se atiende primero). Es la lista que consume la pantalla de gestión
de RRHH.

### `SP_HISTORIAL_VACACIONES_EMPLEADO(P_ID_EMPLEADO)`

Lista `FECHA_INICIO, FECHA_FIN, ESTADO, FECHA_REGISTRO` del empleado, de la
solicitud más reciente a la más antigua. La usa `misVacacionesUI()` para
refrescar el historial propio después de cada solicitud.

### `SP_ACTUALIZAR_VACACIONES(P_ID_VACACION, P_NUEVA_INICIO, P_NUEVA_FIN)`

Registro inexistente → `ERROR: REGISTRO DE VACACIONES NO ENCONTRADO.`
Estado distinto de `PENDIENTE` →
`ERROR: SOLO SE PUEDEN MODIFICAR VACACIONES PENDIENTES.`
Ya terminadas (`FECHA_FIN < CURDATE()`) →
`ERROR: NO SE PUEDEN MODIFICAR VACACIONES QUE YA TERMINARON.`
Fechas efectivas invertidas (combinando lo enviado y lo actual) →
`ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.`

Actualiza con `COALESCE` (NULL conserva) y repite `AND ESTADO = 'PENDIENTE'`
como guarda atómica. Devuelve
`EXITO: VACACIONES (ID: <id>) ACTUALIZADAS CORRECTAMENTE PARA EL EMPLEADO ID: <id>.`

> La UI no edita vacaciones; el SP igual protege las aprobadas y rechazadas.
>
> **Hueco conocido:** la actualización **no re-valida el solapamiento** con
> otras vacaciones (el alta sí). El tope de 15 días sí se re-valida por el
> trigger `TR_VALIDAR_LIMITE_VACACIONES_UPDATE`.

### `SP_REPORTE_DIAS_CONSUMIDOS(P_ID_EMPLEADO)`

Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.` Devuelve una fila:
`NOMBRE`, `TOTAL_DIAS_TOMADOS` (solo vacaciones **`APROBADO`** del año actual),
`DIAS_RESTANTES` (`15 - tomados`) y `ESTATUS_VACACIONES`: `DISPONIBLE` o
`EXCEDE LÍMITE` (si el saldo es negativo).

> El reporte mide días **tomados**; el tope del alta mide días **reservados**
> (pendientes + aprobadas). Por eso una pendiente descuenta cupo en el alta
> pero todavía no aparece en este reporte.

### `SP_VALIDAR_CUPO_VACACIONES(P_CARGO, OUT P_DISPONIBLE)`

Valida la regla de cobertura por cargo: no dejar más de la mitad del personal
del cargo de vacaciones al mismo tiempo. Solo cuentan las vacaciones
**`APROBADO`**.

- Cargo sin empleados → `ERROR: CARGO NO ENCONTRADO O SIN EMPLEADOS ASIGNADOS.`
- Calcula `P_DISPONIBLE = ((ausentes_hoy + 1) <= total_cargo / 2)`.

> **Nota:** el total del cargo cuenta **todos** los empleados, incluidos los
> `INACTIVO`, porque no filtra por `ESTADO`. Si hay muchos inactivos en el
> cargo, el cupo queda más restrictivo de lo que debería.
>
> Es un `OUT BOOLEAN`: el cliente lo lee como parámetro de salida, no como
> result set.

### `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES()`

Lista los empleados con vacaciones **`APROBADO`** hoy, con cargo, fechas y
`DIAS_PARA_RETORNAR = DATEDIFF(FECHA_FIN, CURDATE())`, ordenados por fecha de
fin. Si no hay nadie, devuelve 0 filas (no es error).

## Triggers

### `TR_VALIDAR_LIMITE_VACACIONES`

`BEFORE INSERT`. Suma los días **no rechazados** ya cargados en el **año de
`NEW.FECHA_INICIO`** + los nuevos; si supera 15 →
`ERROR: VACACIONES DENEGADAS. EL EMPLEADO EXCEDERÍA EL LÍMITE DE 15 DÍAS ANUALES.`

### `TR_VALIDAR_LIMITE_VACACIONES_UPDATE`

`BEFORE UPDATE`. Misma cuenta (solo no rechazadas), **excluyendo la propia
fila** (`ID_VACACION <> NEW.ID_VACACION`), para que editar un registro no se
cuente dos veces. Mismo mensaje de error.

> Los dos triggers son la red de seguridad para altas/ediciones por SQL
> directo; el SP de alta valida lo mismo con mensajes más específicos.

## Flujo y UI

1. **Solicitud (empleado):** "Mis vacaciones" en el menú principal. La app
   obtiene el `ID_EMPLEADO` desde `USUARIOS.ID_EMPLEADO` usando el usuario de
   la sesión (si el usuario no está vinculado, avisa y no deja pedir). Muestra
   el historial con `SP_HISTORIAL_VACACIONES_EMPLEADO` y ofrece "Nueva
   solicitud": fecha inicio y fecha fin (`YYYY-MM-DD`). Llama a
   `SP_SOLICITAR_VACACIONES`, muestra `MENSAJE` o el error SQL y refresca el
   historial. No edita ni borra.
2. **Gestión (RRHH/ADMIN):** "Empleados" → "17. Gestionar vacaciones". Lista
   los pendientes con `SP_LISTAR_VACACIONES_PENDIENTES`, pide el ID y la
   acción (1 aprobar / 2 rechazar), llama a `SP_GESTIONAR_VACACION` y muestra
   `MENSAJE` o el error SQL. Repite hasta que el usuario elige 0. Una
   solicitud ya resuelta vuelve a fallar con "solo se pueden gestionar
   vacaciones pendientes": no hay doble resolución.
3. **Efecto en asistencia (módulo 11):** una vacación **`APROBADO`** que cubre
   la fecha bloquea el registro y la justificación de asistencia. Una
   `PENDIENTE` o `RECHAZADO` no bloquea.

## Reglas de negocio

- **Máximo 15 días por año** (contados con `DATEDIFF + 1`, extremos
  inclusive), por SP y por trigger. Reservan las pendientes y las aprobadas;
  las rechazadas liberan cupo.
- **Sin solapamiento** con vacaciones pendientes o aprobadas (las rechazadas
  no bloquean).
- **No se solicitan vacaciones en el pasado** (alta).
- **No se editan vacaciones aprobadas, rechazadas ni terminadas**; la UI no
  edita.
- **Estados:** `PENDIENTE` (default), `APROBADO`, `RECHAZADO`.
- **Una sola resolución**: solo una solicitud `PENDIENTE` pasa a `APROBADO` o
  `RECHAZADO`; el SP no permite volver a gestionarla.
- **Cobertura por cargo:** no más de la mitad del personal de vacaciones a la
  vez (solo aprobadas).
- **Solo las vacaciones aprobadas bloquean la asistencia** (módulo 11).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
