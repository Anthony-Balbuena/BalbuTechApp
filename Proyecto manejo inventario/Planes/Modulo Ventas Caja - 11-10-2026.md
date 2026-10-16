# Módulo Ventas Caja (C++) — 11/10/2026

> Estado: en curso por partes. Parte 1 hecha. Parte 2 pendiente de aprobación.
> Alcance: solo C++ (`ventas.h/cpp`, `roles.cpp`). La base ya existe y no se modifica en este módulo.

## Terminología (acordada 11/10/2026)

- `SUBTOTAL` = suma de líneas sin IVA. Equivale a `VENTAS.TOTAL` / `COMPRAS.TOTAL`.
- `ITBIS` = impuesto por línea (`MONTO_ITBIS`), tasa de `CONFIGURACION`.
- `BRUTO a pagar` = `SUBTOTAL + ITBIS - ITBIS devuelto`. Se lee en `VISTA_VENTA_CON_IVA` (`TOTAL_CON_IVA`).
- El `TOTAL` nunca se recalcula con IVA para no romper pagos ni candados.

## Plan por partes

### Parte 1 — Botón Ventas global (HECHA 11/10/2026)
- Archivos: `ventas.h`, `ventas.cpp` (nuevo), `roles.cpp` (menú + permiso).
- Menú ADMIN `10. Ventas`, RRHH `5. Ventas`, EMPLEADO `3. Ventas`.
- Permiso `GESTIONAR_VENTAS` otorgado a los tres roles (decisión: modo simple).
- Submenú: `1. Venta rápida (pendiente)` + `2. Ver venta con IVA` (lee `VISTA_VENTA_CON_IVA`).
- Verificación: `bash build.sh` → `OK: ./output/app`.
- Nota: modo simple implica que todos pueden anular/cancelar. Pendiente futuro: separar `REGISTRAR_VENTA` de `GESTIONAR_VENTAS`.

### Parte 2 — Carrito por código/ID (HECHA 11/10/2026)
- Entrada: código de barra (= `CODIGO`), `ID_PRODUCTO` o nombre.
- Resolución con `SP_CONSULTAR_PRODUCTOS_FILTRADO` + lectura directa por ID.
- Agrupación en memoria por producto (`x2`, `x3`), muestra precio unitario y parcial.
- Sin tabla CARRITO (ver decisión abajo).
- Listado inicial con `SP_CONSULTAR_INVENTARIO('')` (ID/CODIGO/NOMBRE/PRECIO/STOCK), como el buscar-con-Enter de categorías.

### Parte 3 — Cierre y totales (HECHA 11/10/2026)
- `21_SP_INICIAR_VENTA` → loop `SP_AGREGAR_DETALLE_VENTA` → lectura `VISTA_VENTA_CON_IVA`.
- Mostrar `SUBTOTAL / ITBIS / BRUTO`.
- Si una línea falla, `SP_CANCELAR_VENTA` automática para no dejar basura en `EN_PROCESO`.
- Archivos: `ventas.cpp` (`cerrarVenta`). Compila.

### Parte 4 — Pago y ticket (HECHA 11/10/2026, fix triggers 11/10/2026)
- Listar con `SP_LISTAR_METODOS_PAGO`, registrar con `24_SP_REGISTRAR_PAGO` por el BRUTO.
- El trigger pasa a `REALIZADA`. Mostrar vuelto con `MONTO_RECIBIDO`.
- Fix 11/10/2026 en `modulos/24- PAGOS.sql`: los 6 comparadores (`TR_VALIDAR_MONTO_PAGO`, `TR_AUTO_FINALIZAR_VENTA`, `TR_VALIDAR_UPDATE_PAGO`, `TR_RECALCULAR_ESTADO_PAGO_UPDATE`, `TR_RECALCULAR_ESTADO_PAGO_BORRADO`, `SP_ANULAR_PAGO`) ahora comparan contra el BRUTO (`TOTAL + ITBIS - ITBIS devuelto`, mismo de la vista). El bono 1% sigue sobre el SUBTOTAL. `VISTA_VENTAS_PENDIENTES_PAGO` ahora salda por BRUTO.
- Suites `t_pago_bruto*.sql` verdes en TEST (parcial/abierta, sobrepago frenado, bruto exacto REALIZADA + vuelto 64 + bono 2.00, anular reabre) y humo en TECH; residuos 0.
- Archivos: `ventas.cpp` (`pagarVenta` cobra `c.bruto`). Compila.

## Decisión: tabla CARRITO vs. memoria (11/10/2026)

Pregunta: ¿crear tabla CARRITO?

Respuesta: no. Usar vector en memoria en `ventas.cpp`.

- Tabla CARRITO: persiste entre sesiones y cajas, pero exige limpieza por usuario/caja, control de concurrencia y purga de abandonados. Riesgo de residuos y más transacciones.
- Memoria (vector): simple, sin residuos, rápido, suficiente para consola de una caja por ejecución. Se pierde al cerrar la app, lo cual es correcto para un ticket no iniciado en base.

Solo crear tabla si se requiere carrito persistente multi-caja o venta en pausa entre turnos. No es el caso actual.

## Multicaja tipo supermercado (11/10/2026)

- La base ya permite varias cajas a la vez: cada terminal corre su propio `output/app` contra la misma `BALBU_TECH` (`DB_HOST`), cada cierre abre su propio `#ID` y el trigger `TR_AUDITORIA_MOVIMIENTO_VENTA` descuenta con `UPDATE ... WHERE STOCK_ACTUAL >= cantidad`. La perdedora recibe `STOCK INSUFICIENTE` y cancela.
- Límite actual: `SP_CIERRE_CAJA(fecha)` es global del día, no por caja. No hay tabla `CAJA/TURNO` (fondo inicial, apertura por empleado, cierre por caja).
- Futuro: crear `CAJA/TURNO` para auditar cuánto hizo cada caja. Por ahora se opera multi-instancia simple + bono 1% por empleado.

## Pendiente inventario (11/10/2026, a pedido)

- [x] Reporte de stock crítico en app (HECHO 14/10: `6. Reporte De Stock` en productos, verificado en vivo).
- [x] Kardex por producto en app (HECHO 14/10: `3. Movimientos` en stock con `SP_KARDEX_*`).

## Pendiente reporte por periodo (13/10/2026, para después)

- [x] APP C++ (14/10/2026): `SP_REPORTE_PERIODO(desde, hasta)` real (solo REALIZADA, sin ganancia, consolidado = lo mostrado) + pantalla con el flujo del prototipo (año, meses, completo/días, tarjetas + consolidado). Sin `rand()`: ITBIS real. Movido a `Realizado.md`.
- [ ] WEB: API mínima (`GET /api/reporte`) que llame al mismo SP + adaptar `index.html` (fetch en vez de random) + deploy. La web hoy es estática con simulados.

## Pendiente ganancias (12/10/2026, para después)

- [x] Ver ganancias (14/10/2026): ya existe — `P_COMPRA` + `MONTO_GANANCIA` + `38- GANANCIAS.sql` + `8. Ganancias` en ventas. Tachado por desactualizado.
- [x] Ganancias por mes 15/10: cubierto con `11. Ganancias por periodo` + mensual en app (verificado en vivo).

## Progreso

- [x] Mapa suplidor-producto 6 pasos (14/10/2026): tabla `PRODUCTO_PROVEEDOR` + trigger al RECIBIDA + `SP_PRODUCTO_SUPLIDORES/HISTORIAL/REPORTE_PRECIOS/PROVEEDOR_ACTIVO` (archivo 40) + carrito elige suplidor por línea con historial + split por factura + `6. Precios por suplidor`. Verificado: 2 suplidores, trigger, reporte, anular/cancelar. TEST guarda #10/#11 CANCELADA + TProdS como evidencia.
- [x] Reintentos al cerrar (14/10/2026): proveedor/empleado/cliente con 3 intentos estilo login + el carrito se conserva si falla; en ventas igual. Humo en vivo OK (proveedor malo → reintenta → compra #7 ABIERTA). Nota TEST: la compra #7 quedó CANCELADA como evidencia (las compras no se borran por diseño) con su proveedor/empleado anclados por FK.
> Movido a `Realizado.md` (14/10/2026). Solo queda lo pendiente abajo.

## Archivos tocados

- `ventas.h`, `ventas.cpp` (nuevo).
- `roles.cpp` (include + menús + cases + permisos).
- `modulos/19- COMPRAS.sql`, `modulos/23- DETALLE_VENTA.sql` (solo comentarios ITBIS 11/10/2026).
