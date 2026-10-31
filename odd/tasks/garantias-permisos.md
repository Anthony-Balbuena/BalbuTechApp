# Garantías con permisos propios y flujo estructurado

Objetivo: sacar Garantías de `GESTIONAR_VENTAS`, darle 4 permisos finos, autor y
fechas en las tablas, validación por fecha y registro automático al confirmar la
venta.
Rama: `main`. Entrega: commits directos; el push lo hace el dueño.
Runner: `bash build.sh` + `db/*.sh` contra `BALBU_TECH_TEST`.

## Specs

- **S1.** Cuatro permisos nuevos: `GARANTIAS_REGISTRAR`, `GARANTIAS_RECLAMAR`,
  `GARANTIAS_FINALIZAR`, `GARANTIAS_CONSULTAR`. Matriz: registrar y reclamar en
  ADMIN, GERENTE, SUBGERENTE y VENDEDOR; finalizar solo ADMIN, GERENTE y
  SUBGERENTE; consultar los cuatro más CONTABILIDAD.
- **S2.** `GESTIONAR_VENTAS` no se borra ni se le quitan pares: lo siguen usando
  otras nueve acciones de Ventas. Solo deja de abrir Garantías.
- **S3.** El ítem "Garantias" del menú de Ventas se abre si el rol tiene
  cualquiera de los cuatro permisos. Adentro, cada opción pide su permiso y se
  numera sobre lo visible, sin huecos, con despacho por acción.
- **S4.** VENDEDOR no ve "Finalizar reclamo" y el SP también lo rechaza.
- **S5.** `GARANTIAS` guarda `ID_EMPLEADO` (quién la registró) y
  `FECHA_REGISTRO`.
- **S6.** `RECLAMOS_GARANTIAS` guarda `ID_EMPLEADO`, `ID_EMPLEADO_CIERRE` y
  `FECHA_CIERRE`.
- **S7.** Reclamar exige `CURRENT_DATE BETWEEN FECHA_INICIO AND FECHA_FIN`
  además de `ESTADO = 'ACTIVA'`.
- **S8.** Finalizar exige estado `PENDIENTE` o `APROBADO`; `CERRADO` y
  `RECHAZADO` se rechazan con error.
- **S9.** `SP_MARCAR_GARANTIAS_VENCIDAS()` pasa a `VENCIDA` las `ACTIVA` con
  `FECHA_FIN` anterior a hoy.
- **S10.** Registro automático: al pasar la venta a `REALIZADA` se crea la
  garantía de cada línea cuyo producto tenga `DIAS_GARANTIA > 0`, con el
  empleado de la venta. Idempotente (no duplica ni rompe la venta).
- **S11.** El registro manual pide ID de venta y muestra las líneas en una tabla
  para elegir; no pide el ID de detalle a ciegas.
- **S12.** Reclamar y finalizar listan lo que corresponde en vez de pedir IDs.
- **S13.** Tablas alineadas con `tabla.h`; el color va solo en la celda de
  estado.
- **S14.** Test nuevo `db/test-garantias.sh` en transacción con `ROLLBACK`,
  menús por rol actualizados y `check-app-sps.sh` con los SPs nuevos.

## Tasks

- [x] **T1** `modulos/63- GARANTIAS_FLUJO.sql`: columnas, FKs, `PRODUCTOS.DIAS_GARANTIA`, SPs y trigger automático. (S5-S10) — aplicado 2× en TEST sin error.
- [x] **T2** `modulos/62- PERMISOS_GARANTIAS.sql`: 4 permisos y matriz. (S1, S2) — aplicado 2× en TEST: 58 permisos / 213 pares.
- [x] **T3** `ventas.cpp`: submenú dinámico, listados y llamadas con empleado. (S3, S4, S11-S13) — build OK; `roles.cpp` y `tabla.h` incluidos.
- [x] **T4** `db/test-garantias.sh` nuevo y `db/test-menus-por-rol.sh` actualizado. (S14) — 11 OK / 0 FAIL; menús con Garantías OK.
- [x] **T5** Build y corrida completa en TEST. (S14) — `build.sh` OK, suite completa OK, `check-app-sps` 99/0.
- [x] **T6** `.md` de los dos módulos, `Realizado.md` y `PENDIENTES.md`. — hecho; falta solo la viva.
- [ ] **T7** Commits: SQL y C++ por separado. — en curso.

## Log

- **L1** (30/10/2026) Pedido del dueño, textual: «dame el plan» y luego
  «si dale asi». Interpretado como la opción automática: la garantía se crea
  sola al confirmarse la venta con los días del producto, y el registro manual
  queda como respaldo para ventas viejas.
- **L2** (30/10/2026) Estado verificado antes de empezar: `GARANTIAS` y
  `RECLAMOS_GARANTIAS` vacías en TEST y en la viva (0 filas), 54 permisos en
  ambas bases, `GESTIONAR_VENTAS` en ADMIN/GERENTE/SUBGERENTE/VENDEDOR, módulo
  34 sin cablear, `PRODUCTOS.DIAS_GARANTIA` inexistente.
- **L3** (30/10/2026) `TR_FINALIZAR_RECLAMO_APROBADO` ya cancela la garantía al
  aprobar un reclamo, y `TR_VALIDAR_CAMBIO_RECLAMO` bloquea reabrir y tocar
  `CERRADO`/`RECHAZADO`. El flujo nuevo se apoya en esos dos, no los reemplaza.
- **L4** (30/10/2026) Evidencia en TEST: `63` y `62` aplicados dos veces cada
  uno sin error; `db/test-garantias.sh` 11 OK / 0 FAIL con 3/3 errores
  esperados y 0 residuos `ZZ GAR`; `test-menus-por-rol.sh` todo OK
  (Garantías: ADMIN/GERENTE/SUBGERENTE 5, VENDEDOR 4, CONTABILIDAD 2;
  `PRUEBA_VEN_GEST` 8 en Ventas); `test-migracion-roles.sh` VENDEDOR 15;
  `check-app-sps.sh` 99/0. Suite completa (auditorías, login/menús EOF,
  asistencia, contratos) OK.
- **L5** (30/10/2026) Dos correcciones durante la implementación: el SP de
  consulta invoca `SP_MARCAR_GARANTIAS_VENCIDAS()` antes de listar (no hay
  scheduler), y la UI no pide IDs a ciegas: lista y valida contra lo listado.
- **L6** (30/10/2026) Pendiente la viva: orden `backup → 63 → binario → 62`,
  porque el binario viejo usa las firmas viejas y el `62` antes del binario
  esconde Garantías del menú.
