# Módulo 32 — HISTORIAL_MOVIMIENTOS_PRODUCTO

Historial del stock con el **antes y el después**: qué producto, qué tipo de
movimiento, cuánto y entre qué valores se movió el stock. Permite reconstruir en
qué momento cambió cada producto.

**Depende de:** `PRODUCTOS` (9), `INVENTARIO` (17), `DETALLES_VENTA` (23),
`DETALLE_COMPRA` (22) y `DEVOLUCIONES` (26).

> **La app no lee esta tabla.** Es auditoría pura: la escribe cada trigger de
> negocio y la consulta `HISTORIAL_MOVIMIENTOS_PRODUCTO` solo desde SQL.

Fuente: `modulos/32- HISTORIAL_MOVIMIENTOS_PRODUCTO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### HISTORIAL_MOVIMIENTOS_PRODUCTO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_MOVIMIENTO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` **ON DELETE CASCADE** | Producto. |
| `TIPO_MOVIMIENTO` | `ENUM('ENTRADA','SALIDA','AJUSTE','VENTA','DEVOLUCION')` | NOT NULL | Tipo. |
| `CANTIDAD` | `INT` | NOT NULL | Unidades movidas. |
| `STOCK_ANTERIOR` | `INT` | NOT NULL | Stock antes del movimiento. |
| `STOCK_NUEVO` | `INT` | NOT NULL | Stock después. |
| `FECHA_MOVIMIENTO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `OBSERVACION` | `VARCHAR(200)` | NULL | Motivo o referencia. |

**Índice:** `IX_HIST_MOVIMIENTO_FECHA` (`FECHA_MOVIMIENTO`). El acceso por
producto lo cubre el índice del FK.

> **El `ENUM` tiene un valor que la otra bitácora no tiene: `VENTA`.** En
> `MOVIMIENTOS_INVENTARIO` (20) las ventas se anotan como `SALIDA`; acá tienen
> tipo propio. Las dos bitácoras **no** comparten dominio, así que un `UNION`
> entre ambas exige mapear.
>
> **`CANTIDAD` no tiene `CHECK`**: acá se aceptan negativos o cero, a diferencia
> de la bitácora de movimientos.
>
> **La FK borra en cascada**: si alguna vez se borra un producto, se lleva todo
> su historial. Es la única tabla de auditoría con `ON DELETE CASCADE`.

## Triggers

Los tres son **solo de registro**: el stock ya lo movió otro trigger de la
cadena, y estos leen el resultado.

### `TR_HISTORIAL_VENTA` (`AFTER INSERT ON DETALLES_VENTA`)

Anota `VENTA` con `STOCK_NUEVO = stock actual` y
`STOCK_ANTERIOR = STOCK_NUEVO + CANTIDAD`.

Corre `FOLLOWS TR_ACTUALIZAR_TOTAL_VENTA`, después de que
`TR_AUDITORIA_MOVIMIENTO_VENTA` (23) descontó el stock.

> **El antes/después se deduce, no se lee**: se asume que el stock actual ya
> tiene descontada esta línea. Si el orden de la cadena se rompe, el historial
> miente sin avisar.

### `TR_HISTORIAL_COMPRA` (`AFTER INSERT ON DETALLE_COMPRA`)

Anota `ENTRADA` con `STOCK_NUEVO = stock actual` y
`STOCK_ANTERIOR = STOCK_NUEVO − CANTIDAD`.

Corre `FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA`, al final de la cadena de alta de
compras (total → stock → auditoría → costo → historial).

> El orden ya **no** depende del orden accidental de creación (20/10/2026): está
> declarado con `FOLLOWS`. La versión anterior del trigger quedó comentada en el
> archivo.

### `TR_HISTORIAL_DEVOLUCION` (`AFTER UPDATE ON DEVOLUCIONES`)

En `PENDIENTE → APROBADA`/`REEMBOLSADA`, anota `DEVOLUCION` con
`STOCK_NUEVO = stock actual` y `STOCK_ANTERIOR = STOCK_NUEVO − CANTIDAD`, más el
motivo de la devolución.

Corre `FOLLOWS TR_MARCAR_VENTA_DEVUELTA`, o sea **después** de
`TR_REINTEGRAR_STOCK_DEVOLUCION` (26) y de marcar la venta como devuelta.

> El comentario del archivo dice "TR_REINTEGRAR_STOCK_DEVOLUCION (25)"; el
> trigger vive en el **26**. Referencia de archivo desactualizada, sin efecto en
> el código.

### Triggers eliminados

| Objeto | Por qué |
|---|---|
| `TR_HISTORIAL_AJUSTE` | Trigger genérico sobre `UPDATE INVENTARIO`: anotaba **todo** movimiento como "Ajuste manual de inventario", incluso compras y ventas, y **sumaba una tercera fila** a las que ya escribía el trigger de negocio. Cada movimiento dejaba 3 filas en el historial. |
| `TR_HISTORIAL_DEVOLUCION` sobre `DETALLES_DEVOLUCION` | La tabla no existe; las devoluciones viven enteras en `DEVOLUCIONES`. Quedó comentado y con su `DROP` para limpiar bases viejas. |

> Regla que quedó: **una sola fila por movimiento**, escrita por quien lo hizo
> (la lista completa está en `17- INVENTARIO.sql`).

## Reglas de negocio

- **Una fila por movimiento de stock, con el antes y el después.**
- **Los triggers solo registran**: nunca mueven stock.
- **El orden de la cadena está declarado** con `FOLLOWS`, no depende de la
  creación.
- **La venta tiene tipo propio (`VENTA`)**; en la otra bitácora es `SALIDA`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
