# Módulo 43 — VISTAS_REPORTES

Las **cinco vistas de reportes** que cruzan compras, ventas y devoluciones. Se
importan al final a propósito.

**Depende de:** `COMPRAS` y `DETALLE_COMPRA`/`DEVOLUCION_COMPRA` (19),
`PAGOS_COMPRA` (19), `VENTAS` (21), `PAGOS` (24), `DEVOLUCIONES` (26),
`CLIENTES` (4), `PROVEEDORES` (5) y `EMPLEADOS` (8).
**Son usadas por:** `SP_COMPRAS_PENDIENTES` (19), `SP_REPORTE_VENTAS` (24),
`SP_VENTAS_ULTIMAS`, `SP_VENTA_ENCABEZADO`, `SP_COMPRAS_ULTIMAS`,
`SP_COMPRA_ENCABEZADO` y `SP_VENTAS_PENDIENTES` (39).

> **Ninguna vista se consulta desde la app**: el C++ no las menciona. Siempre hay
> un `SP` en el medio.

## Por qué este módulo existe

MariaDB **valida las tablas referenciadas al crear una vista**. Las cinco leen
`DETALLE_COMPRA`/`DEVOLUCION_COMPRA` (19) y `DEVOLUCIONES` (26), que se importan
**después** de los módulos donde estaban definidas (19, 21 y 24). En una
base existente nunca fallaban porque las tablas ya estaban; en una reconstrucción
desde cero el `CREATE VIEW` fallaba y el import, con `--force`, **seguía sin las
cinco vistas**.

**Este módulo corre después del 42, cuando ya existen todas las tablas. No
cambiar el número sin revisar el orden del import.**

## Vistas

### `VW_COMPRA_NETA`

La base **numérica** de una compra, en un solo lugar. Espejo de `VW_VENTA_NETA`
(ventas), que ya funcionaba así. No junta `PROVEEDORES` a propósito: el nombre
lo agrega quien presenta.

`ID_COMPRA`, `ID_PROVEEDOR`, `FECHA`, `ESTADO`, `SUBTOTAL_ORIGINAL` (=
`COMPRAS.TOTAL`), `ITBIS_ORIGINAL`, `ITBIS_REEMBOLSADO`, `ITBIS_NETO`,
`BRUTO_NETO`, `PAGADO` y `SALDO`.

> (15/11/2026) **Existe para terminar con la fórmula repetida.** El bruto
> (`TOTAL + ITBIS de las líneas − ITBIS devuelto`) estaba escrito a mano en más
> de un lugar y en **dos estilos distintos**: `VISTA_COMPRA_CON_IVA` lo armaba
> con `JOIN` + `SUM`, y `VISTA_COMPRAS_PENDIENTES_PAGO` con subconsultas
> correlacionadas, **dos veces en la misma vista** (en el `SELECT` y otra vez en
> el `WHERE`). Editar una copia y no la otra desincronizaba el reporte contra el
> listado de pendientes, en silencio.

### `VISTA_COMPRA_CON_IVA`

`ID_COMPRA`, `PROVEEDOR`, `FECHA`, `ESTADO`, `SUBTOTAL` (= `COMPRAS.TOTAL`),
`ITBIS` y `TOTAL_CON_IVA`.

- `ITBIS` = ITBIS de las líneas − ITBIS devuelto de las devoluciones
  **`PROCESADA`**.
- `TOTAL_CON_IVA` = `SUBTOTAL` + `ITBIS`.

> (15/11/2026) Los números salen de **`VW_COMPRA_NETA`**: acá solo se le agrega el
> nombre del proveedor. Antes repetía la fórmula, y la misma fórmula vivía en
> otros lugares con otro estilo.

> **Ojo con la mercancía devuelta:** acá **no** se resta, y es a propósito.
> `COMPRAS.TOTAL` **ya viene reducido** por el trigger
> `TR_PROCESAR_DEVOLUCION_COMPRA` (19), que hace `TOTAL = TOTAL - SUBTOTAL_DEVUELTO`
> al procesar la devolución. Restarlo otra vez en la vista contaría la devolución
> dos veces y bajaría de más lo que se le debe al proveedor.

### `VISTA_COMPRAS_PENDIENTES_PAGO`

Las compras **no canceladas** con saldo distinto de cero: `ID_COMPRA`,
`PROVEEDOR`, `FECHA`, `TOTAL`, `PAGADO`, `SALDO`, `ESTADO`, de la más nueva a la
más vieja.

> **El saldo puede ser negativo**: significa dinero a favor (compra devuelta que
> ya estaba pagada). Filtra `SALDO <> 0`, así que esos casos **se muestran**.
>
> (15/11/2026) La fórmula del `SALDO` salía de `VW_COMPRA_NETA`, y el `WHERE` usa
> el mismo `SALDO` que el `SELECT`: ya no pueden divergir. Antes estaba escrita
> dos veces con subconsultas correlacionadas, más lenta que los `JOIN` agrupados
> de su hermana.

### `VISTA_VENTA_CON_IVA`

`ID_VENTA`, `CLIENTE`, `FECHA`, `ESTADO`, `SUBTOTAL` (= `VENTAS.TOTAL`), `ITBIS`
y `TOTAL_CON_IVA`.

- `ITBIS` = ITBIS de las líneas − ITBIS reembolsado de las devoluciones
  **`APROBADA`/`REEMBOLSADA`**.
- `TOTAL_CON_IVA` = `SUBTOTAL` + `ITBIS`.

> **Misma asimetría que en compras**: devolver mercancía **no baja** el subtotal
> de la venta; solo se descuenta el ITBIS devuelto. El `TOTAL` de la venta queda
> intacto aunque el cliente haya devuelto todo.
>
> **El estado de la devolución se repite literal** (`IN ('APROBADA',
> 'REEMBOLSADA')`) en tres vistas y en el trigger de pagos: un estado nuevo de
> devolución hay que agregarlo en todos lados.

### `VISTA_VENTAS_PENDIENTES_PAGO`

Las ventas **no canceladas ni devueltas** con `SALDO > 0`: `ID_VENTA`,
`ID_CLIENTE`, `ESTADO`, `TOTAL`, `PAGADO`, `SALDO`, `FECHA` y `HORAS_ABIERTA`
(horas desde que se abrió, calculadas con `NOW()`).

> **`DEVUELTA` desaparece del listado** aunque tenga saldo: el reporte asume que
> a una venta devuelta no se le cobra nada. Es una decisión de negocio, y está
> solo acá — no en un `CHECK` ni en un trigger.
>
> **`SALDO > 0`, no `<> 0`:** una devolución parcial puede dejar el saldo en
> negativo (a favor del cliente) y esas filas no son deuda, así que no se listan.
>
> **Un borrador `EN_PROCESO` sin líneas queda afuera**: su total es 0, así que su
> saldo es 0. Por eso el aviso de borradores viejos sale por
> `SP_VENTAS_BORRADOR_VIEJO` (39) y no por esta vista.
>
> Lee de `VW_VENTA_NETA` con un `WHERE`; el filtro de estado y saldo vive en la
> vista, no en quien la consulta.

### `VW_REPORTE_VENTAS`

Una fila por venta, con **todo**: `ID_VENTA`, `FECHA`, `ESTADO`, `EMPLEADO`,
`CLIENTE`, `FACTURA`, `TOTAL`, `PAGADO`, `SALDO`.

> **No excluye nada**: canceladas y devueltas aparecen, con su saldo tal cual
> (puede ser negativo). Está documentado en el propio archivo; quien quiere solo
> lo cobrable usa `VISTA_VENTAS_PENDIENTES_PAGO`.
>
> **`JOIN` (no `LEFT JOIN`) a `EMPLEADOS` y `CLIENTES`**: si faltara el empleado
> o el cliente, la venta desaparece del reporte sin aviso.
>
> **Es la vista más cara de las cinco**: tres subconsultas correlacionadas por
> fila. `SP_REPORTE_VENTAS` (24) la filtra por rango de fechas, pero el motor
> igual tiene que resolver cada subconsulta para las filas del rango.

## Reglas de negocio

- **El "total con IVA" (BRUTO) es `TOTAL + ITBIS de líneas − ITBIS devuelto`**,
  en compras y en ventas.
- **Solo las devoluciones que mueven dinero descuentan**: `PROCESADA` en compras,
  `APROBADA`/`REEMBOLSADA` en ventas.
- **La mercancía devuelta no baja el subtotal**, solo su ITBIS.
- **Un saldo negativo es dinero a favor**, no un error.
- **Se importan al final** porque MariaDB valida las tablas al crear la vista.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
