# Módulo 10 — USUARIOS

Cuentas de acceso al sistema. Cada cuenta se ata a **un empleado** (relación
1:1: `ID_EMPLEADO` es `UNIQUE`), tiene un rol que define sus permisos y
guarda la contraseña como **hash PBKDF2**. La cuenta arranca `ACTIVO`.

**Depende de:** `EMPLEADOS` (8) y `ROLES` (3).
**Es usado por:** `LOG_USUARIOS` (29), `PERMISOS_RO` (36) y `AUDITORIA_SISTEMA`
(6).

Fuente: `modulos/10- USUARIOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### USUARIOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_USUARIO` | `INT` | PK, AUTO_INCREMENT | Identificador de la cuenta. |
| `ID_EMPLEADO` | `INT` | NOT NULL, **UNIQUE**, FK → `EMPLEADOS` | Empleado dueño. Un empleado = una cuenta. |
| `ID_ROL` | `INT` | NOT NULL, FK → `ROLES` | Rol que otorga permisos. |
| `USUARIO` | `VARCHAR(50)` | NOT NULL, **UNIQUE** | Nombre de login. |
| `CONTRASENA` | `VARCHAR(512)` | NOT NULL | Hash PBKDF2 con formato `pbkdf2$<iter>$<salt_b64>$<hash_b64>`. **Nunca** texto plano. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | DEFAULT `'ACTIVO'` | Sin `NOT NULL`; el default cubre. |
| `FECHA_CREACION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta de la cuenta. |

**Índice:** `IX_USER` sobre `USUARIO` (login) — redundante con el índice del
`UNIQUE`, igual que en CATEGORIAS.

**Migración incluida:** `ALTER TABLE USUARIOS MODIFY CONTRASENA
VARCHAR(512) NOT NULL` (el `255` original truncaba el hash PBKDF2). Es
idempotente.

## Semilla del administrador

**Este módulo ya no crea usuarios.** (08/11/2026) Se quitó el bloque
`PREPARE`/`EXECUTE` que llamaba a `SP_INSERTAR_USUARIO` para sembrar
`abalbuena`: los `.sql` importan las tablas vacías a propósito y los datos de
arranque viven en scripts.

La cuenta se crea con `db/seed-admin.sh <usuario> <clave>`, que arma un
`EMPLEADOS` mínimo, inserta la fila en `USUARIOS` y deriva la clave con PBKDF2
(`SP_LOGIN_AUTENTICAR` la migra al formato del servidor en el primer login).

## Procedimientos almacenados

### `SP_GET_USUARIO_LOGIN(P_USUARIO)`

**Sin uso en la app actual.** La usaba `autenticacion.cpp` (eliminado el 03/11/2026); hoy `login.cpp` hace el `SELECT` directo sobre `USUARIOS`. Devuelve
`ID_USUARIO, CONTRASENA (hash), NOMBRE_ROL` **solo si la cuenta está
`ACTIVO`**. La app compara el hash; la base no ve la clave en claro.

### `SP_INSERTAR_USUARIO(P_ID_EMPLEADO, P_ID_ROL, P_USUARIO, P_HASH_CLAVE)`

**Usada por la app** (`usuarios.cpp`).

1. Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.`
2. Empleado `INACTIVO` (despedido) → `ERROR: EL EMPLEADO ESTA INACTIVO
   (DESPEDIDO). NO SE LE PUEDE CREAR UN USUARIO.` (08/11/2026)
3. Empleado con cuenta → `ERROR: ESTE EMPLEADO YA TIENE UN USUARIO ASIGNADO.`
4. Limpia el usuario: `LOWER(REPLACE(TRIM(...), ' ', '.'))` (espacios → puntos).
5. Usuario ya usado → `ERROR: USUARIO YA EN USO.`
6. Inserta y devuelve `EXITO: USUARIO "<usuario>" CREADO.`

> **Notas:** no valida que `P_ID_ROL` exista (lo corta la FK con error
> técnico `1452`) ni que el usuario quede vacío (un `''` entra como usuario
> vacío). El hash llega ya calculado desde la app.

### `SP_ACTUALIZAR_USUARIO(P_ID_USUARIO, P_USUARIO, P_ID_ROL, P_ID_EMPLEADO)`

**Usada por la app.** No toca la contraseña. `NULL` conserva.

- ID inexistente → `ERROR: USUARIO NO EXISTE.`
- Si llega `P_ID_EMPLEADO`: tiene que existir y estar `ACTIVO`
  (`ERROR: EL EMPLEADO NO EXISTE O ESTA INACTIVO (DESPEDIDO).`) y no puede
  tener otra cuenta (`ERROR: ESTE EMPLEADO YA TIENE UN USUARIO ASIGNADO.`).
- Nombre de usuario repetido → `ERROR: USUARIO YA EN USO.`
- Limpia el usuario con `LOWER(TRIM(...))` — **no** convierte espacios en
  puntos (distinto del alta).
- Devuelve `EXITO: DATOS ACTUALIZADOS.`

> Los tres chequeos se agregaron el 08/11/2026: antes el `UNIQUE` soltaba un
> error técnico `1062` sin explicación.

### `SP_TOGGLE_ESTADO_USUARIO(P_ID_USUARIO)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`. ID inexistente →
`ERROR: EL USUARIO NO EXISTE.` Devuelve
`USUARIO: "<usuario>" - CAMBIO DE: <antes> A: <después>`.

> (08/11/2026) No deja activar la cuenta de un empleado despedido:
> `ERROR: EL EMPLEADO ESTA INACTIVO (DESPEDIDO). REACTIVE AL EMPLEADO ANTES
> DE ACTIVAR SU USUARIO.` Primero se reactiva el empleado (módulo 8).

### `SP_BUSCAR_USUARIOS_FILTRADO(P_BUSQUEDA)`

**La app no la llama.** Lista cuentas con empleado y rol; busca por nombre de
usuario o nombre de empleado; ordena por usuario.

### `SP_CAMBIAR_CONTRASENA` — eliminada (05/11/2026)

Existió como cambio "voluntario": comparaba el hash viejo contra `CONTRASENA`
antes de escribir el nuevo. Con el módulo `65` ese campo queda en `NULL` para
todo usuario migrado, así que no podía funcionar; tampoco tenía caller ni
permiso mapeado. El módulo `10` ahora solo ejecuta
`DROP PROCEDURE IF EXISTS SP_CAMBIAR_CONTRASENA`. El cambio de clave real es
`SP_CAMBIAR_CLAVE_USUARIO` (módulo `67`).

### `SP_LOGIN_USUARIO(P_USUARIO, P_PASSWORD_HASH)`

**La app no la llama.** Login por hash en un solo SP: devuelve una fila
`ESTADO = 'EXITO'` con `ROL` e `ID_USUARIO`, o `ESTADO = 'ERROR'` con `NULL`s.
La app ya no usa esta ruta: `login.cpp` consulta `USUARIOS` directo y compara del lado C++.

### `PARA_INSERTAR_USUARIOS()`

**Usada por la app.** **2 result sets**: roles (`ID_ROL, NOMBRE_ROL`) y
empleados (`ID_EMPLEADO, NOMBRE`), ambos por ID. (08/11/2026) La lista de
empleados viene filtrada por `ESTADO = 'ACTIVO'`: los despedidos no se ofrecen.

### `PARA_ACTUALIZAR_USUARIOS()`

**Usada por la app.** Lista cuentas con `ID_ROL/NOMBRE_ROL` e
`ID_EMPLEADO/NOMBRE_EMPLEADO` para la pantalla de edición.

### `PARA_ACT_DESAC_USUARIOS()`

**Usada por la app.** Lista `ID_USUARIO, USUARIO, ESTADO, EMPLEADO` para
activar/desactivar cuentas.

### `SP_BUSCAR_USUARIOS(P_FILTRO)`

**Usada por la app** (`usuarios.cpp:buscarUsuario`). Devuelve
`ID_USUARIO, USUARIO AS NOMBRE_USUARIO, ESTADO`; con filtro vacío trae todos.

### `SP_CAMBIAR_CLAVE_USUARIO(P_ID_USUARIO, P_HASH)`

**Usada por la app** (`usuarios.cpp:cambiarClaveUsuario`). Setea la clave
**sin pedir la clave actual**. Si el ID no existe devuelve
`ERROR: EL USUARIO NO EXISTE.`; si existe,
`EXITO: CLAVE DEL USUARIO ID <id> ACTUALIZADA.`

> Es la vía que usa un administrador para resetear claves. El cambio
> "voluntario" con verificación de la clave vieja era `SP_CAMBIAR_CONTRASENA`,
> eliminada el 05/11/2026. Desde el módulo `67` este SP escribe
> `CLAVE_SERVIDOR` con pepper, no `CONTRASENA`.

## Triggers

### `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION`

`AFTER UPDATE ON EMPLEADOS`. Cuando el empleado pasa de `ACTIVO` a
`INACTIVO`:

1. pone `INACTIVO` su cuenta en `USUARIOS`;
2. registra en `LOG_USUARIOS` (`ACCION = 'BLOQUEO_AUTO_POR_LIQUIDACION'`,
   `ACTIVO` → `INACTIVO`).

> Se dispara también al despedir desde `SP_DESPEDIR_EMPLEADO` (módulo 8):
> despedir al empleado le bloquea el acceso automáticamente. Las sesiones
> abiertas las borra `TR_INVALIDAR_SESION_EMPLEADO_INACTIVO` (módulo 66).

## Funciones

`FN_TIENE_PERMISO` **no vive acá**: la versión canónica está en
`36- PERMISOS_ROLES.sql` (el comentario del archivo lo aclara).

## Reglas de negocio

- **Una cuenta por empleado** (`ID_EMPLEADO` UNIQUE).
- **Usuario único** y normalizado a minúsculas (alta: espacios → puntos).
- **Contraseña siempre hasheada** (PBKDF2, 512 caracteres de columna).
- **La cuenta inactiva no puede loguearse** (`ESTADO = 'ACTIVO'` en el login).
- **Despido ⇒ bloqueo automático** de la cuenta por trigger.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
