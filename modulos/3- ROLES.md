# Módulo 3 — ROLES

Los roles del sistema (`ADMIN`, `RRHH`, `VENDEDOR`, `GERENTE`, `SUBGERENTE`,
`ALMACEN`, `CONTABILIDAD`). El nombre es único y de acá cuelgan los permisos
(`36`) y los usuarios (`10`).

**Es usado por:** `roles.cpp` (alta, edición y búsqueda), `login.cpp` y
`usuarios.cpp` (combo de roles).

Fuente: `modulos/3- ROLES.sql` · Base: `BALBU_TECH` · Revisado: 22/10/2026.

## Tablas

### ROLES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_ROL` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `NOMBRE_ROL` | `VARCHAR(50)` | NOT NULL, **UNIQUE** | Nombre del rol. |

**Índice:** `IX_ROLES_NOMBRE` sobre `NOMBRE_ROL`, **además** del índice que ya
crea el `UNIQUE`.

> `IX_ROLES_NOMBRE` es **redundante**: el `UNIQUE` de la columna ya genera un
> índice con la misma columna. Solo agrega costura de escritura.

**Semillas (idempotentes):** `ADMIN`, `RRHH`, `VENDEDOR`, `GERENTE`,
`SUBGERENTE`, `ALMACEN`, `CONTABILIDAD`, con `INSERT IGNORE`. En una base ya
migrada no cambia los `ID_ROL` existentes; el renombre de `EMPLEADO` a
`VENDEDOR` y la baja de `CAJERO` van en la migración viva (`backups/`).

> Sin esas filas fallan los seeds de `ROL_PERMISO` (FK) y el login. Los permisos
> por rol salen de la base (`36`); el nombre del rol ya **no** se compara en el
> código.

> El archivo tiene un **`SELECT * FROM ROLES;` suelto** en medio del script: al
> importar imprime la tabla en la salida. Inofensivo, pero ensucia el log.
>
> También arranca con `-- Active: ...@@127.0.0.1@3306@BALBU_TECH`, rastro de un
> cliente SQL.

## Procedimientos almacenados

### `SP_INSERTAR_ROL(P_NOMBRE_ROL)`

**Usada por la app** (`roles.cpp`). Normaliza con `TRIM` + colapso de espacios
(`REGEXP_REPLACE`).

- nombre vacío → `ERROR: EL NOMBRE DEL ROL ES OBLIGATORIO.`
- nombre repetido → `ERROR: ESTE ROL YA EXISTE.`
- Inserta y devuelve `EXITO: ROL "<nombre>" INSERTADO. ID: <id>`.

> **Carrera cubierta:** dos altas simultáneas pasan el `EXISTS` y choca el
> `UNIQUE`; ahí el error es técnico (`1062`), no el mensaje amigable. No hay
> `EXIT HANDLER` que lo traduzca.

### `SP_ACTUALIZAR_ROL(P_ID_ROL, P_NOMBRE_ROL)`

**Usada por la app** (`roles.cpp`).

- rol inexistente → `ERROR: EL ROL NO EXISTE.`
- nombre vacío → `ERROR: EL NOMBRE DEL ROL NO PUEDE ESTAR VACÍO.`
- nombre repetido en otro rol → `ERROR: ESTE ROL YA EXISTE.`
- Devuelve `EXITO: ROL ID <id> ACTUALIZADO.`

> **`NOMBRE_ROL = NULL` no cambia nada y responde éxito**: el `COALESCE` deja el
> valor viejo. No es un error, pero el mensaje sugiere que algo se actualizó.

### `SP_BUSCAR_ROLES(P_BUSQUEDA)`

**Usada por la app.** Búsqueda parcial con `LIKE '%texto%'`. Vacío o `NULL`
devuelve **todos** los roles.

> `LIKE` interpreta `%` y `_` del texto buscado como comodines: buscar `_`
> devuelve todo.

### `SP_LISTAR_ROLES()`

Todos los roles (`ID_ROL`, `NOMBRE_ROL`) ordenados alfabéticamente. **La app no
lo llama**: usa `SP_BUSCAR_ROLES` con texto vacío.

## Reglas de negocio

- **El nombre del rol es único** y se guarda normalizado (sin espacios de más).
- **Los roles base existen siempre** (seed idempotente).
- **Un rol no se borra** desde este módulo: solo se crea y se renombra.
- **Los permisos no viven acá**, viven en `PERMISOS_ROLES` (36).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
