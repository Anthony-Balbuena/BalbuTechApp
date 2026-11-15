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

`SP_LOGIN_AUTENTICAR` **no se define acá**: su dueño es el módulo `66`, que
parte de esta misma verificación y agrega el token de `SESIONES` (la columna
`TOKEN` que la app necesita para operar). Hasta el 15/11/2026 el `65` tenía su
propia copia, sin token; con las dos definiciones el login dependía del orden
de importación y se retiró la copia vieja. El `66` es quien hace el `DROP ...
IF EXISTS` y la vuelve a crear.

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

---

## CAMBIO_CLAVE_SERVIDOR (ex módulo 67)

Reescritura de `SP_CAMBIAR_CLAVE_USUARIO` absorbida dentro del `65` el
14/11/2026 (ver el `## Log` de `odd/tasks/consolidacion-modulos.md`). El texto
viaja verbatim; solo se degradaron los encabezados un nivel.

### Que rompia

El modulo 65 movio la verificacion de la clave al servidor: desde entonces el
verificador es

```text
USUARIOS.CLAVE_SERVIDOR = SHA2(pepper || derivado)
```

y `CONTRASENA` queda en `NULL` para todo usuario que ya entro al menos una vez.

`SP_CAMBIAR_CLAVE_USUARIO` se quedo en la version vieja: recibia un hash
SHA256 del cliente y lo escribia en `CONTRASENA`. Con un usuario ya migrado
eso tenia dos consecuencias, las dos verificadas con el test:

| Sintoma | Por que |
|---|---|
| La clave nueva no entra | el login compara `CLAVE_SERVIDOR` primero |
| La clave vieja sigue entrando | `CLAVE_SERVIDOR` nunca cambio |
| `CONTRASENA` vuelve a tener material de clave | justo lo que el 65 habia sacado |
| Las sesiones abiertas siguen validas | el token no depende de la clave |

### Que hace el modulo

Reescribe `SP_CAMBIAR_CLAVE_USUARIO` para que reciba el derivado en el formato
serializado que ya produce la app:

```text
pbkdf2$<iteraciones>$<sal_base64>$<derivado_base64>
```

y lo guarde como lo espera el login:

1. Parsea `iter`, `sal` y `derivado`.
2. Lee el pepper de `SECRETO_SISTEMA` (`PEPPER_LOGIN`).
3. Escribe `SALT_LOGIN`, `ITER_LOGIN` y
   `CLAVE_SERVIDOR = SHA2(CONCAT(pepper, derivado), 256)`.
4. Deja `CONTRASENA = NULL`.
5. Borra las filas de `SESIONES` de ese usuario.
6. Devuelve `EXITO: CLAVE DEL USUARIO ID <n> ACTUALIZADA.`

Si el usuario no existe devuelve `ERROR: EL USUARIO NO EXISTE.`; si el hash no
matchea `^pbkdf2\$<iter>\$<sal>\$<derivado>$` devuelve
`ERROR: FORMATO DE CLAVE INVALIDO.` Nunca acepta texto plano ni el SHA256 viejo:
los dos dejarian la clave en un formato que el login ya no usa. El patron exige
iteraciones numericas y mayores a cero; antes las validaba con un `LIKE`, y un
`pbkdf2$abc$...` moria en un `1292` crudo en vez de rechazarse.

### Quien puede

Solo `USUARIOS_CLAVE`, que hoy tiene unicamente el rol `ADMIN`. La guarda va
**incluida en el cuerpo** del procedimiento (`CALL SP_EXIGIR_PERMISO(...)`)
para que el modulo sea autosuficiente: si alguien lo aplica suelto sobre una
base sin el inyector, igual queda protegido.

Es un **reset administrativo**: no pide la clave actual. La app no puede
verificarla sin traer a memoria el material de clave del usuario, y el sentido
del 65 fue justamente que ese material no salga de la base.

### Cambio en la app

`usuarios.cpp` deja de mandar SHA256 en los dos caminos que escriben clave:

| Funcion | Antes | Ahora |
|---|---|---|
| `registrarUsuario()` | `aplicarHash(clavePlana)` | `generar_hash_pbkdf2(...)` |
| `cambiarClaveUsuario()` | `aplicarHash(claveNueva)` | `generar_hash_pbkdf2(...)` |

El alta importaba tanto como el cambio: un usuario creado con SHA256 queda sin
sal y **no migra nunca**, porque la migracion del 65 exige
`CONTRASENA LIKE 'pbkdf2$%'`.

Si la derivacion falla, la app avisa y no escribe nada.

### Como aplicarlo

Ya no es un archivo: vive al final del módulo `65` y se aplica reimportando el
`65` (más `bash build.sh` para la parte de la app).

Requiere `65` (columnas `SALT_LOGIN`, `ITER_LOGIN`, `CLAVE_SERVIDOR` y
`SECRETO_SISTEMA`) y `66` (`SESIONES` y `SP_EXIGIR_PERMISO`). Es idempotente:
se puede reaplicar sin efectos.

El modulo `10` **ya no la define**: `SP_CAMBIAR_CLAVE_USUARIO` tiene un solo
dueno, este modulo. Del mismo modo, `SP_LOGIN_AUTENTICAR` tiene un solo dueno,
el `66` (que la reescribe con el token). Antes cada par estaba duplicado y
ganaba el ultimo importado.

### Que no hace

- No borra `SP_INSERTAR_USUARIO` ni otros `SP` de usuarios.
- No implementa autocambio por parte del usuario: no pide la clave actual.
- (05/11/2026) `SP_CAMBIAR_CONTRASENA`, el gemelo muerto del modulo `10`, se
  elimino por decision del dueno: no tenia caller ni mapeo.

### Verificacion

`db/test-cambio-clave.sh`, contra `BALBU_TECH_TEST` con el binario nuevo:

| Caso | Resultado esperado |
|---|---|
| Login inicial con clave `pbkdf2` | migra a `CLAVE_SERVIDOR` |
| Admin cambia la clave | `CONTRASENA` `NULL`, `CLAVE_SERVIDOR` nueva |
| Sal del cambio | distinta de la anterior |
| Sesiones del usuario | 0 despues del cambio |
| Token emitido antes | ya no existe |
| Clave nueva / clave vieja | entra / no entra |
| Token de `VENDEDOR` | rechazo `SIN PERMISO` |
| Token de `ADMIN` | `EXITO` |
| `abc123`, `pbkdf2$abc$...`, `pbkdf2$0$...` | `FORMATO DE CLAVE INVALIDO`, sin tocar la clave |

