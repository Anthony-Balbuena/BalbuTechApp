# Módulo 20 — MOVIMIENTOS_INVENTARIO

Bitácora de todo lo que le pasa al stock: entradas, salidas, ajustes y
devoluciones. Cada fila dice qué producto, quién lo movió, cuánto, cuándo y por
qué. Es la fuente del **kardex**.

**Depende de:** `PRODUCTOS` (9), `EMPLEADOS` (8), `INVENTARIO` (17) y
`HISTORIAL_MOVIMIENTOS_PRODUCTO` (32).
**Es usado por:** `inventario.cpp` (ajuste y kardex).

> **Los triggers que escriben acá no viven en este archivo:** se mudaron a la
> tabla que los dispara — `TR_AUDITORIA_MOVIMIENTO_COMPRA` y
> `TR_AUDITORIA_BORRADO_COMPRA` al **22**, `TR_AUDITORIA_MOVIMIENTO_VENTA` al
> **23** y las devoluciones al **26**. El módulo quedó como tabla + SP de ajuste
> manual + kardex.

Fuente: `modulos/20- MOVIMIENTOS_INVENTARIO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### MOVIMIENTOS_INVENTARIO

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

## Procedimientos almacenados

### `20_SP_REGISTRAR_AJUSTE_INVENTARIO(P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION)`

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

### `SP_KARDEX_PRODUCTO(P_ID_PRODUCTO)`

**Usada por la app.** Los **50** movimientos más recientes de un producto:
`ID_MOVIMIENTO`, `PRODUCTO`, `FECHA`, `TIPO_MOVIMIENTO`, `CANTIDAD`,
`EMPLEADO`, `OBSERVACION`.

### `SP_KARDEX_TODOS()`

**Usada por la app.** Los **50** movimientos más recientes de todos los
productos, mismo formato.

> Los dos kardex usan `JOIN` a `EMPLEADOS`: si un empleado desapareciera, sus
> movimientos desaparecerían del kardex. No muestran el stock resultante; para
> eso está `HISTORIAL_MOVIMIENTOS_PRODUCTO` (32).

## Reglas de negocio

- **Todo movimiento de stock deja una fila**, venga de compras, ventas,
  devoluciones o ajuste manual.
- **La cantidad siempre es positiva**; el tipo dice si suma o resta.
- **`DEVOLUCION` suma** (mercancía que vuelve); `SALIDA` y `AJUSTE` restan.
- **Una salida no puede dejar el stock negativo.**
- **El kardex está topeado a 50 filas**: no hay paginación.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
