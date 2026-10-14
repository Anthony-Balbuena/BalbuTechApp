# Plan — Cobrar compra colgada

> EJECUTADO 14/10/2026 (renombrado a Pagar compra: en compras se paga).
> Detalle en `Realizado.md`.

## Parte 1 — BD: `SP_COMPRAS_PENDIENTES()`

- En `19.5- PAGOS_COMPRA.sql` (junto a su vista):
  `SELECT ID_COMPRA, PROVEEDOR, ESTADO, PAGADO, SALDO FROM VISTA_COMPRAS_PENDIENTES_PAGO ORDER BY ID_COMPRA DESC LIMIT 20`.
- Sin `DEFAULT`, con `DROP IF EXISTS` (reglas 14/10).
- La vista ya existe y salda a BRUTO excluyendo CANCELADA: no se toca.

## Parte 2 — C++: `5. Cobrar compra`

- `cobrarCompraUI()` en `compras.cpp`, espejo de `cobrarVentaUI()`:
  lista COMPRA/PROVEEDOR/ESTADO/PAGADO/SALDO, pide solo ID compra
  (el empleado lo pide `pagarCompra`, Enter = dueño), re-lee el SALDO,
  arma `CierreCompra` con bruto = saldo y llama `pagarCompra(c)`.
- Menú: `5. Cobrar compra`, Volver pasa a 6.

## Parte 3 — Verificación sin ensuciar

- `INFORMATION_SCHEMA` para el SP + `INFORMATION_SCHEMA` ya probada.
- E2E de listado + selección con `xxx` (cancela antes de pagar):
  la #2 debe salir con su SALDO real. El pago real lo hace el usuario.
- Agregar los 4 SP nuevos (`PERIODO` x3 + este) a `db/check-app-sps.sh`
  para que el chequeo los cubra.
- `build.sh` OK. Sin residuos.
