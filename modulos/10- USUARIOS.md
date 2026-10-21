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

Bloque con `PREPARE`/`EXECUTE` que crea `abalbuena` (empleado 1, rol 1) **solo
si** el empleado 1 existe y todavía no tiene cuenta. Si no, devuelve
`SEMILLA DE USUARIO OMITIDA (...)`.

> **Importante:** la contraseña sembrada es el placeholder
> `CAMBIAR_ANTES_DE_USAR`, **no un hash**. No sirve para loguearse: la app
> compara hashes. La clave real se setea con `db/seed-admin.sh <usuario>
> <clave>` (o con `SP_CAMBIAR_CLAVE_USUARIO`). La clave vieja se sacó del
> archivo porque estaba publicada en un repo público.

## Procedimientos almacenados

### `SP_GET_USUARIO_LOGIN(P_USUARIO)`

**Usada por la app** (`autenticacion.cpp`). Devuelve
`ID_USUARIO, CONTRASENA (hash), NOMBRE_ROL` **solo si la cuenta está
`ACTIVO`**. La app compara el hash; la base no ve la clave en claro.

### `SP_INSERTAR_USUARIO(P_ID_EMPLEADO, P_ID_ROL, P_USUARIO, P_HASH_CLAVE)`

**Usada por la app** (`usuarios.cpp`).

1. Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.`
2. Empleado con cuenta → `ERROR: ESTE EMPLEADO YA TIENE UN USUARIO ASIGNADO.`
3. Limpia el usuario: `LOWER(REPLACE(TRIM(...), ' ', '.'))` (espacios → puntos).
4. Usuario ya usado → `ERROR: USUARIO YA EN USO.`
5. Inserta y devuelve `EXITO: USUARIO "<usuario>" CREADO.`

> **Notas:** no valida que `P_ID_ROL` exista (lo corta la FK con error
> técnico `1452`) ni que el usuario quede vacío (un `''` entra como usuario
> vacío). El hash llega ya calculado desde la app.

### `SP_ACTUALIZAR_USUARIO(P_ID_USUARIO, P_USUARIO, P_ID_ROL, P_ID_EMPLEADO)`

**Usada por la app.** No toca la contraseña. `NULL` conserva.

- ID inexistente → `ERROR: USUARIO NO EXISTE.`
- Limpia el usuario con `LOWER(TRIM(...))` — **no** convierte espacios en
  puntos (distinto del alta).
- Devuelve `EXITO: DATOS ACTUALIZADOS.`

> Sin chequeo de duplicados: un usuario repetido o un empleado que ya tiene
> cuenta terminan en el error técnico del `UNIQUE` (`1062`).

### `SP_TOGGLE_ESTADO_USUARIO(P_ID_USUARIO)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`. ID inexistente →
`ERROR: EL USUARIO NO EXISTE.` Devuelve
`USUARIO: "<usuario>" - CAMBIO DE: <antes> A: <después>`.

### `SP_BUSCAR_USUARIOS_FILTRADO(P_BUSQUEDA)`

**La app no la llama.** Lista cuentas con empleado y rol; busca por nombre de
usuario o nombre de empleado; ordena por usuario.

### `SP_CAMBIAR_CONTRASENA(P_ID_USUARIO, P_CLAVE_ACTUAL_HASH, P_CLAVE_NUEVA_HASH)`

**La app no la llama.** Cambia la clave **solo si el hash actual coincide**.
Si no → `ERROR: USUARIO NO ENCONTRADO O CLAVE ACTUAL INCORRECTA.` Devuelve
`EXITO: CONTRASEÑA ACTUALIZADA PARA EL USUARIO: "<usuario>" (ID: <id>)`.

### `SP_LOGIN_USUARIO(P_USUARIO, P_PASSWORD_HASH)`

**La app no la llama.** Login por hash en un solo SP: devuelve una fila
`ESTADO = 'EXITO'` con `ROL` e `ID_USUARIO`, o `ESTADO = 'ERROR'` con `NULL`s.
La app usa `SP_GET_USUARIO_LOGIN` y compara del lado C++.

### `PARA_INSERTAR_USUARIOS()`

**Usada por la app.** **2 result sets**: roles (`ID_ROL, NOMBRE_ROL`) y
empleados (`ID_EMPLEADO, NOMBRE`), ambos por ID.

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

**Usada por la app** (`usuarios.cpp:cambiarClaveUsuario`). Setea el hash
**sin pedir la clave actual** (a diferencia de `SP_CAMBIAR_CONTRASENA`). Si el
ID no existe devuelve `ERROR: EL USUARIO NO EXISTE.`; si existe,
`EXITO: CLAVE DEL USUARIO ID <id> ACTUALIZADA.`

> Es la vía que usa un administrador para resetear claves. El cambio
> "voluntario" con verificación de la clave vieja es `SP_CAMBIAR_CONTRASENA`.

## Triggers

### `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION`

`AFTER UPDATE ON EMPLEADOS`. Cuando el empleado pasa de `ACTIVO` a
`INACTIVO`:

1. pone `INACTIVO` su cuenta en `USUARIOS`;
2. registra en `LOG_USUARIOS` (`ACCION = 'BLOQUEO_AUTO_POR_LIQUIDACION'`,
   `ACTIVO` → `INACTIVO`).

> Se dispara también al despedir desde `SP_DESPEDIR_EMPLEADO` (módulo 8):
> despedir al empleado le bloquea el acceso automáticamente.

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
