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

- [ ] Reporte de stock crítico en app (el SP `SP_REPORTE_STOCK_CRITICO` existe, falta pantalla).
- [ ] Kardex por producto en app (la bitácora `MOVIMIENTOS_INVENTARIO` ya se guarda, falta consulta por ítem).

## Progreso


## Archivos tocados

- `ventas.h`, `ventas.cpp` (nuevo).
- `roles.cpp` (include + menús + cases + permisos).
- `modulos/19- COMPRAS.sql`, `modulos/23- DETALLE_VENTA.sql` (solo comentarios ITBIS 11/10/2026).
