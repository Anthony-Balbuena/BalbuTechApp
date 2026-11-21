# Módulo 25 — GARANTIAS

El agregado completo del posventa: la garantía de cada producto vendido, el
reclamo que se abre sobre ella, el técnico al que se le asigna, la bitácora del
trabajo técnico y el flujo que los conecta. **Una sola garantía por línea de
venta**, con fecha final siempre posterior a la inicial.

**Depende de:** `DETALLES_VENTA` (21), `PRODUCTOS` (9), `EMPLEADOS` (8) y
`USUARIOS` (10).
**Es usado por:** `ventas.cpp` (alta de garantía, reclamo, cierre y consultas) y
`26- DEVOLUCIONES` (FK y lectura de la garantía).

> **Este archivo aloja además un SP de devoluciones** (`26_SP_RECHAZAR_DEVOLUCION`),
> que por nombre y por tema pertenece al módulo **26**. Funciona, pero vive lejos
> de su tabla.

> **(14/11/2026) Absorbe los módulos `27`, `34`, `35` y `63`.** Estaban separados
> por el orden de import —cada tabla necesita la anterior creada— y porque el
> `63` era un parche correctivo posterior. Con las cinco secciones en un archivo,
> ese orden se cumple solo. El `63` redefine tres `SP` de las secciones de arriba:
> los `DROP` están más abajo, en la sección del flujo, y las dos versiones quedan
> a la vista para que se lea el cambio de firma.

Fuente: `modulos/25- GARANTIAS.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

## Tablas

### GARANTIAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_GARANTIA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_DETALLE_VENTA` | `INT` | NOT NULL, FK → `DETALLES_VENTA` **ON DELETE CASCADE** | Línea garantizada. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Desde cuándo corre. |
| `FECHA_FIN` | `DATE` | NOT NULL | Hasta cuándo corre. |
| `ESTADO` | `ENUM('ACTIVA','VENCIDA','CANCELADA')` | NOT NULL, DEFAULT `'ACTIVA'` | Estado. |
| `ID_EMPLEADO` | `INT` | NULL, FK → `EMPLEADOS` | Quién la registró. |
| `FECHA_REGISTRO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se registró. |

`ID_EMPLEADO` y `FECHA_REGISTRO` **no están en el `CREATE TABLE`**: las agrega el
`ALTER` de la sección del flujo, más abajo, porque un `CREATE TABLE` sin
`IF NOT EXISTS` no tocaría las bases que ya tienen la tabla.

**Restricciones:** `UQ_GARANTIA_DETALLE` UNIQUE (`ID_DETALLE_VENTA`) — una
garantía por línea — y `CK_GARANTIA_FECHAS` CHECK (`FECHA_FIN > FECHA_INICIO`).

**Índices:** `IX_GARANTIA_INICIO`, `IX_GARANTIA_FIN` (las que están por vencer o
ya vencieron) e `IX_GARANTIA_ESTADO` (las vigentes).

> **`VENCIDA` la escribe un solo SP.** Hasta el `63` era decorativa: nadie la
> pasaba. Ahora `SP_MARCAR_GARANTIAS_VENCIDAS` (sección del flujo) la escribe, y
> `SP_CONSULTAR_GARANTIAS` la invoca antes de listar para no depender de un
> scheduler. **El resto del flujo sigue sin mirar la fecha**: la validación de
> vigencia vive en el `SP` de reclamo, no en la tabla.
>
> La FK `ON DELETE CASCADE` es letra muerta: las líneas de venta no se borran.

## Procedimientos almacenados

### `SP_REGISTRAR_GARANTIA(P_ID_DETALLE_VENTA, P_DIAS_VALIDEZ)`

> **Versión vieja, sin autor — RETIRADA del `.sql` el 19/11/2026.** La sección
> del flujo define `SP_REGISTRAR_GARANTIA(P_ID_DETALLE_VENTA, P_DIAS_VALIDEZ,
> P_ID_EMPLEADO)`, que es la que llama `ventas.cpp`. La copia de 2 parámetros
> era código muerto (el `DROP` del flujo se la llevaba puesta). Lo de abajo
> queda como historia de lo que hacía.

**Crea la garantía contando desde hoy**.

1. detalle inexistente → `ERROR: EL DETALLE DE VENTA NO EXISTE.`
2. línea ya garantizada → `ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.`
3. Inserta con `FECHA_INICIO = CURRENT_DATE` y
   `FECHA_FIN = CURRENT_DATE + P_DIAS_VALIDEZ`.
4. Devuelve `EXITO` / `GARANTÍA REGISTRADA CON ÉXITO.` / `ID_GENERADO`.

> **Carrera cubierta:** las dos sesiones pasan el `COUNT`, pero
> `UQ_GARANTIA_DETALLE` corta a la segunda. Patrón correcto: validar + confiar
> en el índice.
>
> **`P_DIAS_VALIDEZ` no se valida.** Con `0` la fecha final queda **igual** al
> inicio y el `CHECK CK_GARANTIA_FECHAS` aborta con error técnico; con un valor
> negativo, lo mismo. Con `NULL`, el `NOT NULL` de `FECHA_FIN` lo corta. Ningún
> camino devuelve un mensaje amigable.

### `26_SP_RECHAZAR_DEVOLUCION(P_ID_DEVOLUCION, P_MOTIVO_RECHAZO)`

**Usada por la app** (`ventas.cpp`), pero **opera sobre `DEVOLUCIONES`** (26).

1. devolución inexistente → `ERROR: LA DEVOLUCIÓN NO EXISTE.`
2. estado distinto de `PENDIENTE` →
   `ERROR: SOLO SE PUEDEN RECHAZAR DEVOLUCIONES EN ESTADO PENDIENTE.`
3. Deja `ESTADO = 'RECHAZADA'` y **concatena** el motivo:
   `<motivo original> | RECHAZO: <motivo>`. Si el original era `NULL`, guarda
   solo el rechazo (P12, 07/10/2026).

> **Por qué existe este SP:** es la alternativa al paso 3 de
> `25_SP_PROCESAR_DEVOLUCION` (26), que cambia el estado **sin anotar motivo**.
> Rechazar **libera la cuota** (las `RECHAZADA` no cuentan para el tope) y su
> fila **sí se puede borrar** (`TR_BLOQUEAR_BORRADO` solo frena `APROBADA` y
> `REEMBOLSADA`).
>
> **Sin motivo, el motivo se pierde:** `CONCAT('RECHAZO: ', NULL)` da `NULL`, así
> que un `P_MOTIVO_RECHAZO` nulo deja `MOTIVO` en `NULL` en vez de anotar algo.
> No se valida que venga.

## Triggers

### `TR_VALIDAR_FECHAS_GARANTIA` (`BEFORE INSERT`)

Si `FECHA_INICIO` viene en el pasado, **la corrige a hoy en silencio** (no
devuelve error). Es el **único** candado del flujo que autocorrige en vez de
cortar: un inicio pasado nunca queda grabado, pero tampoco se avisa.

## Movidos a otros archivos

- `VISTA_DEVOLUCIONES_PENDIENTES` → **26**.

## Reglas de negocio

- **Una garantía por línea de venta** (UNIQUE).
- **La fecha final siempre es posterior al inicio** (CHECK).
- **La garantía arranca hoy**, no en la fecha de la venta.
- **Un inicio en el pasado se corrige solo**, sin avisar.
- **`VENCIDA` no lo escribe nadie**: la vigencia se evalúa por fecha.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Reclamos de garantía: `RECLAMOS_GARANTIAS` (ex módulo 27)

Los reclamos que se abren sobre una garantía: qué pasó, cuándo y en qué estado
quedó. Es la **puerta de entrada** al uso de una garantía (arriba, en este módulo).

**Depende de:** `GARANTIAS` (arriba) y `AUDITORIA_SISTEMA` (6).
**Es usado por:** `ventas.cpp` (alta y cierre del reclamo).

Fuente: `modulos/25- GARANTIAS.sql`, sección RECLAMOS_GARANTIAS · Revisado: 14/11/2026.

### Tablas

#### RECLAMOS_GARANTIAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_RECLAMO_GARAN` | `INT` | PK, AUTO_INCREMENT | Identificador (el nombre va truncado). |
| `ID_GARANTIA` | `INT` | NOT NULL, FK → `GARANTIAS` **ON DELETE CASCADE** | Garantía reclamada. |
| `FECHA_RECLAMO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se abrió. |
| `DESCRIPCION` | `VARCHAR(255)` | NOT NULL | Qué pasó. |
| `ESTADO` | `ENUM('PENDIENTE','APROBADO','RECHAZADO','CERRADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |
| `ID_EMPLEADO` | `INT` | NULL, FK → `EMPLEADOS` | Quién abrió el reclamo. |
| `ID_EMPLEADO_CIERRE` | `INT` | NULL, FK → `EMPLEADOS` | Quién lo cerró. |
| `FECHA_CIERRE` | `TIMESTAMP` | NULL | Cuándo se cerró. |

Las tres últimas las agrega el `ALTER` de la sección del flujo, más abajo.

**Índice:** `IX_RECLAMO_GARANTIA_FECHA` (`FECHA_RECLAMO`), para listar del más
reciente al más viejo.

> La FK `ON DELETE CASCADE` es letra muerta: las garantías no se borran.

#### Máquina de estados

```
PENDIENTE ──> APROBADO ──> CERRADO
    └──────> RECHAZADO
```

`RECHAZADO` y `CERRADO` son **terminales**; nadie vuelve a `PENDIENTE`.

### Procedimientos almacenados

#### `27_SP_REGISTRAR_RECLAMO_GARANTIA(P_ID_GARANTIA, P_DESCRIPCION)`

> **Versión vieja, sin autor ni validación de fechas — RETIRADA del `.sql` el
> 19/11/2026.** El flujo define `(P_ID_GARANTIA, P_DESCRIPCION, P_ID_EMPLEADO)`,
> que es la que llama `ventas.cpp`. La copia de 2 parámetros era código muerto.
> Lo de abajo queda como historia.

**Usada por la app** (`ventas.cpp`).

1. garantía inexistente → `ERROR: LA GARANTÍA NO EXISTE.`
2. garantía no `ACTIVA` →
   `ERROR: ESTA GARANTÍA NO ESTÁ ACTIVA Y NO SE PUEDE RECLAMAR.`
3. Inserta el reclamo en `PENDIENTE` y devuelve
   `EXITO: RECLAMO REGISTRADO CORRECTAMENTE.`

> **El agujero que esta versión dejaba abierto:** la garantía vencida por fecha
> seguía aceptando reclamos. El SP solo mira `ESTADO`, y en esta sección nadie
> pasa una garantía a `VENCIDA`, así que una garantía con `FECHA_FIN` en el
> pasado sigue figurando `ACTIVA` y el reclamo entra sin chistar. **La versión
> del flujo compara las fechas**; esta, no.
>
> **`P_DESCRIPCION` no se valida**: la columna es `NOT NULL`, pero una cadena
> vacía o de solo espacios pasa.

#### `27_SP_FINALIZAR_RECLAMO_TOTAL(P_ID_RECLAMO)` — **ELIMINADO (15/11/2026)**

> **Se eliminó.** El cierre va por `SP_FINALIZAR_RECLAMO(id_asignacion)`, que
> cierra la asignación **y** el reclamo juntos, sella `ID_EMPLEADO_CIERRE` y
> `FECHA_CIERRE`, y escribe la auditoría. Convivir con los dos caminos dejaba
> reclamos `CERRADO` con asignaciones `EN_PROCESO` colgando.
> El módulo deja un `DROP PROCEDURE IF EXISTS` para limpiar las bases viejas.

**Ya no la llama nadie.**

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

### Triggers

#### `TR_VALIDAR_CAMBIO_RECLAMO` (`BEFORE UPDATE`)

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

#### `TR_FINALIZAR_RECLAMO_APROBADO` (`AFTER UPDATE`)

En `PENDIENTE → APROBADO`, pasa la **garantía** a `CANCELADA`.

> **Una aprobación quema la garantía entera**, incluso si el reclamo cubría una
> sola unidad de una línea con varias. No hay devolución de stock ni reemplazo:
> la base registra el caso, la reposición se resuelve afuera.
>
> **No escribe auditoría**; el cierre que sí lo hace es `SP_FINALIZAR_RECLAMO`
> (el viejo `27_SP_FINALIZAR_RECLAMO_TOTAL` se eliminó el 15/11/2026).

#### `TR_BLOQUEAR_BORRADO_RECLAMO` (`BEFORE DELETE`)

Solo se borra un reclamo `PENDIENTE`:
`ERROR: EL RECLAMO PROCESADO NO SE BORRA; USE LOS SPS DE CIERRE.`

### Reglas de negocio

- **Solo se reclama sobre una garantía `ACTIVA`** — que no es lo mismo que
  vigente por fecha.
- **Un reclamo aprobado cancela la garantía** completa.
- **`RECHAZADO` y `CERRADO` son terminales**; no se reabren.
- **Un reclamo procesado no se borra** (auditoría).
- **El cierre deja rastro** en `AUDITORIA_SISTEMA` con el usuario de la sesión.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Asignación de reclamos: `ASIGNACIONES_RECLAMOS` (ex módulo 34)

A qué técnico se le asignó cada reclamo de garantía, con prioridad, estado de la
asignación y fechas. Un reclamo puede pasar por varias asignaciones a lo largo
del tiempo; el avance del trabajo vive **acá**, no en el reclamo.

**Depende de:** `RECLAMOS_GARANTIAS` (arriba) y `EMPLEADOS` (8).
**Es usado por:** **nadie**. La app **no** llama a ninguno de los dos `SP`; cierra
reclamos con el cierre (hoy `SP_FINALIZAR_RECLAMO`), que **no toca esta tabla**.

Fuente: `modulos/25- GARANTIAS.sql`, sección ASIGNACIONES_RECLAMOS · Revisado: 14/11/2026.

### Tablas

#### ASIGNACIONES_RECLAMOS

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

**Índice:** `IDX_EMPLEADO_FECHA` sobre `(ID_EMPLEADO, FECHA_ASIGNACION)`,
declarado dentro del `CREATE TABLE`.

> **El índice duplicado se eliminó el 15/11/2026.** `ASIGNACIONES_RECLAMOS`
> llegó a tener dos índices sobre las mismas columnas: `IDX_EMPLEADO_FECHA` y
> `IDX_ASIGNACIONES_EMPLEADO_FECHA` (este último heredado del ex módulo 34).
> Queda uno solo; el `DROP INDEX IF EXISTS` del `.sql` limpia las bases viejas
> que todavía lo tengan.
>
> **La FK del reclamo borra en cascada**: borrar un reclamo se lleva sus
> asignaciones. La FK del empleado **no** tiene `ON DELETE`, así que un técnico
> con asignaciones no se puede borrar.
>
> **`PENDIENTE` nunca se usa**: el `SP` inserta directo en `EN_PROCESO`, así que
> ese estado del `ENUM` es decorativo. Y el `CHECK` de fechas solo compara contra
> la fecha de asignación por defecto, no contra la del reclamo.

**Migración incluida:** ~~`ALTER TABLE ... ADD CONSTRAINT IF NOT EXISTS
CHK_FECHAS_VALIDAS CHECK (FECHA_FINALIZACION >= FECHA_ASIGNACION)`, idempotente.~~
(19/11/2026) El `CHECK` ahora se declara dentro del `CREATE TABLE
ASIGNACIONES_RECLAMOS`: no hay `ALTER` suelto que buscar.

### Procedimientos almacenados

#### `SP_ASIGNAR_TECNICO_RECLAMO(P_ID_RECLAMO, P_ID_EMPLEADO, P_PRIORIDAD, P_OBSERVACIONES)`

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

#### `SP_FINALIZAR_RECLAMO(P_ID_ASIGNACION, P_OBSERVACIONES_FINALES)`

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
> **La app SÍ lo llama** desde el 15/11/2026: `reclamoFinalizarUI` (`ventas.cpp`)
> lista las asignaciones en curso con `SP_CONSULTAR_ASIGNACIONES` y cierra por
> acá. Antes el cierre pasaba por `27_SP_FINALIZAR_RECLAMO_TOTAL` (eliminado), que
> dejaba la asignación en `EN_PROCESO` para siempre.

### Reglas de negocio

- **Un reclamo tiene, como mucho, una asignación en curso** (validado en el `SP`,
  no en la base).
- **Solo se asigna sobre un reclamo `PENDIENTE`.**
- **El avance vive en `ESTADO_ASIGNACION`**, no en el estado del reclamo.
- **Finalizar la asignación cierra el reclamo.**
- **Borrar el reclamo borra sus asignaciones.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Detalle de reparaciones: `DETALLE_REPARACIONES` (ex módulo 35)

Bitácora del trabajo técnico sobre una asignación: qué se hizo, qué repuesto se
usó, cuánto costó, cuánto tiempo llevó, en qué estado va y dónde está la
evidencia.

**Depende de:** `ASIGNACIONES_RECLAMOS` (arriba) y `USUARIOS` (10).

> **La app no usa este módulo**: ni la tabla ni el SP aparecen en el código C++.
> Está en la base, sin flujo que lo alimente.

Fuente: `modulos/25- GARANTIAS.sql`, sección DETALLE_REPARACIONES · Revisado: 14/11/2026.

### Tablas

#### DETALLE_REPARACIONES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_REPARACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_ASIGNACION` | `INT` | NOT NULL, FK → `ASIGNACIONES_RECLAMOS` **ON DELETE CASCADE** | Asignación que avanza. |
| `ID_USUARIO` | `INT` | NOT NULL, FK → `USUARIOS` | Quién registra el avance. |
| `FECHA_ACCION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ACCION_REALIZADA` | `VARCHAR(255)` | NOT NULL | Qué se hizo. |
| `ID_PRODUCTO` | `INT` | NULL, FK → `PRODUCTOS` | Repuesto del catálogo (15/11/2026). NULL = la reparación no usó repuesto. |
| `CANTIDAD_REPUESTO` | `INT` | NULL, CHECK `> 0` | Unidades consumidas. Descuenta stock real. |
| `COSTO_REPUESTO` | `DECIMAL(10,2)` | DEFAULT `0.00` | Costo **congelado** al registrar (`P_COMPRA × cantidad`). |
| `TIEMPO_EMPLEADO_MIN` | `INT` | DEFAULT `0` | Minutos de trabajo. |
| `ESTADO_AVANCE` | `ENUM('PENDIENTE','EN_PROCESO','COMPLETADO','CANCELADO')` | NOT NULL, DEFAULT `'EN_PROCESO'` | Estado del avance. |
| `RUTA_EVIDENCIA` | `VARCHAR(255)` | NULL | Ruta o nombre del archivo de evidencia. |

**Sin índices propios:** solo los que crean las FK (asignación y usuario).

> **El repuesto es texto libre, no `ID_PRODUCTO`**: no descuenta stock ni entra
> en el costo de ventas. Si el repuesto sale del inventario, esa salida se
> registra por otro lado (o no se registra).

### Procedimientos almacenados

#### `SP_REGISTRAR_AVANCE_REPARACION(P_ID_ASIGNACION, P_ID_USUARIO, P_ACCION, P_REPUESTO, P_COSTO, P_TIEMPO, P_ESTADO, P_RUTA)`

**La app no lo llama.**

1. asignación inexistente → `ERROR: ASIGNACIÓN NO EXISTE.`
2. asignación `COMPLETADO` → `ERROR: REPARACIÓN YA FINALIZADA.`
3. estado de avance fuera del `ENUM` → `ERROR: ESTADO DE AVANCE DESCONOCIDO.`
4. Inserta y devuelve `EXITO: AVANCE Y EVIDENCIA REGISTRADOS.`

> **Lo que no valida:**
> - **`P_ID_USUARIO`**: si no existe, salta el `1452` del FK, no un mensaje.
> - **`P_ACCION`**: vacía o `NULL` termina en el `NOT NULL` (error técnico).
> - **`P_COSTO` y `P_TIEMPO`**: negativos se aceptan; `NULL` en `COSTO_REPUESTO`
>   también (la columna admite nulos, aunque tenga `DEFAULT 0.00`).
> - **El estado de la asignación `CANCELADO`**: solo frena `COMPLETADO`, así que
>   se puede seguir cargando avances sobre una reparación cancelada.

### Reglas de negocio

- **Es una bitácora**: cada fila es un avance, no se actualiza ni se cierra.
- **No se avanza una asignación completada.**
- **El avance no mueve stock ni dinero**: el repuesto es un dato descriptivo.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Flujo de garantía: autor, fechas y consultas (ex módulo 63)

### Que hace

Cierra los huecos del flujo de garantías que quedaron abiertos en las secciones
de arriba:

- `GARANTIAS` no guardaba quien la registro ni cuando.
- `RECLAMOS_GARANTIAS` no guardaba quien abrio el reclamo, quien lo cerro
  ni cuando se cerro.
- `27_SP_REGISTRAR_RECLAMO_GARANTIA` solo miraba `ESTADO = 'ACTIVA'`: una
  garantia con `FECHA_FIN` en el pasado seguia siendo reclamable.
- `VENCIDA` estaba en el `ENUM` pero ningun objeto lo escribia.
- La UI pedia `ID detalle de venta`, `ID garantia` y `ID reclamo` a ciegas.
- No habia forma de que la garantia se registrara sola al confirmar la
  venta.

Objetos que agrega o reemplaza:

- Columna `PRODUCTOS.DIAS_GARANTIA INT NULL` con
  `CK_PRODUCTO_DIAS_GARANTIA (NULL o >= 0)`. **Declarada en el módulo 9**, no
  acá: es una columna de `PRODUCTOS` y la tabla se lee completa en su archivo
  (19/11/2026 dejó de agregarse con `ALTER` desde este módulo).
- Columnas `GARANTIAS.ID_EMPLEADO`, `GARANTIAS.FECHA_REGISTRO` y sus FK,
  declaradas en el `CREATE TABLE GARANTIAS` de este módulo.
- Columnas `RECLAMOS_GARANTIAS.ID_EMPLEADO`,
  `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE` y sus FK, declaradas en el
  `CREATE TABLE RECLAMOS_GARANTIAS` de este módulo.
- `SP_REGISTRAR_GARANTIA` (firma nueva, 3 parametros).
- `27_SP_REGISTRAR_RECLAMO_GARANTIA` (firma nueva, 3 parametros).
- ~~`27_SP_FINALIZAR_RECLAMO_TOTAL`~~ (firma nueva, 2 parametros): **eliminado el
  15/11/2026**; el cierre va por `SP_FINALIZAR_RECLAMO(id_asignacion)`.
- `SP_CONSULTAR_GARANTIAS`, `SP_CONSULTAR_RECLAMOS`,
  `SP_LINEAS_VENTA_CON_GARANTIA`, `SP_MARCAR_GARANTIAS_VENCIDAS`.
- Trigger `TR_REGISTRAR_GARANTIA_VENTA`.

### Por que

- Sin autor, un reclamo no tiene responsable y una garantia no tiene quien
  la respalde. `FECHA_REGISTRO` y `FECHA_CIERRE` dan la linea de tiempo que
  antes habia que adivinar por `FECHA_RECLAMO`.
- Validar solo el estado deja pasar reclamos sobre garantias vencidas por
  fecha: el estado se queda en `ACTIVA` hasta que alguien lo cambie, y
  nadie lo cambiaba.
- El vendedor atiende al cliente en el mostrador: si la UI le pide IDs de
  detalle, el flujo depende de que alguien los anote a mano.
- Registrar la garantia a mano despues de cada venta es trabajo repetido y
  facil de olvidar. Con `DIAS_GARANTIA` por producto, el pase a `REALIZADA`
  la crea sola.

### Como aplicarlo

Ya no hay nada que aplicar aparte: esta sección va dentro de
`25- GARANTIAS.sql` y corre con el import normal del módulo.

Es idempotente: los SPs y el trigger se recrean con `DROP IF EXISTS` + `CREATE`.
Las columnas y restricciones **ya no se agregan con `ALTER`**: están declaradas
en el `CREATE TABLE` de cada tabla (`PRODUCTOS.DIAS_GARANTIA` quedó en el módulo
9). Una base vieja que no las tenga ya no se pone al día corriendo este módulo:
hay que recrearla o migrarla a mano, porque el import es para base fresca.

### Orden de despliegue

1. Backup de la base.
2. Correr el módulo `25` completo: esta sección va incluida.
3. Desplegar el binario nuevo.

El binario viejo llama a los SPs con la firma anterior y falla al registrar
o finalizar. Como `GARANTIAS` y `RECLAMOS_GARANTIAS` estaban vacias y el
flujo no se usaba, la ventana es de minutos y no se pierden datos.

Los permisos `GARANTIAS_*` viven en el `36` (ex módulo 62) y van después del
binario: el binario viejo abre Garantías con `GESTIONAR_VENTAS` y, si el `36`
corre antes, el ítem desaparece del menú hasta desplegar.

### Como funciona el registro automatico

`TR_REGISTRAR_GARANTIA_VENTA` es `AFTER UPDATE ON VENTAS` con
`FOLLOWS TR_CAMBIO_ESTADO_VENTA`, asi que corre despues de que el historial
de estados ya escribio su fila.

Solo actua cuando `NEW.ESTADO = 'REALIZADA'` y `OLD.ESTADO <> 'REALIZADA'`.
Para cada linea de la venta cuyo producto tenga `DIAS_GARANTIA > 0` inserta
una fila en `GARANTIAS` con `FECHA_INICIO = CURRENT_DATE`,
`FECHA_FIN = CURRENT_DATE + DIAS_GARANTIA` y `ID_EMPLEADO = NEW.ID_EMPLEADO`
(el empleado de la venta). El `ON DUPLICATE KEY UPDATE` respeta
`UQ_GARANTIA_DETALLE`: si la linea ya tiene garantia, no la duplica ni
rompe la venta.

`DIAS_GARANTIA` en `NULL` o `0` significa "sin garantia automatica". Los 49
productos existentes quedan en `NULL`: no se inventan dias.

### Que preserva

- `TR_FINALIZAR_RECLAMO_APROBADO` sigue cancelando la garantia cuando un
  reclamo se aprueba.
- `TR_VALIDAR_CAMBIO_RECLAMO` sigue bloqueando reabrir un reclamo y tocar
  `CERRADO` o `RECHAZADO`.
- `TR_VALIDAR_FECHAS_GARANTIA` sigue autocorrigiendo un `FECHA_INICIO`
  pasado a hoy en los `INSERT`.
- `CK_GARANTIA_FECHAS` sigue exigiendo `FECHA_FIN > FECHA_INICIO`; por eso
  `SP_REGISTRAR_GARANTIA` rechaza dias menores a 1.
- `TR_CAMBIO_ESTADO_VENTA` conserva el orden 1 en `VENTAS`; el trigger nuevo
  queda en 2.
- El historial de estados de venta y el total de la venta no cambian.

### Que no hace

- No cablea las asignaciones (`ASIGNACIONES_RECLAMOS`, sección de arriba): la
  tabla sigue vacía y sin uso.
- No ata un reembolso al reclamo.
- No backfillea garantias de ventas viejas: para eso queda el alta manual,
  que ahora pide ID de venta y muestra las lineas.
- No cambia `SP_VENTA_LINEAS`: ese SP alimenta la factura y no devuelve el
  ID del detalle. El alta manual usa `SP_LINEAS_VENTA_CON_GARANTIA`.

### Verificacion

Histórico: aplicado como módulo `63` en `BALBU_TECH_TEST` el 30/10/2026, dos
veces seguidas sin error (la segunda pasada no cambia nada). Revalidado el
14/11/2026 ya fusionado dentro del `25`:

- `DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh` ->
  **11 OK, 0 FAIL**, con los 3 errores esperados vistos. El test corre en
  una transaccion con `ROLLBACK` y no deja filas `ZZ GAR`.
- El registro automatico crea la garantia con autor, `FECHA_REGISTRO` y los
  30 dias del producto; el producto sin `DIAS_GARANTIA` no la crea.
- El alta manual guarda autor y 45 dias; la segunda alta del mismo detalle
  falla con "YA TIENE UNA GARANTIA ASIGNADA" y no inserta.
- `SP_LINEAS_VENTA_CON_GARANTIA` devuelve la linea con `TIENE_GARANTIA = SI`.
- Reclamar dentro de fecha funciona y guarda autor; finalizar desde
  `PENDIENTE` deja `CERRADO` con `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE`;
  finalizar un `CERRADO` falla; reclamar una garantia con `FECHA_FIN` pasada
  falla con "VENCIDA POR FECHA".
- `SP_MARCAR_GARANTIAS_VENCIDAS()` pasa a `VENCIDA` la `ACTIVA` vencida.
- `check-app-sps.sh` en TEST: 99/0 (suma los 6 SPs que usa la app).
- `test-menus-por-rol.sh`: ADMIN/GERENTE/SUBGERENTE 5 opciones en Garantias,
  VENDEDOR 4 (sin "Finalizar reclamo"), CONTABILIDAD 2.
- `test-migracion-roles.sh`: VENDEDOR pasa de 12 a 15 permisos.
