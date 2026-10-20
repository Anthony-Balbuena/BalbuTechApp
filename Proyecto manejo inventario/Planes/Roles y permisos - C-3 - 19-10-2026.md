# Roles y permisos — C-3 (19/10/2026)

> Nota de trabajo. **C-3 quedó ejecutado el 20/10/2026** (permisos administrables, una sola fuente de verdad: la base). **La decisión de producto también está tomada: el set final de roles de la tienda quedó definido el 20/10/2026** (sección 1) y ya está sembrado en los módulos 3 y 36.
>
> Dato clave: una vez que C-3 esté, **agregar un rol nuevo es crear el rol y tildar permisos en la app** (1 minuto, sin tocar código). No hace falta congelar el universo de roles hoy.

---

## 1. Decisión pendiente (completar en casa)

> **Estado: RESUELTA el 20/10/2026.** El set final de roles quedó definido y ya está
> implementado: la semilla de roles vive en `modulos/3- ROLES.sql` y la matriz de
> permisos en `modulos/36- PERMISOS_ROLES.sql`. La decisión completa está en
> "Set final de roles (decidido el 20/10/2026)" más abajo en esta misma sección.

**Pregunta:** ¿quiénes van a usar el sistema día a día y qué hace cada uno?

| Persona / puesto | Qué hace | Rol propuesto |
|---|---|---|
| Dueño / administrador del sistema | Configura roles, usuarios y todo el sistema | ADMIN |
| Encargado de la tienda | Opera ventas, caja, compras, stock y personal | GERENTE |
| Mostrador / caja | Cobra, registra ventas, consulta productos y clientes | CAJERO |
| Almacén / stock | Productos, categorías, marcas, inventario, compras y proveedores | ALMACEN |
| Recursos humanos | Empleados, contratos, asistencia y reportes | RRHH |
| Personal de piso | Consulta catálogo y clientes, registra asistencia, pide permisos | EMPLEADO |

**Regla base:** un rol = una **función del negocio**, no una persona ni un módulo. Cada usuario tiene **un solo rol** (`USUARIOS.ID_ROL`), así que los roles deben cubrir las combinaciones reales del equipo.

### Set recomendado (tienda de tecnología)

| Rol | Para quién | Permisos |
|---|---|---|
| **ADMIN** | Dueño / administrador del sistema | Todos (incluye Roles y Usuarios) |
| **GERENTE** | Encargado de la tienda | Todo lo operativo: Ventas/Caja, Compras, Inventario, Productos, Categorías, Marcas, Clientes, Proveedores, Empleados/Asistencia, Reportes. Usuarios sí, **Roles no** |
| **VENDEDOR** | Mostrador / caja | Ventas (incl. caja), consultar productos y clientes, registrar asistencia, solicitar permiso |
| **ALMACEN** | Stock y compras | Productos, Inventario, Compras, Proveedores, Categorías, Marcas, consultar reportes. Sin ventas ni usuarios |
| **RRHH** | Recursos humanos (si existe la figura) | Empleados, asistencia, permisos, reportes. Sin ventas ni inventario |
| **CONTABILIDAD** *(opcional)* | Contador externo / dueño para números | Solo consulta de reportes y ganancias — requiere que C-3 separe "ver reportes" de "operar ventas" |

**Si la tienda es chica (dueño + 1 o 2 personas):** el set real es **ADMIN + GERENTE + VENDEDOR**. ALMACEN y RRHH los absorbe el GERENTE o el ADMIN.

### Lo que NO conviene crear

- **COMPRAS** separado de **ALMACEN** → en tienda chica es la misma persona.
- **CAJERO** separado de **VENDEDOR** → la caja va con la venta.
- Un rol por módulo ("rol de inventario", "rol de clientes") → eso son **permisos**, no roles.
- Un rol por persona ("rol de Juan") → si Juan hace dos funciones, se le da un rol combinado o se le agregan permisos al rol que ya tiene.

### Set final de roles (decidido el 20/10/2026)

Seis roles, uno por función del negocio. La base es la única fuente de verdad: esta
matriz es la que siembran los módulos y la que se puede ajustar después desde la app
(submenú Roles).

| Rol | Para quién | Cantidad de permisos | Permisos |
|---|---|---|---|
| **ADMIN** | Dueño / administrador del sistema | 18 | Todos: roles, usuarios, empleados, contratos, clientes, proveedores, categorías, marcas, productos, métodos de pago, inventario, ventas, compras, reportes, consultas de productos/clientes, asistencia y permisos |
| **GERENTE** | Encargado de la tienda | 16 | Todos **menos** `GESTIONAR_ROLES` y `GESTIONAR_USUARIOS` (es decir, incluye empleados, contratos, clientes, proveedores, categorías, marcas, productos, métodos de pago, inventario, ventas, compras, reportes, consultas, asistencia y permisos) |
| **CAJERO** | Mostrador / caja | 6 | `GESTIONAR_VENTAS`, `GESTIONAR_CLIENTES`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`, `CONSULTAR_REPORTES` |
| **ALMACEN** | Stock y compras | 7 | `GESTIONAR_PRODUCTOS`, `GESTIONAR_CATEGORIAS`, `GESTIONAR_MARCAS`, `GESTIONAR_INVENTARIO`, `GESTIONAR_COMPRAS`, `GESTIONAR_PROVEEDORES`, `CONSULTAR_PRODUCTOS` |
| **RRHH** | Recursos humanos | 3 | `GESTIONAR_EMPLEADOS`, `GESTIONAR_CONTRATOS`, `CONSULTAR_REPORTES` |
| **EMPLEADO** | Personal de piso | 5 | `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`, `GESTIONAR_VENTAS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` |

**Reglas que quedan fijadas:**

- **Crear roles y usuarios es exclusivo de ADMIN.** Solo ADMIN tiene `GESTIONAR_ROLES` y
  `GESTIONAR_USUARIOS`; ningún otro rol llega al submenú Roles ni al de Usuarios.
- **Los contratos tienen permiso propio: `GESTIONAR_CONTRATOS`.** Sin ese permiso las
  opciones 12 a 15 del submenú de Empleados (generar, subir, ver y finalizar contrato)
  ni siquiera se imprimen, y si el usuario escribe el número igual la app le responde en
  rojo y lo devuelve al menú. Lo tienen ADMIN, GERENTE y RRHH.
- **La base manda.** Los permisos de cada rol se administran desde la app; el módulo
  `36- PERMISOS_ROLES.sql` solo siembra la matriz inicial.

**Diferencias con el set recomendado de arriba** (queda el registro de la recomendación
original, pero el set final es el de esta tabla):

- **VENDEDOR → CAJERO**: se conserva el rol de mostrador, pero con el nombre `CAJERO` y
  con `GESTIONAR_CLIENTES` y `GESTIONAR_METODOS_PAGO` además de ventas y consultas.
- **GERENTE no administra usuarios**: la recomendación le daba usuarios; el set final se
  los deja solo a ADMIN, para que un encargado no pueda crear cuentas.
- **CONTABILIDAD no se crea**: la consulta de reportes entra por `CONSULTAR_REPORTES`
  (ya lo tienen ADMIN, GERENTE, CAJERO y RRHH) y no hace falta un rol aparte.
- **ALMACEN sin reportes**: la recomendación le daba "consultar reportes"; el set final
  se queda con stock y compras.

---

## 2. Diagnóstico verificado (19/10/2026)
- **Base viva:** `ROLES` = ADMIN(1), RRHH(2), EMPLEADO(3); `ROL_PERMISO` = ADMIN 16, RRHH 5, EMPLEADO 4; usuario `admin` con `ID_ROL = 1`.
- **`CHK_ROL_NOMBRE` existe** en `ROL_PERMISO`: solo acepta ADMIN/RRHH/EMPLEADO → cualquier rol nuevo nace inerte.
- **`FN_TIENE_PERMISO`** recibe `P_ACCION VARCHAR(20)`: trunca `GESTIONAR_PROVEEDORES` (21) y `GESTIONAR_METODOS_PAGO` (23) → nunca matchean por esa vía (auditoría #9: subir a `VARCHAR(80)`).
- **`GESTIONAR_METODOS_PAGO` no existe en `PERMISOS`** (hay 16) pero `roles.cpp` lo usa para el menú → permiso fantasma: hoy el módulo abre solo por la lista hardcodeada del C++.
- **`roles.cpp` ignora la base:** `obtenerPermisosPorRol` tiene 3 listas hardcodeadas y `tienePermiso` las consulta **primero**; `FN_TIENE_PERMISO` es solo fallback. Menú hardcodeado por nombre de rol (ADMIN / RRHH / "else").
- **Desfasajes C++ ↔ DB:** RRHH y EMPLEADO tienen `GESTIONAR_VENTAS` en el C++ pero **no** en `ROL_PERMISO`.
- **`SP_ASIGNAR_PERMISO_A_ROL` existe pero ningún `.cpp` lo llama**; no hay SP para **quitar** un permiso.
- **`FK_ROL_PERMISO_ROL` sin `ON UPDATE CASCADE`** → renombrar un rol que ya tiene permisos rompe por FK.

---

## 3. Plan C-3 (checklist para ejecutar)

### Paso 0 — Backup
- [x] Dump de `ROLES`, `ROL_PERMISO`, `PERMISOS` + definiciones de `FN_TIENE_PERMISO` y SPs a `backups/` (gitignored).

### Paso 1 — Base viva
- [x] `ALTER TABLE ROL_PERMISO DROP CONSTRAINT CHK_ROL_NOMBRE;`
- [x] Recrear `FK_ROL_PERMISO_ROL` con **`ON UPDATE CASCADE`**.
- [x] Insertar permiso faltante `GESTIONAR_METODOS_PAGO` y asignarlo a ADMIN.
- [x] Sembrar `GESTIONAR_VENTAS` para RRHH y EMPLEADO (hoy lo tienen solo por el C++; sin esto dejarían de vender al quitar el hardcodeo).
- [x] Recrear `FN_TIENE_PERMISO` con `P_ACCION VARCHAR(80)`.
- [x] Crear `SP_QUITAR_PERMISO_A_ROL`.

### Paso 2 — Módulos SQL
- [x] `modulos/36- PERMISOS_ROLES.sql`: sin `CHK_ROL_NOMBRE`, FK con `ON UPDATE CASCADE`, seed con `GESTIONAR_METODOS_PAGO` + `GESTIONAR_VENTAS` en RRHH/EMPLEADO, FN `VARCHAR(80)`, SP de quitar. Import desde cero = base viva.

### Paso 3 — C++ (`roles.cpp`)
- [x] `obtenerPermisosPorRol`: consultar la base (`ROL_PERMISO ⋈ PERMISOS` por nombre de rol). **Borrar las 3 listas hardcodeadas.**
- [x] `tienePermiso`: solo base (FN corregida), sin atajo local.
- [x] **Menú dinámico**: misma lista y orden que el menú ADMIN actual (1 Roles … 13 Caja), filtrado por permisos reales + "Ver permisos" y "Cerrar sesión" siempre. ADMIN queda idéntico; RRHH/EMPLEADO ven solo lo suyo (cambia la numeración); un rol nuevo ve su menú real.
- [x] Submenú Roles: agregar **Asignar permiso**, **Quitar permiso** y **Ver permisos de rol** (con lista de permisos disponibles para elegir), llamando a los SPs.

### Paso 4 — Verificación
- [x] Compilar.
- [x] ADMIN: menú 1-15 idéntico y Métodos de pago abre (permiso nuevo).
- [x] EMPLEADO/RRHH: mismas acciones que hoy (vender incluido).
- [x] Crear rol `VENDEDOR` → asignar `CONSULTAR_PRODUCTOS` + `GESTIONAR_VENTAS` → usuario de prueba con ese rol → menú solo con Productos/Ventas/Caja/Ver permisos; Roles/Usuarios/Compras no aparecen ni abren.
- [x] Quitar un permiso → desaparece del menú y bloquea el módulo.
- [x] Renombrar un rol con permisos → OK (cascade).
- [x] Regresión: venta rápida y asistencia siguen bien.

### Rollback
- Restaurar las 3 tablas desde el dump y revertir `cpp`/módulos con git (nada se commitea hasta aprobar).

---

## 4. Referencias

- Auditoría: `Auditoria/Auditoria completa - Codigo y BD - 18-10-2026.md` → sección **C-3** y prioridades **#8** (una sola fuente de verdad: la base) y **#9** (`FN_TIENE_PERMISO VARCHAR(80)`).
- Archivos: `modulos/36- PERMISOS_ROLES.sql`, `modulos/3- ROLES.sql`, `roles.cpp`, `modulos/10- USUARIOS.sql` (alta de usuario con `ID_ROL`).
- Estado general: C-1 (rotación de credenciales de BD) y C-2 (purga de la clave personal del historial público) **hechos 19/10**. Este era el último crítico de la auditoría.

---

## 5. Ejecutado (20/10/2026)

- **Base viva:** `CHK_ROL_NOMBRE` eliminado; `FK_ROL_PERMISO_ROL` con `ON UPDATE CASCADE`; `PERMISOS` = 17 (incluye `GESTIONAR_METODOS_PAGO`); `ROL_PERMISO` = ADMIN 17, RRHH 6, EMPLEADO 5; `FN_TIENE_PERMISO` con `P_ACCION VARCHAR(80)`; creados `SP_QUITAR_PERMISO_A_ROL` y `SP_LISTAR_PERMISOS_POR_ROL` (params de rol a `VARCHAR(50)`).
- **Código:** `roles.cpp` sin listas hardcodeadas. `tienePermiso` consulta solo `FN_TIENE_PERMISO`; menú dinámico con el orden histórico de ADMIN filtrado por permisos; submenú Roles con Asignar/Quitar/Ver permisos. `modulos/36` actualizado (import desde cero = base viva) e incluye migración idempotente para bases existentes (`DROP CONSTRAINT`/`DROP FOREIGN KEY IF EXISTS` + FK con cascade).
- **Verificado:** build OK; menú ADMIN 1–15 idéntico; RRHH y EMPLEADO conservan sus módulos (Caja incluida); rol `VENDEDOR` de prueba mostró solo Productos/Ventas/Caja; asignar y quitar permiso desde la app cambió el menú al instante; renombrar rol con permisos conservó las filas (`ON UPDATE CASCADE`); prueba de VENDEDOR borrada al terminar (sin residuos).
- **Rollback:** `backups/roles-antes-20-10.sql` (dump completo con rutinas) y `backups/roles-antes-set-final-20-10.sql` (dump de roles/permisos antes del set final). El código se revierte con git.
- **Pendiente:** nada de C-3. El set final de roles quedó definido y aplicado (ver las dos entradas siguientes). Con C-3 listo, cada rol nuevo se crea y se le tildan permisos desde la app.
- **Set final de roles (20/10/2026, mismo día):** quedó decidido el set de 6 roles (ADMIN, GERENTE, CAJERO, ALMACEN, RRHH, EMPLEADO) con su matriz de permisos (sección 1). Cambios en el repo: `modulos/3- ROLES.sql` siembra los 6 roles; `modulos/36- PERMISOS_ROLES.sql` agrega el permiso `GESTIONAR_CONTRATOS` (18 permisos), reemplaza la matriz de permisos por rol y agrega un bloque de migración idempotente que borra de RRHH los permisos que el set final deja afuera (`GESTIONAR_ROLES`, `GESTIONAR_USUARIOS`, `GESTIONAR_CLIENTES`, `GESTIONAR_VENTAS`); `empleados.cpp` esconde las opciones 12 a 15 (contratos) si el usuario no tiene `GESTIONAR_CONTRATOS` y bloquea la opción con aviso en rojo.
- **Base viva (20/10/2026):** el set final **sí quedó aplicado**. Se aplicó la semilla de los 6 roles de `modulos/3- ROLES.sql` (solo el `INSERT IGNORE`: el `CREATE TABLE ROLES` del módulo no tiene `IF NOT EXISTS` y tiraría "tabla ya exists") y después `modulos/36- PERMISOS_ROLES.sql` completo (la migración de RRHH corre sola dentro del módulo). Estado verificado en la base: 6 roles, 18 permisos, matriz ADMIN 18 / GERENTE 16 / CAJERO 6 / ALMACEN 7 / RRHH 3 / EMPLEADO 5.
- **Verificación end-to-end (20/10/2026):** se crearon 5 usuarios temporales (uno por rol, con la clave de `admin`) y se entró a la app con cada uno: ADMIN ve los 15 ítems de siempre; GERENTE ve todo **menos Roles y Usuarios**; CAJERO ve Clientes/Productos/Métodos de pago/Ventas/Caja; ALMACEN ve Proveedores/Categorías/Marcas/Productos/Compras/Inventario; RRHH ve solo Empleados; EMPLEADO ve Clientes/Productos/Ventas/Caja. El gate de contratos se probó de las dos formas: con `GESTIONAR_CONTRATOS` las opciones 12 a 15 se imprimen; sin el permiso **no se imprimen** y al escribir el número la app responde en rojo "No tienes permiso para gestionar contratos." (probado quitando el permiso a GERENTE con `SP_QUITAR_PERMISO_A_ROL` y volviéndolo a asignar después). `db/check-app-sps.sh`: 0 faltantes de 85. Los 5 usuarios y los 5 empleados de prueba se borraron: **0 residuos** (queda 1 usuario y 1 empleado, los reales).
- **Rollback del set final:** `backups/roles-antes-set-final-20-10.sql` (dump de `ROLES`, `PERMISOS` y `ROL_PERMISO` antes de aplicar). Los datos de prueba de la verificación se limpian con `backups/96-limpiar-pruebas.sql`.
