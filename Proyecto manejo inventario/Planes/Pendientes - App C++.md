# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje, unique_ptr, pausa y autologin pruebas: hechos ✅ (10-11/10). Push: lo hace el usuario.


## C++ críticos (barrido 10/10, verificados)



## BD medios (barrido 10/10, con línea)


## Web / Docker (barrido 10/10)


- [ ] `Pagina_Web` es mock (`Math.random()`); CDN sin SRI
- [ ] Sin `.env`; seed `admin/admin123` en plano e inyectable
- [ ] `.devcontainer` abandonado; labels de tasks desactualizados

## Menú ventas (revisión 12/10, solo con SPs/vistas existentes)

- [x] Devolucion de venta (opcion 5): registrar + aprobar/rechazar. Hecho 12/10: devolucionVentaUI() en ventas.cpp + renumerado (Volver=6); e2e menu real (PENDIENTE, aprueba, stock 8->9).
- [x] Cierre de caja (opcion 7, Volver=8): SP_CIERRE_CAJA iterando sus 3 result sets. Hecho 12/10: e2e con pago del dia (resumen + por estado + por metodo).
- [x] Reporte de ventas por rango (opcion 6, Volver=7): SP_REPORTE_VENTAS con validacion AAAA-MM-DD. Hecho 12/10: e2e con datos, rango vacio e invertido (SIGNAL capturado).
- [x] Ver pagos de una venta (en opcion 2 tras listar: pide ID, Enter omite). Hecho 12/10: e2e muestra pagos.
- [ ] Garantías/reclamos UI (submenú propio; después del 1-3).
- [ ] Historial de estados (lectura a `21.5`, informativo).
