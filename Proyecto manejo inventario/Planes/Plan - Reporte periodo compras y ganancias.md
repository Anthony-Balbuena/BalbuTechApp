# Plan — Reporte por período: compras y ganancias

> EJECUTADO 14/10/2026. Detalle en `Realizado.md`.

## Parte 1 — Período de compras

- `SP_REPORTE_PERIODO_COMPRA(desde, hasta)` en `19- COMPRAS.sql`:
  una fila (TRANSACCIONES, SUBTOTAL, ITBIS, BRUTO) sobre `RECIBIDA`
  (espejo de REALIZADA: saldada al 100%). ITBIS de `DETALLE_COMPRA.MONTO_ITBIS`
  menos `DEVOLUCION_COMPRA.MONTO_ITBIS_DEVUELTO` (solo procesadas).
  Mismas validaciones NULL y DESDE>HASTA que el de ventas.
- Pantalla en `compras.cpp` (copia el flujo de `reportePeriodoUI`;
  helpers `diasEnMes`/`nombreMes`/`fmt2` duplicados como `esNumericoC`).
  Opción `4. Reporte por periodo`, Volver pasa a 5.
- Verificación: `INFORMATION_SCHEMA` + e2e por pipe + `build.sh` OK.

## Parte 2 — Período de ganancias

- `SP_REPORTE_PERIODO_GANANCIA(desde, hasta)` en `38- GANANCIAS.sql`:
  una fila (TRANSACCIONES, SUBTOTAL, BRUTA, DEVUELTA, NETA) con las
  fórmulas de `VW_GANANCIAS`, filtrado por `DATE(V.FECHA)`, excluye
  CANCELADA. Sin IVA (la ganancia va sin impuesto, regla del 38).
- Pantalla en `ventas.cpp`: tarjetas con bruta/devuelta/neta + consolidado.
  Opción `11. Ganancias por periodo`, Volver pasa a 12.
- Verificación: e2e por pipe contra mes con y sin costo (NULL honesto)
  + `build.sh` OK. Sin residuos (lo de prueba se cancela).

## Orden y reglas

1. Parte 1, probar, luego Parte 2 (no se mezclan archivos salvo menú de ventas).
2. Sin `DEFAULT` en params (regla 14/10). `CREATE` con `DROP IF EXISTS`.
3. Import del archivo tocado + verificación por `INFORMATION_SCHEMA`
   (no por exit code). `build.sh` al final de cada parte.
