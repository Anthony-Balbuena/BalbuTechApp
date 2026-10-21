# Módulo 12 — VACACIONES_EMPLEADOS

Vacaciones por empleado: rango de fechas con tope de **15 días por año**.
No se solapan con otras vacaciones del mismo empleado y, si se borra el
empleado, se borran sus vacaciones (`ON DELETE CASCADE`).

**Depende de:** `EMPLEADOS` (8).
**Es consultado por:** `ASISTENCIA_EMPLEADOS` (11) — tanto el SP de registro
como el trigger de bloqueo miran si el empleado está de vacaciones.

> **La app todavía no consume este módulo**: no hay pantalla de vacaciones ni
> `CALL` en el C++ (los SP existen para el cliente actual/futuro y para las
> validaciones de asistencia).

Fuente: `modulos/12- VACACIONES_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### VACACIONES_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_VACACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` **ON DELETE CASCADE** | Empleado. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Primer día. |
| `FECHA_FIN` | `DATE` | NOT NULL | Último día (inclusive). |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta del registro. |

**Restricción:** `CK_FECHAS_VACACIONES` → `FECHA_FIN >= FECHA_INICIO`.

> **Ojo con el borrado:** la FK es `ON DELETE CASCADE`. Borrar un empleado
> borra su historial de vacaciones; la app no borra empleados (los
> desactiva), pero un `DELETE` manual se lleva todo.

## Procedimientos almacenados

### `SP_INSERTAR_VACACIONES(P_ID_EMPLEADO, P_FECHA_INICIO, P_FECHA_FIN)`

Empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`

**Validaciones en orden (`SIGNAL 45000`):**
1. inicio anterior a hoy → `ERROR: NO PUEDES REGISTRAR VACACIONES EN EL PASADO.`
2. fin menor que inicio →
   `ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.`
3. solapamiento con vacaciones existentes (cualquiera de los tres cruces) →
   `ERROR: EL EMPLEADO YA TIENE VACACIONES EN ESE RANGO.`
4. límite anual: días ya tomados **en el año de `FECHA_INICIO`** + días
   pedidos (`DATEDIFF + 1`, extremos inclusive) > 15 →
   `ERROR: EL EMPLEADO SUPERA EL LÍMITE DE 15 DÍAS POR AÑO.`

Inserta y devuelve
`EXITO: VACACIONES REGISTRADAS PARA "<nombre>" (ID: <id>) DEL <inicio> AL <fin>.`

> No valida que el empleado esté `ACTIVO` (se pueden cargar vacaciones a un
> inactivo).

### `SP_ACTUALIZAR_VACACIONES(P_ID_VACACION, P_NUEVA_INICIO, P_NUEVA_FIN)`

Registro inexistente → `ERROR: REGISTRO DE VACACIONES NO ENCONTRADO.`
Ya terminadas (`FECHA_FIN < CURDATE()`) →
`ERROR: NO SE PUEDEN MODIFICAR VACACIONES QUE YA TERMINARON.`
Fechas efectivas invertidas (combinando lo enviado y lo actual) →
`ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.`
Actualiza con `COALESCE` (NULL conserva) y devuelve
`EXITO: VACACIONES (ID: <id>) ACTUALIZADAS CORRECTAMENTE PARA EL EMPLEADO ID: <id>.`

> **Hueco conocido:** la actualización **no re-valida el solapamiento** con
> otras vacaciones (el alta sí). El tope de 15 días sí se re-valida por el
> trigger `TR_VALIDAR_LIMITE_VACACIONES_UPDATE`.

### `SP_REPORTE_DIAS_CONSUMIDOS(P_ID_EMPLEADO)`

Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.` Devuelve una fila:
`NOMBRE`, `TOTAL_DIAS_TOMADOS` (año actual), `DIAS_RESTANTES` (`15 - tomados`)
y `ESTATUS_VACACIONES`: `DISPONIBLE` o `EXCEDE LÍMITE` (si el saldo es
negativo).

### `SP_VALIDAR_CUPO_VACACIONES(P_CARGO, OUT P_DISPONIBLE)`

Valida la regla de cobertura por cargo: no dejar más de la mitad del personal
del cargo de vacaciones al mismo tiempo.

- Cargo sin empleados → `ERROR: CARGO NO ENCONTRADO O SIN EMPLEADOS ASIGNADOS.`
- Calcula `P_DISPONIBLE = ((ausentes_hoy + 1) <= total_cargo / 2)`.

> **Nota:** el total del cargo cuenta **todos** los empleados, incluidos los
> `INACTIVO`, porque no filtra por `ESTADO`. Si hay muchos inactivos en el
> cargo, el cupo queda más restrictivo de lo que debería.
>
> Es un `OUT BOOLEAN`: el cliente lo lee como parámetro de salida, no como
> result set.

### `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES()`

Lista los empleados de vacaciones **hoy** con cargo, fechas y
`DIAS_PARA_RETORNAR = DATEDIFF(FECHA_FIN, CURDATE())`, ordenados por fecha de
fin. Si no hay nadie, devuelve 0 filas (no es error).

## Triggers

### `TR_VALIDAR_LIMITE_VACACIONES`

`BEFORE INSERT`. Suma los días ya cargados en el **año de
`NEW.FECHA_INICIO`** + los nuevos; si supera 15 →
`ERROR: VACACIONES DENEGADAS. EL EMPLEADO EXCEDERÍA EL LÍMITE DE 15 DÍAS ANUALES.`

### `TR_VALIDAR_LIMITE_VACACIONES_UPDATE`

`BEFORE UPDATE`. Misma cuenta pero **excluyendo la propia fila**
(`ID_VACACION <> NEW.ID_VACACION`), para que editar un registro no se cuente
dos veces. Mismo mensaje de error.

> Los dos triggers son la red de seguridad para altas/ediciones por SQL
> directo; el SP de alta valida lo mismo con mensajes más específicos.

## Reglas de negocio

- **Máximo 15 días por año** (contados con `DATEDIFF + 1`, extremos
  inclusive), por SP y por trigger.
- **Sin solapamiento** entre vacaciones del mismo empleado (en el alta).
- **No se cargan vacaciones en el pasado** (alta).
- **No se editan vacaciones ya terminadas.**
- **Cobertura por cargo:** no más de la mitad del personal de vacaciones a la
  vez.
- **Asistencia bloqueada** durante vacaciones (módulo 11).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
