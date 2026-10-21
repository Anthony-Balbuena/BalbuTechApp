# Módulo 40 — PRODUCTO_PROVEEDOR

Mapa **quién vende qué**: un producto puede comprarse a N proveedores y un
proveedor trae N productos. La tabla guarda la **última compra** por pareja
producto–proveedor (precio + fecha); el historial completo vive en las líneas
de compra (`DETALLE_COMPRA` + `COMPRAS`).

`PRODUCTOS.ID_PROVEEDOR` sigue siendo el proveedor **preferido**; este mapa
no lo reemplaza ni lo modifica.

**Depende de:** `PRODUCTOS` (9), `PROVEEDORES` (5) y, por el trigger,
`COMPRAS` (19) y `DETALLE_COMPRA` (22).

Fuente: `modulos/40- PRODUCTO_PROVEEDOR.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### PRODUCTO_PROVEEDOR

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

## Triggers

### `TR_MAPA_COMPRA_RECIBIDA`

`AFTER UPDATE ON COMPRAS`. Cuando una compra **pasa a `RECIBIDA`**
(`NEW.ESTADO = 'RECIBIDA' AND OLD.ESTADO <> 'RECIBIDA'`), por cada línea de
`DETALLE_COMPRA` inserta o actualiza la pareja con
`ULTIMO_PRECIO = DC.PRECIO_UNITARIO` y `ULTIMA_FECHA = COMPRAS.FECHA`.

- Compras `ABIERTA` o `CANCELADA` **no** alimentan el mapa.
- Está declarado con **`FOLLOWS TR_RECALCULAR_COSTO_COMPRA_CANCELADA`**
  (trigger del módulo 22): corre **después** de ese. Sin el `FOLLOWS`, el
  orden dependía del orden accidental de creación.

> **Dependencia de orden:** `FOLLOWS` exige que el otro trigger exista al
> momento de crear este. El import ordena los archivos (`sort -V`), así que
> el 22 se crea antes que el 40 y la creación funciona. Si algún día se
> recrea `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` **después** de este, hay que
> recrear también este trigger para restaurar el orden.
>
> La versión anterior (sin `FOLLOWS`) quedó comentada en el archivo como
> referencia histórica; no se debe reactivar.

## Procedimientos almacenados

### `SP_PRODUCTO_SUPLIDORES(P_ID_PRODUCTO)`

**Usada por la app** (`compras.cpp`). Devuelve los proveedores que venden ese
producto con `ULTIMO_PRECIO` y `ULTIMA_FECHA`, **del más barato al más caro**
(para elegir en el carrito).

### `SP_PRODUCTO_HISTORIAL_PRECIOS(P_ID_PRODUCTO)`

**Usada por la app** (`compras.cpp`). Historial de precios pagados: proveedor,
precio, fecha, cantidad e ID de compra, **solo de compras `RECIBIDA`**, de lo
más nuevo a lo más viejo, **limitado a 20 filas**.

### `SP_REPORTE_PRECIOS_COMPRA()`

**Usada por la app** (`compras.cpp`). Por producto con mapa:
`SUPLIDORES` (cantidad), `MAS_BARATO` y `DONDE_BARATO`,
`MAS_CARO` y `DONDE_CARO`, `ULTIMA_COMPRA`. Ordenado por nombre.

> Un producto **sin** filas en el mapa no aparece en el reporte (usa
> `JOIN`, no `LEFT JOIN`).

### `SP_PROVEEDOR_ACTIVO(P_ID_PROVEEDOR)`

**Usada por la app** (`compras.cpp`, dos veces). Devuelve el nombre del
proveedor **solo si existe y está `ACTIVO`**; si no, no devuelve filas. Sirve
para validar la elección por línea en el carrito de compras.

## Reglas de negocio

- **Una fila por pareja producto–proveedor** (PK compuesta).
- **El mapa guarda solo la última compra** por pareja; el historial completo
  se lee de `DETALLE_COMPRA` + `COMPRAS`.
- **Solo compras recibidas alimentan el mapa** (el trigger ignora abiertas y
  canceladas).
- **`ULTIMO_PRECIO` nunca negativo** (CHECK).
- **El proveedor preferido del producto no se toca**: `PRODUCTOS.ID_PROVEEDOR`
  sigue mandando para el alta/edición del producto.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
