# Módulo 22 — DETALLE_COMPRA

Las líneas de cada compra (qué producto, cuánta cantidad y a qué precio) más
todo lo que cuelga de ellas: stock, total, costo del producto, bitácora y
devoluciones. También aloja la tabla **`DEVOLUCION_COMPRA`** y sus triggers,
porque necesitan `DETALLE_COMPRA` ya creada.

**Depende de:** `COMPRAS` (19), `PRODUCTOS` (9), `INVENTARIO` (17),
`CONFIGURACION` (ITBIS) y `EMPLEADOS` (8).
**Es usado por:** compras (19), pagos de compra (19.5), devoluciones (19.6),
movimientos de inventario (20) y el mapa compra-recibida (40).

Fuente: `modulos/22-DETALLE_COMPRA.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## El ITBIS de la línea

La factura del suplidor **trae el ITBIS incluido**, así que el SP lo descuenta:

```
BRUTO_LINEA  = cantidad × precio_factura
PRECIO_NETO  = ROUND((BRUTO_LINEA − ROUND(BRUTO_LINEA × tasa/(100+tasa), 2)) / cantidad, 2)
MONTO_ITBIS  = ROUND(BRUTO_LINEA − cantidad × PRECIO_NETO, 2)
```

`DETALLE_COMPRA.PRECIO_UNITARIO` guarda el **neto** y `MONTO_ITBIS` el impuesto.
`SUBTOTAL` (columna generada) es `cantidad × neto`. El **ITBIS absorbe el
redondeo** (15/10/2026) para que el total cuadre al centavo con la factura.

De ahí sale el **BRUTO** que se paga: `COMPRAS.TOTAL + SUM(MONTO_ITBIS) − ITBIS
devuelto`.

## Tablas

### DETALLE_COMPRA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_DETALLE_COMPRA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_COMPRA` | `INT` | NOT NULL, FK → `COMPRAS` **ON DELETE CASCADE** | Compra. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` | Producto. |
| `CANTIDAD` | `INT` | NOT NULL, CHECK `> 0` | Cantidad comprada. |
| `PRECIO_UNITARIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Precio **neto** (sin ITBIS). |
| `SUBTOTAL` | `DECIMAL(10,2)` | **GENERATED ... STORED** | `CANTIDAD × PRECIO_UNITARIO`. |
| `MONTO_ITBIS` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00` | ITBIS de la línea, con la tasa vigente al registrar. |

**Restricción:** `UQ_COMPRA_PRODUCTO` UNIQUE (`ID_COMPRA`, `ID_PRODUCTO`): un
producto una sola vez por compra.

**Índices:** `IX_DETALLE_COMPRA_COMPRA` (todas las líneas de una compra),
`IX_DETALLE_COMPRA_PRODUCTO` (historial de precios y compras de un producto) y
`IX_COMPRA_PROVEEDOR`.

> `IX_COMPRA_PROVEEDOR` está **sobre `COMPRAS(ID_PROVEEDOR)`**, aunque se crea
> en este archivo. Funciona, pero vive lejos de su tabla.

> La FK `ON DELETE CASCADE` es letra muerta en la práctica: `COMPRAS` tiene un
> trigger que prohíbe borrar compras.

### DEVOLUCION_COMPRA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_DEVOLUCION_COMPRA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_DETALLE_COMPRA` | `INT` | NOT NULL, FK → `DETALLE_COMPRA` | Línea devuelta. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quien registra. |
| `FECHA` | `DATE` | NOT NULL, DEFAULT `CURRENT_DATE` | Fecha. |
| `CANTIDAD` | `INT` | NOT NULL, CHECK `> 0` | Cuánto se devuelve. |
| `MOTIVO` | `VARCHAR(200)` | NULL | Motivo (se le agrega ` | RECHAZO: ...` al rechazar). |
| `CONDICION_PRODUCTO` | `ENUM('BUENO','DANADO','USADO')` | NOT NULL, DEFAULT `'BUENO'` | Estado de la mercancía. |
| `SUBTOTAL_DEVUELTO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Neto devuelto, congelado al registrar. |
| `MONTO_ITBIS_DEVUELTO` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00` | ITBIS devuelto. |
| `ESTADO` | `ENUM('PENDIENTE','PROCESADA','RECHAZADA')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |

**Índices:** `IX_DEVOLUCION_COMPRA_FECHA` e `IX_DEVOLUCION_COMPRA_ESTADO_FECHA`
(`ESTADO, FECHA`) para "devoluciones pendientes del día".

> El `CHECK SUBTOTAL_DEVUELTO > 0` es clave: un subtotal 0 devolvería mercancía
> sin bajar el `TOTAL` y la compra nunca llegaría a `DEVUELTA`. Se re-aplica con
> un `ALTER ... MODIFY` para bases viejas.

## Procedimientos almacenados

### `22_SP_AGREGAR_DETALLE_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO)`

**Usada por la app** (`compras.cpp`). `P_PRECIO` es el precio **de factura (con
ITBIS)**.

1. compra inexistente → `ERROR: LA COMPRA NO EXISTE.`
2. compra no `ABIERTA` →
   `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
3. producto inexistente → `ERROR: EL PRODUCTO NO EXISTE.`
4. producto no `ACTIVO` → `ERROR: EL PRODUCTO NO ESTA ACTIVO.`
5. cantidad `<= 0` → `ERROR: CANTIDAD INVALIDA.`
6. precio `<= 0` → `ERROR: PRECIO INVALIDA.`
7. producto repetido → `ERROR: PRODUCTO YA AGREGADO.`
8. tasa de ITBIS ausente → `ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.`

Inserta y devuelve `EXITO: PRODUCTO AGREGADO.` o, si el neto iguala o supera el
precio de venta,
`EXITO: PRODUCTO AGREGADO (ADVERTENCIA: PRECIO DE COMPRA IGUAL O MAYOR AL DE VENTA).`

> **Aviso, no error:** comprar sin margen se permite; solo avisa.
>
> **Dato nulo:** `P_CANTIDAD` `NULL` no cae en `<= 0` (comparación con `NULL`
> es `NULL`), sigue y termina en el error técnico del `NOT NULL`.

### `SP_QUITAR_DETALLE_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO)`

**La app no la llama.** Saca una línea de una compra `ABIERTA`.

- línea inexistente → `ERROR: EL PRODUCTO NO ESTA EN ESTA COMPRA.`
- compra no `ABIERTA` → `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
- stock insuficiente →
  `ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).`
- Borra la línea (los efectos los hacen los triggers de `DELETE`) y devuelve
  `EXITO: PRODUCTO #<id> QUITADO DE LA COMPRA #<id>.`

### `SP_MODIFICAR_LINEA_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO)`

**La app no la llama.** Corrige cantidad o precio de una línea de una compra
`ABIERTA`. **No hace `UPDATE`** (está prohibido por trigger): **borra la línea
vieja e inserta la nueva**, así los mismos triggers reajustan stock, total,
bitácora y costo. `P_PRECIO` es de factura, con el mismo cálculo de ITBIS.

Valida producto en la compra, compra `ABIERTA`, cantidad y precio positivos y
producto `ACTIVO`. Devuelve `EXITO: LINEA MODIFICADA.` (+ la advertencia de
margen si aplica).

> **Consecuencias del borrar-y-reescribir:** el `ID_DETALLE_COMPRA` cambia (la
> línea es nueva), y el stock se devuelve y se vuelve a sumar. Las devoluciones
> apuntan a líneas de compras `RECIBIDA`, que este SP no puede tocar, así que no
> hay riesgo de dejar una devolución huérfana.

## Vistas y funciones

### `VISTA_DETALLE_COMPRA`

Líneas con nombre del producto, cantidad, precio y subtotal. **La app no la
usa.**

### `FN_COSTO_COMPRA_VIGENTE(P_ID_PRODUCTO)`

**La app no la llama** (la usan los triggers). Devuelve el `PRECIO_UNITARIO` de
la **última línea** de compra del producto cuya compra **no esté `CANCELADA`**,
o **0** si nunca se compró.

> Es la **única definición** de la regla del costo de compra (20/10/2026). Antes
> cada trigger repetía su versión y ninguna miraba las compras canceladas: una
> compra cancelada dejaba su precio pegado en `PRODUCTOS.P_COMPRA` (costo
> fantasma).
>
> **Detalle fino:** excluye solo `CANCELADA`. Una compra `DEVUELTA` sigue
> contando como costo aunque su mercancía ya volvió al proveedor.

## Triggers de `DETALLE_COMPRA`

### Orden declarado (20/10/2026)

| Momento | Orden |
|---|---|
| `BEFORE INSERT` | `TR_BLOQUEAR_COMPRA_CERRADA` |
| `AFTER INSERT` | `TR_CALCULAR_TOTAL_COMPRA` → `TR_ACTUALIZAR_STOCK_COMPRA` → `TR_AUDITORIA_MOVIMIENTO_COMPRA` → `TR_ACTUALIZAR_COSTO_COMPRA` |
| `BEFORE UPDATE` | `TR_BLOQUEAR_UPDATE_DETALLE_COMPRA` |
| `BEFORE DELETE` | `TR_BLOQUEAR_BORRADO_COMPRA_CERRADA` |
| `AFTER DELETE` | `TR_RECALCULAR_TOTAL_COMPRA` → `TR_ACTUALIZAR_STOCK_BORRADO_COMPRA` → `TR_AUDITORIA_BORRADO_COMPRA` → `TR_RECALCULAR_COSTO_BORRADO_COMPRA` |

El orden está declarado con `FOLLOWS`; antes dependía del orden **accidental**
de creación (`information_schema.TRIGGERS.ACTION_ORDER`).

### `TR_BLOQUEAR_COMPRA_CERRADA` (`BEFORE INSERT`)

Compra no `ABIERTA` → `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
Reemplaza al viejo `TR_BLOQUEAR_COMPRA_CANCELADA`, que solo cubría `CANCELADA`.

### `TR_CALCULAR_TOTAL_COMPRA` (`AFTER INSERT`)

Prende `@COMPRAS_INTERNO = 1`, hace `TOTAL = TOTAL + NEW.SUBTOTAL` y lo apaga.
El `EXIT HANDLER` **apaga la bandera antes de `RESIGNAL`** (P11C, 07/10/2026):
las variables de usuario **no** se revierten con `ROLLBACK`.

### `TR_ACTUALIZAR_STOCK_COMPRA` (`AFTER INSERT`)

Suma la cantidad a `INVENTARIO.STOCK_ACTUAL`; si el producto no tiene fila, la
crea con `STOCK_MINIMO = 5` y `UBICACION = 'ALMACEN_PRINCIPAL'`
(`INSERT ... ON DUPLICATE KEY UPDATE`), así no se pierde una entrada por falta
de registro de inventario.

### `TR_AUDITORIA_MOVIMIENTO_COMPRA` (`AFTER INSERT`)

Anota en `MOVIMIENTOS_INVENTARIO` una `ENTRADA` con el empleado de la compra y
la observación `Compra registrada ID: <id>`.

### `TR_ACTUALIZAR_COSTO_COMPRA` (`AFTER INSERT`)

`PRODUCTOS.P_COMPRA = FN_COSTO_COMPRA_VIGENTE(producto)` (la última compra
válida manda).

### `TR_BLOQUEAR_UPDATE_DETALLE_COMPRA` (`BEFORE UPDATE`)

**Ninguna línea se edita nunca**:
`ERROR: LA LINEA DE UNA COMPRA NO SE PUEDE EDITAR; USE SP_MODIFICAR_LINEA_COMPRA.`

### `TR_BLOQUEAR_BORRADO_COMPRA_CERRADA` (`BEFORE DELETE`)

- compra no `ABIERTA` →
  `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
- stock insuficiente →
  `ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).`

### `TR_RECALCULAR_TOTAL_COMPRA` (`AFTER DELETE`)

Recalcula `TOTAL` como `SUM(SUBTOTAL)` de lo que queda (0 si no queda nada). Usa
el mismo candado interno.

### `TR_ACTUALIZAR_STOCK_BORRADO_COMPRA` (`AFTER DELETE`)

Resta la cantidad del stock y, **en el mismo trigger**, escribe **una** fila de
`HISTORIAL_MOVIMIENTOS_PRODUCTO` con `STOCK_ANTERIOR`/`STOCK_NUEVO` y
observación `Producto quitado de la compra`. Van juntos a propósito: así el
antes/después sale siempre bien.

### `TR_AUDITORIA_BORRADO_COMPRA` (`AFTER DELETE`)

Anota la `SALIDA` en `MOVIMIENTOS_INVENTARIO` con el empleado de la compra.

### `TR_RECALCULAR_COSTO_BORRADO_COMPRA` (`AFTER DELETE`)

Recalcula `P_COMPRA` con la compra válida anterior, o 0 si no queda ninguna.

### Trigger eliminado: `TR_PROCESAR_COMPRA`

Solo queda el `DROP`. Sumaba el stock **dos veces** y registraba la `ENTRADA` dos
veces (una con empleado fijo 1). Lo que hacía ya lo cubren
`TR_ACTUALIZAR_STOCK_COMPRA` y `TR_AUDITORIA_MOVIMIENTO_COMPRA`.

## Triggers de `DEVOLUCION_COMPRA`

### `TR_PROCESAR_DEVOLUCION_COMPRA` (`AFTER UPDATE`)

Solo cuando `PENDIENTE → PROCESADA`:

1. la compra debe seguir `RECIBIDA` →
   `ERROR: LA COMPRA NO ESTA RECIBIDA; NO SE PUEDE PROCESAR LA DEVOLUCION.`
2. el stock debe alcanzar →
   `ERROR: EL STOCK ACTUAL NO ALCANZA PARA DEVOLVER (YA HUBO VENTAS DE ESA MERCANCIA).`
3. `SUBTOTAL_DEVUELTO` no puede pasar del `TOTAL` actual →
   `ERROR: EL SUBTOTAL DE LA DEVOLUCION EXCEDE EL TOTAL DE LA COMPRA.`
4. efectos: baja stock, anota `SALIDA` en `MOVIMIENTOS_INVENTARIO`, escribe una
   fila de `HISTORIAL_MOVIMIENTOS_PRODUCTO` con tipo `DEVOLUCION`, baja el
   `TOTAL` de la compra (con el candado `@COMPRAS_INTERNO`) y, si el `TOTAL`
   llega a `<= 0`, deja la compra **`DEVUELTA`**.

`RECHAZADA` no dispara nada. Mismo patrón `P11C` para apagar la bandera ante error.

### `TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA` (`BEFORE UPDATE`)

Si `OLD.ESTADO <> 'PENDIENTE'` y cambia estado, cantidad, subtotal o línea:
`ERROR: LA DEVOLUCION YA FUE PROCESADA O RECHAZADA; SU FILA NO CAMBIA.`
Mientras sigue `PENDIENTE` deja editar la cantidad, pero re-valida el cupo
(comprado − otras devoluciones vigentes):
`ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES DE ESTE PRODUCTO).`

### `TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA` (`BEFORE DELETE`)

Una devolución `PROCESADA` no se borra:
`ERROR: LA DEVOLUCION PROCESADA NO SE BORRA; EL STOCK Y EL TOTAL YA SE MOVIERON.`
`PENDIENTE` y `RECHAZADA` sí se pueden descartar.

## Trigger sobre `COMPRAS`

### `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` (`AFTER UPDATE ON COMPRAS`)

Cuando una compra pasa a `CANCELADA`, recalcula `P_COMPRA` de **todos** sus
productos con `FN_COSTO_COMPRA_VIGENTE`.

> **Cadena de orden:** corre `FOLLOWS TR_CAMBIO_ESTADO_COMPRA` (módulo 19) y
> **antes** de `TR_MAPA_COMPRA_RECIBIDA` (módulo 40). Si se recrea el trigger de
> 19 sin recrear los `FOLLOWS` de la cadena, se rompe el orden. Recrear el
> trigger del módulo 40 exige recrear este de 22 primero… y viceversa: la
> cadena completa se rehace de una vez.

## Reglas de negocio

- **Un producto, una línea por compra** (UNIQUE).
- **El cliente paga el BRUTO**; la base guarda el neto y el ITBIS por línea.
- **Ninguna línea se edita**: se quita y se vuelve a agregar.
- **Solo compras `ABIERTA` aceptan altas, bajas o modificaciones de líneas.**
- **El stock se mueve solo**: entra al agregar, sale al quitar.
- **No se puede quitar mercancía ya vendida** (stock insuficiente).
- **El total y el costo se recalculan solos**, nunca a mano.
- **Una compra cancelada no deja costo fantasma** en el producto.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
