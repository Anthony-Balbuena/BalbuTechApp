# Auditoría general de la BD — 08/10/2026

> Solo lectura: no se tocó código ni datos. Verificado contra la BD viva `BALBU_TECH`.

## 🔴 Errores reales (fallan SIEMPRE al ejecutarse)

1. **`SP_TOGGLE_ESTADO_MARCA`** — `2- MARCAS.sql:123`: alterna `'ACTIVO'/'INACTIVO'`, pero `MARCAS.ESTADO` es `ENUM('ACTIVA','INACTIVA')` → ERROR 1265. El toggle de marcas es imposible.
2. **`SP_TOGGLE_ESTADO_METODO_PAGO`** — `4-METODOS_PAGO.sql:142`: hace `UPDATE METODOS_PAGO SET ESTADO=…`, pero la tabla **no tiene columna ESTADO** → Unknown column.
3. **`SP_ASIGNAR_TECNICO_RECLAMO`** — `34- ASIGNAR RECLAMOS.sql:96`: pone `ESTADO='EN_PROCESO'`, pero `RECLAMOS_GARANTIAS.ESTADO` es `('PENDIENTE','APROBADO','RECHAZADO','CERRADO')` → ERROR 1265. Además `TR_FINALIZAR_RECLAMO_APROBADO` nunca ve ese estado.
4. **`SP_ASIGNAR_PERMISO_A_ROL` / `FN_TIENE_PERMISO`** — `36- PERMISOS_ROLES.sql:110,169,181`: leen tabla `USUARIOS_SISTEMA`, que **no existe** (lo real es `USUARIOS` + `ROLES`).
5. **`SP_REGISTRAR_ASISTENCIA`** — `11-ASISTENCIA_EMPLEADOS.sql:100`: inserta en tabla `ASISTENCIA`, que **no existe** (lo real es `ASISTENCIA_EMPLEADOS` con otras columnas).
6. **`27_SP_FINALIZAR_RECLAMO_TOTAL`** — `27- RECLAMOS_GARANTIAS.sql:117`: inserta en `LOG_AUDITORIA`, que **no existe** (existen `AUDITORIA_SISTEMA`, `LOG_USUARIOS`, `LOG_AUDITORIA_PERMISOS`) → siempre ROLLBACK.
7. **SP de `28-LOG_ACCESOS.sql:45`** — usa `U.NOMBRE_USUARIO`, pero la columna real es `USUARIOS.USUARIO`.
8. **`sp_obtener_categorias_marcas`** — `Mejoras_extras.sql:4`: lee `categorias`/`marcas` minúsculas con columnas que no existen (real: `CATEGORIAS(ID_CATEGORIA,NOMBRE)`, `MARCAS(ID_MARCA,NOMBRE)`).

## 🟡 Gemelos en BD (mismo propósito, dos nombres)

- **IDÉNTICOS** (candidatos a borrar, previa revisión de uso en C++): `SP_HISTORIAL_PERMISOS_EMPLEADO` = `13_SP_HISTORIAL_PERMISOS_EMPLEADO`; `27_SP_FINALIZAR_RECLAMO_TOTAL` = `35_SP_FINALIZAR_RECLAMO_TOTAL`.
- **DIFERENTES** (comparar cuerpo antes de tocar): `SP_BUSCAR_CATEGORIAS` vs `1_SP_BUSCAR_CATEGORIAS`; `SP_TOGGLE_ESTADO_CATEGORIA` vs `1_SP_TOGGLE_ESTADO_CATEGORIA`; `SP_TOGGLE_ESTADO_PROVEEDOR` vs `5_SP_TOGGLE_ESTADO_PROVEEDOR`.
- `VERANTESDEINSERT`: sin hits en repo → probable muerto (verificar en BD).

## 🟢 Mejoras (no rompen, pero conviene)

- **Sin transacción/handler:** casi todos los SPs fuera de compras/ventas escriben a pelo. Críticos multi-statement: `SP_ASIGNAR_TECNICO_RECLAMO`, `SP_FINALIZAR_RECLAMO`, `SP_REGISTRAR_LIQUIDACION`, `20_SP_REGISTRAR_AJUSTE_INVENTARIO`, `SP_REGISTRAR_GARANTIA`, `26_SP_RECHAZAR_DEVOLUCION`, `SP_REGISTRAR_AVANCE_REPARACION`.
- **Sin FK:** `PRODUCTOS.ID_PROVEEDOR` (huérfanos posibles), `LOG_USUARIOS(ID_USUARIO,ID_USUARIO_ADMIN)`, `ROL_PERMISO(ROL_NOMBRE)` vs `ROLES` (CHECK en vez de FK).
- **Sin CHECK/ENUM:** `HISTORIAL_ESTADOS_COMPRA/VENTA.ESTADO_* VARCHAR(20)` admite estados inválidos; `DETALLE_REPARACIONES.ESTADO_AVANCE` sin ENUM.
- **Contraseñas:** `USUARIOS.CONTRASENA` migrada a 512 pero params de SPs en `VARCHAR(255)` → trunca el hash.
- **Triggers sin orden explícito** (orden = creación, frágil al recargar): `DETALLES_VENTA AFTER INSERT ×3`, `DEVOLUCIONES AFTER UPDATE ×3`, `EMPLEADOS AFTER UPDATE ×2`.
- **Tablas sin BEFORE:** `RECLAMOS_GARANTIAS` (estados y DELETE libres), `DEVOLUCIONES` sin BEFORE INSERT, `VACACIONES/BONOS/LIQUIDACIONES` sin control en UPDATE.
- `PROVEEDORES.TELEFONO/EMAIL UNIQUE` anulables → varios NULL burlan la unicidad.

## ✅ Sano (verificado en vivo)

- Cero huérfanos, cero duplicados (marcas/productos/proveedores), cero precios ≤ 0, cero stock negativo.
- Ningún trigger fantasma en BD (los `DROP` de limpieza sí corrieron).
- Flujos de compras y ventas: blindados y probados.
- 5 productos sin fila en `INVENTARIO` → por diseño (se crea al comprar).
