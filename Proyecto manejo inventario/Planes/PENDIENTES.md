# PENDIENTES — todo en un solo lugar

> **Único archivo de pendientes del proyecto.** De arriba abajo = prioridad.
> Lo hecho vive en `Realizado.md`; los detalles largos, en `Auditoria/` y `Flujos/`.
> Actualizado: 23/10/2026.

---

## 🔴 P0 — Ahora (bloquea lo que estás haciendo)

### 1. Permisos finos: terminar la migración (Tanda B)

Estado: **la viva ya está migrada** (22/10: 7 roles, 30 permisos, matriz idéntica a TEST; backup `backups/pre_roles_20261022_200029.sql`). **Usuarios, Empleados, Clientes y Proveedores** ya tienen el patrón; **Proveedores quedó en `feat/permisos-finos-proveedores` con `48350c4` (work unit) + `80e1f14`/`c1cd640` (docs), sin pushear.** La viva quedó en 34 permisos / 122 pares (backup `backups/pre_proveedores_20261022_233409.sql`).

- [x] Clientes: `615270e` `feat(permisos): agregar permisos finos al modulo Clientes`
- [x] Asistencia: `3151fef` + fix `292161a`
- [x] Proveedores: `48350c4` (work unit) + `80e1f14`/`c1cd640` (docs); push pendiente.
- [ ] Seguir en este orden: **Categorías → Marcas → Productos → Métodos de pago → Compras → Inventario → Ventas → Caja** (simples primero, grandes al final).

**Estimación de esfuerzo (23/10):** Proveedores hecho. Quedan 8 módulos:

- Simples (1 work unit cada uno, como Proveedores): **Categorías, Marcas, Productos, Métodos de pago**.
- Grandes (varias sesiones cada uno, tocan flujos): **Compras, Inventario, Ventas, Caja**.
- Orden de magnitud: **semanas de trabajo intermitente, no horas**. Sin fecha exacta hasta cerrar Categorías y medir el ritmo real.

**Patrón** (referencia: `clientes.cpp`, el más chico y limpio):

- enum de acciones + vector `{etiqueta, permiso, accion}`; `permiso` vacío = siempre visible.
- Lista filtrada con `tienePermiso()` y **despacho por `accion`**, nunca por número absoluto.
- Numerar sobre lo visible (sin huecos); no repetir `tienePermiso` dentro de cada `case`.
- Incluir `roles.h` en el `.cpp`.
- En `roles.cpp`, `{}` significa **siempre visible** (no usar vector vacío para "todos").

**Por módulo:** proponer permisos (`X_VER`, `X_CREAR`, `X_EDITAR`, `X_ESTADO`), aplicar el patrón, actualizar `roles.cpp`, `modulos/36- PERMISOS_ROLES.sql/.md` y `db/test-menus-por-rol.sh`; probar en `BALBU_TECH_TEST` y **recién después** la viva con backup previo.

**Trampas ya encontradas:**

- `FN_TIENE_PERMISO` no valida cuentas `INACTIVO` (un usuario dado de baja sigue devolviendo `TRUE`).
- `REGISTRAR_ASISTENCIA` **ya no abre Empleados**: desde el 23/10/2026 abre el
  ítem propio `Asistencia` (primero del menú). `CONSULTAR_ASISTENCIA` filtra los
  reportes; VENDEDOR, ALMACEN y CONTABILIDAD solo fichan y ven lo suyo.
  **Resuelto** (ver `Realizado.md`, 23/10).
- El cliente `mariadb` dentro de `docker compose exec` pierde las comillas dobles del SQL (usar archivo `.sql` o here-doc).
- `db/import.sh` no dropea la base; y el `DROP` borra el grant de `balbu_app` (hay que volver a otorgarlo).
- `ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE` es ambiguo si el `SELECT` también lee `ROL_PERMISO`.

### 2. RRHH: pruebas visuales pendientes

- [ ] **13 Permisos:** solicitar → aprobar uno y rechazar otro → reintentar aprobar el ya aprobado ("solo pendientes") → ver la fila en `LOG_AUDITORIA_PERMISOS`.
- [ ] **12 Vacaciones:** solicitar → aprobar/rechazar → reintentar; una **aprobada** que cubra hoy bloquea la asistencia, una **pendiente o rechazada** no; cupo de 15 días + solapamiento (rechazar libera).
- [ ] **28 Accesos:** entrar/salir y ver las filas.
- [ ] Limpiar los datos de prueba (permisos, vacaciones, log) al terminar.

Cierre: build OK, `check-app-sps` 93/0, visual OK, sin datos de prueba.

### 3. Contratos: cargar los datos de la empresa

- [ ] `UPDATE` sobre `CONFIGURACION` con `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`. Hoy el contrato los imprime como `____________`.
- No existe tabla `EMPRESA` (se creó, el dueño la rechazó y se borró el mismo día). Todo va en `CONFIGURACION`.

---

## 🟠 P1 — Alta prioridad (funcionalidad a medias)

### 4. Contratos: campos legales RD + revisión legal

- [ ] Agregar a la plantilla: nacionalidad, edad, sexo, estado civil, **RNL** (Registro Nacional del Trabajador), lugar de prestación, provincia y municipio. Checklist y fuentes: `Flujos/Contrato de trabajo - requisitos legales RD.md`.
- [ ] Revisión legal del texto antes de usarlo con personal real (la plantilla ya lo dice al pie).

### 5. RRHH: módulos que faltan

- [ ] **14 Bonos** — pantalla mínima (listar, pagar, anular). El 1% ya lo genera el trigger de 24.
- [ ] **15 Historial laboral** — `CARGO_ANTERIOR/NUEVO VARCHAR(30)` vs `EMPLEADOS.CARGO VARCHAR(50)`: ampliar a 50 y migrar.
- [ ] **30 Auditoría de permisos** — trigger activo; falta el lector y decidir si guarda el actor (hoy no lo tiene).
- [ ] **16 Liquidaciones** — **no tocar todavía**: la fórmula `SALARIO * AÑOS` es placeholder y "Despedir" vs "Liquidar" no cierra. Decidir el flujo de negocio primero.

### 6. Decisiones de producto (una vez cada una)

- [ ] **¿RRHH va o no?** (12, 13, 14, 16 y el historial de 15). Con lo ya hecho, va.
- [ ] **¿28 LOG_ACCESOS?** Ya está cableado y commiteado; solo falta la prueba visual (P0).
- [ ] **¿34 ASIGNAR RECLAMOS?** Cablear el flujo o borrarlo con su tabla.
- [ ] **¿35 DETALLE_REPARACIONES?** ¿Repuesto con stock o texto libre?
- [ ] **¿19.5 anular pago y 22 quitar/modificar línea?** ¿Pantalla o SQL?

### 7. Bugs y deuda con impacto

- [ ] **Venta multi-línea atómica** (P-4 de la auditoría).
- [ ] **P-3 validaciones**: 8 errores pintados en verde, advertencia de precio descartada y monto de la liquidación tomado del cliente.
- [ ] **Costo fantasma al cancelar una compra** (auditoría #1: `PRODUCTO FASE I` quedó con `P_COMPRA` de dos compras canceladas y cero válidas).
- [ ] **`EMPLEADOS.CEDULA` sin `UNIQUE`** (riesgo latente; hoy 9 empleados con 9 cédulas distintas).
- [ ] **Rotar la clave del administrador** (C-2 de la auditoría; la de `root` ya se rotó el 19/10).
- [ ] **`SP_ACTUALIZAR_VACACIONES`**: al cablear la edición, validar solapamiento y fecha futura (hoy no lo hace; no es alcanzable desde la UI).
- [ ] **Drift TEST ↔ viva en asistencia**: la viva tiene `11_SP_REGISTRAR_ENTRADA` y TEST no; además TEST tenía dos que a la viva le faltaban. Diffear definiciones antes de copiar, no asumir cuál es la buena.
- [ ] **Barrido del resto de los `while` con `leerDatoSeguro`** (el 18/10 solo se tocó `contrato.cpp`; los bucles con EOF pueden girar sin fin).

### 8. Hallazgos del mapa de módulos (21/10)

- [ ] **El BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) está copiado en 6 objetos por flujo (compras y ventas) más las 5 vistas del 43. Extraer una función compartida.
- [ ] **Devolver mercancía no baja el subtotal**: solo descuenta el ITBIS devuelto.
- [ ] **`VENCIDA` de GARANTIAS nunca se escribe**: hoy se puede reclamar una garantía vencida.
- [ ] **El 18 atribuye todo al empleado 1** y el 29 guarda `ID_USUARIO_ADMIN` en `NULL`: la auditoría no dice quién fue.
- [ ] **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño.

---

## 🟡 P2 — Media (reproducibilidad y limpieza)

- [ ] **P-5**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas y `GESTIONAR_METODOS_PAGO` en sus módulos, y sacar de los módulos el `UPDATE`, los `SELECT *` y los `CALL` de semilla.
- [ ] **`db/import.sh`** sigue con `--force` (ahora cuenta los `^ERROR` y avisa): hacerlo fallar de verdad.
- [ ] **Consolidar los `ALTER` de 25** dentro del `CREATE TABLE`; `DROP IF EXISTS` en los `CREATE` del módulo 11.
- [ ] **3 tests shell** pendientes y notas obsoletas del índice (`modulos/00- INDICE.md`).
- [ ] **`db/crear-usuarios.sh` no existe**: buscar el comando de provisión de la máquina del trabajo y compararlo con `balbu_app` / `balbu_admin`.
- [ ] **`.atl/` entró en `d623ac0`**: decidir si se versiona (si no: `git rm -r --cached .atl` + commit).
- [ ] **Sidecar `.borrador`** guarda PII en texto plano junto al HTML (registrado y aceptado por el dueño).
- [ ] **`contratos/firmados/`**: sin listado, renombre ni limpieza; la administra RRHH a mano.
- [ ] **P-6**: decidir cablear o retirar lo construido y no cableado (garantías, reclamos, reparaciones, bonos manuales).

---

## 🔵 P3 — Baja / bloqueado

- [ ] **NCF / comprobante fiscal DGII** — **bloqueado** por el trámite en la oficina virtual (autorización + asignación de secuencia). La app no inventa números.
- [ ] **API para la web**: `GET /api/reporte` que llame al mismo SP + `fetch` en `index.html` (hoy la web es estática con simulados).
- [ ] **Lector biométrico** — sin equipo. El corte ya está: `marcarAsistenciaAuto()` toma `sesionActual.idEmpleado`; el modo huella reemplaza esa lectura sin tocar el resto. Falta decidir equipo (define opción A o B).
- [ ] **Permisos por cargo** (reclutamiento 12 vs contrataciones 13/14/15): hoy es convención del flujo, la app no separa roles. Fuera de alcance.
- [ ] Borrar la rama `backup-casa-20-10` (después del merge).

---

## ✅ Planes cerrados (por si buscás el detalle)

| Plan | Cuándo | Dónde quedó |
|---|---|---|
| Generar contrato (borrador) | 19/10 | `Realizado.md` — 3ª parte |
| Registrar contrato firmado (fases 1–8) | 19/10 | `Realizado.md` — 4ª parte |
| C-3: permisos administrables | 20/10 | commit del 20/10 |
| Set final de 7 roles | 22/10 | commit `22b2f8e` |
| Asistencia v1 y v2 | 16–17/10 | `Realizado.md` |
| Flujo de compras / ventas | 08/10 | `Realizado.md` |
| Observaciones SQL | 09/10 | cerrado salvo "consolidar ALTER" (P2) |

---

## Comandos

```bash
# Build
./build.sh

# SPs que usa la app (debe dar 93/0)
DB_HOST=127.0.0.1 bash db/check-app-sps.sh

# Menús por rol (sobre TEST)
BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh

# Contrato: UI
DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=linux01 BALBU_USER=admin BALBU_PASS=admin123 bash db/test-contrato-borrador.sh

# Contratos: SQL
DB_PASSWORD=linux01 DB_NAME=BALBU_TECH_TEST bash db/test-contratos-subir.sh
```

---

## Referencias

- `Realizado.md` — lo hecho, con evidencia.
- `Auditoria/` — hallazgos con detalle (18/10 código + BD; 08/10 solo lo abierto).
- `Flujos/` — requisitos legales del contrato, flujo de producto y de BD.
- `Reglas/Reglas de trabajo.md` — cómo se trabaja.
