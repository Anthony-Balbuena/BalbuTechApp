# 65 - Login verificado en el servidor

## Que hace

Mueve la verificacion de la clave desde el binario a la base. Antes el cliente
leia `USUARIOS.CONTRASENA` y comparaba PBKDF2 en C++; eso obligaba a darle a
`balbu_app` `SELECT` sobre el hash: con la clave del `.env`, cualquiera bajaba
los hashes y los atacaba offline.

Ahora el flujo es:

1. `SP_LOGIN_PARAMETROS(usuario)` devuelve `SAL`, `ITER` y `FORMATO`. Nada de
   eso es secreto: sin el pepper, la sal no sirve para atacar el hash.
2. El cliente deriva PBKDF2-SHA256 con esa sal y esas iteraciones.
3. `SP_LOGIN_AUTENTICAR(usuario, derivado)` compara del lado del servidor,
   aplica el bloqueo por intentos y escribe `LOG_ACCESOS`.

## Objetos

### Tabla `SECRETO_SISTEMA`

| Columna | Tipo | Para que |
|---|---|---|
| `CLAVE` | `VARCHAR(50)` PK | nombre del secreto (`PEPPER_LOGIN`, `EXIGIR_PERMISO_SP`) |
| `VALOR` | `VARCHAR(255)` NOT NULL | el valor |

El pepper se genera **una sola vez** con
`LOWER(SHA2(CONCAT(UUID(), UUID(), NOW(6), RAND()), 256))`; si la fila ya
existe, `ON DUPLICATE KEY UPDATE CLAVE = CLAVE` la deja intacta. Regenerarlo
invalida todas las claves guardadas.

### Columnas nuevas en `USUARIOS`

| Columna | Tipo | Para que |
|---|---|---|
| `SALT_LOGIN` | `VARCHAR(64)` NULL | sal usada para derivar |
| `ITER_LOGIN` | `INT` NULL | iteraciones usadas |
| `CLAVE_SERVIDOR` | `VARCHAR(128)` NULL | `SHA2(pepper ‖ derivado)`, en hex |

`CONTRASENA` pasa a `VARCHAR(512) NULL`: en el formato nuevo queda vacia y el
verificador es `CLAVE_SERVIDOR`.

### Procedimientos

| Procedimiento | Firma | Devuelve |
|---|---|---|
| `SP_LOGIN_PARAMETROS` | `(P_USUARIO)` | `SAL`, `ITER`, `FORMATO` |
| `SP_LOGIN_AUTENTICAR` | `(P_USUARIO, P_CREDENCIAL)` | `RESULTADO`, `MINUTOS`, datos de sesion |

`FORMATO` puede ser `SERVIDOR`, `PBKDF2`, `SHA256` o `NOEXISTE`. Si el usuario
no existe se devuelve una sal fija (`AAAAAAAAAAAAAAAAAAAAAA==`) para que el
cliente derive igual y la respuesta no delate por tiempo si la cuenta existe.

`RESULTADO` es uno de `OK`, `CLAVE`, `BLOQUEADO`, `INACTIVO`.

## Migracion automatica

Un usuario con el formato viejo (`pbkdf2$iter$sal$hash` en `CONTRASENA`) entra
normal: el cliente deriva con la sal del propio hash y el servidor compara
contra el ultimo campo. En ese primer login exitoso el SP:

1. copia `SALT_LOGIN` e `ITER_LOGIN` desde el hash viejo,
2. escribe `CLAVE_SERVIDOR = SHA2(pepper ‖ derivado)`,
3. deja `CONTRASENA = NULL`.

No hace falta rotar claves a mano ni pedirle a nadie que cambie la contrasena.
La migracion ocurre **solo si el login fue exitoso**: una clave incorrecta no
deja al usuario a medio migrar.

## Por que

- El hallazgo A6 decia que los permisos no se podian sostener contra la base:
  la app leia el hash, `SECRETO_SISTEMA` no existia y el bloqueo era del
  cliente (se salteaba llamando al SP desde un cliente SQL).
- Con el pepper fuera del alcance de la app, un volcado de `USUARIOS` no sirve
  para atacar offline.
- El bloqueo pasa a ser del servidor: el conteo y el registro viven en
  `LOG_ACCESOS` y no dependen del binario.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/65- LOGIN_SERVIDOR.sql"
```

Idempotente: `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS` y
`DROP ... IF EXISTS` antes de cada rutina.

Orden: `64` y despues `65`, y despues `66` (que reemplaza
`SP_LOGIN_AUTENTICAR` para agregar el token). **Compilar y desplegar el
binario nuevo antes de aplicar `66` con `EXIGIR = 1`**: el binario viejo no
manda token y todo responderia `SESION INVALIDA`.

## Que preserva

- Las claves existentes: no se piden cambios de contrasena.
- `LOG_ACCESOS` y su formato: `SP_REGISTRAR_ACCESO` sigue siendo el que escribe.
- El contrato de la app: `login.cpp` ya no lee `CONTRASENA`; pide parametros y
  despues autentica.

## Que no hace

- No crea la sesion con token ni las guardas por rutina: eso es el modulo `66`.
- No revoca privilegios: `db/grant-minimos.sql` se aplica aparte con root.

## Verificacion

Aplicado en `BALBU_TECH_TEST` el 03/11/2026 y en `BALBU_TECH` el 05/11/2026.

- `db/test-login-servidor.sh`: primer login en formato viejo y migracion
  (`CONTRASENA` en NULL, `CLAVE_SERVIDOR` y `SALT_LOGIN` completos), segundo
  login en formato servidor, clave mala rechazada, y `balbu_app` sin acceso a
  `USUARIOS.CONTRASENA` ni a `SECRETO_SISTEMA`.
- `db/test-lockout.sh`: el conteo y el bloqueo funcionan con el SP nuevo.
