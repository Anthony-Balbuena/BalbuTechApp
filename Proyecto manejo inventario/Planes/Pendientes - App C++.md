# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje, unique_ptr, pausa y autologin pruebas: hechos ✅ (10-11/10). Push: lo hace el usuario.


## C++ críticos (barrido 10/10, verificados)



## BD medios (barrido 10/10, con línea)


## Web / Docker (barrido 10/10)


- [ ] `Pagina_Web` es mock (`Math.random()`); CDN sin SRI
- [ ] Sin `.env` (HECHO aquí 14/10: `.env` creado, gitignored); seed `admin/admin123` se deja como está (decisión del dueño 14/10)
- [ ] `.devcontainer` abandonado; labels de tasks desactualizados

## Menú ventas (revisión 12/10, solo con SPs/vistas existentes)

> Hechos movidos a `Realizado.md` (14/10/2026).
- [x] Garantías/reclamos UI (HECHO 14/10: `12. Garantias` en ventas con registrar/reclamar/finalizar).
- [x] Historial de estados (HECHO 14/10: `13. Historial de venta` con `SP_HISTORIAL_VENTA`).
- [x] Ayudante único para todo ID/monto a ciegas (HECHO 15/10: `leerNumeroConIntentos` en seguridad.h/cpp + 19 puntos de pagos y devoluciones migrados; detalle en `Realizado.md`).
- [ ] Barrido restante de entradas a ciegas: `cancelarVentaUI`, reportes por período, historial y vistas (login y cierres mantienen su bucle propio de 3).
