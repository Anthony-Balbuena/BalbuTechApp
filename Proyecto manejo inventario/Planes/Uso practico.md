# Uso práctico — Caja y ventas (11/10/2026)

Notas operativas para el uso diario. Lo que exige la base va primero.

## Cancelar una venta con pagos (orden obligatorio)

1. `4. Anular pago` por cada pago de la venta (pide ID pago + ID empleado).
2. `3. Cancelar venta` (pide ID venta + ID del empleado dueño).

Si se intenta cancelar con pagos pendientes, la base lo rechaza. El orden lo
exige el candado `TR_VALIDAR_ACTUALIZACION_VENTA`, no la app.

## Reglas de cancelación

- Solo ventas en `EN_PROCESO` y con cero pagos.
- Solo el empleado dueño (el que la inició) puede cancelarla.
- Al cancelar se repone el stock y queda el movimiento `ENTRADA` en bitácora.

## Anular un pago

- Si la venta estaba `REALIZADA`, vuelve a `EN_PROCESO` y se retira el bono
  pendiente del 1% (el bono se calcula sobre el SUBTOTAL).
- No se tocan pagos de ventas `CANCELADA` o `DEVUELTA`.

## Cobro

- Se cobra el TOTAL (bruto = SUBTOTAL + ITBIS − ITBIS devuelto).
- El parcial del carrito es sin IVA; el ticket muestra SUBTOTAL / ITBIS / TOTAL.
- Los precios con IVA incluido se muestran solo en pantalla; la base guarda
  neto + `MONTO_ITBIS` por línea.

## Carrito

- Vive solo en memoria: si se cierra la app antes de guardar, se pierde.
- Nada toca stock ni totales hasta cerrar la venta.
- Si una línea falla al cerrar, la venta se cancela sola para no dejar basura.
