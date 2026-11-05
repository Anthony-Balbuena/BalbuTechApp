# 64 - T2 seguridad: bloqueo por fuerza bruta

## Que hace

Cierra el hallazgo A4 de la auditoria del 03/11 en una base ya importada, sin
reimportar la matriz de permisos:

| Objeto | Tipo | Que cambia |
|---|---|---|
| `IX_LOG_ACCESOS_USUARIO_FECHA` | indice | `(USUARIO_INTENTADO, FECHA_ACCESO)` sobre `LOG_ACCESOS` |
| `FN_TIENE_PERMISO` | funcion | ignora cuentas con `ESTADO <> 'ACTIVO'` |
| `SP_ESTADO_BLOQUEO_LOGIN` | procedimiento | devuelve `FALLOS` y `MINUTOS` de un usuario |

Los modulos `28` y `36` ya traen los dos primeros cambios para una base nueva;
este modulo los aplica sobre la viva sin volver a correr la matriz completa.

## Por que

- **El indice.** El login cuenta fallos con
  `USUARIO_INTENTADO = ? AND ESTADO_INTENTO = 'FALLIDO' AND FECHA_ACCESO >= NOW() - INTERVAL 15 MINUTE`.
  Sin indice eso es un recorrido completo de `LOG_ACCESOS` en cada intento, o
  sea que un atacante podia convertir el bloqueo en una carga al servidor.
  La clave compuesta deja el filtro como rango: usuario fijo y fecha ordenada.
- **`FN_TIENE_PERMISO` sin `ESTADO`.** La version anterior resolvia el rol sin
  mirar si la cuenta estaba activa, asi que un usuario desactivado seguia
  pasando el control de permisos con solo existir en `USUARIOS`.
- **El conteo del bloqueo.** La app no puede leer `LOG_ACCESOS` (le abriria
  todo el historial de accesos), pero necesita saber cuantos fallos lleva la
  cuenta. `SP_ESTADO_BLOQUEO_LOGIN` corre como `DEFINER` y devuelve solo dos
  numeros.

El umbral no vive en el SQL: `P_VENTANA_MIN` llega desde `login.cpp`
(`VENTANA_BLOQUEO_MIN`) para que la ventana se cambie en un solo lugar.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/64- SEGURIDAD_T2.sql"
```

Es idempotente: el indice usa `ADD INDEX IF NOT EXISTS`, la funcion y el
procedimiento se recrean con `DROP ... IF EXISTS`. Se puede correr las veces
que haga falta.

Orden: despues de `28` y `36` (necesita `LOG_ACCESOS` y `FN_TIENE_PERMISO`).
Antes de `66`: ese modulo agrega el token de sesion al login.

## Como funciona el bloqueo

1. Un acceso **exitoso** reinicia la cuenta sin borrar evidencia: solo cuentan
   los fallos posteriores al ultimo `EXITOSO`.
2. Se cuentan los `FALLIDO` de la ventana vigente.
3. Al llegar al limite, `SP_LOGIN_AUTENTICAR` responde `BLOQUEADO` con los
   minutos que faltan y **no escribe** en `LOG_ACCESOS`. Si escribiera, cada
   reintento correria la ventana y el bloqueo no venceria nunca.
4. Vencida la ventana, la clave correcta vuelve a entrar.

## Verificacion

Aplicado en `BALBU_TECH_TEST` y en `BALBU_TECH` el 03/11/2026 y el 05/11/2026.

- `db/test-lockout.sh`: cinco fallos bloquean, el intento bloqueado no deja
  fila, la clave correcta entra al vencer la ventana y `FN_TIENE_PERMISO`
  devuelve 0 para una cuenta `INACTIVO`.
- `db/test-login-servidor.sh` e2e: el login usa el indice; el conteo del SP
  coincide con el de `LOG_ACCESOS`.
