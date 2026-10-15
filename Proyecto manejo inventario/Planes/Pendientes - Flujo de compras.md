# Pendientes — Flujo de compras

> **✅ COMPLETO (08/10/2026).** Detalle movido a `Realizado.md` (BD) el 14/10/2026.

## Pendientes del flujo completo

- [x] **Parte 6** — HECHO 13/10: existe `compras.h/cpp` completo (carrito, ticket, pago, devolución).

## Fixes y cambios de archivos ejecutados ✅



## Decisiones pendientes


## Notas sueltas

- Contextos de compras ya existen (`contexto tabla compras.txt` con 21 secciones + detalle compra, pagos compra, devolucion compra, historial estados compra): las partes de este plan **documentan lo nuevo y lo que falte**, sin repetir lo ya registrado.
- Mismas reglas de siempre: respaldo previo, "lo viejo comentado arriba + nuevo debajo" al editar, pruebas en `ROLLBACK` con residuos 0, y registro en contexto + Obsidian con aprobación.
- Los archivos `.sql` usan `END ;` dentro de `DELIMITER //`: para recargar objeto por objeto, extraer el bloque y usar `END //` (patrón P11 de ventas).
