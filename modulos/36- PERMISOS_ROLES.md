# Módulo 36 — PERMISOS_ROLES

La matriz de permisos: qué acciones existen (`PERMISOS`) y qué rol puede hacer
cada una (`ROL_PERMISO`). Desde el 20/10/2026 **la base es la única fuente de
verdad**: la app consulta con `FN_TIENE_PERMISO`, no compara nombres de rol en el
código.

**Depende de:** `ROLES` (3) y `USUARIOS` (10).
**Es usado por:** `roles.cpp` (asignar, quitar, listar y validar),
`empleados.cpp` y el resto de los módulos de UI (cada uno pregunta por su
permiso).

Fuente: `modulos/36- PERMISOS_ROLES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### PERMISOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PERMISO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `NOMBRE_PERMISO` | `VARCHAR(80)` | NOT NULL, **UNIQUE** | Clave que consulta la app. |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Texto para la UI. |

**Semillas (18, idempotentes con `ON DUPLICATE KEY UPDATE`):**
`GESTIONAR_ROLES`, `GESTIONAR_USUARIOS`, `GESTIONAR_EMPLEADOS`,
`GESTIONAR_CLIENTES`, `GESTIONAR_PROVEEDORES`, `GESTIONAR_CATEGORIAS`,
`GESTIONAR_MARCAS`, `GESTIONAR_PRODUCTOS`, `GESTIONAR_METODOS_PAGO`,
`GESTIONAR_INVENTARIO`, `GESTIONAR_VENTAS`, `GESTIONAR_COMPRAS`,
`CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`,
`REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` y `GESTIONAR_CONTRATOS` (el último,
nuevo).

> **El catálogo de permisos no se administra desde la app**: no hay SP de alta,
> edición ni baja. Un permiso nuevo **solo** entra por semilla. Lo que la app sí
> administra es **qué rol lo tiene**.
>
> **16 de los 18 se consultan en el código**; `REGISTRAR_ASISTENCIA` y
> `SOLICITAR_PERMISO` están en la matriz pero ningún `cpp` los pide todavía.

### ROL_PERMISO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ROL_NOMBRE` | `VARCHAR(50)` | NOT NULL, PK (compuesta), FK → `ROLES.NOMBRE_ROL` **ON UPDATE CASCADE** | Rol. |
| `ID_PERMISO` | `INT` | NOT NULL, PK (compuesta), FK → `PERMISOS` **ON DELETE CASCADE** | Permiso. |

> **La clave es el nombre del rol, no su ID.** Por eso `ROL_NOMBRE` tuvo que
> pasar de `VARCHAR(30)` a `VARCHAR(50)` para poder atar el FK (09/10/2026).
>
> **`ON UPDATE CASCADE`** es lo que hace que renombrar un rol con
> `SP_ACTUALIZAR_ROL` (3) arrastre sus permisos.
>
> **`ON DELETE CASCADE`** del permiso: borrar un permiso limpia la matriz sin
> avisar.

**Matriz que queda al importar:**

| Rol | Permisos |
|---|---|
| `ADMIN` | **los 18** |
| `GERENTE` | todos **menos** `GESTIONAR_ROLES` y `GESTIONAR_USUARIOS` |
| `CAJERO` | `GESTIONAR_VENTAS`, `GESTIONAR_CLIENTES`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`, `CONSULTAR_REPORTES` |
| `ALMACEN` | `GESTIONAR_PRODUCTOS`, `GESTIONAR_CATEGORIAS`, `GESTIONAR_MARCAS`, `GESTIONAR_INVENTARIO`, `GESTIONAR_COMPRAS`, `GESTIONAR_PROVEEDORES`, `CONSULTAR_PRODUCTOS` |
| `RRHH` | `GESTIONAR_EMPLEADOS`, `GESTIONAR_CONTRATOS`, `CONSULTAR_REPORTES` |
| `EMPLEADO` | `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`, `GESTIONAR_VENTAS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` |

**Migraciones incluidas** (idempotentes, `C-3` del 20/10/2026):
1. `DROP CONSTRAINT IF EXISTS CHK_ROL_NOMBRE` — saca el `CHECK` que limitaba los
   roles a `ADMIN`/`RRHH`/`EMPLEADO`.
2. Recrea el FK del rol con `ON UPDATE CASCADE`.
3. **Borra cuatro pares de `RRHH`** (`GESTIONAR_ROLES`, `GESTIONAR_USUARIOS`,
   `GESTIONAR_CLIENTES`, `GESTIONAR_VENTAS`) que el set final ya no le da.

> **Ese `DELETE` corre en cada import.** Los permisos que el dueño haya cargado
> a mano para `RRHH` **se respetan** (solo borra esos cuatro pares), pero si
> alguien vuelve a asignarle `GESTIONAR_CLIENTES` a `RRHH` desde la app, el
> próximo import se lo saca.

## Procedimientos almacenados

### `SP_ASIGNAR_PERMISO_A_ROL(P_ROL_NOMBRE, P_NOMBRE_PERMISO)`

**Usada por la app** (`roles.cpp`).

- rol inexistente → `ERROR: EL ROL NO EXISTE EN EL SISTEMA.`
- permiso inexistente → `ERROR: EL PERMISO NO EXISTE.`
- Inserta con `ON DUPLICATE KEY UPDATE` (idempotente) y devuelve
  `EXITO: PERMISO <permiso> ASIGNADO A <rol>`.

> No existe camino para **crear** un permiso desde la app: solo se asignan los
> 18 sembrados.

### `SP_QUITAR_PERMISO_A_ROL(P_ROL_NOMBRE, P_NOMBRE_PERMISO)`

**Usada por la app.** Valida rol y permiso y borra el par.

- si el rol no lo tenía → `AVISO: <rol> NO TENIA EL PERMISO <permiso>.`
- si lo tenía → `EXITO: PERMISO <permiso> QUITADO A <rol>.`

> **Aviso, no error**: quitar dos veces es inofensivo.

### `SP_LISTAR_PERMISOS_POR_ROL(P_ROL_NOMBRE)`

**Usada por la app.** Los permisos del rol (`ID_PERMISO`, `NOMBRE_PERMISO`,
`DESCRIPCION`) ordenados por nombre.

> Si el rol no existe devuelve **cero filas**, no un error.

## Funciones

### `FN_TIENE_PERMISO(P_USERNAME, P_ACCION) → BOOLEAN`

**Usada por la app** (`roles.cpp`). `TRUE` si el rol del usuario tiene ese
permiso; `FALSE` si el usuario no existe o no lo tiene.

> **Es la puerta de autorización real del sistema**, y depende de que el nombre
> del permiso coincida **exacto** con el string del `cpp`.
>
> **Declarada `DETERMINISTIC` leyendo cuatro tablas** (misma incorrección que
> `FN_CONTAR_ITEMS_COMPRA` en 19). MySQL lo acepta, pero el declarante es falso y
> puede inducir al optimizador a cachear un resultado que cambia.
>
> **No mira si el usuario está activo**: un usuario dado de baja conserva su rol
> mientras exista la fila, y la función sigue devolviendo `TRUE`.

## Reglas de negocio

- **La base manda**: los permisos se leen de `ROL_PERMISO`, no del nombre del rol
  en el código.
- **`ADMIN` tiene todo**; `GERENTE` todo lo operativo salvo roles y usuarios.
- **Renombrar un rol arrastra sus permisos** (`ON UPDATE CASCADE`).
- **Un permiso nuevo solo entra por semilla**; la app solo asigna y quita.
- **Quitar un permiso que no estaba no es error**, es aviso.
- **El import re-aplica la matriz y borra cuatro pares de `RRHH`.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
