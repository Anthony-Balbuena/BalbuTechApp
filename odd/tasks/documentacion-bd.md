# Documentación de la BD — módulos SQL

Objetivo: un `.md` por cada módulo `.sql` del directorio `modulos/`, con el
formato del piloto `42- CONTRATOS.md`, sin tocar ningún `.sql`.
Rama: `main` (commits locales, sin push). Runner: N/A (documentación pasiva).

## Specs

- **S1** — Un `.md` por módulo en `modulos/NN- NOMBRE.md`, con el mismo nombre
  base que el `.sql`.
- **S2** — Formato del piloto: encabezado (rol, dependencias, fuente, base,
  fecha), `## Tablas` columna por columna (tipo, restricciones, descripción y
  por qué), `## Procedimientos almacenados` (firma, limpieza, validaciones en
  orden, mensajes exactos, uso desde la app), `## Triggers` (incluye los
  eliminados y su motivo), `## Vistas`/`## Funciones` si existen, y
  `## Reglas de negocio`.
- **S3** — Todo objeto `CREATE` del `.sql` (tabla, índice, SP, trigger, vista,
  función) debe aparecer en su `.md`. Los objetos eliminados se documentan con
  el motivo, no se omiten.
- **S4** — Ningún `.sql` se modifica: `git diff -- 'modulos/*.sql'` vacío.
- **S5** — Un commit por lote, `docs(modulos): lote N — <dominio>`, sin push.
- **S6** — El índice general de la BD queda como mejora futura (anotado en
  `Proyecto manejo inventario/Planes/Observaciones futuras SQL.md`), fuera de
  este trabajo.

## Tasks

- [x] **T1 — Lote 1: catálogo y maestros** (módulos 1, 2, 4, 5, 7, 9, 17, 40;
  63 objetos). 8 `.md`. Commit `docs(modulos): lote 1 — catálogo y maestros`.
- [x] **T2 — Lote 2: RRHH y usuarios** (8, 10, 11, 12, 13, 14, 15, 16, 41;
  88 objetos). 9 `.md`. Commit `docs(modulos): lote 2 — RRHH y usuarios`.
- [x] **T3 — Lote 3: compras** (19, 19.1, 19.5, 19.6, 22; 62 objetos).
  5 `.md`. Commit `docs(modulos): lote 3 — compras`.
- [x] **T4 — Lote 4: ventas y postventa** (21, 21.5, 23, 24, 25, 26, 27, 35,
  38, 39; 85 objetos).
  10 `.md`. Commit `docs(modulos): lote 4 — ventas y postventa`.
- [ ] **T5 — Lote 5: inventario y movimientos** (18, 20, 32; 12 objetos).
- [ ] **T6 — Lote 6: seguridad, logs y config** (3, 6, 28, 29, 30, 33, 34, 36;
  ~32 objetos).
- [ ] **T7 — Lote 7: vistas de reportes** (43; 5 objetos).

## Log

- **L1** — Pedido del dueño: *"¿Incluyo el índice general como último paso del
  trabajo? pon esto junto a la mejorar futuras para el sql y dame el plan para
  la fase 2"*. Decisión: índice general → mejoras futuras; se entrega el plan
  por lotes.
- **L2** — *"dlae arranca"*: se escribe `modulos/1- CATEGORIAS.md` como
  muestra de formato.
- **L3** — *"si"*: formato aprobado; se completan los 7 módulos restantes del
  Lote 1 y se commitea el lote.
- **L4** — Verificación del lote: 8 `.md`, 63 objetos `CREATE` cubiertos
  (chequeo nombre por nombre contra el `.sql`), `git diff -- 'modulos/*.sql'`
  vacío. Los índices se documentan dentro de la sección de su tabla (formato
  del piloto); el conteo de secciones es menor que el de `CREATE` por eso.
- **L5** — Hallazgos anotados sin tocar el SQL: índice redundante en
  CATEGORIAS; `UNIQUE` duplicado en PROVEEDORES; normalización de teléfono
  distinta entre alta y edición en CLIENTES; `LENGTH` vs `CHAR_LENGTH` en
  PRODUCTOS; seed no idempotente en 2, 4 y 7; sentencias sueltas de migración
  en PRODUCTOS.
- **L6** — Lote 2 documentado: 9 `.md` (8, 10, 11, 12, 13, 14, 15, 16, 41),
  **88 objetos** cubiertos, `git diff -- 'modulos/*.sql'` vacío.
- **L7** — Corrección del método de verificación: el regex anclado en
  `^CREATE` **subcontaba** (los SP de varios archivos van indentados). El
  chequeo pasa a `^[[:space:]]*CREATE ...` y con eso 12 apareció con 8 objetos
  reales en vez de 2. Hallazgos del lote, anotados sin tocar el SQL:
  `CEDULA` sin UNIQUE en EMPLEADOS (solo la valida el SP) y salario `NULL` que
  esquiva la validación; `IX_ASISTENCIA_EMPLEADO` redundante y hora tope
  `08:30` hardcodeada; la actualización de vacaciones no re-valida
  solapamiento y `SP_VALIDAR_CUPO_VACACIONES` cuenta inactivos;
  `VISTA_TOTAL_BONOS_POR_EMPLEADO` promete 0 y devuelve `NULL`; el cargo del
  historial es `VARCHAR(30)` contra `VARCHAR(50)` en EMPLEADOS (riesgo de
  truncar el `UPDATE`); el cálculo de LIQUIDACIONES es un placeholder (no Ley
  16-92) y bloquea el `DELETE` del empleado por el trigger de auditoría; el
  cuadre de TURNO_CAJA suma **todos** los pagos del período, no los de la caja.
  Módulos 12, 13, 14, 15 y 16 **no los consume la app** hoy.
- **L8** — Lote 3 documentado: 5 `.md` (19, 19.1, 19.5, 19.6, 22),
  **62 objetos** cubiertos, `git diff -- 'modulos/*.sql'` vacío. El chequeo
  automático marcó 3 índices sin documentar en el 22 (se agregaron); el resto
  pasó nombre por nombre.
- **L9** — Hallazgos del lote 3, anotados sin tocar el SQL: **el tope de pago de
  una compra es el BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) y está repetido
  en **6 lugares** (2 SP y 4 triggers), así que cualquier cambio hay que
  hacerlo en todos; `SP_REGISTRAR_NOTA_CREDITO_COMPRA` no valida que la nota
  deje el saldo pagado en negativo; los candados `@COMPRAS_INTERNO` son
  variables de sesión que cualquiera puede setear; `FN_CONTAR_ITEMS_COMPRA`
  promete "productos distintos" y hace `COUNT(*)`, y está declarada
  `DETERMINISTIC` leyendo tablas; `IX_COMPRA_PROVEEDOR` se crea en el 22 pero
  vive en `COMPRAS`; `FN_COSTO_COMPRA_VIGENTE` excluye solo `CANCELADA`, así
  que una compra `DEVUELTA` sigue marcando costo; `SP_MODIFICAR_LINEA_COMPRA`
  borra y reinserta (cambia el `ID_DETALLE_COMPRA`); el pago de una compra se
  anula con `DELETE` físico. Orden de triggers de `DETALLE_COMPRA` y de
  `COMPRAS` declarado con `FOLLOWS` (recrear uno exige rehacer la cadena).
- **L10** — *"dale"*: arranca el Lote 4. 10 `.md` (21, 21.5, 23, 24, 25, 26, 27,
  35, 38, 39), **85 objetos** cubiertos, `git diff -- 'modulos/*.sql'` vacío.
  Hallazgos del lote, anotados sin tocar el SQL:
  - El **BRUTO de venta** (`TOTAL + ITBIS − ITBIS devuelto`) está duplicado en
    **6 lugares** (1 SP y 5 triggers de `PAGOS`) y **solo resta el ITBIS
    devuelto, no el subtotal**: devolver mercancía no baja `VENTAS.TOTAL`.
  - `TR_VALIDAR_ACTUALIZACION_VENTA` exige cobrar la **base** para marcar
    `REALIZADA`, mientras el cierre automático de `PAGOS` exige **bruto + ITBIS**.
  - **`VENCIDA` nunca se escribe**: una garantía con `FECHA_FIN` pasada sigue
    `ACTIVA`, y `27_SP_REGISTRAR_RECLAMO_GARANTIA` no mira la fecha, solo el
    estado → se puede reclamar una garantía vencida. Aprobar un reclamo
    **cancela la garantía entera**.
  - **La cuota de devoluciones no tiene candado ni índice único**: dos altas
    simultáneas de la misma línea pueden sobrepasar lo vendido (en compras sí
    hay `FOR UPDATE`). `25_SP_PROCESAR_DEVOLUCION` tampoco bloquea la fila.
  - `TR_BLOQUEAR_CAMBIO_DEVOLUCION` no protege `MOTIVO` ni
    `MONTO_ITBIS_REEMBOLSADO`: cambiarlos en una devolución procesada mueve el
    bruto de la venta sin candado.
  - `VISTA_REPORTES_DEVOLUCIONES` no filtra estado (cuenta las `RECHAZADA`).
  - `VW_GANANCIAS_MENSUAL` y `SP_REPORTE_PERIODO_GANANCIA` solo excluyen
    `CANCELADA`: **`EN_PROCESO` cuenta como ganancia antes de cobrarse** y
    `DEVUELTA` también entra. Contradice los reportes de ventas (`REALIZADA`).
  - Costo desconocido (`NULL`) se convierte en 0 en `GANANCIA_NETA`: subestima
    sin avisar.
  - Los SP de devolución y reclamo están **cruzados de archivo**: el prefijo
    `25_`/`26_` no dice en qué módulo vive cada uno.
  - `35- DETALLE_REPARACIONES`: **nada de la app lo usa**; el repuesto es texto
    libre (no descuenta stock), no valida usuario/costo negativos y solo frena
    la asignación `COMPLETADO` (no `CANCELADO`).
  - `IX_VENTAS_FECHA` e `IX_CLIENTE_NOMBRE` se crean en el 23 pero pertenecen a
    `VENTAS` y `CLIENTES` (mismo patrón que el 22).
  - Varios `.sql` arrancan con `-- Active: <id>@@127.0.0.1@3306@BALBU_TECH`,
    rastro de un cliente SQL, no sintaxis del proyecto.
