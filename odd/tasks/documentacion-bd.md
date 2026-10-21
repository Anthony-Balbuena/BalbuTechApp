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
- [ ] **T2 — Lote 2: RRHH y usuarios** (8, 10, 11, 12, 13, 14, 15, 16, 41;
  ~65 objetos).
- [ ] **T3 — Lote 3: compras** (19, 19.1, 19.5, 19.6, 22; ~50 objetos).
- [ ] **T4 — Lote 4: ventas y postventa** (21, 21.5, 23, 24, 25, 26, 27, 35,
  38, 39; ~71 objetos).
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
