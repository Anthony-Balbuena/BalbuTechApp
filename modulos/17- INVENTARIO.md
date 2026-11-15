# Módulo 17 — INVENTARIO

Stock por producto: cantidad actual, mínimo deseado y ubicación física. **Una
fila por producto** (UNIQUE), con FK a `PRODUCTOS` en cascada. Es la fuente de
verdad del stock: ventas, compras y ajustes lo mueven, y el resto de los
módulos lo lee.

**Depende de:** `PRODUCTOS` (9).
**Es usado por:** `HISTORIAL_MOVIMIENTOS_PRODUCTO` (32), ventas/compras y los
reportes de stock.

> **Absorbe el `20` (14/11/2026):** el kardex `MOVIMIENTOS_INVENTARIO`, su ajuste
> manual y sus consultas viven ahora **en este mismo archivo**, al final, en la
> sección «MOVIMIENTOS_INVENTARIO (ex módulo 20)».

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

### `SP_INSERTAR_INVENTARIO` — ELIMINADO el 15/11/2026

Daba de alta la fila de inventario con `STOCK_ACTUAL = 0` y devolvía un result
set con `ESTADO = 'EXITO'`. Nadie la llamaba: el alta la hace
`20_SP_REGISTRAR_AJUSTE_INVENTARIO`, la puerta del ajuste, que sí deja el
movimiento en el kardex. Se retiró como resto del ítem 12c de `PENDIENTES.md`;
en su lugar quedó un `DROP ... IF EXISTS` para limpiar las bases que ya la
tenían.

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
  0 y no dejaba movimiento. El ajuste tiene una sola vía:
  `20_SP_REGISTRAR_AJUSTE_INVENTARIO`, al final de este archivo.
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
  devoluciones, cancelaciones y ajustes (el kardex, al final de este archivo)
  son las vías válidas.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## MOVIMIENTOS_INVENTARIO (ex módulo 20)

Kardex del stock: absorbido dentro del `17` el 14/11/2026 (ver «Estado de la
documentación» y el `## Log` de `odd/tasks/consolidacion-modulos.md`). El cuerpo
del ex `20` viaja **verbatim**: acá solo se degradaron los encabezados un nivel.

Bitácora de todo lo que le pasa al stock: entradas, salidas, ajustes y
devoluciones. Cada fila dice qué producto, quién lo movió, cuánto, cuándo y por
qué. Es la fuente del **kardex**.

**Depende de:** `PRODUCTOS` (9), `EMPLEADOS` (8), `INVENTARIO` (esta misma
sección, arriba) y `HISTORIAL_MOVIMIENTOS_PRODUCTO` (32).
**Es usado por:** `inventario.cpp` (ajuste y kardex).

> **Los triggers que escriben acá no viven en este archivo:** se mudaron a la
> tabla que los dispara — `TR_AUDITORIA_MOVIMIENTO_COMPRA` y
> `TR_AUDITORIA_BORRADO_COMPRA` al **19**, `TR_AUDITORIA_MOVIMIENTO_VENTA` al
> **21** y las devoluciones al **26**. La sección quedó como tabla + SP de ajuste
> manual + kardex.

Fuente: `modulos/17- INVENTARIO.sql`, sección del ex módulo `20` · Base:
`BALBU_TECH` · Revisado: 20/10/2026 · Fusionado: 14/11/2026.

### Tablas

#### MOVIMIENTOS_INVENTARIO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_MOVIMIENTO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` | Producto movido. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quién lo movió. |
| `TIPO_MOVIMIENTO` | `ENUM('ENTRADA','SALIDA','AJUSTE','DEVOLUCION')` | NOT NULL | Naturaleza. |
| `CANTIDAD` | `INT` | NOT NULL, CHECK `> 0` | **Siempre positiva**: el signo lo da el tipo. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `OBSERVACION` | `VARCHAR(200)` | NULL | Motivo o referencia (trae el ID de la compra/venta). |

**Índices:** `IX_MOVIMIENTO_PRODUCTO` (kardex por producto),
`IX_MOVIMIENTO_FECHA` (kardex del día) e `IX_CANTIDAD_MOVIINVENTORIO`
(`CANTIDAD`).

> El índice por cantidad es de muy baja utilidad: nadie busca "movimientos de 7
> unidades", y agrega costo a cada `INSERT`. El nombre, además, tiene un typo
> (`MOVIINVENTORIO`).

### Procedimientos almacenados

#### `20_SP_REGISTRAR_AJUSTE_INVENTARIO(P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION)`

**Usada por la app** (`inventario.cpp`). El único punto de carga **manual** de
stock.

1. producto inexistente → `ERROR: PRODUCTO NO EXISTE.`
2. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
3. cantidad nula o `<= 0` → `ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.`
4. si el producto no tiene fila en `INVENTARIO`, la crea con stock 0,
   mínimo 5 y ubicación `ALMACEN_PRINCIPAL`.
5. `SALIDA` o `AJUSTE` con stock insuficiente →
   `ERROR: STOCK INSUFICIENTE PARA EL MOVIMIENTO.`
6. inserta el movimiento, actualiza el stock (`+` para `ENTRADA`/`DEVOLUCION`,
   `−` para el resto) y escribe **una** fila en
   `HISTORIAL_MOVIMIENTOS_PRODUCTO` con stock anterior y nuevo.
7. Devuelve `EXITO: MOVIMIENTO <TIPO> REGISTRADO Y STOCK ACTUALIZADO.`

> **`AJUSTE` siempre resta.** No existe ajuste al alza: para sumar hay que usar
> `ENTRADA`. Es contraintuitivo y no está validado en ningún lado.
>
> **Transacción propia:** abre solo si `@@in_transaction = 0`; anidada no la
> cierra. El `EXIT HANDLER` hace `ROLLBACK` solo en el caso propio, con
> `RESIGNAL`.
>
> **La validación de stock no bloquea la fila.** El `SELECT` del stock es sin
> `FOR UPDATE`: dos ajustes simultáneos pueden leer el mismo valor y dejar el
> stock negativo o desincronizado con la bitácora.
>
> **No valida que el producto esté `ACTIVO`**: se puede mover mercancía de un
> producto dado de baja.
>
> **Escribe el historial a mano**, en vez de confiar en un trigger: una sola
> fila por movimiento, con el antes/después correcto.

#### `SP_KARDEX_PRODUCTO(P_ID_PRODUCTO)`

**La app ya no la llama** (08/11/2026): la reemplazó `SP_KARDEX_PAGINADO`. Los
**50** movimientos más recientes de un producto: `ID_MOVIMIENTO`, `PRODUCTO`,
`FECHA`, `TIPO_MOVIMIENTO`, `CANTIDAD`, `EMPLEADO`, `OBSERVACION`.

#### `SP_KARDEX_TODOS()`

**La app ya no la llama** (08/11/2026), mismo motivo. Los **50** movimientos
más recientes de todos los productos, mismo formato.

#### `SP_KARDEX_PAGINADO(P_ID_PRODUCTO, P_PAGINA, P_POR_PAGINA)`

(08/11/2026) Una página del kardex, del movimiento más nuevo al más viejo.
`P_ID_PRODUCTO = 0` o `NULL` → todos los productos. `P_PAGINA` nulo o `< 1` → 1;
`P_POR_PAGINA` nulo o `< 1` → 10. La usa "Inventario > Movimientos".
Permiso: `INVENTARIO_VER`.

#### `SP_CONTAR_MOVIMIENTOS(P_ID_PRODUCTO)`

Cuántos movimientos hay (todos, o los de un producto), para el "Página 1 de N".
Mismo criterio que el paginado: `0`/`NULL` = todos.

> Un solo par sirve para las dos vistas del kardex, en vez de duplicar el
> `SP` por producto y por todos.

> Los kardex usan `JOIN` a `EMPLEADOS`: si un empleado desapareciera, sus
> movimientos desaparecerían del kardex. No muestran el stock resultante; para
> eso está `HISTORIAL_MOVIMIENTOS_PRODUCTO` (32).

### Reglas de negocio

- **Todo movimiento de stock deja una fila**, venga de compras, ventas,
  devoluciones o ajuste manual.
- **La cantidad siempre es positiva**; el tipo dice si suma o resta.
- **`DEVOLUCION` suma** (mercancía que vuelve); `SALIDA` y `AJUSTE` restan.
- **Una salida no puede dejar el stock negativo.**
- **El kardex está topeado a 50 filas**: no hay paginación.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

