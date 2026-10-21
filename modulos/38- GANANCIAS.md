# Módulo 38 — GANANCIAS

Ganancia por línea vendida, a partir de la **foto histórica**
`DETALLES_VENTA.MONTO_GANANCIA`, neta de devoluciones aprobadas. Solo lectura.
La ganancia va sobre la **base sin IVA**: el impuesto no es ganancia.

**Depende de:** `DETALLES_VENTA` (23), `VENTAS` (21) y `DEVOLUCIONES` (26).
**Es usado por:** `ventas.cpp` (`SP_REPORTE_PERIODO_GANANCIA`). Las dos vistas, no.

Fuente: `modulos/38- GANANCIAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Vistas

### `VW_GANANCIAS`

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

### `VW_GANANCIAS_MENSUAL`

Agrupada por `MES` (`'YYYY-MM'`): `VENTAS` (distintas), `SUBTOTAL`,
`GANANCIA_BRUTA`, `GANANCIA_DEVUELTA` y `GANANCIA_NETA`, del mes más nuevo al
más viejo.

> **Solo excluye `CANCELADA`**: las ventas `EN_PROCESO` — nunca cobradas — y las
> `DEVUELTA` **sí** suman. Es la diferencia clave con los reportes de ventas, que
> filtran `REALIZADA`. Comparar este total contra `SP_REPORTE_PERIODO` (24) da
> distinto, y no es un error de cuenta: son universos diferentes.
>
> Los meses **sin ventas no aparecen** (agrupa sobre `VENTAS`, sin calendario).

## Procedimientos almacenados

### `SP_REPORTE_PERIODO_GANANCIA(P_DESDE, P_HASTA)`

**Usada por la app** (`ventas.cpp`). Una fila por rango **inclusive**:
`TRANSACCIONES`, `SUBTOTAL`, `BRUTA`, `DEVUELTA` y `NETA`.

- fechas nulas → `ERROR: DEBE INDICAR DESDE Y HASTA.`
- `DESDE > HASTA` → `ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.`

Mismas fórmulas de `VW_GANANCIAS`, sin IVA, y **también excluye solo
`CANCELADA`**.

> **Misma asimetría que la vista:** una venta `EN_PROCESO` cuenta como ganancia
> antes de cobrarse. Es el espejo de `SP_REPORTE_PERIODO` (24) en estructura,
> pero **no en el filtro de estado**: aquel usa `REALIZADA`.

## Reglas de negocio

- **La ganancia es un snapshot al vender** (`precio − costo` del momento), no se
  recalcula si después cambia el costo del producto.
- **Se mide sobre la base sin IVA.**
- **Las devoluciones aprobadas descuentan la ganancia** proporcional.
- **Costo desconocido = `NULL`**, y en los totales cuenta como `0`.
- **`CANCELADA` queda afuera; `EN_PROCESO` y `DEVUELTA` entran.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
