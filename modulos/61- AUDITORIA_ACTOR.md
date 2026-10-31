# 61 - Auditoria con actor

## Que hace

Cierra los tres ultimos huecos de actor que quedaban despues de los modulos
56 y 57: la auditoria de clientes y de productos guardaba el usuario de
MySQL (`balbu_app`) en vez de quien hizo el cambio, y el historial de estado
de producto atribuia todo al empleado 1.

Objetos que reemplaza:

- Triggers de clientes: `TR_AUDIT_CLIENTES_INSERT`, `TR_AUDIT_CLIENTES_UPDATE`.
- Trigger de productos: `TR_AUDITORIA_PRODUCTOS_UPDATE` (cambio de precio).
- Trigger de historial: `TR_LOG_CAMBIO_ESTADO_PRODUCTO`.
- Columna `HISTORIAL_ESTADOS_PRODUCTO.ID_EMPLEADO`: pasa a `NULL`.

## Por que

- `CURRENT_USER()` y `USER()` devuelven la cuenta de MySQL, que siempre es
  `balbu_app`. La auditoria decia "lo hizo la app", no quien lo hizo.
- `TR_LOG_CAMBIO_ESTADO_PRODUCTO` caia a `IFNULL(@ID_EMPLEADO_ACTUAL, 1)`:
  cualquier cambio de estado sin empleado en la conexion quedaba firmado
  por el empleado 1, que es un dato falso, no un dato vacio.
- La app no dejaba `@ID_EMPLEADO_ACTUAL` en la conexion al cambiar el estado
  de un producto, asi que el fallback se disparaba siempre.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/61- AUDITORIA_ACTOR.sql"
```

Es idempotente: `DROP TRIGGER IF EXISTS` + `CREATE`, y el `MODIFY` de la
columna deja el mismo tipo si ya se corrio. No toca datos: el `ALTER` solo
relaja `NOT NULL` a `NULL` y no reescribe valores existentes.

## Que preserva

- Los triggers siguen cayendo a `USER()` cuando no hay usuario en la
  conexion, igual que el modulo 57. Lo que cambia es que ahora primero
  miran `@ID_USUARIO_ACTUAL`.
- El orden de los triggers `AFTER UPDATE` sobre `PRODUCTOS` no cambia:
  `TR_AUDITORIA_PRODUCTOS_UPDATE` sigue primero (1) y
  `TR_LOG_CAMBIO_ESTADO_PRODUCTO` lo sigue con `FOLLOWS` (2).
- `AUDITORIA_SISTEMA` y `HISTORIAL_ESTADOS_PRODUCTO` conservan su forma;
  solo cambia el valor que se guarda en las columnas de actor.
- El historial previo no se reescribe: las filas viejas con empleado 1
  quedan como estan.

## Que no hace

- No arregla el actor de los modulos 18 y 29 por si solo: el 29 lo cerro el
  56 y el 18 lo cierra este modulo. Si falta aplicar el 56 en alguna base,
  `LOG_USUARIOS.ID_USUARIO_ADMIN` sigue en `NULL`.
- No agrega actor a `AUDITORIA_SISTEMA` para tablas que todavia usan
  `USER()` sin mirar la variable de sesion.
- No cambia la UI: el cableado de `@ID_EMPLEADO_ACTUAL` y `@MOTIVO_CAMBIO`
  en `cambiarEstadoProducto()` (`productos.cpp`) y la limpieza en
  `cerrarSesion()` (`sesion.cpp`) van en el mismo commit, pero son codigo de
  la app, no del modulo.

## Verificacion

Aplicado en `BALBU_TECH_TEST` el 30/10/2026 con backup
`backups/111-antes-modulo-61-test-20261030_223349.sql`:

- `DB_NAME=BALBU_TECH_TEST bash db/test-auditoria-producto.sh` -> **5 OK, 0 FAIL**
  (historial con empleado, auditoria de precio con el usuario de la sesion,
  historial en `NULL` sin empleado, `INSERT` y `UPDATE` de clientes).
- `HISTORIAL_ESTADOS_PRODUCTO.ID_EMPLEADO` queda `IS_NULLABLE = YES`.
- Los tres triggers de clientes y productos leen `@ID_USUARIO_ACTUAL`;
  ningun trigger de la base conserva el fallback `, 1)`.
- El test corre en una transaccion con `ROLLBACK`: no deja filas `ZZ AUDIT`.
- Aplicarlo tres veces seguidas no cambia nada ni devuelve error.
- `check-app-sps.sh` 93/0 y `test-menus-por-rol.sh` 43/43 en TEST.

Pendiente: aplicar en la viva con backup previo.
