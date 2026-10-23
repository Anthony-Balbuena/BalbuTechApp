# Permisos finos — Proveedores (Tanda B, módulo 1)

Objetivo: pasar Proveedores del permiso paraguas `GESTIONAR_PROVEEDORES` a
cuatro permisos finos, con el mismo patrón que Clientes, sin perder accesos.
Rama: `feat/permisos-finos-proveedores`. Estrategia de entrega: `ask-on-risk`
(default). Runner: `bash build.sh`, `db/test-menus-por-rol.sh`,
`db/check-app-sps.sh`.

## Specs

- **S1** — `proveedores.cpp` usa el patrón de `clientes.cpp`: enum de acciones,
  vector `{etiqueta, permiso, accion}`, lista visible filtrada con
  `tienePermiso()`, numeración sobre lo visible y despacho por `accion`.
  Incluye `roles.h`. No usa números absolutos ni repite `tienePermiso` dentro
  de cada `case`.
- **S2** — Opciones y permisos:

  | Opción | Permiso |
  |---|---|
  | Agregar proveedor | `PROVEEDORES_CREAR` |
  | Actualizar proveedor | `PROVEEDORES_EDITAR` |
  | Activar/Desactivar proveedor | `PROVEEDORES_ESTADO` |
  | Buscar proveedor | `PROVEEDORES_VER` |
  | Listar proveedores | `PROVEEDORES_VER` |
  | Volver al Menu Principal | *(siempre)* |

- **S3** — Matriz: los cuatro permisos reemplazan a `GESTIONAR_PROVEEDORES`.
  ADMIN, GERENTE, SUBGERENTE y ALMACEN reciben los cuatro. VENDEDOR, RRHH y
  CONTABILIDAD no reciben ninguno. Ningún rol pierde otro acceso.
- **S4** — `roles.cpp` muestra el ítem Proveedores si el usuario tiene
  cualquiera de los cuatro permisos.
- **S5** — SQL: `modulos/36- PERMISOS_ROLES.sql` queda con 34 permisos y la
  matriz final; `modulos/46- PERMISOS_PROVEEDORES.sql` migra bases existentes
  (idempotente, preserva roles personalizados que tenían el paraguas) y borra
  `GESTIONAR_PROVEEDORES`. Orden: binario nuevo antes del SQL que borra.
- **S6** — Tests: `db/test-menus-por-rol.sh` cubre un rol con solo
  `PROVEEDORES_VER` (3 opciones: Buscar, Listar, Volver) y ALMACEN/Proveedores
  (6 opciones); build OK; `check-app-sps.sh` 93/0; `test-menus-por-rol.sh`
  completo OK. Probar en `BALBU_TECH_TEST`; la viva solo con backup previo.
- **S7** — Docs: `modulos/5- PROVEEDORES.md` documenta los permisos y el mapa
  del submenú; `modulos/36- PERMISOS_ROLES.md` actualiza matriz y conteos;
  `modulos/00- INDICE.md` agrega el módulo 46; `Realizado.md` y
  `PENDIENTES.md` al cerrar.

## Tasks

- [x] **T1 — Código** (`proveedores.cpp/h`, `roles.cpp`): patrón Clientes +
  gate con los cuatro permisos. S1, S2, S4. Route: inline.
- [x] **T2 — SQL canónico** (`modulos/36- PERMISOS_ROLES.sql`): catálogo y
  matriz. S3, S5. Route: inline.
- [x] **T3 — Migración** (`modulos/46- PERMISOS_PROVEEDORES.sql/.md`):
  idempotente, preserva accesos. S5. Route: inline.
- [x] **T4 — Tests** (`db/test-menus-por-rol.sh`): rol solo VER + ALMACEN.
  S6. Route: inline.
- [x] **T5 — Docs** (`5- PROVEEDORES.md`, `36- PERMISOS_ROLES.md`,
  `00- INDICE.md`, `Realizado.md`, `PENDIENTES.md`). S7. Route: inline.
- [x] **T6 — Verificación**: build, `check-app-sps`, menús, TEST; luego viva
  con backup. S6. Route: inline.

Commit del work unit: `48350c4` (rama `feat/permisos-finos-proveedores`; el amend movió el hash original `6c2dad5`).

## Log

- **L1** — Pedido del dueño: *"arranca"* (inicio de la Tanda B, primer módulo
  Proveedores, según `Proyecto manejo inventario/Planes/PENDIENTES.md`).
- **L2** — Exploración: `proveedores.cpp` tiene 6 opciones fijas y usa
  `GESTIONAR_PROVEEDORES`; `clientes.cpp` es el patrón de referencia. Matriz
  actual: 31 permisos / 110 pares; ADMIN 31, GERENTE 25, SUBGERENTE 19,
  RRHH 12, VENDEDOR 10, ALMACEN 9, CONTABILIDAD 4.
- **L3** — Decisión: los cuatro permisos se otorgan a ADMIN, GERENTE,
  SUBGERENTE y ALMACEN (los que hoy tienen el paraguas). La migración
  preserva cualquier rol personalizado que tuviera el paraguas.
- **L4** — Verificación en TEST: `build.sh` OK; `test-menus-por-rol.sh` OK
  (nuevo `PRUEBA_PROV_VER` → 3 opciones y `ALMACEN/Proveedores` → 6);
  `test-migracion-roles.sh` OK; `test-asistencia-propia.sh` OK;
  `test-contrato-borrador.sh` 15/15; `check-app-sps` 93/0. `36` reimportado
  sobre TEST: 34 permisos / 122 pares; `46` dos veces sin duplicar.
- **L5** — Viva `BALBU_TECH`: backup
  `backups/pre_proveedores_20261022_233409.sql` (596 KB); `46` dos veces.
  Quedó 34 permisos / 122 pares (ADMIN 34, GERENTE 28, SUBGERENTE 22, RRHH 12,
  VENDEDOR 10, ALMACEN 12, CONTABILIDAD 4); los 4 roles con los 4 permisos y
  `GESTIONAR_PROVEEDORES` eliminado. Proveedores, empleados y contratos
  intactos.
- **L6** — Commit: `48350c4` en `feat/permisos-finos-proveedores` (el amend movió el hash original `6c2dad5`).
- **L7** — Review RDD (`review-4a4672daf469b43b`): consentida; lentes
  `review-risk` y `review-reliability`; ambas devolvieron salida vacía
  (`provider_result_empty`, `reviewer_result_not_admissible`). Se declararon
  no alcanzables y la review terminó en `unachievable_lens_slot`, sin
  aprobación. No se inventó PASS. El work unit sigue verificado por tests; la
  review queda para reintentar con otro modelo.
