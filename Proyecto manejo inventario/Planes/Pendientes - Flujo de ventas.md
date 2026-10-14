    # Pendientes — Flujo de ventas

> **✅ FLUJO COMPLETO CERRADO (07/10/2026).** Detalle movido a `Realizado.md` (BD) el 14/10/2026.

## P11 + P12 — fixes operativos (CERRADOS ✅)


## Parte 1b — stock atómico (CERRADA ✅)

                                                                                                                                                                                                                                                                        
## Parte 2 (cobro) — CERRADA ✅ (avances P8/P9 aquí; ejecución en "flujo completo")


## Pendientes del flujo completo


## Notas sueltas

- El cambio de A1 vive en `modulos/20- MOVIMIENTOS_INVENTARIO.sql` (lo viejo quedó comentado arriba de lo nuevo).
- Los archivos del repo usan `END ;` dentro de `DELIMITER //`; para cargarlos con el cliente `mariadb` hay que pasarlos a `END //` (o usar el loader).
- Al recrear un trigger se mueve al **final** de su cola: revisar siempre `information_schema.TRIGGERS.ACTION_ORDER` después de tocar cualquiera de `DETALLES_VENTA`. *(En MariaDB la columna es `ACTION_TIMING`, no `TRIGGER_TIMING`.)*
- `21.5- HISTORIAL_ESTADOS_VENTA.sql` usa finales **LF** (el resto de `modulos/` es CRLF): al editarlo, preservar LF.
- Suites de pruebas: `Proyecto manejo inventario/Pruebas/test_blindaje_p3.sql` (correr con `mariadb --force`).
