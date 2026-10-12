# Pendientes — Flujo de compras

> **✅ COMPLETO (08/10/2026):** plan espejo del flujo de ventas (ya cerrado). **Todo hecho:** blindaje total de los 5 SPs + P11C + P12C, extracción del archivo `19.1`, **Partes 1, 2, 3, 4, 5 y 7** y **residuos #426/#464 cancelados** (nueva línea base en contexto compras §27). La Parte 6 (C++) queda **fuera de alcance: no se toca**.

## Pendientes del flujo completo

- [ ] **Parte 6** — ⛔ **Fuera de alcance** (solo SQL; el módulo C++ no se toca).

## Fixes y cambios de archivos ejecutados ✅



## Decisiones pendientes


## Notas sueltas

- Contextos de compras ya existen (`contexto tabla compras.txt` con 21 secciones + detalle compra, pagos compra, devolucion compra, historial estados compra): las partes de este plan **documentan lo nuevo y lo que falte**, sin repetir lo ya registrado.
- Mismas reglas de siempre: respaldo previo, "lo viejo comentado arriba + nuevo debajo" al editar, pruebas en `ROLLBACK` con residuos 0, y registro en contexto + Obsidian con aprobación.
- Los archivos `.sql` usan `END ;` dentro de `DELIMITER //`: para recargar objeto por objeto, extraer el bloque y usar `END //` (patrón P11 de ventas).
