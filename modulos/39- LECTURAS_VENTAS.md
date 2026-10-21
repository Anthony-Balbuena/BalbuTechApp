# Módulo 39 — LECTURAS_VENTAS

**Puertas de solo lectura** para la app C++ (fase 3, 13/10/2026): todo lo que las
pantallas de ventas y compras muestran sale por estos 14 SP, sin un solo `SELECT`
a mano en el `.cpp`.

**Depende de:** `VISTA_VENTA_CON_IVA` y `VISTA_COMPRA_CON_IVA` y
`VISTA_VENTAS_PENDIENTES_PAGO` (43), `VISTA_RESUMEN_PAGOS` (24),
`VW_GANANCIAS` y `VW_GANANCIAS_MENSUAL` (38), `DETALLES_VENTA` (23),
`DETALLE_COMPRA` (22) y `DEVOLUCIONES` (26).

> **Todos los SP están en uso.** Es el módulo con mejor cobertura de la app: cada
> uno tiene su llamada en `ventas.cpp` o `compras.cpp`.

Fuente: `modulos/39- LECTURAS_VENTAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Lecturas de ventas (`ventas.cpp`)

### `SP_VENTAS_ULTIMAS()`

Las **20** ventas más recientes de `VISTA_VENTA_CON_IVA`: `ID_VENTA`, `CLIENTE`,
`FECHA`, `ESTADO`, `SUBTOTAL`, `ITBIS`, `TOTAL_CON_IVA`. Sin paginar.

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

### `SP_PAGOS_ULTIMOS()`

Los **20** pagos más recientes de `VISTA_RESUMEN_PAGOS` (con `ID_VENTA`).

### `SP_DETALLES_VENDIDOS_ULTIMOS()`

Las **20** líneas vendidas más recientes: `ID_DETALLE_VENTA`, `ID_VENTA`,
`PRODUCTO`, `CANTIDAD`.

> **No filtra por estado de la venta**: muestra líneas de ventas canceladas como
> si fueran ventas.

### `SP_DEVOLUCION_PENDIENTE_POR_DETALLE(P_ID_DETALLE)`

El `ID_DEVOLUCION` de la **última** devolución `PENDIENTE` de esa línea, o cero
filas. Se usa para no abrir dos reclamos sobre la misma línea.

### `SP_VENTAS_PENDIENTES()`

Las **20** ventas más recientes de `VISTA_VENTAS_PENDIENTES_PAGO` (43):
`ID_VENTA`, `ID_CLIENTE`, `ESTADO`, `TOTAL`, `PAGADO`, `SALDO`.

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

### `SP_COMPRA_ENCABEZADO(P_ID_COMPRA)`

La misma fila para **una** compra. Sin ID válido, cero filas.

### `SP_COMPRA_LINEAS(P_ID_COMPRA)`

Líneas de la compra: `ID_DETALLE_COMPRA`, `PRODUCTO`, `CANTIDAD`,
`PRECIO_UNITARIO` (**neto**), `SUBTOTAL`, `MONTO_ITBIS` y `TOTAL_LINEA`
(`SUBTOTAL + MONTO_ITBIS`), por `ID_DETALLE_COMPRA`.

## Reglas de negocio

- **Estos SP no escriben nada**: son la única puerta de lectura de las pantallas.
- **Los topes son fijos** (20 o 30 filas): no hay paginación; el resto de la
  historia no se puede ver desde la app.
- **Sin validación de existencia**: un ID inexistente devuelve cero filas, nunca
  un error.
- **Heredan los filtros de sus vistas**: donde la vista incluye `EN_PROCESO` o
  `DEVUELTA`, el listado también.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
