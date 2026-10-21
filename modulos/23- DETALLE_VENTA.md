# Módulo 23 — DETALLES_VENTA

Las líneas de cada venta: producto, cantidad, precio, descuento de línea y los
snapshots de ITBIS y ganancia. De acá cuelga el movimiento de stock y el total
de la venta.

**Depende de:** `VENTAS` (21), `PRODUCTOS` (9), `INVENTARIO` (17),
`CONFIGURACION` (ITBIS) y `EMPLEADOS` (8).
**Es usado por:** pagos (24), garantías (25), devoluciones (26), reclamos (27),
ganancias (38) y lecturas (39).

Fuente: `modulos/23- DETALLE_VENTA.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### DETALLES_VENTA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_DETALLE_VENTA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_VENTA` | `INT` | NOT NULL, FK → `VENTAS` **ON DELETE CASCADE** | Venta. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` | Producto. |
| `CANTIDAD` | `INT` | NOT NULL, CHECK `> 0` | Unidades. |
| `PRECIO_UNITARIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Precio de lista al vender. |
| `PORCENTAJE_DESCUENTO` | `DECIMAL(5,2)` | NOT NULL, DEFAULT `0.00`, CHECK entre 0 y 100 | Descuento de la línea en %. |
| `SUBTOTAL` | `DECIMAL(10,2)` | **GENERATED ... STORED** | `ROUND(cantidad × precio × (1 − desc/100), 2)`. |
| `MONTO_ITBIS` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00` | ITBIS de la línea **sobre el bruto con descuento**. |
| `MONTO_GANANCIA` | `DECIMAL(10,2)` | NULL | Snapshot `(precio − costo) × cantidad`. `NULL` = costo desconocido. |

**Restricción:** `UQ_VENTA_PRODUCTO` UNIQUE (`ID_VENTA`, `ID_PRODUCTO`).

**Índices:** `IX_VENTAS_FECHA` y `IX_CLIENTE_NOMBRE`.

> Igual que pasó en compras: acá se crean dos índices que **pertenecen a otras
> tablas** — `IX_VENTAS_FECHA` es de `VENTAS` y `IX_CLIENTE_NOMBRE` de
> `CLIENTES`. Funcionan, pero viven lejos de su tabla.
>
> **`MONTO_GANANCIA` puede ser `NULL` a propósito:** si el producto nunca se
> compró (`P_COMPRA = 0`), la ganancia no se inventa. Los reportes tienen que
> tolerar `NULL`.

## Procedimientos almacenados

### `SP_AGREGAR_DETALLE_VENTA(P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, P_ID_EMPLEADO, P_DESCUENTO_PCT)`

**Usada por la app** (`ventas.cpp`). El precio **no se pasa**: se toma el
`PRODUCTOS.PRECIO` vigente.

**Validaciones en orden:**
1. venta inexistente → `ERROR: LA VENTA NO EXISTE.`
2. `P_ID_EMPLEADO` nulo → `ERROR: EL EMPLEADO NO EXISTE.` (un `NULL` burlaba la
   comparación siguiente)
3. empleado distinto del dueño →
   `ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.`
4. cantidad nula o `<= 0` → `ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.`
5. descuento `< 0` o `> 100` →
   `ERROR: EL DESCUENTO DEBE ESTAR ENTRE 0 Y 100.` (`NULL` cuenta como 0)
6. producto inexistente → `ERROR: EL PRODUCTO NO EXISTE.`
7. stock insuficiente (sin fila de inventario = 0) → `ERROR: STOCK INSUFICIENTE.`
8. producto repetido → `ERROR: EL PRODUCTO YA ESTA EN ESTA VENTA.`
9. tasa de ITBIS ausente → `ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.`

**Cálculos:**
- `MONTO_ITBIS = ROUND(subtotal_con_descuento × tasa / 100, 2)`
- `MONTO_GANANCIA = ROUND(subtotal_con_descuento − cantidad × P_COMPRA, 2)`, o
  `NULL` si el costo es 0/`NULL`.

Inserta y devuelve `EXITO: PRODUCTO AGREGADO CORRECTAMENTE.`

> **El chequeo de stock de acá es la primera red, no la garantía.** Lee sin
> candado: en una carrera entre dos cajeros puede ver un número viejo. La
> garantía real es el descuento condicional del trigger (módulo 20/23) y, en
> última instancia, el error `1020` del servidor.
>
> **Handler P10:** el `1020` ("Record has changed since last read") es
> alcanzable en producción; el SP lo traduce a
> `ERROR: STOCK INSUFICIENTE, INTENTE DE NUEVO.` La sentencia ya revirtió
> sola: solo cambiaba el mensaje.
>
> **Sin `DEFAULT` en el parámetro del descuento:** el servidor 10.11 no soporta
> valores por defecto en parámetros de procedures; el llamador manda `0` o
> `NULL`.

## Triggers

### Orden declarado

| Momento | Orden |
|---|---|
| `BEFORE INSERT` | `TR_BLOQUEAR_VENTA_FINALIZADA` → `TR_VALIDAR_STOCK_DETALLE_VENTA` |
| `AFTER INSERT` | `TR_AUDITORIA_MOVIMIENTO_VENTA` → `TR_ACTUALIZAR_TOTAL_VENTA` → `TR_HISTORIAL_VENTA` (32) |

> La cadena completa del `AFTER INSERT` termina en `TR_HISTORIAL_VENTA`
> (módulo 32), que anota el antes/después del stock **después** de que el total
> ya se actualizó. Está declarado con `FOLLOWS TR_ACTUALIZAR_TOTAL_VENTA`.
| `BEFORE UPDATE` | `TR_BLOQUEAR_UPDATE_DETALLE_VENTA` |
| `BEFORE DELETE` | `TR_BLOQUEAR_BORRADO_DETALLE_VENTA` |

### `TR_BLOQUEAR_VENTA_FINALIZADA` (`BEFORE INSERT`)

- venta inexistente → `ERROR: LA VENTA NO EXISTE.`
- venta `REALIZADA`, `CANCELADA` o `DEVUELTA` →
  `ERROR: NO SE PUEDEN AGREGAR PRODUCTOS A UNA VENTA QUE YA NO ESTA ABIERTA.`

### `TR_VALIDAR_STOCK_DETALLE_VENTA` (`BEFORE INSERT`)

- producto sin fila en `INVENTARIO` →
  `ERROR: EL PRODUCTO NO TIENE REGISTRO EN INVENTARIO.`
- stock menor a la cantidad → `ERROR: STOCK INSUFICIENTE.`

> También es red, no garantía: lee sin candado. Si la lectura queda vieja,
> corta el descuento condicional del `AFTER INSERT` o el `1020`.

### `TR_AUDITORIA_MOVIMIENTO_VENTA` (`AFTER INSERT`)

Descuenta el stock **en una sola sentencia**:

```sql
UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
 WHERE ID_PRODUCTO = NEW.ID_PRODUCTO AND STOCK_ACTUAL >= NEW.CANTIDAD;
IF ROW_COUNT() = 0 THEN SIGNAL ... 'ERROR: STOCK INSUFICIENTE.'; END IF;
```

Si no alcanza, no descuenta nada y aborta la línea entera. Después anota la
`SALIDA` en `MOVIMIENTOS_INVENTARIO`.

> **La versión vieja (comentada en el archivo) restaba sin comprobar** y podía
> dejar stock negativo; la frenaba el `CHECK` de `INVENTARIO` con un error
> técnico. La actual comprueba y resta en el mismo golpe.

### `TR_ACTUALIZAR_TOTAL_VENTA` (`AFTER INSERT`, `FOLLOWS` la auditoría)

`TOTAL = TOTAL + NEW.SUBTOTAL` con `@VENTAS_INTERNO = 1` y `EXIT HANDLER` que
apaga la bandera antes de `RESIGNAL` (P11).

### `TR_BLOQUEAR_UPDATE_DETALLE_VENTA` (`BEFORE UPDATE`)

**Ninguna línea se edita**:
`ERROR: LA LINEA DE UNA VENTA NO SE PUEDE EDITAR.`
Si el cajero se equivocó, se cancela la venta y se rehace.

### `TR_BLOQUEAR_BORRADO_DETALLE_VENTA` (`BEFORE DELETE`)

**Ninguna línea se borra**, ni siquiera `EN_PROCESO`:
`ERROR: LA LINEA DE UNA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA.`

> **Diferencia clave con compras:** allá existe `SP_QUITAR_DETALLE_COMPRA` y se
> puede sacar una línea; acá **no hay ninguna vía** para quitar o editar una
> línea. El único camino es cancelar la venta completa. Cancelar repone el stock
> pero **deja las líneas** como evidencia.

## Vistas

### `VISTA_DETALLE_VENTA`

Líneas con `FACTURA` de la venta, nombre del producto, cantidad, precio y
subtotal. **La app no la usa.**

## Reglas de negocio

- **Un producto, una línea por venta** (UNIQUE).
- **El precio sale del maestro**, no lo elige el cajero.
- **Descuento por línea entre 0 y 100 %**, y baja también el ITBIS y la ganancia.
- **El stock se descuenta con comprobación atómica**: nunca queda negativo.
- **Las líneas no se editan ni se borran**: se cancela la venta.
- **La ganancia es un snapshot** al momento de vender; si el costo se desconoce,
  queda `NULL`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
