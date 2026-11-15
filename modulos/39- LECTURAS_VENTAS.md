# Módulo 39 — LECTURAS_VENTAS

**Puertas de solo lectura** para la app C++ (fase 3, 13/10/2026): todo lo que las
pantallas de ventas y compras muestran sale por estos 30 SP, sin un solo `SELECT`
a mano en el `.cpp`.

**Depende de:** `VISTA_VENTA_CON_IVA` y `VISTA_COMPRA_CON_IVA` y
`VISTA_VENTAS_PENDIENTES_PAGO` (43), `VISTA_RESUMEN_PAGOS` (24),
`VW_GANANCIAS` y `VW_GANANCIAS_MENSUAL` (esta misma sección, al final),
`DETALLES_VENTA` (21), `DETALLE_COMPRA` (19) y `DEVOLUCIONES` (26).

> **Todos los SP están en uso.** Es el módulo con mejor cobertura de la app: cada
> uno tiene su llamada en `ventas.cpp` o `compras.cpp`.

> **Absorbe el `38` (14/11/2026):** las dos vistas de ganancia y
> `SP_REPORTE_PERIODO_GANANCIA` viven ahora **en este mismo archivo**, al final,
> en la sección «GANANCIAS (ex módulo 38)».

Fuente: `modulos/39- LECTURAS_VENTAS.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

## Lecturas de ventas (`ventas.cpp`)

### `SP_VENTAS_ULTIMAS()`

Las **20** ventas más recientes de `VISTA_VENTA_CON_IVA`: `ID_VENTA`, `CLIENTE`,
`FECHA`, `ESTADO`, `SUBTOTAL`, `ITBIS`, `TOTAL_CON_IVA`. Sin paginar.

> Sigue en uso: la llama `cancelarVentaUI` para elegir el ID a cancelar. La
> pantalla «Ver venta con IVA» usaba este SP hasta el 15/11/2026.

### `SP_VENTAS_ULTIMAS_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página de las ventas registradas, con las mismas columnas que
`SP_VENTAS_ULTIMAS`. Ordena por `ID_VENTA DESC` y usa 10 por página por
defecto; `P_PAGINA` y `P_POR_PAGINA` nulas o menores a 1 caen a 1 y 10.

> (15/11/2026) Reemplaza a `SP_VENTAS_ULTIMAS` en «Ver venta con IVA»: antes se
> imprimía la factura **completa** de las 20 últimas, así que una venta vieja
> quedaba inalcanzable y la pantalla tapaba la terminal.

### `SP_CONTAR_VENTAS_ULTIMAS()`

Cuántas ventas hay registradas, para el «Página 1 de N» de la pantalla. Cuenta
sobre `VISTA_VENTA_CON_IVA`, la misma que lista el SP de arriba, así el total
siempre cuadra.

### `SP_VENTA_ENCABEZADO(P_ID_VENTA)`

La misma fila de arriba para **una** venta. Si el ID no existe, devuelve **cero
filas**, no un error.

### `SP_VENTA_LINEAS(P_ID_VENTA)`

Líneas de la venta con `PRODUCTO`, `CANTIDAD`, `PRECIO_UNITARIO`,
`PORCENTAJE_DESCUENTO`, `SUBTOTAL`, `MONTO_ITBIS` y `TOTAL_LINEA`
(`SUBTOTAL + MONTO_ITBIS`), por `ID_DETALLE_VENTA`.

> Lee las columnas de `DETALLES_VENTA` **directo**, no por una vista: es el
> único SP del módulo que muestra el descuento de línea.

### `SP_VENTA_ESTADO(P_ID_VENTA)`

Solo el `ESTADO`. Pensado para decidir qué acciones ofrecer (`CANCELADA` y
`DEVUELTA` no admiten nada).

### `SP_PAGOS_POR_VENTA(P_ID_VENTA)`

Pagos de la venta desde `VISTA_RESUMEN_PAGOS`: `ID_PAGO`, `NOMBRE_METODO`,
`MONTO`, `MONTO_RECIBIDO`, `NOMBRE_EMPLEADO`, por `ID_PAGO`.

### `SP_PAGOS_ULTIMOS()` — eliminada (08/11/2026)

Listaba los 20 pagos más recientes. Quedó **sin caller** al paginar las
pantallas de Ventas y se reemplazó por `SP_PAGOS_ULTIMOS_PAGINADO`. El módulo
solo ejecuta `DROP PROCEDURE IF EXISTS` para limpiar una base que la tenga.

### `SP_DETALLES_VENDIDOS_ULTIMOS()` — eliminada (08/11/2026)

Listaba las 20 líneas vendidas más recientes (y no filtraba por estado de la
venta: mostraba líneas de ventas canceladas). Quedó **sin caller** y se
reemplazó por `SP_DETALLES_VENDIDOS_PAGINADO`.

### `SP_DEVOLUCION_PENDIENTE_POR_DETALLE(P_ID_DETALLE)`

El `ID_DEVOLUCION` de la **última** devolución `PENDIENTE` de esa línea, o cero
filas. Se usa para no abrir dos reclamos sobre la misma línea.

### `SP_VENTAS_PENDIENTES()`

Las **20** ventas más recientes de `VISTA_VENTAS_PENDIENTES_PAGO` (43):
`ID_VENTA`, `ID_CLIENTE`, `ESTADO`, `TOTAL`, `PAGADO`, `SALDO`, `FECHA` y
`HORAS_ABIERTA`.

> **`TOTAL` y `SALDO` van a BRUTO** (cambio del 12/10/2026): antes, con `TOTAL`
> base, una venta ya pagada mostraba saldo negativo.

### `SP_GANANCIAS_MENSUAL()`

`MES`, `VENTAS`, `SUBTOTAL`, `GANANCIA_BRUTA`, `GANANCIA_DEVUELTA`,
`GANANCIA_NETA` desde `VW_GANANCIAS_MENSUAL` (38). Hereda su filtro: **solo
excluye `CANCELADA`**.

### `SP_GANANCIAS_LINEAS(P_MES)`

Hasta **30** líneas de `VW_GANANCIAS` (38) del mes pedido (`'YYYY-MM'`), o de
todos si `P_MES` viene `NULL` o vacío. `ITBIS`, `COSTO_TOTAL`, `TOTAL_LINEA`,
`GANANCIA`, `GANANCIA_NETA`.

## Lecturas de compras (`compras.cpp`)

### `SP_COMPRAS_ULTIMAS()`

Las **20** compras más recientes de `VISTA_COMPRA_CON_IVA`: `ID_COMPRA`,
`PROVEEDOR`, `FECHA`, `ESTADO`, `SUBTOTAL`, `ITBIS`, `TOTAL_CON_IVA`.

> (08/11/2026) La app ya **no** la usa: no permitía llegar a una compra vieja.
> Queda por compatibilidad; el listado va por los dos de abajo.

### `SP_COMPRAS_ULTIMAS_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página del mismo listado, de la más nueva a la más vieja. `P_PAGINA` nulo o
`< 1` → 1; `P_POR_PAGINA` nulo o `< 1` → 10. La usa "Ver compra con IVA",
"Devolucion de compra" y "Cancelar compra" (módulo `compras.cpp`).

### `SP_CONTAR_COMPRAS()`

`COUNT(*)` de `COMPRAS`, para el "Página 1 de N" del paginador.

### `SP_COMPRAS_PENDIENTES_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página de `VISTA_COMPRAS_PENDIENTES_PAGO`: `ID_COMPRA`, `PROVEEDOR`,
`ESTADO`, `PAGADO`, `SALDO`. La usa "Pagar compra".

### `SP_CONTAR_COMPRAS_PENDIENTES()`

`COUNT(*)` de las compras con saldo, para el paginador del pago.

> Los cuatro van con `COMPRAS_VER`: en la matriz, todo rol con
> `COMPRAS_PAGAR`, `COMPRAS_CANCELAR` o `COMPRAS_DEVOLVER` también lo tiene.

### `SP_VENTAS_PENDIENTES_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página de `VISTA_VENTAS_PENDIENTES_PAGO`, con las mismas columnas que
`SP_VENTAS_PENDIENTES` (incluidas `FECHA` y `HORAS_ABIERTA`). La usa "Cobrar
venta" (`ventas.cpp`).

### `SP_CONTAR_VENTAS_PENDIENTES()`

`COUNT(*)` de las ventas con saldo, para el paginador del cobro.

### `SP_VENTAS_BORRADOR_VIEJO(P_HORAS)`

Las ventas `EN_PROCESO` **sin líneas** y con más de `P_HORAS` horas de abiertas
(48 si llega nulo o en 0): `ID_VENTA`, `FECHA`, `HORAS_ABIERTA`.

> (15/11/2026) Existe porque estos borradores **no pueden salir** por
> `VISTA_VENTAS_PENDIENTES_PAGO`: esa vista filtra `SALDO > 0` y un borrador sin
> líneas tiene total 0, así que queda descartado. Tampoco se pueden cobrar (no
> hay nada que cobrar): la salida es cancelarlas por ID. El umbral llega por
> parámetro para que el plazo lo decida el negocio y no quede escrito en el SQL.
> La pantalla de cobro lo usa para el aviso en amarillo.

### `SP_HISTORIAL_VENTA_PAGINADO(P_ID_VENTA, P_PAGINA, P_POR_PAGINA)`

Una página del historial de estados (`HISTORIAL_ESTADOS_VENTA`), del cambio más
nuevo al más viejo: `ID_VENTA`, `FECHA`, `ESTADO_ANTERIOR`, `ESTADO_NUEVO`,
`EMPLEADO`, `MOTIVO`. `P_ID_VENTA = 0` significa **todas las ventas**, igual que
en su hermana sin paginar.

> (15/11/2026) `SP_HISTORIAL_VENTA` (21) **no tiene `LIMIT`**: devolvía el
> historial completo. Con 30 filas en la viva no molesta, pero crece para
> siempre y la pantalla no tenía forma de dejar de dibujar. Esta es la que usa
> «Historial de venta» desde entonces.

### `SP_CONTAR_HISTORIAL_VENTA(P_ID_VENTA)`

Cuántos cambios de estado hay, para el «Página 1 de N» del historial. Lleva el
**mismo `JOIN` con `EMPLEADOS`** que el `SELECT` de arriba a propósito: si un
empleado faltara, la fila no se listaría pero sí se contaría, y las páginas no
cuadrarían.

### `SP_PAGOS_ULTIMOS_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página de `VISTA_RESUMEN_PAGOS`: `ID_PAGO`, `ID_VENTA`, `NOMBRE_METODO`,
`MONTO`, `MONTO_RECIBIDO`, `NOMBRE_EMPLEADO`. La usa "Anular pago".

### `SP_CONTAR_PAGOS()`

`COUNT(*)` de `PAGOS`, para el paginador de "Anular pago".

### `SP_DETALLES_VENDIDOS_PAGINADO(P_PAGINA, P_POR_PAGINA)`

Una página de las líneas vendidas (`ID_DETALLE_VENTA`, `ID_VENTA`, `PRODUCTO`,
`CANTIDAD`), de la más nueva a la más vieja. La usa "Devolucion de venta".

### `SP_CONTAR_DETALLES_VENDIDOS()`

`COUNT(*)` de `DETALLES_VENTA`, para el paginador de la devolución.

> Los seis van con `GESTIONAR_VENTAS`, el mismo permiso que sus hermanas sin
> paginar y el que exigen las tres pantallas que los llaman.

### `SP_COMPRA_ENCABEZADO(P_ID_COMPRA)`

La misma fila para **una** compra. Sin ID válido, cero filas.

### `SP_COMPRA_LINEAS(P_ID_COMPRA)`

Líneas de la compra: `ID_DETALLE_COMPRA`, `PRODUCTO`, `CANTIDAD`,
`PRECIO_UNITARIO` (**neto**), `SUBTOTAL`, `MONTO_ITBIS` y `TOTAL_LINEA`
(`SUBTOTAL + MONTO_ITBIS`), por `ID_DETALLE_COMPRA`.

## Reglas de negocio

- **Estos SP no escriben nada**: son la única puerta de lectura de las pantallas.
- **Los topes son fijos** (20 o 30 filas) en las versiones viejas: **(08/11/2026)
  las pantallas pasaron a las variantes `*_PAGINADO`, que traen de 10 en 10 con
  un `*_CONTAR_*` al lado. Las viejas quedan por compatibilidad, salvo
  `SP_VENTAS_PENDIENTES`, que la app todavía usa para resolver el saldo de una
  venta puntual.**
- **Sin validación de existencia**: un ID inexistente devuelve cero filas, nunca
  un error.
- **Heredan los filtros de sus vistas**: donde la vista incluye `EN_PROCESO` o
  `DEVUELTA`, el listado también.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Reporte de ventas paginado (ex módulo 60)

Absorbido el 14/11/2026 desde el ex módulo `60` (ver el `## Log` de
`odd/tasks/consolidacion-modulos.md`). El resto del `60` era **idéntico** a lo que
ya definen el `24`, el `21` y el `43`, así que se retiró entero.

- `SP_REPORTE_VENTAS_PAGINADO(P_FECHA_INICIO, P_FECHA_FIN, P_PAGINA, P_POR_PAGINA)`:
  una página del listado de ventas por rango (la fecha final entra completa), con
  las mismas columnas de `VW_REPORTE_VENTAS`. Rango invertido → error. Permiso:
  `CONSULTAR_REPORTES`.
- `SP_CONTAR_REPORTE_VENTAS(P_FECHA_INICIO, P_FECHA_FIN)`: el total del mismo
  rango, para el "Página 1 de N".

> El reporte por rango no tiene tope y un mes de ventas no entra en una pantalla.
> La app pasó a usar este par; `SP_REPORTE_VENTAS` queda por compatibilidad.

## GANANCIAS (ex módulo 38)

Ganancia por línea vendida: absorbida dentro del `39` el 14/11/2026 (ver «Estado
de la documentación» y el `## Log` de `odd/tasks/consolidacion-modulos.md`). El
cuerpo del ex `38` viaja **verbatim**: acá solo se degradaron los encabezados un
nivel.

Ganancia por línea vendida, a partir de la **foto histórica**
`DETALLES_VENTA.MONTO_GANANCIA`, neta de devoluciones aprobadas. Solo lectura.
La ganancia va sobre la **base sin IVA**: el impuesto no es ganancia.

**Depende de:** `DETALLES_VENTA` (21), `VENTAS` (21) y `DEVOLUCIONES` (26).
**Es usado por:** `ventas.cpp` (`SP_REPORTE_PERIODO_GANANCIA`). Las dos vistas, no.

Fuente: `modulos/39- LECTURAS_VENTAS.sql`, sección del ex módulo `38` · Base:
`BALBU_TECH` · Revisado: 20/10/2026 · Fusionado: 14/11/2026.

> **Las dos vistas viven al final del archivo, y los SP que las consultan están
> arriba.** No rompe nada: MariaDB no valida las tablas ni las vistas del cuerpo
> de una rutina al crearla, solo al ejecutarla (mismo criterio que ya estaba
> documentado para los triggers y para los `SP` de devolución del `19`). Al
> terminar el import existen las dos.

### Vistas

#### `VW_GANANCIAS`

Una fila por línea de venta: `PRODUCTO`, `CANTIDAD`, `PRECIO_UNITARIO`,
`SUBTOTAL`, `ITBIS`, `TOTAL_LINEA` (subtotal + ITBIS), `COSTO_TOTAL`,
`GANANCIA`, `GANANCIA_DEVUELTA` y `GANANCIA_NETA`.

- `COSTO_TOTAL = SUBTOTAL − MONTO_GANANCIA`, o `NULL` si el costo se desconoce.
- `GANANCIA_DEVUELTA` = `SUM(MONTO_GANANCIA_REEMBOLSADA)` de las devoluciones
  `APROBADA`/`REEMBOLSADA` de esa línea, `0` si no hay.
- `GANANCIA_NETA = IFNULL(GANANCIA, 0) − GANANCIA_DEVUELTA`.

> **`NULL` se convierte en 0 en la neta.** Una línea con costo desconocido
> aporta `0` de ganancia en vez de quedar marcada: el total **subestima** la
> ganancia real sin avisar.
>
> **No filtra por estado de la venta**: incluye `EN_PROCESO` (todavía no cobrada)
> y `DEVUELTA`. Sirve para mirar líneas, no para un total contable.

#### `VW_GANANCIAS_MENSUAL`

Agrupada por `MES` (`'YYYY-MM'`): `VENTAS` (distintas), `SUBTOTAL`,
`GANANCIA_BRUTA`, `GANANCIA_DEVUELTA` y `GANANCIA_NETA`, del mes más nuevo al
más viejo.

> **Solo excluye `CANCELADA`**: las ventas `EN_PROCESO` — nunca cobradas — y las
> `DEVUELTA` **sí** suman. Es la diferencia clave con los reportes de ventas, que
> filtran `REALIZADA`. Comparar este total contra `SP_REPORTE_PERIODO` (24) da
> distinto, y no es un error de cuenta: son universos diferentes.
>
> Los meses **sin ventas no aparecen** (agrupa sobre `VENTAS`, sin calendario).

### Procedimientos almacenados

#### `SP_REPORTE_PERIODO_GANANCIA(P_DESDE, P_HASTA)`

**Usada por la app** (`ventas.cpp`). Una fila por rango **inclusive**:
`TRANSACCIONES`, `SUBTOTAL`, `BRUTA`, `DEVUELTA` y `NETA`.

- fechas nulas → `ERROR: DEBE INDICAR DESDE Y HASTA.`
- `DESDE > HASTA` → `ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.`

Mismas fórmulas de `VW_GANANCIAS`, sin IVA, y **también excluye solo
`CANCELADA`**.

> **Misma asimetría que la vista:** una venta `EN_PROCESO` cuenta como ganancia
> antes de cobrarse. Es el espejo de `SP_REPORTE_PERIODO` (24) en estructura,
> pero **no en el filtro de estado**: aquel usa `REALIZADA`.

### Reglas de negocio

- **La ganancia es un snapshot al vender** (`precio − costo` del momento), no se
  recalcula si después cambia el costo del producto.
- **Se mide sobre la base sin IVA.**
- **Las devoluciones aprobadas descuentan la ganancia** proporcional.
- **Costo desconocido = `NULL`**, y en los totales cuenta como `0`.
- **`CANCELADA` queda afuera; `EN_PROCESO` y `DEVUELTA` entran.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
