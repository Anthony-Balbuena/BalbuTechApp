# Módulo 36 — PERMISOS_ROLES

La matriz de permisos: qué acciones existen (`PERMISOS`) y qué rol puede hacer
cada una (`ROL_PERMISO`). Desde el 20/10/2026 **la base es la única fuente de
verdad**: la app consulta con `FN_TIENE_PERMISO`, no compara nombres de rol en el
código.

**Depende de:** `ROLES` (3) y `USUARIOS` (10).
**Es usado por:** `roles.cpp` (asignar, quitar, listar y validar),
`empleados.cpp` y el resto de los módulos de UI (cada uno pregunta por su
permiso).

Fuente: `modulos/36- PERMISOS_ROLES.sql` · Base: `BALBU_TECH` · Revisado: 22/10/2026.

## Tablas

### PERMISOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PERMISO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `NOMBRE_PERMISO` | `VARCHAR(80)` | NOT NULL, **UNIQUE** | Clave que consulta la app. |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Texto para la UI. |

**Semillas (28, idempotentes con `ON DUPLICATE KEY UPDATE`):**
`GESTIONAR_ROLES`, `USUARIOS_VER`, `USUARIOS_CREAR`, `USUARIOS_EDITAR`,
`USUARIOS_ESTADO`, `USUARIOS_CLAVE`, `EMPLEADOS_VER`, `EMPLEADOS_CREAR`,
`EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`, `JUSTIFICAR_ASISTENCIA`,
`GESTIONAR_PERMISOS_EMPLEADO`, `GESTIONAR_VACACIONES_EMPLEADO`,
`GESTIONAR_CLIENTES`, `GESTIONAR_PROVEEDORES`, `GESTIONAR_CATEGORIAS`,
`GESTIONAR_MARCAS`, `GESTIONAR_PRODUCTOS`, `GESTIONAR_METODOS_PAGO`,
`GESTIONAR_INVENTARIO`, `GESTIONAR_VENTAS`, `GESTIONAR_COMPRAS`,
`CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`,
`REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` y `GESTIONAR_CONTRATOS`.

> **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `USUARIOS_CREAR`,
> `USUARIOS_EDITAR`, `USUARIOS_ESTADO` y `USUARIOS_CLAVE`). El viejo
> `GESTIONAR_USUARIOS` **ya no existe**: el import lo borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.

> **El módulo Empleados usa 7 permisos finos** (`EMPLEADOS_VER`,
> `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`,
> `JUSTIFICAR_ASISTENCIA`, `GESTIONAR_PERMISOS_EMPLEADO` y
> `GESTIONAR_VACACIONES_EMPLEADO`). El viejo `GESTIONAR_EMPLEADOS` **ya no
> existe**: mismo borrado en cascada que `GESTIONAR_USUARIOS`.
>
> **`CONSULTAR_REPORTES` y `REGISTRAR_ASISTENCIA` no dan acceso al módulo**:
> solo filtran opciones una vez adentro. `VENDEDOR` tiene los dos y **no** debe
> entrar a ver la asistencia de todos.

> **El catálogo de permisos no se administra desde la app**: no hay SP de alta,
> edición ni baja. Un permiso nuevo **solo** entra por semilla. Lo que la app sí
> administra es **qué rol lo tiene**.
>
> **Los 28 se consultan en el código**: los de Empleados en `empleados.cpp` y
> `roles.cpp`; `REGISTRAR_ASISTENCIA` ya no queda suelto (opción 7 del submenú
> de Empleados). `SOLICITAR_PERMISO` lo usa el menú principal (`Mis permisos` y
> `Mis vacaciones`).

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
| `ADMIN` | **los 28** |
| `GERENTE` | todos **menos** `GESTIONAR_ROLES` y los 5 `USUARIOS_*` (22) |
| `SUBGERENTE` | todos **menos** `GESTIONAR_ROLES`, los 5 `USUARIOS_*`, los 7 `EMPLEADOS_*` finos y `GESTIONAR_CONTRATOS` (14) |
| `RRHH` | los 7 finos de Empleados, `GESTIONAR_CONTRATOS`, `CONSULTAR_REPORTES` y `SOLICITAR_PERMISO` (10) |
| `VENDEDOR` | `GESTIONAR_VENTAS`, `GESTIONAR_CLIENTES`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` (8) |
| `ALMACEN` | `GESTIONAR_PRODUCTOS`, `GESTIONAR_CATEGORIAS`, `GESTIONAR_MARCAS`, `GESTIONAR_INVENTARIO`, `GESTIONAR_COMPRAS`, `GESTIONAR_PROVEEDORES`, `CONSULTAR_PRODUCTOS`, `SOLICITAR_PERMISO` (8) |
| `CONTABILIDAD` | `CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CONSULTAR_CLIENTES` (3) |

### Mapa del submenú de Empleados

El submenú conserva el orden histórico de 18 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Empleado | `EMPLEADOS_CREAR` |
| 2 | Actualizar Datos | `EMPLEADOS_EDITAR` |
| 3 | Despedir Empleado | `EMPLEADOS_BAJA` |
| 4 | Reactivar Empleado | `EMPLEADOS_BAJA` |
| 5 | Buscar Empleado | `EMPLEADOS_VER` |
| 6 | Listar Empleados | `EMPLEADOS_VER` |
| 7 | Marcar asistencia | `REGISTRAR_ASISTENCIA` |
| 8 | Ver asistencia | `CONSULTAR_REPORTES` |
| 9 | Justificar asistencia | `JUSTIFICAR_ASISTENCIA` |
| 10 | Asistencia del dia | `CONSULTAR_REPORTES` |
| 11 | Historial de asistencia | `CONSULTAR_REPORTES` |
| 12 | Generar contrato | `GESTIONAR_CONTRATOS` |
| 13 | Subir contrato (al firmar) | `GESTIONAR_CONTRATOS` |
| 14 | Ver contratos | `GESTIONAR_CONTRATOS` |
| 15 | Finalizar contrato | `GESTIONAR_CONTRATOS` |
| 16 | Gestionar permisos | `GESTIONAR_PERMISOS_EMPLEADO` |
| 17 | Gestionar vacaciones | `GESTIONAR_VACACIONES_EMPLEADO` |
| 18 | Volver al Menu Principal | *(siempre)* |

**Migraciones incluidas** (idempotentes; las 3 primeras son `C-3` del
20/10/2026, la 4.ª y la 5.ª del 22/10/2026):
1. `DROP CONSTRAINT IF EXISTS CHK_ROL_NOMBRE` — saca el `CHECK` que limitaba los
   roles a `ADMIN`/`RRHH`/`EMPLEADO`.
2. Recrea el FK del rol con `ON UPDATE CASCADE`.
3. **Borra los pares de `RRHH`** que el set final ya no le da
   (`GESTIONAR_ROLES`, los 5 `USUARIOS_*`, `GESTIONAR_CLIENTES` y
   `GESTIONAR_VENTAS`).
4. **Borra del catálogo `GESTIONAR_USUARIOS`**, el permiso único que reemplazan
   los 5 permisos finos de Usuarios (`ON DELETE CASCADE` limpia sus pares).
5. **Borra del catálogo `GESTIONAR_EMPLEADOS`**, el permiso único que reemplazan
   los 7 permisos finos de Empleados (mismo `ON DELETE CASCADE`).

> **Esos `DELETE` corren en cada import.** Los permisos que el dueño haya cargado
> a mano para `RRHH` **se respetan** (solo borra esos pares), pero si
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
> 28 sembrados.

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
- **`ADMIN` tiene todo**; `GERENTE` todo lo operativo salvo roles y los 5
  permisos de Usuarios (22); `SUBGERENTE` además no toca empleados ni contratos
  (14); `RRHH` conserva personal, contratos y reportes (10).
- **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `CREAR`,
  `EDITAR`, `ESTADO`, `CLAVE`); el submenú muestra solo las acciones habilitadas.
- **El módulo Empleados usa 7 permisos finos**; el submenú muestra solo las
  acciones habilitadas y renumera sobre lo visible.
- **`CONSULTAR_REPORTES` y `REGISTRAR_ASISTENCIA` no abren Empleados**: son
  opciones adentro, no llave del módulo.
- **Renombrar un rol arrastra sus permisos** (`ON UPDATE CASCADE`).
- **Un permiso nuevo solo entra por semilla**; la app solo asigna y quita.
- **Quitar un permiso que no estaba no es error**, es aviso.
- **El import re-aplica la matriz y borra los pares viejos de `RRHH`.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
