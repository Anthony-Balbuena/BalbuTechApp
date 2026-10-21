# Para mañana en el trabajo — 21/10/2026

Lo que hay que tener a mano al llegar: qué módulos de la base **no usa la app**,
qué significa eso en la práctica y qué hay que decidir.

Contexto: los 45 módulos SQL quedaron documentados (un `.md` por `.sql`) y el
mapa está en `modulos/00- INDICE.md`. El índice marca cada módulo con ✅ usa ·
◐ usa parte · — no usa. **Esto es el detalle de los 14 con "—" y los 5 con "◐".**

---

## La aclaración que importa

**"No usa" = la app no ejecuta ninguno de sus `SELECT`/`CALL`.** No significa que
estén vacíos ni que sean código muerto: varios **se llenan solos por triggers**.
Borrar uno de esos rompe el `INSERT` de la venta o de la compra.

---

## Los 14 módulos que la app no usa

### Grupo A — se llenan solos por triggers (6)

| Módulo | Qué guarda | Quién lo escribe |
|---|---|---|
| 6 — AUDITORIA_SISTEMA | Bitácora por tabla y registro | Triggers de 6, 27 y 40 |
| 15 — HISTORIAL_LABORAL_EMPLEADO | Cambios de cargo y salario | Trigger de `EMPLEADOS` |
| 18 — HISTORIAL_ESTADOS_PRODUCTO | Altas y bajas de producto | Trigger de `PRODUCTOS` |
| 19.1 — HISTORIAL_ESTADOS_COMPRA | Cambios de estado de compra | Triggers del 19 |
| 29 — LOG_USUARIOS | Cambios de rol y estado de usuarios | Trigger de `USUARIOS` |
| 32 — HISTORIAL_MOVIMIENTOS_PRODUCTO | Cada movimiento con stock antes/después | Triggers de 22, 23 y 26 |

**No borrar.** Son auditoría viva que solo se consulta por SQL.

> **Hallazgo del 18:** la app **sí lo alimenta**, porque el toggle de productos
> (`SP_TOGGLE_ESTADO_PRODUCTOS`, módulo 9) hace `UPDATE PRODUCTOS SET ESTADO` y
> dispara el trigger. Como nunca se llama al `SP` del 18, las variables de sesión
> quedan vacías y **todas las filas quedan atribuidas al empleado `1`** con el
> motivo "Cambio de estado automático".

### Grupo B — nunca se escriben ni se leen (3)

| Módulo | Estado real |
|---|---|
| 28 — LOG_ACCESOS | Vacío: el login **no registra** intentos |
| 30 — LOG_AUDITORIA_PERMISOS | Vacío: depende del 13, que no se usa |
| 34 — ASIGNAR RECLAMOS | Vacío: la app cierra con `27_SP_FINALIZAR_RECLAMO_TOTAL`, que no lo toca |

**Los únicos candidatos reales a limpieza.** Pero antes hay que decidir si hacen
falta (ver checklist).

### Grupo C — funcionalidad completa pero sin pantalla (5)

| Módulo | Qué falta |
|---|---|
| 12 — VACACIONES_EMPLEADOS | 5 `SP`, 2 triggers, sin menú |
| 13 — PERMISOS_EMPLEADOS | 3 `SP` y una vista, sin menú |
| 14 — BONOS_EMPLEADOS | 5 `SP`, 2 triggers, sin menú |
| 16 — LIQUIDACIONES | Cálculo placeholder y trigger que bloquea el `DELETE` del empleado |
| 35 — DETALLE_REPARACIONES | Hoy el repuesto es **texto libre**: no descuenta stock |

**El modelo de RRHH está entero y no hay UI.** Es la deuda más cara: ~25 objetos
que se mantienen en cada cambio de esquema sin dar nada al usuario.

---

## Los 5 módulos parciales

| Módulo | Qué usa la app | Qué queda sin cablear |
|---|---|---|
| 8 — EMPLEADOS | 4 de 10 `SP`: insertar, actualizar, despedir, reactivar | Nómina, aniversarios, aumento por cargo, búsqueda rápida, recibo |
| 17 — INVENTARIO | La tabla (otros módulos la leen y escriben) | Su único `SP` de alta |
| 19.5 — PAGOS_COMPRA | Registrar pago y compras pendientes | **Anular pago** y nota de crédito |
| 22 — DETALLE_COMPRA | Agregar línea | Quitar y modificar línea |
| 38 — GANANCIAS | El `SP` de período | Las dos vistas |

> Si un pago de compra se cargó mal, **hoy no hay pantalla para anularlo**: se
> corrige por SQL.

---

## Las tres consecuencias

1. **"No usado" ≠ "borrable".** Los 6 del grupo A los escriben triggers de otros
   módulos; borrarlos revienta el alta de compras y ventas.
2. **El grupo B sí es candidato a limpieza**, pero primero hay que decidir
   producto: el 28 es *una* llamada en el login, no un módulo nuevo.
3. **El grupo C es una decisión, no un bug.** RRHH son 5 módulos, ~25 objetos y
   una pantalla que no existe.

---

## Para decidir (checklist)

- [ ] **¿RRHH va o no va?** (12, 13, 14, 16 y el historial del 15)
- [ ] **¿Registro de accesos?** (28: cablear el login o borrar el módulo)
- [ ] **¿Asignación de reclamos?** (34: cablear el flujo o borrarlo con su tabla)
- [ ] **¿Detalle de reparaciones?** (35: repuesto con stock o texto libre)
- [ ] **Anular pago (19.5) y quitar/modificar línea (22):** ¿pantalla o SQL?

## Pendientes técnicos del día

- [ ] Buscar el **comando de provisión de usuarios** de la máquina del trabajo y
  compararlo con los usuarios ya creados (`balbu_app`, `balbu_admin`). El archivo
  `db/crear-usuarios.sh` todavía **no existe**.
- [ ] **Push**: `main` está 10 commits adelante de `origin/main` (los hace el
  dueño).
- [ ] Borrar la rama `backup-casa-20-10` (después del merge).

## Dónde está todo

- `modulos/00- INDICE.md` — el mapa: orden de import, objetos cruzados, fórmulas
  repetidas, qué no usa la app y "dónde buscar qué".
- `modulos/NN- NOMBRE.md` — un documento por módulo, con hallazgos anotados **sin
  arreglar**.
- `odd/tasks/documentacion-bd.md` — log del trabajo (L1 a L12), con los hallazgos
  completos.
- `Proyecto manejo inventario/Planes/Observaciones futuras SQL.md` — deuda técnica
  del esquema.

## Los cinco hallazgos que más duelen

1. **El BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) está copiado en 6 objetos por
   flujo (compras y ventas) más las 5 vistas del 43. No hay función compartida.
2. **Devolver mercancía no baja el subtotal**: solo descuenta el ITBIS devuelto.
3. **`VENCIDA` de GARANTIAS nunca se escribe**: se puede reclamar una garantía
   vencida.
4. **El 18 atribuye todo al empleado 1** y el 29 guarda `ID_USUARIO_ADMIN` en
   `NULL`: la auditoría no dice quién fue.
5. **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño.
