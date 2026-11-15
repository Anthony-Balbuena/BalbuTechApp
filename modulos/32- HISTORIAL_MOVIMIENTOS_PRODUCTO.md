# Módulo 32 — HISTORIAL_MOVIMIENTOS_PRODUCTO

Historial del stock con el **antes y el después**: qué producto, qué tipo de
movimiento, cuánto y entre qué valores se movió el stock. Permite reconstruir en
qué momento cambió cada producto.

**Depende de:** `PRODUCTOS` (9), `PROVEEDORES` (5), `INVENTARIO` (17),
`DETALLES_VENTA` (21), `DETALLE_COMPRA` (19) y `DEVOLUCIONES` (26); el trigger del
mapa también necesita `COMPRAS` (19).

> **La app no lee esta tabla.** Es auditoría pura: la escribe cada trigger de
> negocio y la consulta `HISTORIAL_MOVIMIENTOS_PRODUCTO` solo desde SQL.
>
> **Absorbe el `40` (14/11/2026):** el mapa producto–proveedor y sus cuatro `SP`
> viven ahora **en este mismo archivo**, al final, en la sección
> «PRODUCTO_PROVEEDOR (ex módulo 40)».

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
> `MOVIMIENTOS_INVENTARIO` (17) las ventas se anotan como `SALIDA`; acá tienen
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
`TR_AUDITORIA_MOVIMIENTO_VENTA` (21) descontó el stock.

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
> el código. (El `25` era el módulo `GARANTIAS` antes de absorber el posventa.)

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

---

## PRODUCTO_PROVEEDOR (ex módulo 40)

Mapa producto–proveedor absorbido dentro del `32` el 14/11/2026 (ver el `## Log`
de `odd/tasks/consolidacion-modulos.md`). El cuerpo del ex `40` viaja
**verbatim**: acá solo se degradaron los encabezados un nivel.

Mapa **quién vende qué**: un producto puede comprarse a N proveedores y un
proveedor trae N productos. La tabla guarda la **última compra** por pareja
producto–proveedor (precio + fecha); el historial completo vive en las líneas
de compra (`DETALLE_COMPRA` + `COMPRAS`).

`PRODUCTOS.ID_PROVEEDOR` sigue siendo el proveedor **preferido**; este mapa
no lo reemplaza ni lo modifica.

**Depende de:** `PRODUCTOS` (9), `PROVEEDORES` (5) y, por el trigger,
`COMPRAS` y `DETALLE_COMPRA` (19).

Fuente: `modulos/32- HISTORIAL_MOVIMIENTOS_PRODUCTO.sql`, sección del ex módulo
`40` · Base: `BALBU_TECH` · Revisado: 20/10/2026 · Fusionado: 14/11/2026.

### Tablas

#### PRODUCTO_PROVEEDOR

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PRODUCTO` | `INT` | PK (compuesta), NOT NULL, FK → `PRODUCTOS` | Producto. |
| `ID_PROVEEDOR` | `INT` | PK (compuesta), NOT NULL, FK → `PROVEEDORES` | Proveedor. |
| `ULTIMO_PRECIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `>= 0` | Último precio unitario pagado. |
| `ULTIMA_FECHA` | `DATETIME` | NOT NULL | Fecha de la compra que fijó ese precio. |

**PK compuesta** (`ID_PRODUCTO`, `ID_PROVEEDOR`): una fila por pareja. El
`ON DUPLICATE KEY UPDATE` del trigger se apoya en ella.

**FKs:** `FK_MAPA_PRODUCTO` y `FK_MAPA_PROVEEDOR` (sin cascada: no se puede
borrar un producto/proveedor que tenga filas en el mapa).

### Triggers

#### `TR_MAPA_COMPRA_RECIBIDA`

`AFTER UPDATE ON COMPRAS`. Cuando una compra **pasa a `RECIBIDA`**
(`NEW.ESTADO = 'RECIBIDA' AND OLD.ESTADO <> 'RECIBIDA'`), por cada línea de
`DETALLE_COMPRA` inserta o actualiza la pareja con
`ULTIMO_PRECIO = DC.PRECIO_UNITARIO` y `ULTIMA_FECHA = COMPRAS.FECHA`.

- Compras `ABIERTA` o `CANCELADA` **no** alimentan el mapa.
- Está declarado con **`FOLLOWS TR_RECALCULAR_COSTO_COMPRA_CANCELADA`**
  (trigger del módulo 19): corre **después** de ese. Sin el `FOLLOWS`, el
  orden dependía del orden accidental de creación.

> **Dependencia de orden:** `FOLLOWS` exige que el otro trigger exista al
> momento de crear este. El import ordena los archivos (`sort -V`), así que el
> `19` se crea antes que este (`32`) y la creación funciona. Si algún día se
> recrea `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` **después** de este, hay que
> recrear también este trigger para restaurar el orden.
>
> La versión anterior (sin `FOLLOWS`) quedó comentada en el archivo como
> referencia histórica; no se debe reactivar.

### Procedimientos almacenados

#### `SP_PRODUCTO_SUPLIDORES(P_ID_PRODUCTO)`

**Usada por la app** (`compras.cpp`). Devuelve los proveedores que venden ese
producto con `ULTIMO_PRECIO` y `ULTIMA_FECHA`, **del más barato al más caro**
(para elegir en el carrito).

#### `SP_PRODUCTO_HISTORIAL_PRECIOS(P_ID_PRODUCTO)`

**Usada por la app** (`compras.cpp`). Historial de precios pagados: proveedor,
precio, fecha, cantidad e ID de compra, **solo de compras `RECIBIDA`**, de lo
más nuevo a lo más viejo, **limitado a 20 filas**.

#### `SP_REPORTE_PRECIOS_COMPRA()`

**Usada por la app** (`compras.cpp`). Por producto con mapa:
`SUPLIDORES` (cantidad), `MAS_BARATO` y `DONDE_BARATO`,
`MAS_CARO` y `DONDE_CARO`, `ULTIMA_COMPRA`. Ordenado por nombre.

> Un producto **sin** filas en el mapa no aparece en el reporte (usa
> `JOIN`, no `LEFT JOIN`).

#### `SP_PROVEEDOR_ACTIVO(P_ID_PROVEEDOR)`

**Usada por la app** (`compras.cpp`, dos veces). Devuelve el nombre del
proveedor **solo si existe y está `ACTIVO`**; si no, no devuelve filas. Sirve
para validar la elección por línea en el carrito de compras.

### Reglas de negocio

- **Una fila por pareja producto–proveedor** (PK compuesta).
- **El mapa guarda solo la última compra** por pareja; el historial completo
  se lee de `DETALLE_COMPRA` + `COMPRAS`.
- **Solo compras recibidas alimentan el mapa** (el trigger ignora abiertas y
  canceladas).
- **`ULTIMO_PRECIO` nunca negativo** (CHECK).
- **El proveedor preferido del producto no se toca**: `PRODUCTOS.ID_PROVEEDOR`
  sigue mandando para el alta/edición del producto.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

