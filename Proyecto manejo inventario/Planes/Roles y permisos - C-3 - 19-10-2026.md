# Roles y permisos — C-3 (19/10/2026)

> Nota de trabajo. **C-3 quedó ejecutado el 20/10/2026** (permisos administrables, una sola fuente de verdad: la base). Falta solo la decisión de producto: **definir el set final de roles de la tienda** (sección 1), que ahora se crea desde la app sin tocar código.
>
> Dato clave: una vez que C-3 esté, **agregar un rol nuevo es crear el rol y tildar permisos en la app** (1 minuto, sin tocar código). No hace falta congelar el universo de roles hoy.

---

## 1. Decisión pendiente (completar en casa)

**Pregunta:** ¿quiénes van a usar el sistema día a día y qué hace cada uno?

| Persona / puesto | Qué hace | Rol propuesto |
|---|---|---|
| | | |
| | | |
| | | |

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
- **Rollback:** `backups/roles-antes-20-10.sql` (dump completo con rutinas). El código se revierte con git; nada se commiteó todavía.
- **Pendiente:** completar la tabla de la sección 1 (set final de roles). Con C-3 listo, cada rol nuevo se crea y se le tildan permisos desde la app.
