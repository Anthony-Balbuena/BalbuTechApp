# Flujo — Registrar producto

> Creado 09/10/2026. SPs: `SP_INSERTAR_PRODUCTO`, `SP_ACTUALIZAR_PRODUCTOS`, `SP_TOGGLE_ESTADO_PRODUCTOS` (`9- PRODUCTOS.sql`). Cargadores: `PARA_INSERTAR_PRODUCTO`, `PARA_ACTUALIZARDATOS`. App: `productos.cpp`.

## El flujo

```text
Alta:   PARA_INSERTAR (combos) -> SP_INSERTAR (limpia, valida x10, INSERT, nace ACTIVO sin inventario)
Cambio: PARA_ACTUALIZARDATOS -> SP_ACTUALIZAR (parcial con COALESCE, valida, UPDATE)
Estado: SP_TOGGLE (ACTIVO <-> INACTIVO, loguea el cambio)
```

## Datos de diseño

- **Sin stock al nacer** — `INVENTARIO` se crea con la primera compra (`ON DUPLICATE KEY`).
- **Sin triggers al INSERT** — solo 2 de UPDATE (auditoría de precio + historial de estado).
- **Sin transacción** — un solo statement por SP (atómicos); FK + UNIQUEs son la red.
- La app manda **8 args** al alta (con imagen) y **9** al cambio (proveedor + imagen).

## Pendientes

- [ ] P8. Descripción corta al actualizar — el alta exige ≥ 10 caracteres pero `SP_ACTUALIZAR_PRODUCTOS` acepta cualquiera (solo limpia). Unificar el mínimo en el UPDATE.
