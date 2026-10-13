# Flujo de trabajo — 13/10/2026

Todo lo hecho hoy. Traído de las notas con fecha para dejarlo junto.

## Ganancias: columnas pedidas

- Líneas con `VENTA | FECHA | PRODUCTO | CANT | ITBIS | P.COMPRA | P.VENTA | GANANCIA` (`VW_GANANCIAS` + `38- GANANCIAS.sql` con ITBIS y TOTAL_LINEA, app alineada).
- Corrección: precio de compra NO es el subtotal. Prueba con la fila `RX 7900 XTX`: `68440 − 58000 = 10440 ≠ 15000`. P.COMPRA es el costo real (`43000`) y así cuadra.

## Precio e ITBIS

- El `PRECIO` es base neta: el 18% se calcula desde ahí y se suma (`2000 → 3600... IVA 360 → paga 2360`). Verificado en `SP_AGREGAR_DETALLE_VENTA`.
- Decisión: no dar vuelta el modelo a impuesto incluido (reescribía 4 archivos y mezclaba historial). En registro de producto sale `El cliente pagará: $X (ITBIS incluido)`.

## Ajustar precio de compra

- Ajustar costo = precio al que compraste al proveedor, no el de venta.
- Displays a `P.COMPRA`: menú `Ajustar p.compra`, listados y buscar-productos.

## Renombre COSTO → P_COMPRA

- Columna y lecturas renombradas en `9- PRODUCTOS.sql`, triggers del 22, `inventario.cpp`, `productos.cpp`. Parámetro del SP quedó `P_COSTO` (posicional, no afecta). Datos intactos, verificado en TEST y TECH.

## P_COMPRA NOT NULL (prueba)

- Estimados al 80% del precio (`9600 / 41600 / 36000 / 28800`) — NO SON REALES, reemplazar por facturas de proveedor. Frescos nacen en `0` = pendiente. Archivos y TECH/TEST alineados.

## JOIN de stock + filtros ID

- `SP_CONSULTAR_PRODUCTOS_FILTRADO` trae `STOCK` (LEFT JOIN, sin fila igual lista). Filtros por ID repuestos (se habían perdido en una recarga) en los dos SP. Ajustar (opciones 1 y 2) lista `ID | NOMBRE | ESTADO | P.COMPRA | STOCK`. Verificado en TEST y TECH.
