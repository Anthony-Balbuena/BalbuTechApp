# Pendientes — Flujo de ventas

> Parte 1b (stock atómico) → A1 ✅ hecho. Esto es lo que queda.

## Pendientes de la Parte 1b

- [x] **A2** ✅ — Hecho (06/10/2026): 13 líneas de comentario en los bloques de `SP_AGREGAR_DETALLE_VENTA` y `TR_VALIDAR_STOCK_DETALLE_VENTA` (son *red de mensajes amigables*, no la garantía — la garantía es el `UPDATE` condicional del trigger en el archivo 20). Solo comentarios, cero SQL.
- [x] **A3** ✅ — Prueba de carrera real con **2 sesiones** (06/10/2026): 4 variantes, la segunda venta nunca se registró y cero residuos. Detectó que en carrera encadenada InnoDB aborta con `ERROR 1020` (ver P10). *Pendiente de este punto: recrear los suites viejos (`test_blindaje`, `smoke_fase1`, `test_fase_h`, `test_paquetito_j/k`).*
- [x] **A4** ✅ — Hecho (06/10/2026): secciones 14 (stock atómico, A1-A3) y 15 (P8) agregadas al final de `Contextos.opencodetxt/contexto tabla ventas.txt`, estilo de las secciones 6-13. 231 → 291 líneas, solo adiciones.

## Pendientes de la Parte 2 (cobro)

- [x] **P8** ✅ — Hecho (06/10/2026): `ID_EMPLEADO NOT NULL` + `FK_PAGO_EMPLEADO` en `PAGOS`; `24_SP_REGISTRAR_PAGO` valida al empleado (`ERROR: EL EMPLEADO NO EXISTE.`) en vez de poner `DESCONOCIDO`, y el `INSERT` guarda quién cobró; `VISTA_RESUMEN_PAGOS` con `NOMBRE_EMPLEADO`. Cuerpo viejo del SP comentado arriba del nuevo. Pruebas OK (pago 200 → `REALIZADA` + bono 2.00; empleado 9999 → error amigable), residuos 0. *Ojo: las bases TEST/PRE/V92 quedaron sin la columna.*
- [x] **P9** ✅ — Hecho (07/10/2026, Opción A): `MONTO_RECIBIDO DECIMAL(10,2) NULL CHECK (MONTO_RECIBIDO >= MONTO)` en `PAGOS`; `24_SP_REGISTRAR_PAGO` con param `DEFAULT NULL` (las llamadas viejas siguen sirviendo), validación `ERROR: EL MONTO RECIBIDO ES MENOR QUE EL PAGO.`, `INSERT` con `IFNULL` y mensaje con vuelto; `VISTA_RESUMEN_PAGOS` con `VUELTO`. `MONTO` no cambió de significado → saldos, cierre, cancelaciones y devoluciones intactos. Pruebas OK (vuelto 50, error amigable, llamada vieja sin param), residuos 0. *Ojo: TEST/PRE/V92 sin la columna. **Parte 1b cerrada** (A1·A2·A3·A4·P8·P10·P9).*
- [x] **P10** ✅ — Hecho (06/10/2026): el `ERROR 1020` **sí es alcanzable en producción** (los triggers de un `INSERT` comparten transacción: el BEFORE lee el stock sin candado y el AFTER lo descuento; repro en `autocommit` con triggers temporales; un proc en autocommit NO lo reproduce porque cada sentencia va sola). `SP_AGREGAR_DETALLE_VENTA` ahora trae `DECLARE EXIT HANDLER FOR 1020` → `'ERROR: STOCK INSUFICIENTE, INTENTE DE NUEVO.'` (`23- DETALLE_VENTA.sql`, +26 líneas, 0 borradas). Carrera determinista → mensaje amigable y residuos 0; regresión OK (ruta feliz y `ERROR: STOCK INSUFICIENTE.` normal intacto). *No se repartió a pagos/ventas: su INSERT candada VENTAS por FK (no demostrado).*

## Pendientes del flujo completo

- [ ] **Parte 2** — Cobro y cierre automático: `24_SP_REGISTRAR_PAGO`, `TR_VALIDAR_MONTO_PAGO`, `TR_AUTO_FINALIZAR_VENTA`, bono del 1%.
- [ ] **Parte 3** — Blindajes: `TR_VALIDAR_ACTUALIZACION_VENTA`, `@VENTAS_INTERNO`, orden de triggers, historial de estados.
- [ ] **Parte 4** — Cancelación y reversión de stock: `SP_CANCELAR_VENTA`, `SP_ANULAR_PAGO`.
- [ ] **Parte 5** — Devoluciones y garantías: `25- DEVOLUCIONES.sql`, `26- GARANTIAS.sql`.
- [ ] **Parte 6** — Módulo C++ `ventas.cpp` (no existe): menú + permiso `GESTIONAR_VENTAS`, alta, cobro, cancelación/listados.
- [ ] **Parte 7** — Reportes y cierre de caja: SP de listado, `VW_REPORTE_VENTAS` real, conectar `Pagina_Web` (hoy usa `Math.random()`).

## Notas sueltas

- El cambio de A1 vive en `modulos/20- MOVIMIENTOS_INVENTARIO.sql` (lo viejo quedó comentado arriba de lo nuevo).
- Los archivos del repo usan `END ;` dentro de `DELIMITER //`; para cargarlos con el cliente `mariadb` hay que pasarlos a `END //` (o usar el loader).
- Al recrear un trigger se mueve al **final** de su cola: revisar siempre `information_schema.TRIGGERS.ACTION_ORDER` después de tocar cualquiera de `DETALLES_VENTA`.
