# Permisos finos y menús por rol — Informe 22/10/2026

Estado del trabajo al cierre del 22/10/2026, para retomar en casa.

---

## 1. Qué se hizo hoy

Dos tandas sobre el mismo objetivo: **que al iniciar sesión la app lea los permisos del
usuario y le muestre únicamente lo que puede ejecutar**.

### Tanda A — Set final de roles (cerrada y commiteada)

- 7 roles definitivos: `ADMIN`, `GERENTE`, `SUBGERENTE`, `RRHH`, `VENDEDOR`, `ALMACEN`,
  `CONTABILIDAD`.
- `EMPLEADO` renombrado a `VENDEDOR`; `CAJERO` eliminado y sus permisos absorbidos por
  `VENDEDOR`.
- `ALMACEN` conserva el nombre exacto (no existe `ALMACENERO`).
- Migración aplicada a `BALBU_TECH_TEST` y a `BALBU_TECH`, con backup previo.
- Commit: `22b2f8e Menu por rol`.

### Tanda B — Permisos finos por acción (en curso)

Se reemplazaron los permisos "paraguas" por permisos por acción y se reescribieron los
submenús con el patrón del menú principal: **lista filtrada + despacho por acción**.

| Módulo | Estado | Commit |
|---|---|---|
| Roles | Ya estaba por permiso (C-3) | `22b2f8e` |
| Usuarios | Terminado y verificado | `22b2f8e` |
| Empleados | Terminado y verificado | `c609b05` |
| Clientes | Terminado y verificado, **sin commit** | — |
| Proveedores | Pendiente | — |
| Categorías | Pendiente | — |
| Marcas | Pendiente | — |
| Productos | Pendiente | — |
| Métodos de pago | Pendiente | — |
| Ventas | Pendiente | — |
| Compras | Pendiente | — |
| Inventario | Pendiente | — |
| Caja (turnos) | Pendiente | — |

`Accesos` es un visor de logs y no forma parte de los 12 operativos.

---

## 2. Estado actual de las bases

### `BALBU_TECH` (viva)

- 7 roles, 30 permisos, 93 SPs de la app (0 faltantes).
- Matriz de permisos por rol:

| Rol | Permisos |
|---|---:|
| ADMIN | 30 |
| GERENTE | 24 |
| SUBGERENTE | 16 |
| RRHH | 10 |
| VENDEDOR | 10 |
| ALMACEN | 8 |
| CONTABILIDAD | 3 |

### `BALBU_TECH_TEST`

- Recreada desde cero con `backups/91-recrear-test.sql` y `db/import.sh` (45/45 archivos,
  0 errores).
- Misma matriz que la viva.
- El usuario `admin` se sembró con `db/seed-admin.sh`.

> **Ojo al retomar:** los `CREATE TABLE` de `modulos/*.sql` no son idempotentes. Si TEST
> queda sucia, hay que recrearla antes de importar. La viva nunca se toca con el import.

---

## 3. Catálogo de permisos (30)

### Módulos ya migrados a permisos finos

**Usuarios (5):**
`USUARIOS_VER`, `USUARIOS_CREAR`, `USUARIOS_EDITAR`, `USUARIOS_ESTADO`,
`USUARIOS_CLAVE`.

**Empleados (7):**
`EMPLEADOS_VER`, `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`,
`JUSTIFICAR_ASISTENCIA`, `GESTIONAR_PERMISOS_EMPLEADO`,
`GESTIONAR_VACACIONES_EMPLEADO`.

**Clientes (4):**
`CLIENTES_VER`, `CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`.

### Permisos todavía "paraguas" (los que faltan migrar)

- `GESTIONAR_PROVEEDORES`
- `GESTIONAR_CATEGORIAS`
- `GESTIONAR_MARCAS`
- `GESTIONAR_PRODUCTOS` + `CONSULTAR_PRODUCTOS`
- `GESTIONAR_METODOS_PAGO`
- `GESTIONAR_VENTAS`
- `GESTIONAR_COMPRAS`
- `GESTIONAR_INVENTARIO`
- `GESTIONAR_ROLES` (Roles ya filtra su submenú por permiso)
- `GESTIONAR_CONTRATOS` (contratos dentro de Empleados)
- `REGISTRAR_ASISTENCIA`, `CONSULTAR_REPORTES`, `SOLICITAR_PERMISO`

### Permisos eliminados (no volver a crearlos)

`GESTIONAR_USUARIOS`, `GESTIONAR_EMPLEADOS`, `GESTIONAR_CLIENTES`,
`CONSULTAR_CLIENTES`, `EMPLEADO`, `CAJERO` (roles).

---

## 4. El patrón implementado (copiar en cada módulo)

Archivo de referencia: `clientes.cpp` (el más chico y limpio).

```cpp
namespace {

enum class AccionCliente { Agregar, Actualizar, Estado, Buscar, Listar, Volver };

struct OpcionCliente {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionCliente accion;
};

static const vector<OpcionCliente>& opcionesClientes() {
    static const vector<OpcionCliente> opciones = {
        {"Agregar Cliente",          "CLIENTES_CREAR",  AccionCliente::Agregar},
        {"Actualizar Cliente",       "CLIENTES_EDITAR", AccionCliente::Actualizar},
        {"Cambiar Estado",           "CLIENTES_ESTADO", AccionCliente::Estado},
        {"Buscar Cliente",           "CLIENTES_VER",    AccionCliente::Buscar},
        {"Listar Clientes",          "CLIENTES_VER",    AccionCliente::Listar},
        {"Volver al Menu Principal", "",                AccionCliente::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionCliente& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionCliente*> opcionesVisibles() {
    vector<const OpcionCliente*> visibles;
    for (const OpcionCliente& opcion : opcionesClientes()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

}  // namespace
```

Reglas que no se pueden romper:

1. **Numerar sobre lo visible**, no sobre el total. Si un rol no tiene una acción, no
   queda hueco.
2. **Despachar por `elegido.accion`**, nunca por número absoluto. Con lista filtrada,
   "Volver" deja de ser la opción 7.
3. **No duplicar `if (tienePermiso(...))` dentro de cada `case`**: el filtro ya lo hizo la
   lista visible.
4. **Siempre incluir `"roles.h"`** en el `.cpp` para `tienePermiso()`.
5. **No usar un vector de permisos vacío para "todos"** en el menú principal: en
   `roles.cpp`, `{}` significa *siempre visible*.

---

## 5. Mapas de los módulos terminados

### Usuarios (`usuarios.cpp`)

| Opción | Permiso |
|---|---|
| Agregar Usuario | `USUARIOS_CREAR` |
| Actualizar Usuario | `USUARIOS_EDITAR` |
| Cambiar Estado | `USUARIOS_ESTADO` |
| Buscar Usuario | `USUARIOS_VER` |
| Cambiar Clave | `USUARIOS_CLAVE` |
| Listar Usuarios | `USUARIOS_VER` |
| Volver | siempre |

### Empleados (`empleados.cpp`)

| Opción | Permiso |
|---|---|
| Agregar Empleado | `EMPLEADOS_CREAR` |
| Actualizar Datos | `EMPLEADOS_EDITAR` |
| Despedir / Reactivar | `EMPLEADOS_BAJA` |
| Buscar / Listar | `EMPLEADOS_VER` |
| Marcar asistencia | `REGISTRAR_ASISTENCIA` |
| Ver asistencia / Asistencia del día / Historial | `CONSULTAR_REPORTES` |
| Justificar asistencia | `JUSTIFICAR_ASISTENCIA` |
| Generar / Subir / Ver / Finalizar contrato | `GESTIONAR_CONTRATOS` |
| Gestionar permisos | `GESTIONAR_PERMISOS_EMPLEADO` |
| Gestionar vacaciones | `GESTIONAR_VACACIONES_EMPLEADO` |
| Volver | siempre |

**Decisión tomada:** `REGISTRAR_ASISTENCIA` **no da acceso al módulo**. VENDEDOR lo tiene,
y si se usara como llave de entrada podría ver la asistencia de todos. Solo muestra
"Marcar asistencia" a quien ya está adentro.

### Clientes (`clientes.cpp`)

| Opción | Permiso |
|---|---|
| Agregar Cliente | `CLIENTES_CREAR` |
| Actualizar Cliente | `CLIENTES_EDITAR` |
| Cambiar Estado | `CLIENTES_ESTADO` |
| Buscar / Listar | `CLIENTES_VER` |
| Volver | siempre |

**Caso real:** CONTABILIDAD pasó de `CONSULTAR_CLIENTES` a `CLIENTES_VER` y al entrar ve
solo Buscar, Listar y Volver.

---

## 6. Archivos tocados

### Código

- `roles.cpp` — `itemsMenuPrincipal()`: el vector de permisos de cada ítem del menú
  principal.
- `usuarios.cpp` / `usuarios.h` — patrón completo.
- `empleados.cpp` / `empleados.h` — patrón completo.
- `clientes.cpp` / `clientes.h` — patrón completo, **sin commit**.

### Base de datos

- `modulos/36- PERMISOS_ROLES.sql` — catálogo, matriz, `DELETE` idempotentes de los
  permisos viejos.
- `modulos/36- PERMISOS_ROLES.md` — documentación de la matriz.
- `modulos/3- ROLES.sql` / `.md` — set final de 7 roles.
- `modulos/12- VACACIONES_EMPLEADOS.md` y `modulos/13- PERMISOS_EMPLEADOS.md` — gates
  actualizados a los permisos finos.

### Tests

- `db/test-menus-por-rol.sh` — menú principal de los 7 roles + submenú Usuarios +
  submenú Empleados + submenú Clientes (incluye CONTABILIDAD).
- `db/check-app-sps.sh` — 93 SPs de la app.

### Migraciones (en `backups/`, **gitignored**)

- `97-antes-roles-22-10-2026.sql` — backup previo a la tanda de roles.
- `97-roles-set-final.sql` — set final de 7 roles.
- `98-antes-permisos-usuarios-22-10-2026.sql` — backup previo.
- `98-permisos-finos-usuarios.sql`.
- `99-antes-permisos-empleados-22-10-2026.sql` — backup previo.
- `99-permisos-finos-empleados.sql`.
- `100-antes-permisos-clientes-22-10-2026.sql` — backup previo.
- `100-permisos-finos-clientes.sql`.

> **Importante para seguir en casa:** `backups/` está en `.gitignore`, así que esas
> migraciones **no viajan con el repo**. Si se trabaja sobre una base existente hay que
> copiar la carpeta aparte. Si se importa desde cero, `modulos/36- PERMISOS_ROLES.sql` ya
> contiene el estado final y no hacen falta.

---

## 7. Cómo verificar

```bash
# Compilar
docker compose exec app bash build.sh

# Recrear TEST (solo si está sucia) e importar
docker compose exec app bash -lc "cd /workspace && DB_NAME=BALBU_TECH_TEST bash db/import.sh"

# Menús por rol
docker compose exec app bash -lc "cd /workspace && BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh"

# SPs de la app
docker compose exec app bash -lc "cd /workspace && DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh"

# Regresión de contratos
docker compose exec app bash -lc "cd /workspace && BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-contrato-borrador.sh"
```

Resultado esperado al cierre de hoy: build limpio, import 45/45, test de menús 11/11,
contrato 15/15, SPs 93/0.

Si no se recuerda la clave del admin de TEST, volver a correr `db/seed-admin.sh`.

---

## 8. Trampas operativas encontradas

1. **El cliente `mariadb` dentro de `docker compose exec` pierde las comillas dobles** del
   SQL escrito desde PowerShell. Usar un archivo `.sql` temporal o un here-doc en bash.
2. **`db/import.sh` no dropea la base.** Para un test desde cero hay que hacer
   `DROP DATABASE` / `CREATE DATABASE` antes. El `DROP` borra el grant de `balbu_app`:
   hay que volver a otorgarlo.
3. **`ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE`** es ambiguo si el `SELECT` también
   lee `ROL_PERMISO`. En las migraciones se usó el literal o un alias.
4. **`FN_TIENE_PERMISO` no valida el estado de la cuenta.** Un usuario `INACTIVO` con fila
   en `USUARIOS` sigue devolviendo `TRUE` si su rol tiene el permiso. Es un hueco aparte,
   no se tocó.
5. **El trap del test borraba `ROLES` antes que `USUARIOS`** y no limpiaba nada por las
   FKs. El orden correcto es: usuarios → pares del rol → rol → empleados.
6. **Bug corregido en `usuarios.cpp`:** `buscarUsuario()` leía la columna `USUARIO`, pero
   `SP_BUSCAR_USUARIOS` la expone como `NOMBRE_USUARIO`. Reventaba al buscar.

---

## 9. Cómo retomar

1. Revisar `git status`. Debería haber cambios de **Clientes** sin commitear.
2. Commitear Clientes:
   `feat(permisos): agregar permisos finos al modulo Clientes`
3. Seguir con **Proveedores**:
   - Leer `proveedores.cpp`.
   - Proponer permisos finos (`PROVEEDORES_VER`, `PROVEEDORES_CREAR`,
     `PROVEEDORES_EDITAR`, `PROVEEDORES_ESTADO`).
   - Aplicar el patrón de la sección 4.
   - Actualizar `roles.cpp`, `36- PERMISOS_ROLES.sql/.md` y el test.
   - Verificar en TEST y recién después aplicar a la base viva con backup previo.
4. Repetir con Categorías, Marcas, Productos, Métodos de pago, Ventas, Compras,
   Inventario y Caja.

### Orden sugerido

Primero los simples (6 opciones, mismo esqueleto que Clientes):

1. Proveedores
2. Categorías
3. Marcas

Después los medianos:

4. Productos (dos permisos de consulta)
5. Métodos de pago
6. Compras
7. Inventario

Al final los grandes, que necesitan más análisis:

8. Ventas
9. Caja (comparte `GESTIONAR_VENTAS` con Ventas)

---

## 10. Pendientes fuera de esta tanda

- Módulo 16 (Liquidaciones): implementado en BD, sin UI. **No tocar todavía.**
- Módulos 14, 15, 30, 34: sin lector o sin llamadas desde la app. **No tocar todavía.**
- `REGISTRAR_ASISTENCIA` no tiene flujo de autoservicio: "Marcar asistencia" pide cualquier
  ID de empleado. Si se quiere que VENDEDOR marque solo la propia, hay que agregar el
  vínculo usuario ↔ empleado.
- `FN_TIENE_PERMISO` no valida cuentas inactivas.
