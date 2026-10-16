# Realizado

> Consolidado el 14/10/2026: todo lo terminado, movido de las notas. Lo pendiente sigue en su nota original.

## BD — base de datos

### Esquema y costos
- `P_COMPRA` en PRODUCTOS (12/10): nace en 0 = pendiente de factura. Estimados al 80% no son reales.
- Renombre `COSTO` → `P_COMPRA` (9, triggers del 22, lecturas). El parámetro del SP quedó `P_COSTO` (posicional, no afecta). Datos intactos.
- `SP_INSERTAR_PRODUCTO` de 9 parámetros, con `P_COMPRA` antes del precio (13-14/10). Valida `>= 0`. Recargado en TEST y TECH.
- `SP_ACTUALIZAR_PRODUCTOS` acepta `P_COSTO` (NULL conserva, negativo rechaza).
- `MONTO_ITBIS` + `MONTO_GANANCIA` en DETALLES_VENTA; `MONTO_ITBIS_REEMBOLSADO` (+ ganancia reembolsada) en DEVOLUCIONES.
- `SP_AGREGAR_DETALLE_VENTA`: ITBIS con tasa vigente + ganancia snapshot; fix `COSTO` → `P_COMPRA`; costo 0/NULL = ganancia desconocida (no se inventa).
- Las compras mandan `P_COMPRA` (trigger del 22 + recompute al borrar).

### Vistas y lecturas
- `VISTA_VENTA_CON_IVA` (11/10): SUBTOTAL + ITBIS de líneas − ITBIS devuelto = TOTAL final. El TOTAL no se toca.
- `VW_GANANCIAS` + mensual (38): por línea y por mes, sin IVA, neto de devoluciones. Solo reportes internos, nunca en factura.
- `39- LECTURAS` (10 SP de solo lectura) + `FN_TASA_ITBIS()` (33).
- `SP_CONSULTAR_PRODUCTOS_FILTRADO`: STOCK por LEFT JOIN + filtros por ID + PROVEEDOR. Inventario trae `P_COMPRA`.
- Reportes mudados del 37 al 24: vista + 2 SPs, SALDO a BRUTO. Import fresco: 39 archivos, 0 avisos.

### Flujos y blindaje
- Ventas cerrado 07/10 y Compras cerrado 08/10 (Partes 1, 1b, 2, 3, 4, 5 y 7). Fixes P11/P12. Stock atómico. Suites verdes, residuos 0.
- Pago a BRUTO (11/10): 6 comparadores + vista de pendientes. Suites `t_pago_bruto` verdes.
- Cierre de caja, `SP_REPORTE_VENTAS` por rango, ver pagos de una venta.
- Módulo Compras 1-4 (13/10): triggers de pago-compra a BRUTO (7 puntos + vista). Suites verdes.

### Sincronización sede trabajo (14/10)
- Columnas y vistas aplicadas a la BD viva; import 41 archivos, 0 avisos; 10/10 SPs de compras; `FN_TASA_ITBIS() = 18.00`.
- Reporte por período ventas + compras + ganancias (mismo flujo, datos reales, sin `rand()`).
- `5. Pagar compra` (espejo de ventas; en compras se paga, no se cobra): `SP_COMPRAS_PENDIENTES()` en el 19.5 + pantalla con `Monto pagado`; probado con `xxx` sin pagar.
- Abonos (14/10): `pagarCompra` manda lo tipeado (valida >0 y <= pendiente, muestra saldo restante). Probado en vivo con compra TEST #3: abono 3.00 (ABIERTA, saldo 5.00), pago anulado, compra cancelada, producto TEST a INACTIVO. La BD prohíbe borrar filas (residuo: #3 CANCELADA, excluida de reportes).
- Fix `DEFAULT` en params de SP (MariaDB no lo soporta): `1- CATEGORIAS` (5), `24- PAGOS` (1), `28- LOG` (1). La app ya manda aridad completa. `import.sh` ahora cuenta errores reales de sentencia en vez de mentir con "0 avisos".

### Sincronización sede trabajo (15/10)
- Pull de casa aplicado a la viva del trabajo: módulos `20` (kardex), `21.5` (historial), `40` (suplidores) + formato de `2`; tabla `PRODUCTO_PROVEEDOR` + trigger + 7 SP nuevos → `check-app-sps`: 0 faltantes.
- Binario recompilado; humo en vivo: `3. Movimientos` (14 movimientos reales), `13. Historial de venta` (venta 3), submenú `12. Garantias`, `6. Precios por suplidor` (vacío correcto: sin compras RECIBIDA acá todavía).
- Nota: los IDs de marcas difieren entre sedes (acá 1=ASUS; casa 1=LENOVO) — el catálogo de casa NO se copia tal cual: si se carga acá, va con mapeo por nombre, no por ID.
- Catálogo cargado con tope de 10 por tabla (pedido 15/10): +10 categorías (PLACA MADRE…HOGAR INTELIGENTE), +10 marcas (LENOVO, DELL, APPLE, AMD, NVIDIA, INTEL, GIGABYTE, ASROCK, SAMSUNG, LG), +10 proveedores placeholder (`SUPLIDOR 01`–`10`, renombrables con los reales) y +10 productos (LAP-002…LAP-007, RYZ-004, CPU-003, RTX-004, RTX-001). Mapeo por nombre, verificado con `SP_CONSULTAR_PRODUCTOS_FILTRADO`. Precios estimados de referencia; entran con stock cuando se compren por el módulo.

## C++ — app

- Base 10-11/10: submenús 9/9, `unique_ptr`, drenaje de resultados, pausa, autologin de pruebas.
- Ventas Partes 1–4 (11/10): botón 10 por rol, carrito en memoria (sin tabla CARRITO), cierre con cancelación automática, pago por BRUTO + ticket. Detalle histórico en `Modulo Ventas Caja - 11-10-2026.md`.
- Menú ventas 12/10: devolución UI, cierre de caja, reporte por rango `AAAA-MM-DD`, ver pagos.
- Pantalla de pago 12/10: métodos por ID, `A PAGAR / RECIBIDO / DEVUELTO`.
- Costo en buscar-productos + `8. Ganancias` (mensual + líneas). Buscar alineado con CANTIDAD (`printf`).
- Update pide precio de compra; `2. Actualizar costo` en stock.
- Login envenenado (13/10): se drena antes del UPDATE de rehash; admin migra a PBKDF2.
- SELECTs a SP + `FN_TASA_ITBIS()` en la app; `9. Cobrar venta`.
- Compras 1–4 app (13/10): carrito a precio de compra, ticket BALBUTECH, pago por bruto, devolución. Botón `11. Compras` solo ADMIN (menú actual: 14 opciones).
- El alta pide precio de compra antes del de venta + muestra `El cliente pagará` con ITBIS.
- `entrar-local.ps1` local (ignorado): auto-login admin. Compila `OK`.
- Reporte por período ventas (14/10) + compras (`4.`, Volver a 5) + ganancias (`11.`, Volver a 12): `SP_REPORTE_PERIODO_COMPRA` (RECIBIDA) y `SP_REPORTE_PERIODO_GANANCIA` (fórmulas del 38, sin IVA). Probados en vivo.
- Revisión pull 14/10: quite `select *` de depuración en `2- MARCAS.sql`; cargué los 4 SP de período/pendientes en TEST y TECH (la app los llamaba y no existían); `check-app-sps` en TECH da 0 faltantes; reporte octubre en vivo cuadra (6 / 797000 / 143460 / 940460). Quitado de DEFAULTs en CATEGORIAS y PAGO: es el fix de import conocido, la app manda todos los args.
- Pendientes hechos 14/10: Kardex (`SP_KARDEX_PRODUCTO` + `3.` en stock, humo en vivo); Garantías (`12.` con registrar/reclamar/finalizar); Historial (`SP_HISTORIAL_VENTA` + `13.`); `.env` creado (gitignored). Falta tu decisión: seed admin, SRI del CDN, devcontainer y tus ganancias por mes.

## 15/10 — mapa suplidores, reintentos y etiquetas
- Mapa 6 pasos: tabla `PRODUCTO_PROVEEDOR` + trigger al RECIBIDA + 4 SP (archivo 40) + carrito elige suplidor por línea con historial + split por factura + `6. Precios por suplidor`. Verificado 2 suplidores, anular/cancelar; `check-app-sps` 0 faltantes en ambas.
- Reintentos al cerrar (compra y venta): 3 intentos estilo login, el carrito se conserva si falla.
- Rename `COSTO` → `P_COMPRA` (tabla, SPs, triggers, app); `P_COMPRA NOT NULL` con estimados al 80% (NO REALES, van facturas).
- JOIN de stock + filtros ID repuestos en SP productos; listados `ID | NOMBRE | ESTADO | P.COMPRA | STOCK`.
- `P.UNIT` en facturas de venta y compra; carrito muestra precios con ITBIS.

## 15/10 (tarde) — compra rápida y reporte de precios
- Helper `leerNumeroConIntentos` (seguridad.h/cpp, HECHO): 3 intentos por dato, rango min/max, punto o coma, `xxx` cancela, Enter = default donde aplica. Migrados 19 puntos de pagos y devoluciones (compras: pagarCompra método/monto/empleado, devolución, pagar pendiente; ventas: pagarVenta método/monto, cobrar, anular, devolución, garantía). Unificados `esNumerico` y `MAX_INTENTOS` (main.cpp incluye seguridad.h). Build OK.
- `SP_CONSULTAR_PRODUCTOS_FILTRADO` (9) devuelve `ID_PROVEEDOR`; aplicado a la viva.
- Compra rápida en 2 listas con grilla tipo Excel: inicial `ID_PROD | NOMBRE | CANTIDAD`; al elegir confirma `Producto: <id> (<nombre>)`; paso suplidor `ID_PROV | PROVEEDOR` (sin historial lista todos los activos). En prueba en vivo.
- Alta rápida de suplidor sin salir de la compra (`registroRapidoS` en compras.cpp): `0` = nuevo; ID inexistente o nombre ofrecen registrar; nombre obligatorio, tel/email opcionales. Fix `Commands out of sync` (drenar antes del retorno temprano). "Jose tech" creado en vivo desde la compra.
- Reporte `6. Precios por suplidor`: `SP_REPORTE_PRECIOS_COMPRA` (40) ahora trae `MAS_CARO` + `DONDE_CARO` (aplicado a la viva); pantalla `MAS BARATO | BARATO EN | MAS CARO | CARO EN | ULTIMA`. Verificado en vivo (DELL G15: barato Jose tech, caro PM6).
- Revisión 15/10: el pull ya traía todo (helper intentos, registro rápido suplidor, MAS_CARO). Faltaba en la viva: `SP_REPORTE_PRECIOS_COMPRA` con caro (recargado) + backfill del mapa (8 parejas, trigger solo llena desde que existe). `check-app-sps` en TECH: 0 faltantes. Compila `OK`.
- Barrido entradas a ciegas (15/10): `leerNumeroConIntentos` en inventario, productos, ventas y compras (pick, cantidades, cancelar, períodos, garantías, historial, devoluciones, registro). Los bucles de cerrar se quedan a mano: reintentan también errores de BD. Humo en vivo OK.
- Barrido de entradas ciegas a `leerNumeroConIntentos` (15/10): inventario, productos, ventas (pick, cantidad, cancelar, períodos, garantías, historial, devolución) y compras (registro, pick, cantidad, período). Cierres con bucle propio (reintentan errores de BD). Humo en vivo OK, compila OK.
