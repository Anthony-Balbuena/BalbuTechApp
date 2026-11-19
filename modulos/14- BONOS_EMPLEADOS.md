# Módulo 14 — BONOS_EMPLEADOS

Bonos, horas extra y bonificaciones de empleados: fecha, tipo
(`DOBLE_SUELDO`, `HORAS_EXTRA`, `BONIFICACION`), monto y estado
(`PENDIENTE`, `PAGADO`, `ANULADO`). El monto debe ser **> 0** y hay un tope de
**100000** por bono.

También es donde aterriza el **bono automático del 1%** que genera una venta
cobrada (lo crea el trigger `TR_AUTO_FINALIZAR_VENTA` del módulo 24).

**Depende de:** `EMPLEADOS` (8).

> **La app ya gestiona bonos** (18/11/2026): submenú *Empleados → Gestionar
> bonos*, con permiso `GESTIONAR_BONOS_EMPLEADO` (36). Antes había un
> `SP_LISTAR_BONOS` que nadie llamaba: los bonos de venta se creaban por trigger
> y no había forma de verlos ni pagarlos (la viva llegó a 11 `PENDIENTE` por
> $10.330).

> **El bono se cobra dentro del sueldo del mes** (18/11/2026): la nómina (8)
> los suma en el recibo y `SP_PAGAR_NOMINA_EMPLEADO` los marca. Por eso el pago
> ahora deja `FECHA_PAGO` y `PAGADO_POR`: antes «pagar» era solo pasar `ESTADO`
> a `PAGADO` y no quedaba ni cuándo ni quién.

Fuente: `modulos/14- BONOS_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 18/11/2026.

## Tablas

### BONOS_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_BONO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Beneficiario. |
| `FECHA` | `DATE` | NOT NULL | Fecha del bono. |
| `TIPO_BONO` | `ENUM('DOBLE_SUELDO','HORAS_EXTRA','BONIFICACION')` | NOT NULL | Tipo. |
| `MONTO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Monto. Tope lógico 100000 (SP). |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Detalle. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta. |
| `ESTADO` | `ENUM('PENDIENTE','PAGADO','ANULADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |
| `FECHA_PAGO` | `DATE` | NULL | Día en que se pagó. `NULL` mientras está `PENDIENTE` o `ANULADO`. |
| `PAGADO_POR` | `VARCHAR(50)` | NULL | Nombre de usuario que lo pagó (`FN_USUARIO_SESION()`). `NULL` si la conexión no traía sesión válida. |

**Auditoría del pago (18/11/2026):** `FECHA_PAGO` y `PAGADO_POR` se agregan en
el `CREATE TABLE` y, para una base que ya tenía la tabla, con dos `ALTER`
idempotentes que preguntan antes a `INFORMATION_SCHEMA` (mismo patrón que el
módulo 13). `PAGADO_POR` guarda el **nombre**, no el ID: si mañana se borra la
cuenta, el bono sigue diciendo quién lo pagó.

> El bono ID 4 de la viva ($2.000) se pagó a mano antes de esta migración: su
> `FECHA_PAGO` y su `PAGADO_POR` quedan `NULL` y **no se rellenan con datos
> inventados**.

**Índices:** `IX_BONO_EMPLEADO`, `IX_BONO_FECHA`, `IX_BONO_TIPO`,
`IX_BONO_ESTADO`.

**Restos de migración en el archivo:** un `SELECT * FROM BONOS_EMPLEADOS;`
suelto y un `ALTER TABLE ... MODIFY ESTADO ENUM(...) NOT NULL DEFAULT
'PENDIENTE'` idempotente. Se ejecutan en cada import (ruido, sin efecto).

## Procedimientos almacenados

### `SP_REGISTRAR_BONO(P_ID_EMPLEADO, P_FECHA, P_TIPO_BONO, P_MONTO, P_DESCRIPCION)`

- Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.`
- Monto `> 100000` → `ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.`
- Tipo fuera del ENUM → `ERROR: TIPO DE BONO DESCONOCIDO.`
- Inserta y devuelve
  `EXITO: BONO DE $<monto> REGISTRADO A: <nombre> (ID: <id>).`

> No valida monto `<= 0` (lo corta el CHECK con error técnico) ni fecha
> futura. Solo el trigger bloquea fechas viejas.

### `SP_ACTUALIZAR_BONO(P_ID_BONO, P_NUEVO_MONTO, P_NUEVA_DESCRIPCION)`

- ID inexistente → `ERROR: BONO NO ENCONTRADO.`
- Monto `NULL` o `<= 0` → `ERROR: EL MONTO DEBE SER MAYOR A CERO.`
- Monto `> 100000` → `ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.`
- Actualiza monto y descripción (la descripción **se pisa**, incluso con
  `NULL`: no usa `COALESCE`).
- Devuelve `EXITO: BONO ACTUALIZADO CORRECTAMENTE.`

> Si el bono ya está `PAGADO` o `ANULADO`, el trigger
> `TR_BLOQUEAR_CAMBIO_BONO` corta el update con
> `ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.`

### `SP_PAGAR_BONO(P_ID_BONO)`

- No existe → `ERROR: EL BONO NO EXISTE.`
- Ya `PAGADO` → `AVISO: ESTE BONO YA HABIA SIDO PAGADO ANTERIORMENTE.`
- `ANULADO` → `ERROR: NO SE PUEDE PAGAR UN BONO QUE ESTA ANULADO.`
- Pasa a `PAGADO`, escribe `FECHA_PAGO = CURRENT_DATE` y
  `PAGADO_POR = USUARIO` del token de sesión, y devuelve
  `EXITO: EL BONO CON ID <id> HA SIDO MARCADO COMO PAGADO.`

> (18/11/2026) Sin sesión válida `PAGADO_POR` queda `NULL` en vez de inventar un
> nombre. Los mensajes no cambiaron: el test de bonos los sigue esperando igual.

### `SP_ANULAR_BONO(P_ID_BONO)`

- No existe → `ERROR: EL BONO NO EXISTE.`
- Ya `PAGADO` → `ERROR: NO SE PUEDE ANULAR UN BONO QUE YA FUE PAGADO.`
- Ya `ANULADO` → `AVISO: ESTE BONO YA ESTABA ANULADO.`
- Pasa a `ANULADO` y devuelve
  `EXITO: EL BONO CON ID <id> FUE ANULADO CORRECTAMENTE.`

### `SP_LISTAR_BONOS(P_ESTADO)` — **retirado (18/11/2026)**

Tenía un único destino: la pantalla de bonos, que no existía. Al cablearla se
reemplazó por el par paginado de abajo; un listado sin `LIMIT` es una pared de
texto en cuanto pasan los meses (y los bonos de venta crecen solos). Queda el
`DROP` para que una base que ya lo tenía se limpie al reimportar (mismo
precedente que `SP_HISTORIAL_VENTA`).

### `SP_LISTAR_BONOS_PAGINADO(P_ESTADO, P_PAGINA, P_POR_PAGINA)`

Una página de bonos con `NOMBRE_EMPLEADO`; con estado filtra por él, con
`NULL`/vacío trae todos; ordena por `FECHA DESC, ID_BONO DESC`. Página o
tamaño inválidos caen a `1` / `10`.

> El `LIMIT` vive adentro del SP porque `balbu_app` no tiene `SELECT` directo
> sobre la tabla (recorte del 03/11/2026).

### `SP_CONTAR_BONOS(P_ESTADO)`

`TOTAL` de bonos con ese estado, para armar «Página 1 de N». Mismo criterio de
filtro que el paginado: `NULL`/vacío cuenta todos.

### `SP_LISTAR_BONOS_PENDIENTES_EMPLEADO(P_ID_EMPLEADO)` — nuevo (18/11/2026)

Los bonos `PENDIENTE` de **una** persona (`ID_BONO`, `FECHA`, `TIPO_BONO`,
`MONTO`, `DESCRIPCION`), ordenados por fecha. Es el detalle que el recibo de
nómina (módulo 8) muestra debajo del total.

- ID nulo → `ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.`
- Empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
- **No pagina a propósito:** es el detalle de una persona, no un listado del
  área. Va aparte de `SP_LISTAR_BONOS_PAGINADO` para no cambiarle la firma (y la
  de `SP_CONTAR_BONOS`) por algo que solo usa el recibo.

## Triggers

### `TR_VALIDAR_FECHA_BONO`

`BEFORE INSERT`. Fecha anterior a `CURDATE() - 60 DAY` →
`ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 60 DÍAS.`

> El comentario del archivo documenta que se dio de baja un trigger huérfano
> de la BD viva (`14_TR_VALIDAR_FECHA_BONO`, 30 días) que tapaba a este; el
> respaldo quedó en `/tmp/opencode/backup/pre_drop_14trig.txt`.

### `TR_BLOQUEAR_CAMBIO_BONO`

`BEFORE UPDATE`. Si el bono **no** está `PENDIENTE`, no permite cambiar
`ESTADO`, `MONTO`, `TIPO_BONO` ni `ID_EMPLEADO`:
`ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.`

> El monto de un bono pagado alimenta el cierre de caja y es historia: por eso
> se congela. Un `PENDIENTE` sí se puede editar.

> **(18/11/2026)** También congela `FECHA_PAGO` y `PAGADO_POR`: quién pagó y
> cuándo es historia, no un campo editable. La comparación usa `<=>` (igualdad
> segura con `NULL`) porque las columnas arrancan en `NULL` y un `<>` contra
> `NULL` da `NULL`, o sea que no frenaba nada.

### Trigger eliminado: `TR_CALCULAR_BONO_VENTA`

Solo queda el `DROP`. Creaba el bono del 1% **al agregar el producto**, antes
de cobrar, y cancelar la venta no lo borraba. Ahora lo crea
`TR_AUTO_FINALIZAR_VENTA` (módulo 24) cuando se paga el total de la venta.

## Vistas

### `VISTA_TOTAL_BONOS_POR_EMPLEADO`

`ID_EMPLEADO`, `NOMBRE`, `TOTAL_BONIFICADO`, `CANTIDAD_BONOS`, para **todos**
los empleados (`LEFT JOIN`).

> **(18/11/2026)** Los `ANULADO` **no** cuentan: un bono anulado es dinero que
> nunca se otorgó. Antes el `SUM` los sumaba igual y no se notaba porque no
> había pantalla para anular; con la pantalla, anular uno dejaba el total sin
> bajar. Ahora el `CASE` los excluye del total y del conteo.
>
> Efecto colateral bueno: el `CASE` tiene `ELSE 0`, así que un empleado sin
> bonos devuelve `0`, no `NULL` (antes `SUM` de cero filas daba `NULL`).

## Pantalla (app C++)

`bonos.cpp` / `bonos.h`, colgada del submenú de Empleados:

| Acción | SP |
|---|---|
| Listar (10 por página, filtro por estado) | `SP_LISTAR_BONOS_PAGINADO` + `SP_CONTAR_BONOS` |
| Pagar | `SP_PAGAR_BONO` |
| Anular | `SP_ANULAR_BONO` |
| Registrar | `SP_REGISTRAR_BONO` |

- Abre con el permiso **`GESTIONAR_BONOS_EMPLEADO`** (ADMIN, GERENTE y RRHH;
  SUBGERENTE no). Las cuatro rutinas de escritura exigen ese mismo permiso:
  pantalla y rutina con permisos distintos dejarían al rol legítimo en
  `SIN_PERMISO`.
- Filtro por defecto `PENDIENTE`, que es la única lista sobre la que se trabaja.
- **`SP_ACTUALIZAR_BONO` queda sin cablear a propósito:** corregir el monto de
  un bono sin dejar rastro es peor que anularlo y volver a registrarlo, que sí
  deja historia.
- El mensaje del SP se pinta según su familia: `EXITO` verde, `AVISO` amarillo
  (bono ya pagado o ya anulado, que no es una falla), `ERROR` rojo.

> **La nómina no es esta pantalla.** `nomina.cpp` (módulo 8) muestra el recibo
> con el total de bonos pendientes y los paga juntos; acá se carga, se anula y
> se paga un bono suelto. Las dos escriben las mismas columnas de auditoría.

## Reglas de negocio

- **Monto > 0** (CHECK) y **tope de 100000** por bono (SP).
- **Tipo válido** del ENUM.
- **No se cargan bonos con más de 60 días de antigüedad.**
- **Un bono pagado o anulado es inmutable**, incluido quién lo pagó y cuándo.
- **Solo un `PENDIENTE` se paga o se anula**; un pagado no se anula y un
  anulado no se paga.
- **Pagar deja rastro:** `FECHA_PAGO` y `PAGADO_POR` (usuario de la sesión). Sin
  sesión, el pagador queda `NULL` — no se inventa.
- **Bono automático de venta:** 1% de la venta cobrada, creado por el trigger
  del módulo 24.
- **Permiso:** registrar, pagar y anular exigen `GESTIONAR_BONOS_EMPLEADO`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
