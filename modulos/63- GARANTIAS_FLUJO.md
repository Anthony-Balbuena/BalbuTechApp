# 63 - Garantias: autor, fechas y flujo

## Que hace

Cierra los huecos del flujo de garantias que quedaron abiertos desde el
modulo 25:

- `GARANTIAS` no guardaba quien la registro ni cuando.
- `RECLAMOS_GARANTIAS` no guardaba quien abrio el reclamo, quien lo cerro
  ni cuando se cerro.
- `27_SP_REGISTRAR_RECLAMO_GARANTIA` solo miraba `ESTADO = 'ACTIVA'`: una
  garantia con `FECHA_FIN` en el pasado seguia siendo reclamable.
- `VENCIDA` estaba en el `ENUM` pero ningun objeto lo escribia.
- La UI pedia `ID detalle de venta`, `ID garantia` y `ID reclamo` a ciegas.
- No habia forma de que la garantia se registrara sola al confirmar la
  venta.

Objetos que agrega o reemplaza:

- Columna `PRODUCTOS.DIAS_GARANTIA INT NULL` con
  `CK_PRODUCTO_DIAS_GARANTIA (NULL o >= 0)`.
- Columnas `GARANTIAS.ID_EMPLEADO`, `GARANTIAS.FECHA_REGISTRO` y sus FK.
- Columnas `RECLAMOS_GARANTIAS.ID_EMPLEADO`,
  `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE` y sus FK.
- `SP_REGISTRAR_GARANTIA` (firma nueva, 3 parametros).
- `27_SP_REGISTRAR_RECLAMO_GARANTIA` (firma nueva, 3 parametros).
- `27_SP_FINALIZAR_RECLAMO_TOTAL` (firma nueva, 2 parametros).
- `SP_CONSULTAR_GARANTIAS`, `SP_CONSULTAR_RECLAMOS`,
  `SP_LINEAS_VENTA_CON_GARANTIA`, `SP_MARCAR_GARANTIAS_VENCIDAS`.
- Trigger `TR_REGISTRAR_GARANTIA_VENTA`.

## Por que

- Sin autor, un reclamo no tiene responsable y una garantia no tiene quien
  la respalde. `FECHA_REGISTRO` y `FECHA_CIERRE` dan la linea de tiempo que
  antes habia que adivinar por `FECHA_RECLAMO`.
- Validar solo el estado deja pasar reclamos sobre garantias vencidas por
  fecha: el estado se queda en `ACTIVA` hasta que alguien lo cambie, y
  nadie lo cambiaba.
- El vendedor atiende al cliente en el mostrador: si la UI le pide IDs de
  detalle, el flujo depende de que alguien los anote a mano.
- Registrar la garantia a mano despues de cada venta es trabajo repetido y
  facil de olvidar. Con `DIAS_GARANTIA` por producto, el pase a `REALIZADA`
  la crea sola.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/63- GARANTIAS_FLUJO.sql"
```

Es idempotente: `ADD COLUMN IF NOT EXISTS`, las FK y el `CHECK` se agregan
solo si no existen, y los SPs y el trigger se recrean con
`DROP IF EXISTS` + `CREATE`.

## Orden de despliegue

1. Backup de la base.
2. Correr este modulo.
3. Desplegar el binario nuevo.

El binario viejo llama a los SPs con la firma anterior y falla al registrar
o finalizar. Como `GARANTIAS` y `RECLAMOS_GARANTIAS` estaban vacias y el
flujo no se usaba, la ventana es de minutos y no se pierden datos.

El modulo 62 (`PERMISOS_GARANTIAS`) va despues del binario: el binario viejo
abre Garantias con `GESTIONAR_VENTAS` y, si el 62 corre antes, el item
desaparece del menu hasta desplegar.

## Como funciona el registro automatico

`TR_REGISTRAR_GARANTIA_VENTA` es `AFTER UPDATE ON VENTAS` con
`FOLLOWS TR_CAMBIO_ESTADO_VENTA`, asi que corre despues de que el historial
de estados ya escribio su fila.

Solo actua cuando `NEW.ESTADO = 'REALIZADA'` y `OLD.ESTADO <> 'REALIZADA'`.
Para cada linea de la venta cuyo producto tenga `DIAS_GARANTIA > 0` inserta
una fila en `GARANTIAS` con `FECHA_INICIO = CURRENT_DATE`,
`FECHA_FIN = CURRENT_DATE + DIAS_GARANTIA` y `ID_EMPLEADO = NEW.ID_EMPLEADO`
(el empleado de la venta). El `ON DUPLICATE KEY UPDATE` respeta
`UQ_GARANTIA_DETALLE`: si la linea ya tiene garantia, no la duplica ni
rompe la venta.

`DIAS_GARANTIA` en `NULL` o `0` significa "sin garantia automatica". Los 49
productos existentes quedan en `NULL`: no se inventan dias.

## Que preserva

- `TR_FINALIZAR_RECLAMO_APROBADO` sigue cancelando la garantia cuando un
  reclamo se aprueba.
- `TR_VALIDAR_CAMBIO_RECLAMO` sigue bloqueando reabrir un reclamo y tocar
  `CERRADO` o `RECHAZADO`.
- `TR_VALIDAR_FECHAS_GARANTIA` sigue autocorrigiendo un `FECHA_INICIO`
  pasado a hoy en los `INSERT`.
- `CK_GARANTIA_FECHAS` sigue exigiendo `FECHA_FIN > FECHA_INICIO`; por eso
  `SP_REGISTRAR_GARANTIA` rechaza dias menores a 1.
- `TR_CAMBIO_ESTADO_VENTA` conserva el orden 1 en `VENTAS`; el trigger nuevo
  queda en 2.
- El historial de estados de venta y el total de la venta no cambian.

## Que no hace

- No cablea el modulo 34 (`ASIGNACIONES_RECLAMOS`, asignar tecnicos): la
  tabla sigue vacia y sin uso.
- No ata un reembolso al reclamo.
- No backfillea garantias de ventas viejas: para eso queda el alta manual,
  que ahora pide ID de venta y muestra las lineas.
- No cambia `SP_VENTA_LINEAS`: ese SP alimenta la factura y no devuelve el
  ID del detalle. El alta manual usa `SP_LINEAS_VENTA_CON_GARANTIA`.

## Verificacion

Aplicado en `BALBU_TECH_TEST` el 30/10/2026, dos veces seguidas sin error
(la segunda pasada no cambia nada):

- `DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh` ->
  **11 OK, 0 FAIL**, con los 3 errores esperados vistos. El test corre en
  una transaccion con `ROLLBACK` y no deja filas `ZZ GAR`.
- El registro automatico crea la garantia con autor, `FECHA_REGISTRO` y los
  30 dias del producto; el producto sin `DIAS_GARANTIA` no la crea.
- El alta manual guarda autor y 45 dias; la segunda alta del mismo detalle
  falla con "YA TIENE UNA GARANTIA ASIGNADA" y no inserta.
- `SP_LINEAS_VENTA_CON_GARANTIA` devuelve la linea con `TIENE_GARANTIA = SI`.
- Reclamar dentro de fecha funciona y guarda autor; finalizar desde
  `PENDIENTE` deja `CERRADO` con `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE`;
  finalizar un `CERRADO` falla; reclamar una garantia con `FECHA_FIN` pasada
  falla con "VENCIDA POR FECHA".
- `SP_MARCAR_GARANTIAS_VENCIDAS()` pasa a `VENCIDA` la `ACTIVA` vencida.
- `check-app-sps.sh` en TEST: 99/0 (suma los 6 SPs que usa la app).
- `test-menus-por-rol.sh`: ADMIN/GERENTE/SUBGERENTE 5 opciones en Garantias,
  VENDEDOR 4 (sin "Finalizar reclamo"), CONTABILIDAD 2.
- `test-migracion-roles.sh`: VENDEDOR pasa de 12 a 15 permisos.
