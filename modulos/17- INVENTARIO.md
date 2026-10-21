# Módulo 17 — INVENTARIO

Stock por producto: cantidad actual, mínimo deseado y ubicación física. **Una
fila por producto** (UNIQUE), con FK a `PRODUCTOS` en cascada. Es la fuente de
verdad del stock: ventas, compras y ajustes lo mueven, y el resto de los
módulos lo lee.

**Depende de:** `PRODUCTOS` (9).
**Es usado por:** `MOVIMIENTOS_INVENTARIO` (20), `HISTORIAL_MOVIMIENTOS_PRODUCTO`
(32), ventas/compras y los reportes de stock.

Fuente: `modulos/17- INVENTARIO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### INVENTARIO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_INVENTARIO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador. |
| `ID_PRODUCTO` | `INT` | NOT NULL, **UNIQUE**, FK → `PRODUCTOS` **ON DELETE CASCADE** | Producto. Un solo registro por producto. |
| `STOCK_ACTUAL` | `INT` | NOT NULL, DEFAULT 0, CHECK `>= 0` | Unidades en existencia. |
| `STOCK_MINIMO` | `INT` | NOT NULL, DEFAULT 5, CHECK `>= 0` | Umbral de reposición. |
| `UBICACION` | `VARCHAR(100)` | NOT NULL | Lugar físico en la tienda. |
| `FECHA_ACTUALIZACION` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP`, **ON UPDATE `CURRENT_TIMESTAMP`** | Se actualiza sola en cada cambio. |

**Índice:** `IX_INVENTARIO_FECHA` sobre `FECHA_ACTUALIZACION` (reportes por
última actualización).

> **Ojo con el borrado:** la FK es `ON DELETE CASCADE`. Borrar un producto
> borra su fila de inventario. La app no borra productos (solo los
> desactiva), pero un `DELETE` manual se lleva el stock.

## Procedimientos almacenados

### `SP_INSERTAR_INVENTARIO(P_ID_PRODUCTO, P_STOCK_MINIMO, P_UBICACION)`

**La app no la llama.** Da de alta la fila de inventario con
`STOCK_ACTUAL = 0`.

- Producto inexistente → `ERROR: ESTE ID DE PRODUCTO NO EXISTE EN EL CATÁLOGO.`
- Producto ya registrado → `ERROR: ESTE PRODUCTO YA TIENE UN REGISTRO EN INVENTARIO.`
- Devuelve un result set:
  `ESTADO = 'EXITO'`, `ID`, `PRODUCTO`, `MENSAJE = 'AGREGADO AL INVENTARIO CON STOCK 0'`.

> No valida `P_STOCK_MINIMO` negativo ni `P_UBICACION` vacía: eso lo corta la
> base con el CHECK / `NOT NULL` (error técnico, sin mensaje amigable).

## Triggers

### `17_TR_VALIDAR_STOCK_MINIMO`

`AFTER UPDATE ON INVENTARIO`. Si `NEW.STOCK_ACTUAL <= NEW.STOCK_MINIMO`,
inserta una alerta en `LOG_USUARIOS`:
`ID_USUARIO = NULL`, `ACCION = 'ALERTA_STOCK_BAJO'`,
`VALOR_ANTERIOR = 'Producto <id> llego al stock minimo (<min>)'`,
`VALOR_NUEVO = 'PENDIENTE'`.

> - Solo dispara en **UPDATE**, no en INSERT: un producto que nace con stock 0
>   y mínimo 5 no genera alerta hasta que alguien lo actualice.
> - Si el stock queda en o bajo el mínimo, **cada** actualización posterior
>   vuelve a escribir la alerta (no hay deduplicación).
> - Escribe en `LOG_USUARIOS`, tabla del módulo 29. Como el cuerpo del trigger
>   no se valida al crearlo, el import no falla; la tabla existe al momento de
>   ejecutarse.

## Vistas

### `VISTA_PRODUCTOS_CRITICOS`

Productos con `STOCK_ACTUAL <= STOCK_MINIMO`: `ID_PRODUCTO`, `NOMBRE`,
`STOCK_ACTUAL`, `STOCK_MINIMO`, `CANTIDAD_FALTANTE`.

> Queda un comentario de desarrollo dentro del `SELECT`
> (`-- <--- POSIBLE ERROR AQUÍ: ¿...?`) que ya no aplica: la columna real es
> `PRODUCTOS.NOMBRE`.

### `VISTA_VALOR_PRODUCTOS`

`NOMBRE`, `STOCK_ACTUAL`, `PRECIO`, `VALOR_TOTAL_ITEM = STOCK_ACTUAL *
PRECIO`, ordenada de mayor a menor valor.

> Usa `PRODUCTOS.PRECIO` (venta), no `P_COMPRA`: el "valor" es a precio de
> venta, no costo.

## Funciones

### `FN_VALOR_TOTAL_INVENTARIO() → DECIMAL(15,2)`

Suma `STOCK_ACTUAL * PRECIO` de todo el inventario; devuelve `0` si no hay
filas (`IFNULL`). Declarada `DETERMINISTIC`.

**La app no la usa** (ni la usa ninguna vista de este archivo).

## Objetos eliminados (solo queda el `DROP` y el motivo)

El archivo conserva `DROP PROCEDURE IF EXISTS` / `DROP TRIGGER IF EXISTS` con
un comentario que explica por qué se quitó. **No se deben recrear**:

- **`SP_INCREMENTAR_STOCK`** (eliminado): movía stock sin escribir en
  `MOVIMIENTOS_INVENTARIO`, el parámetro `P_PROVEEDOR` no se usaba y el log al
  que apuntaba (`LOG_ENTRADAS_INVENTARIO`) no existe. Rutas vigentes:
  compra (`19_SP_INICIAR_COMPRA` + `22_SP_AGREGAR_DETALLE_COMPRA`) o ajuste
  manual (`20_SP_REGISTRAR_AJUSTE_INVENTARIO`).
- **`SP_RECIBIR_MERCANCIA`** (eliminado): mismo problema, sumaba stock sin
  movimiento ni responsable. La entrada se hace por compra o por ajuste
  manual.
- **`SP_AJUSTE_INVENTARIO`** (eliminado): duplicado de
  `20_SP_REGISTRAR_AJUSTE_INVENTARIO`, no validaba producto, admitía cantidad
  0 y no dejaba movimiento. El ajuste tiene una sola vía: el SP del módulo 20.
- **`17_TR_REGISTRAR_HISTORIAL_INVENTARIO`** (trigger eliminado): anotaba
  toda actualización de stock en `HISTORIAL_MOVIMIENTOS_PRODUCTO` y, junto con
  `TR_HISTORIAL_AJUSTE` (32), duplicaba filas (3 por movimiento y con
  observaciones falsas). Ahora cada movimiento escribe **una** fila desde su
  trigger de negocio (`TR_HISTORIAL_COMPRA`, `TR_HISTORIAL_VENTA`,
  `TR_HISTORIAL_DEVOLUCION`, cancelación o ajuste).

> Se mantiene `17_TR_VALIDAR_STOCK_MINIMO` porque **no** escribe historial:
> solo alerta.

## Reglas de negocio

- **Una fila de inventario por producto** (UNIQUE).
- **Stock y mínimo nunca negativos** (CHECK).
- **`STOCK_ACTUAL` nace en 0** al crear la fila.
- **`FECHA_ACTUALIZACION` se mantiene sola** (`ON UPDATE CURRENT_TIMESTAMP`).
- **Alerta de stock bajo**: en o bajo el mínimo se escribe en `LOG_USUARIOS`
  (solo en updates).
- **El stock no se mueve a mano por SP genérico**: compras, ventas,
  devoluciones, cancelaciones y ajustes (20) son las vías válidas.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
