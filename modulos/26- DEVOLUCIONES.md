# Módulo 26 — DEVOLUCIONES

Lo que un cliente devuelve: por qué, en qué condición llegó, cuánto se le
reembolsa y en qué estado está la solicitud. Puede ligarse a una garantía
(módulo 25) si el reclamo viene por ella.

**Flujo en dos tiempos:** se **registra** la devolución (`PENDIENTE`, sin tocar
stock ni dinero) y después se **procesa** (`APROBADA`, `REEMBOLSADA` o
`RECHAZADA`). Aprobar devuelve **mercancía**, no dinero.

**Depende de:** `DETALLES_VENTA` (23), `GARANTIAS` (25), `EMPLEADOS` (8),
`VENTAS` (21), `INVENTARIO` (17) y `CONFIGURACION` (ITBIS).

> **Los nombres cruzados son reales:** el alta (`SP_REGISTRAR_DEVOLUCION`) y el
> procesamiento (`25_SP_PROCESAR_DEVOLUCION`) viven **acá**, mientras el rechazo
> (`26_SP_RECHAZAR_DEVOLUCION`) vive en el **módulo 25**. El número del prefijo
> no dice en qué archivo está.

Fuente: `modulos/26- DEVOLUCIONES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### DEVOLUCIONES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_DEVOLUCION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_DETALLE_VENTA` | `INT` | NOT NULL, FK → `DETALLES_VENTA` **ON DELETE CASCADE** | Línea devuelta. |
| `ID_GARANTIA` | `INT` | NULL, FK → `GARANTIAS` | Garantía que respalda el reclamo, si aplica. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quien registra. |
| `FECHA` | `DATE` | NOT NULL, DEFAULT `CURRENT_DATE` | Fecha. |
| `CANTIDAD` | `INT` | NOT NULL, CHECK `> 0` | Unidades devueltas. |
| `MOTIVO` | `VARCHAR(200)` | NULL | Motivo (al rechazar se le concatena el rechazo). |
| `CONDICION_PRODUCTO` | `ENUM('BUENO','DANADO','USADO')` | NOT NULL, DEFAULT `'BUENO'` | Estado de la mercancía. |
| `SUBTOTAL_REEMBOLSADO` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00` | **Lo cobrado** por esas unidades (con descuento aplicado). |
| `MONTO_ITBIS_REEMBOLSADO` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00` | ITBIS con la tasa vigente al registrar. |
| `MONTO_GANANCIA_REEMBOLSADA` | `DECIMAL(10,2)` | NULL | Ganancia devuelta, proporcional al margen de la línea. `NULL` = costo desconocido. |
| `ESTADO` | `ENUM('PENDIENTE','APROBADA','RECHAZADA','REEMBOLSADA')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |

**Índices:** `IX_DEVOLUCION_VENTA` (`ID_DETALLE_VENTA`),
`IX_DEVOLUCION_GARANTIA` (`ID_GARANTIA`) e `IX_DEVOLUCION_ESTADO_FECHA`
(`ESTADO, FECHA`, para el reporte de pendientes del día).

> **El reembolso es sobre lo cobrado, no sobre el precio de lista** (16/10/2026):
> `ROUND(cantidad × precio × (1 − descuento/100), 2)`, y el ITBIS se calcula
> sobre eso.
>
> La FK `ON DELETE CASCADE` es letra muerta: las líneas de venta no se borran.

## Procedimientos almacenados

### `SP_REGISTRAR_DEVOLUCION(P_ID_DETALLE_VENTA, P_ID_GARANTIA, P_ID_EMPLEADO, P_CANTIDAD, P_MOTIVO, P_CONDICION_PRODUCTO)`

**Usada por la app** (`ventas.cpp`). Deja la devolución en **`PENDIENTE`**.

**Validaciones en orden:**
1. cantidad nula o `<= 0` → `ERROR: LA CANTIDAD DEBE SER MAYOR A 0.`
2. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
3. detalle inexistente → `ERROR: EL DETALLE DE VENTA NO EXISTE.`
4. garantía informada inexistente → `ERROR: LA GARANTÍA ESPECIFICADA NO EXISTE.`
5. garantía de **otra** línea →
   `ERROR: LA GARANTÍA NO CORRESPONDE A ESTE DETALLE DE VENTA.`
6. cantidad mayor a lo vendido menos lo ya devuelto **o pendiente** →
   `ERROR: LA CANTIDAD SUPERA EL LÍMITE PERMITIDO (YA SE HAN DEVUELTO O ESTÁN PENDIENTES ALGUNAS UNIDADES).`
7. tasa de ITBIS ausente o `<= 0` → `ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.`

**Cálculos:** `SUBTOTAL_REEMBOLSADO` con el descuento de la línea,
`MONTO_ITBIS_REEMBOLSADO = ROUND(subtotal × tasa / 100, 2)` y
`MONTO_GANANCIA_REEMBOLSADA = ROUND(ganancia_línea × cantidad / cantidad_línea, 2)`
(o `NULL` si la línea no tiene ganancia). Devuelve
`EXITO: DEVOLUCIÓN REGISTRADA COMO PENDIENTE.` + `ID_DEVOLUCION`.

> **La cuota suma `PENDIENTE + APROBADA + REEMBOLSADA` y deja fuera las
> `RECHAZADA`**: rechazar libera cupo. La misma cuenta repite
> `TR_BLOQUEAR_CAMBIO_DEVOLUCION` si alguien edita la cantidad a pelo, y
> `TR_VALIDAR_CUOTA_DEVOLUCION` si inserta directo.
>
> **No hay candado (`FOR UPDATE`) ni restricción única en la cuota.** A
> diferencia de compras — donde `SP_REGISTRAR_DEVOLUCION_COMPRA` bloquea las
> filas —, dos altas simultáneas de la misma línea pueden pasar las dos y
> sobrepasar lo vendido. No hay índice que las frene.
>
> **No se valida la venta de la línea**: se puede registrar una devolución de una
> venta todavía `EN_PROCESO` (nunca cobrada).

### `25_SP_PROCESAR_DEVOLUCION(P_ID_DEVOLUCION, P_NUEVO_ESTADO)`

**Usada por la app** (`ventas.cpp`). `P_NUEVO_ESTADO` es
`ENUM('APROBADA','RECHAZADA','REEMBOLSADA')`.

1. devolución inexistente → `ERROR: LA DEVOLUCIÓN NO EXISTE.`
2. estado distinto de `PENDIENTE` → `ERROR: ESTA DEVOLUCIÓN YA FUE PROCESADA.`
3. `UPDATE` del estado y devuelve `EXITO: DEVOLUCIÓN MARCADA COMO <ESTADO>`.

**Lo que dispara el `UPDATE`** (3 triggers, en este orden):
1. `TR_REINTEGRAR_STOCK_DEVOLUCION` — suma stock y deja la `ENTRADA`/`DEVOLUCION`
   en la bitácora;
2. `TR_MARCAR_VENTA_DEVUELTA` — si **no queda ni una unidad** sin devolver y la
   venta estaba `REALIZADA`, la pasa a `DEVUELTA`;
3. `TR_HISTORIAL_DEVOLUCION` (32) — anota el antes/después **leyendo el stock ya
   sumado** por el (1): por eso el orden importa.

> **Aprobar devuelve mercancía, no plata:** los `PAGOS` de la venta quedan
> intactos. El reembolso al cliente está **fuera** del alcance de la base.
>
> **No bloquea la fila:** el `SELECT` del estado es sin `FOR UPDATE`, así que
> bajo concurrencia la validación puede leer un estado viejo; quien corta de
> verdad es `TR_BLOQUEAR_CAMBIO_DEVOLUCION`, con otro mensaje.
>
> **Rechazar por acá no anota motivo:** para eso está
> `26_SP_RECHAZAR_DEVOLUCION` (módulo 25).

### `26_SP_RECHAZAR_DEVOLUCION` (módulo 25)

Documentado en **`25- GARANTIAS.md`**: rechaza con motivo, libera la cuota y deja
borrar la fila.

## Triggers

### `TR_VALIDAR_CUOTA_DEVOLUCION` (`BEFORE INSERT`)

La red del alta directa: detalle inexistente →
`ERROR: EL DETALLE DE VENTA NO EXISTE.`; cantidad por encima de lo vendido menos
lo devuelto/pendiente →
`ERROR: LA CANTIDAD SUPERA LO VENDIDO (YA HAY DEVOLUCIONES DE ESTE DETALLE).`

### `TR_REINTEGRAR_STOCK_DEVOLUCION` (`AFTER UPDATE`)

Solo en `PENDIENTE → APROBADA` o `PENDIENTE → REEMBOLSADA`: suma la cantidad al
stock y anota `DEVOLUCION` en `MOVIMIENTOS_INVENTARIO` con el empleado de la
devolución. `RECHAZADA` no toca inventario.

> Suma stock **sin comprobar nada**: devolver mercancía siempre "entra". No hay
> tope ni validación de estado del producto (`DANADO` también vuelve al stock).

### `TR_MARCAR_VENTA_DEVUELTA` (`AFTER UPDATE`, `FOLLOWS` el anterior)

Si la venta estaba `REALIZADA` y **ninguna** línea tiene unidades sin devolver
(contando solo `APROBADA`/`REEMBOLSADA`), la pasa a `DEVUELTA`. Una devolución
parcial **no** la toca.

> Esta transición la hace el trigger directamente, sin la bandera
> `@VENTAS_INTERNO`; el candado de `VENTAS` la permite porque va a `DEVUELTA`
> desde `REALIZADA` y ya no quedan unidades.

### `TR_BLOQUEAR_CAMBIO_DEVOLUCION` (`BEFORE UPDATE`)

- Fuera de `PENDIENTE`: **ningún** cambio de estado, cantidad, subtotal o línea →
  `ERROR: LA DEVOLUCION YA FUE PROCESADA O RECHAZADA; SU FILA NO CAMBIA.`
- En `PENDIENTE`: se puede editar la cantidad, **revalidando la cuota**
  (`ERROR: LA CANTIDAD SUPERA LO VENDIDO (YA HAY DEVOLUCIONES DE ESTE PRODUCTO).`).

> **No cubre el `MOTIVO` ni el ITBIS:** una devolución procesada todavía admite
> que le cambien el motivo o el `MONTO_ITBIS_REEMBOLSADO`, y eso mueve el bruto
> de la venta sin pasar por ningún candado.

### `TR_BLOQUEAR_BORRADO_DEVOLUCION` (`BEFORE DELETE`)

`APROBADA` o `REEMBOLSADA` no se borra:
`ERROR: LA DEVOLUCION APROBADA NO SE BORRA; EL STOCK YA FUE REINTEGRADO.`
`PENDIENTE` y `RECHAZADA` sí se pueden descartar.

## Vistas

### `VISTA_REPORTES_DEVOLUCIONES`

Agrupa por producto, motivo y condición: `PRODUCTO`, `TOTAL_DEVOLUCIONES`,
`MOTIVO`, `CONDICION_PRODUCTO`.

> No filtra por estado: cuenta también las `RECHAZADA`, así que **no sirve como
> reporte de devoluciones efectivas**.

### `VISTA_DEVOLUCIONES_PENDIENTES`

`ID_DEVOLUCION`, `FECHA`, `ID_VENTA`, `PRODUCTO`, `CANTIDAD` y `MOTIVO` de las
`PENDIENTE`. Es la vista que el viejo `25- GARANTIAS.sql` dejó acá.

**La app no usa ninguna de las dos.**

## Reglas de negocio

- **La devolución no se cobra ni se reembolsa sola**: se registra y se procesa.
- **No se devuelve más de lo vendido**, contando pendientes y aprobadas;
  rechazar libera cupo.
- **El reembolso es sobre lo cobrado** (con descuento), no sobre el precio de lista.
- **Aprobar devuelve mercancía, no dinero.**
- **La venta pasa a `DEVUELTA` solo cuando no queda ni una unidad.**
- **Una devolución procesada no se edita ni se borra** (salvo el motivo y el
  ITBIS, que nadie custodia).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
