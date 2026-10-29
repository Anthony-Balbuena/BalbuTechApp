# 60 - Venta neta y reportes con devoluciones

## Que hace

Crea `VW_VENTA_NETA`, la unica definicion del neto de una venta despues de
sus devoluciones `APROBADA` o `REEMBOLSADA`. Sobre esa vista corrige los
reportes, el cierre de caja y los topes de pago.

Objetos que reemplaza:

- Vistas: `VW_VENTA_NETA`, `VISTA_VENTAS_PENDIENTES_PAGO`,
  `VW_REPORTE_VENTAS`.
- Triggers de pagos: `TR_VALIDAR_MONTO_PAGO`, `TR_AUTO_FINALIZAR_VENTA`,
  `TR_VALIDAR_UPDATE_PAGO`, `TR_RECALCULAR_ESTADO_PAGO_UPDATE`,
  `TR_RECALCULAR_ESTADO_PAGO_BORRADO`.
- Trigger de ventas: `TR_VALIDAR_ACTUALIZACION_VENTA` (el pase a
  `REALIZADA` ahora exige el 100 % del bruto neto).
- SP: `SP_ANULAR_PAGO`, `SP_CIERRE_CAJA`, `SP_REPORTE_PERIODO`.

## Por que

Hasta el 29/10/2026 los reportes restaban el ITBIS reembolsado pero no el
`SUBTOTAL_REEMBOLSADO`. Una devolucion parcial dejaba el bruto y el saldo
inflados. `VENTAS.TOTAL` es el subtotal original y no se toca: la historia
no se reescribe, el neto se calcula.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/60- VENTA_NETA.sql"
```

Es idempotente: usa `CREATE OR REPLACE VIEW` y `DROP`/`CREATE` de triggers
y SPs.

## Que preserva

- `VENTAS.TOTAL` y `VISTA_VENTA_CON_IVA` quedan intactos: el comprobante
  original sigue mostrando la venta como se hizo.
- Las devoluciones `PENDIENTE` y `RECHAZADA` no afectan el neto.
- Compras no se toca: ahi el trigger ya resta `SUBTOTAL_DEVUELTO` de
  `COMPRAS.TOTAL` y restarlo otra vez seria doble descuento.

## Que no hace

- No registra la salida de dinero del reembolso en caja. Hoy `PAGOS` es
  solo entradas; el tratamiento del egreso queda para una fase aparte.
- No ajusta el bono del 1 % ya generado: sigue calculado sobre el subtotal
  original al momento del cobro.
