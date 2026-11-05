# 67 - Cambio de clave en el formato del servidor

## Que rompia

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

## Que hace el modulo

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

## Quien puede

Solo `USUARIOS_CLAVE`, que hoy tiene unicamente el rol `ADMIN`. La guarda va
**incluida en el cuerpo** del procedimiento (`CALL SP_EXIGIR_PERMISO(...)`)
para que el modulo sea autosuficiente: si alguien lo aplica suelto sobre una
base sin el inyector, igual queda protegido.

Es un **reset administrativo**: no pide la clave actual. La app no puede
verificarla sin traer a memoria el material de clave del usuario, y el sentido
del 65 fue justamente que ese material no salga de la base.

## Cambio en la app

`usuarios.cpp` deja de mandar SHA256 en los dos caminos que escriben clave:

| Funcion | Antes | Ahora |
|---|---|---|
| `registrarUsuario()` | `aplicarHash(clavePlana)` | `generar_hash_pbkdf2(...)` |
| `cambiarClaveUsuario()` | `aplicarHash(claveNueva)` | `generar_hash_pbkdf2(...)` |

El alta importaba tanto como el cambio: un usuario creado con SHA256 queda sin
sal y **no migra nunca**, porque la migracion del 65 exige
`CONTRASENA LIKE 'pbkdf2$%'`.

Si la derivacion falla, la app avisa y no escribe nada.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/67- CAMBIO_CLAVE_SERVIDOR.sql"
bash build.sh
```

Requiere `65` (columnas `SALT_LOGIN`, `ITER_LOGIN`, `CLAVE_SERVIDOR` y
`SECRETO_SISTEMA`) y `66` (`SESIONES` y `SP_EXIGIR_PERMISO`). Es idempotente:
se puede reaplicar sin efectos.

El modulo `10` **no se toca**: `SP_CAMBIAR_CLAVE_USUARIO` se redefine aca,
igual que `66` redefinio `SP_LOGIN_AUTENTICAR`.

## Que no hace

- No borra `SP_INSERTAR_USUARIO` ni otros `SP` de usuarios.
- No implementa autocambio por parte del usuario: no pide la clave actual.
- (05/11/2026) `SP_CAMBIAR_CONTRASENA`, el gemelo muerto del modulo `10`, se
  elimino por decision del dueno: no tenia caller ni mapeo.

## Verificacion

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
