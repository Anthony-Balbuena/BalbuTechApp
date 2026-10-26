# PENDIENTES — todo en un solo lugar

> **Único archivo de pendientes del proyecto.** De arriba abajo = prioridad.
> Lo hecho vive en `Realizado.md`; los detalles largos, en `Auditoria/` y `Flujos/`.
> Actualizado: 26/10/2026.

---

## 🔴 P0 — Ahora (bloquea lo que estás haciendo)

### 1. Permisos finos: Tanda B cerrada en TEST y en la viva

Estado: **TEST y la viva migradas** (26/10/2026: 7 roles, **54 permisos**, matriz **54/48/42/12/16/25/4 = 201 pares**; `test-menus-por-rol.sh` 0 fallos en TEST, `check-app-sps` 93/0 en ambas). Backup vivo previo: `backups/106-antes-permisos-inventario-26-10-2026.sql`. Usuarios, Empleados, Clientes, Proveedores, Asistencia, Productos, Ventas, Categorías, Marcas, Métodos de pago, Compras, Caja e Inventario ya están cerrados; **no queda ningún módulo con permiso paraguas**. El detalle con evidencia vive en `Realizado.md`. VENDEDOR ya no ve reportes ni ganancias: el historial tiene permiso propio (`CONSULTAR_HISTORIAL_VENTA`) y Garantías sigue con `GESTIONAR_VENTAS`.

- [x] ~~**Inventario**: migrar sus tres acciones a permisos finos.~~ Hecho en TEST el 26/10 con `INVENTARIO_VER`, `INVENTARIO_AJUSTAR` e `INVENTARIO_COSTO` (módulo `58`).
- [x] ~~**Aplicar el `58` en la viva** con backup previo.~~ Hecho el 26/10 con backup `backups/106-antes-permisos-inventario-26-10-2026.sql`.

**Estimación de esfuerzo (26/10):** ya no quedan módulos con paraguas; la Tanda B está cerrada.

- **Inventario** cerrado: `INVENTARIO_VER` abre Movimientos, `INVENTARIO_AJUSTAR` el ajuste de stock e `INVENTARIO_COSTO` el precio de compra. Cualquiera de los tres abre el ítem del menú.
- **Caja** ya quedó cerrada en esta tanda: permisos propios (`CONSULTAR_CAJA`, `ABRIR_CAJA`, `CERRAR_CAJA`), módulo `53` aplicado en TEST y VENDEDOR conserva los tres.
- **Ventas** ya está cerrado. Solo tiene pendiente el submenú de Garantías, que despacha por número porque es una lista fija sin filtro. No es un bug; se migra si se le agregan permisos propios (ver P1, Garantías).
- Lo que sigue son los P1/P2 (garantías, RRHH, deuda técnica), no permisos finos.

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

### 2. Pruebas de aceptación: todo lo hecho (Tanda A y B)

Todo se prueba **primero en `BALBU_TECH_TEST`**, con la matriz de 54 permisos aplicada (`36`, `44`, `45`, `46`, `47`, `49`, `50`, `51`, `52`, `53`, `58`). La viva sigue en 52 hasta aplicar el `58` con backup previo.

**Automático (ya corre, solo hay que ejecutarlo):**

| Comando | Cubre | Esperado |
|---|---|---|
| `bash build.sh` | compila | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh` | SPs que usa la app | 93/0 |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh` | menú principal + submenús de Usuarios, Empleados, Clientes, Proveedores, Categorías, Marcas, Métodos de pago, Asistencia, Productos, Ventas, Compras, Caja e Inventario | 42/42 |
| `BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST DB_USER=... DB_PASSWORD=... bash db/test-contrato-borrador.sh` | contrato borrador | 15/15 |
| `BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-asistencia-propia.sh` | fichar sin pedir ID | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh` | módulo 44 (rol viejo → VENDEDOR) | 11/11 |

**Manual, por área:**

#### 2.1 Sesión y menú principal

- [ ] ADMIN entra y ve **19** opciones.
- [ ] GERENTE ve **16** y **no** aparecen Roles ni Usuarios.
- [ ] SUBGERENTE ve **16**, con Empleados (solo 3: buscar, listar, volver) y Asistencia (7, con Justificar).
- [ ] RRHH ve **6**; VENDEDOR **10**; ALMACEN **11**; CONTABILIDAD **5**.
- [ ] Usuario con `ESTADO = INACTIVO` **no** puede entrar (el login lo rechaza y deja `LOG_ACCESOS` con `INACTIVO`).
- [ ] **Cambio en caliente:** con una sesión de VENDEDOR abierta, quitarle `CLIENTES_VER` desde ADMIN y volver al menú principal. Clientes desaparece **sin re-login** (el menú consulta `FN_TIENE_PERMISO` en cada vuelta).
- [ ] Al reingresar después de quitar el permiso, la opción sigue ausente.

#### 2.2 Usuarios (solo ADMIN)

- [ ] Crear usuario con rol VENDEDOR y clave; entrar con él.
- [ ] Editar el nombre y el rol; verificar que el menú cambie en el siguiente ingreso.
- [ ] Desactivar la cuenta; el login falla con el aviso correspondiente.
- [ ] Reactivar; el login vuelve a funcionar.
- [ ] Cambiar la clave; la vieja deja de servir y la nueva entra.
- [ ] GERENTE **no** ve el módulo Usuarios.

#### 2.3 Empleados

- [ ] RRHH: crear empleado, editarlo, darlo de baja y reactivarlo.
- [ ] RRHH: gestionar contrato, permiso y vacaciones desde el submenú.
- [ ] SUBGERENTE: entra a Empleados pero solo ve consulta; **no** puede crear, editar ni dar de baja.
- [ ] Un usuario sin ningún permiso `EMPLEADOS_*` no ve el módulo (salvo que tenga `REGISTRAR_ASISTENCIA` o `CONSULTAR_ASISTENCIA`, que abren **Asistencia**, no Empleados).

#### 2.4 Clientes

- [ ] VENDEDOR: ver, crear, editar y cambiar estado. Las cuatro acciones funcionan.
- [ ] CONTABILIDAD: solo `CLIENTES_VER`; ve la consulta y nada más.
- [ ] Quitar `CLIENTES_ESTADO` a VENDEDOR: la opción desaparece del submenú y **no** queda un hueco en la numeración.

#### 2.5 Proveedores

- [ ] ALMACEN: ver, crear, editar y cambiar estado (6 opciones en el submenú).
- [ ] Sin `PROVEEDORES_CREAR`, la opción de alta desaparece y el resto sigue funcionando.

#### 2.6 Asistencia

- [ ] Los 7 roles pueden **fichar** (`REGISTRAR_ASISTENCIA`).
- [ ] VENDEDOR ve 3 opciones, **sin** reportes.
- [ ] SUBGERENTE ve 7, con Justificar.
- [ ] ADMIN, GERENTE, SUBGERENTE y RRHH ven los reportes (`CONSULTAR_ASISTENCIA`).
- [ ] "Mi asistencia" usa el `ID_EMPLEADO` de la sesión, **no** pide ID a mano.
- [ ] `CONSULTAR_ASISTENCIA` **no** abre Empleados.
- [ ] Justificar una ausencia y ver el cambio en el reporte.

#### 2.7 Productos

- [ ] ALMACEN ve 7 (gestión + consulta).
- [ ] CONTABILIDAD ve 4 (solo consulta).
- [ ] Un rol sin `CONSULTAR_PRODUCTOS` no ve el módulo.
- [ ] `PRUEBA_PROD_GEST` (solo gestión) ve 4 y no ve las de consulta.

#### 2.8 Ventas

- [ ] VENDEDOR ve 10: las 7 de gestión, historial, garantías y volver, **sin** reportes ni exportación.
- [ ] `PRUEBA_VEN_GEST` (sin `CONSULTAR_REPORTES`) ve 9: solo las acciones sobre la venta.
- [ ] **Garantías** se abre con `GESTIONAR_VENTAS`; sus 4 opciones son fijas (registrar, reclamar, finalizar, volver).

#### 2.9 Roles

- [ ] Crear un rol nuevo, asignarle `CLIENTES_VER` y entrar con un usuario de ese rol.
- [ ] Quitarle el permiso y verificar que el módulo desaparezca.
- [ ] Borrar el rol: los usuarios que lo tenían no pueden entrar (verificar el mensaje).
- [ ] Renombrar un rol: los permisos lo siguen (`ON UPDATE CASCADE`).

#### 2.10 Migración de roles (módulo 44)

- [ ] En TEST, el test automático ya lo cubre (11/11).
- [ ] En la viva, confirmar que no quedan roles `EMPLEADO` ni `CAJERO` y que sus usuarios pasaron a `VENDEDOR`:

```sql
SELECT NOMBRE_ROL FROM ROLES ORDER BY NOMBRE_ROL;
SELECT COUNT(*) FROM USUARIOS U LEFT JOIN ROLES R ON R.ID_ROL = U.ID_ROL WHERE R.ID_ROL IS NULL;
```

Ambas deben dar 7 roles y 0 usuarios huérfanos.

### 3. RRHH: pruebas visuales pendientes

- [ ] **13 Permisos:** solicitar → aprobar uno y rechazar otro → reintentar aprobar el ya aprobado ("solo pendientes") → ver la fila en `LOG_AUDITORIA_PERMISOS`.
- [ ] **12 Vacaciones:** solicitar → aprobar/rechazar → reintentar; una **aprobada** que cubra hoy bloquea la asistencia, una **pendiente o rechazada** no; cupo de 15 días + solapamiento (rechazar libera).
- [ ] **28 Accesos:** entrar/salir y ver las filas.
- [ ] Limpiar los datos de prueba (permisos, vacaciones, log) al terminar.

Cierre: build OK, `check-app-sps` 93/0, visual OK, sin datos de prueba.

### 4. Contratos: cargar los datos de la empresa

- [ ] `UPDATE` sobre `CONFIGURACION` con `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`. Hoy el contrato los imprime como `____________`.
- No existe tabla `EMPRESA` (se creó, el dueño la rechazó y se borró el mismo día). Todo va en `CONFIGURACION`.

---

## 🟠 P1 — Alta prioridad (funcionalidad a medias)

### 5. Contratos: campos legales RD + revisión legal

- [ ] Agregar a la plantilla: nacionalidad, edad, sexo, estado civil, **RNL** (Registro Nacional del Trabajador), lugar de prestación, provincia y municipio. Checklist y fuentes: `Flujos/Contrato de trabajo - requisitos legales RD.md`.
- [ ] Revisión legal del texto antes de usarlo con personal real (la plantilla ya lo dice al pie).

### 6. Garantías: estructurar el flujo (diseño acordado 23/10)

Hoy **cualquiera con `GESTIONAR_VENTAS`** (ADMIN, GERENTE, SUBGERENTE, VENDEDOR) registra, reclama y finaliza. No queda autor, `VENCIDA` nunca se escribe y el flujo pide IDs a ciegas.

**Permisos nuevos (4):**

| Permiso | Roles |
|---|---|
| `GARANTIAS_REGISTRAR` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `GARANTIAS_RECLAMAR` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `GARANTIAS_FINALIZAR` | ADMIN, GERENTE, SUBGERENTE |
| `GARANTIAS_CONSULTAR` | los 4 + CONTABILIDAD |

La diferencia clave: **el vendedor ya no cierra reclamos**. Atiende y registra, pero la decisión queda en Gerencia. VENDEDOR conserva `GARANTIAS_REGISTRAR` y `GARANTIAS_RECLAMAR`.

**Datos (módulo 48, idempotente):**

- `GARANTIAS`: `ID_EMPLEADO` (quién registró) y `FECHA_REGISTRO`.
- `RECLAMOS_GARANTIAS`: `ID_EMPLEADO`, `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE`.
- Opcional: `PRODUCTOS.DIAS_GARANTIA` para no pedir los días a mano.

**SPs:**

- `SP_REGISTRAR_GARANTIA(detalle, dias, idEmpleado)`.
- `27_SP_REGISTRAR_RECLAMO_GARANTIA(garantia, descripcion, idEmpleado)`; validar `CURRENT_DATE BETWEEN FECHA_INICIO AND FECHA_FIN`, no solo `ESTADO`.
- `27_SP_FINALIZAR_RECLAMO_TOTAL(reclamo, idEmpleado)`; validar que el estado sea `PENDIENTE` o `APROBADO`.
- Nuevo SP de consulta por venta o cliente.
- Proceso o vista que marque `VENCIDA` cuando pasa `FECHA_FIN`.

**UI:**

- Registrar: pedir **ID de venta** y listar sus detalles, en vez de pedir el ID de detalle.
- Reclamar y finalizar: listar lo que corresponde, no pedir IDs de memoria.

**Decisión abierta:** registrar a mano o **automático al confirmar la venta** con los días del producto. Lo segundo es más limpio pero toca el flujo de venta.

**Cierre:** build, `check-app-sps`, test de menús, test nuevo de garantías y prueba manual con VENDEDOR (no debe poder finalizar).

### 7. RRHH: módulos que faltan

- [ ] **14 Bonos** — pantalla mínima (listar, pagar, anular). El 1% ya lo genera el trigger de 24.
- [ ] **15 Historial laboral** — `CARGO_ANTERIOR/NUEVO VARCHAR(30)` vs `EMPLEADOS.CARGO VARCHAR(50)`: ampliar a 50 y migrar.
- [ ] **30 Auditoría de permisos** — trigger activo; falta el lector y decidir si guarda el actor (hoy no lo tiene).
- [ ] **16 Liquidaciones** — **no tocar todavía**: la fórmula `SALARIO * AÑOS` es placeholder y "Despedir" vs "Liquidar" no cierra. Decidir el flujo de negocio primero.

### 8. Decisiones de producto (una vez cada una)

- [ ] **¿RRHH va o no?** (12, 13, 14, 16 y el historial de 15). Con lo ya hecho, va.
- [ ] **¿28 LOG_ACCESOS?** Ya está cableado y commiteado; solo falta la prueba visual (P0).
- [ ] **¿34 ASIGNAR RECLAMOS?** Cablear el flujo o borrarlo con su tabla.
- [ ] **¿35 DETALLE_REPARACIONES?** ¿Repuesto con stock o texto libre?
- [ ] **¿19.5 anular pago y 22 quitar/modificar línea?** ¿Pantalla o SQL?

### 9. Bugs y deuda con impacto

- [ ] **Venta multi-línea atómica** (P-4 de la auditoría).
- [ ] **P-3 validaciones**: 8 errores pintados en verde, advertencia de precio descartada y monto de la liquidación tomado del cliente.
- [ ] **Costo fantasma al cancelar una compra** (auditoría #1: `PRODUCTO FASE I` quedó con `P_COMPRA` de dos compras canceladas y cero válidas).
- [ ] **`EMPLEADOS.CEDULA` sin `UNIQUE`** (riesgo latente; hoy 9 empleados con 9 cédulas distintas).
- [ ] **Rotar la clave del administrador** (C-2 de la auditoría; la de `root` ya se rotó el 19/10).
- [ ] **`SP_ACTUALIZAR_VACACIONES`**: al cablear la edición, validar solapamiento y fecha futura (hoy no lo hace; no es alcanzable desde la UI).
- [ ] **Drift TEST ↔ viva en asistencia**: la viva tiene `11_SP_REGISTRAR_ENTRADA` y TEST no; además TEST tenía dos que a la viva le faltaban. Diffear definiciones antes de copiar, no asumir cuál es la buena.
- [ ] **Barrido del resto de los `while` con `leerDatoSeguro`** (el 18/10 solo se tocó `contrato.cpp`; los bucles con EOF pueden girar sin fin).

### 10. Hallazgos del mapa de módulos (21/10)

- [ ] **El BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) está copiado en 6 objetos por flujo (compras y ventas) más las 5 vistas del 43. Extraer una función compartida.
- [ ] **Devolver mercancía no baja el subtotal**: solo descuenta el ITBIS devuelto.
- [ ] **`VENCIDA` de GARANTIAS nunca se escribe**: hoy se puede reclamar una garantía vencida.
- [ ] **El 18 atribuye todo al empleado 1** y el 29 guarda `ID_USUARIO_ADMIN` en `NULL`: la auditoría no dice quién fue.
- [ ] **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño.

---

## 🟡 P2 — Media (reproducibilidad y limpieza)

- [ ] **P-5**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas, y sacar de los módulos el `UPDATE`, los `SELECT *` y los `CALL` de semilla.
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
| Permisos finos (Tanda A y B) | 22–23/10 | `Realizado.md` — 23/10 |
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
