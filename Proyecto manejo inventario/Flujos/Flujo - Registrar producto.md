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

- [x] P8. Descripción corta al actualizar — el alta exige ≥ 10 caracteres pero `SP_ACTUALIZAR_PRODUCTOS` acepta cualquiera (solo limpia). Unificar el mínimo en el UPDATE. ✅ Hecho 09/10: check `< 10 → SIGNAL` solo si mandan descripción (vacía = omitir); probado (corta rechaza, válida actualiza).
- [ ] B1. `SP_INSERTAR_CATEGORIA`: la app manda 1 arg (nombre) y el SP exige 3 (`P_NOMBRE,P_DESCRIPCION,P_ICONO`) → ERROR 1318. Corregir en **C++** (pedir los 3 datos como hace clientes).
- [ ] B2. `SP_ACTUALIZAR_CATEGORIA`: la app manda 2 y el SP exige 4 → ERROR 1318. Corregir en **C++**.
- [x] B3. `SP_INSERTAR_PRODUCTO`: la app manda 8 (con imagen) y el SP recibe 7 → ERROR 1318. Corregir en **SQL** (agregar `P_IMAGEN` + `INSERT`). ✅ Ya venía resuelto de casa (SP con 8 params); verificado en vivo 09/10.
- [x] B4. `SP_ACTUALIZAR_PRODUCTOS`: la app manda 9 y el SP recibe 7 (falta proveedor/imagen) → ERROR 1318. Corregir en **SQL** (agregar `P_ID_PROVEEDOR`, `P_IMAGEN` con `COALESCE`). ✅ Ya venía resuelto de casa (SP con 9 params, comentario P7); verificado 09/10.
- [x] S4. Orden de triggers en `DETALLES_VENTA`: tres comparten `ACTION_ORDER=1`. Poner `FOLLOWS`/`PRECEDES` explícito (bloqueadores primero). ✅ Hecho 09/10: `VALIDAR_STOCK FOLLOWS BLOQUEAR_VENTA_FINALIZADA` (los otros dos ya los traía casa); orden verificado: BEFORE 1→2, AFTER 1→2→3.
- [x] S5. FKs faltantes: `PRODUCTOS.ID_PROVEEDOR → PROVEEDORES`, `ROL_PERMISO.ROL_NOMBRE → ROLES`, `LOG_USUARIOS.* → USUARIOS` (verificar huérfanos antes con la auditoría en verde). ✅ Hecho 09/10: las 2 primeras ya las traía casa; agregadas `FK_LOG_USUARIOS_USUARIO/ADMIN` (cero huérfanos); import 0 errores.
