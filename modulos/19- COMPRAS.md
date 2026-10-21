# Módulo 19 — COMPRAS

Cabecera de las compras a proveedores: quién la hizo, cuándo, a qué proveedor,
el total y la factura del proveedor si llegó. Los productos comprados van en
`DETALLE_COMPRA` (módulo 22) y los pagos en `PAGOS_COMPRA` (19.5).

**Depende de:** `PROVEEDORES` (5) y `EMPLEADOS` (8).
**Es usado por:** `DETALLE_COMPRA` (22), `PAGOS_COMPRA` (19.5),
`DEVOLUCION_COMPRA` (19.6), `HISTORIAL_ESTADOS_COMPRA` (19.1) y el cierre de
caja (41).

Fuente: `modulos/19- COMPRAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### COMPRAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_COMPRA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PROVEEDOR` | `INT` | NOT NULL, FK → `PROVEEDORES` | Proveedor. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Empleado que hizo la compra. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se abrió. |
| `TOTAL` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00`, CHECK `>= 0` | Total. **Solo lo mueven los triggers de detalle y devolución.** |
| `ESTADO` | `ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA')` | NOT NULL, DEFAULT `'ABIERTA'` | Estado. |
| `FACTURA` | `VARCHAR(30)` | NULL | Nro. de factura del proveedor (opcional). |

**Índices:** `IX_COMPRA_FECHA` (reportes y cierre de caja), `IX_COMPRA_TOTAL`
(análisis de gastos), `IX_COMPRA_EMPLEADO` (compras por empleado) y
`UQ_COMPRA_FACTURA` **UNIQUE (`ID_PROVEEDOR`, `FACTURA`)**.

> `UQ_COMPRA_FACTURA` deja repetir `FACTURA` entre proveedores distintos y
> permite varias compras **sin** factura: en MySQL los `NULL` no colisionan en
> un índice único.

### Máquina de estados

```
ABIERTA ──(pagada al 100%)──> RECIBIDA ──(todo devuelto)──> DEVUELTA
   │                             │
   └──(SP_CANCELAR_COMPRA)──> CANCELADA    └──(anulación/nota de crédito)──> ABIERTA
```

`CANCELADA` y `DEVUELTA` son **terminales**: no vuelven a cambiar nunca.

## Procedimientos almacenados

### `19_SP_INICIAR_COMPRA(P_ID_PROVEEDOR, P_ID_EMPLEADO, OUT P_ID_COMPRA_GENERADO)`

**Usada por la app** (`compras.cpp`).

- Proveedor inexistente → `ERROR: EL PROVEEDOR NO EXISTE.`
- Proveedor no `ACTIVO` → `ERROR: EL PROVEEDOR NO ESTA ACTIVO.`
- Empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
- Inserta con estado `ABIERTA` y `TOTAL` 0, deja el ID en el `OUT` y devuelve
  `EXITO: COMPRA #<id> INICIADA CORRECTAMENTE.`

> El `OUT` es el canal del ID; el `SELECT` del mensaje va aparte.

### `SP_CANCELAR_COMPRA(P_ID_COMPRA, P_ID_EMPLEADO)`

**Usada por la app.** Cancela y **revierte el stock**, todo en una transacción.

**Validaciones en orden:**
1. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
2. compra inexistente → `ERROR: LA COMPRA NO EXISTE.`
3. empleado distinto del dueño →
   `ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA COMPRA.`
4. no está `ABIERTA` →
   `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
5. tiene pagos →
   `ERROR: LA COMPRA TIENE PAGOS REGISTRADOS; ANULELOS ANTES DE CANCELAR.`
6. stock insuficiente para revertir →
   `ERROR: NO SE PUEDE CANCELAR: EL STOCK ACTUAL NO ALCANZA PARA REVERTIR (YA HUBO VENTAS DE ESA MERCANCIA).`

**Efectos, en este orden:**
1. inserta una fila `SALIDA` por producto en `MOVIMIENTOS_INVENTARIO`;
2. descuenta `INVENTARIO.STOCK_ACTUAL`;
3. inserta una fila por producto en `HISTORIAL_MOVIMIENTOS_PRODUCTO` con stock
   anterior/nuevo;
4. deja la compra en `CANCELADA` (el detalle y el total **se conservan** como
   evidencia).

Devuelve `EXITO: COMPRA #<id> CANCELADA Y MERCANCIA REVERTIDA.`

> **Transacción:** abre una propia solo si `@@in_transaction = 0`; si viene de
> otra (llamada anidada, cierre de caja) no la cierra y deja que el de arriba
> decida. El `EXIT HANDLER` hace `ROLLBACK` solo en el caso propio y hace
> `RESIGNAL`.
>
> **Candado interno:** usa la variable de sesión `@COMPRAS_INTERNO = 1` para
> avisarle a `TR_VALIDAR_ACTUALIZACION_COMPRA` que la cancelación viene del SP.
> Como cualquier variable de sesión, se puede setear a mano: el candado evita
> el error accidental, no a un usuario decidido.
>
> **Todo o nada:** el chequeo de stock recorre **todo** el detalle *antes* de
> tocar nada, así un rechazo no deja cambios a medias.

### `SP_ASIGNAR_FACTURA_COMPRA(P_ID_COMPRA, P_FACTURA)`

**La app no la llama** hoy (la factura se asigna por otra vía o queda `NULL`).

- Factura vacía/nula → `ERROR: LA FACTURA NO PUEDE ESTAR VACIA.`
- Compra inexistente → `ERROR: LA COMPRA NO EXISTE.`
- `CANCELADA` o `DEVUELTA` → `ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA.`
- Ya usada por otra compra del mismo proveedor →
  `ERROR: ESA FACTURA YA EXISTE PARA ESTE PROVEEDOR.`
- Asigna con `TRIM` y devuelve
  `EXITO: FACTURA <nro> ASIGNADA A LA COMPRA #<id>.`

> **Carrera cubierta:** si dos sesiones asignan la misma factura a la vez, las
> dos pasan la validación y choca el índice (`1062`). El `EXIT HANDLER` detecta
> `SQLSTATE 23000` y devuelve el **mismo mensaje amigable** en vez del error
> técnico. Es el patrón correcto: validar + confiar en el índice.

### `SP_REPORTE_PERIODO_COMPRA(P_DESDE, P_HASTA)`

**Usada por la app.** Reporte de compras **`RECIBIDA`** en un rango inclusive
(por `DATE(C.FECHA)`).

- Fechas nulas → `ERROR: DEBE INDICAR DESDE Y HASTA.`
- `DESDE > HASTA` → `ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.`
- Devuelve una fila: `TRANSACCIONES` (compras distintas), `SUBTOTAL`
  (base), `ITBIS` (ITBIS de las líneas **menos** el ITBIS devuelto de las
  devoluciones `PROCESADA`) y `BRUTO` (`SUBTOTAL + ITBIS`).

> Es el espejo de `SP_REPORTE_PERIODO` (ventas). Solo `RECIBIDA` cuenta como
> gasto real; `CANCELADA` y `DEVUELTA` quedan afuera.

## Funciones

### `FN_CONTAR_ITEMS_COMPRA(P_ID_COMPRA)`

**La app no la llama.** Devuelve `COUNT(*)` de las líneas de la compra (0 si no
tiene).

> **Ojo:** el comentario dice "productos distintos", pero es `COUNT(*)` **sin
> `DISTINCT`**: si el mismo producto aparece en dos líneas, cuenta 2. Además
> está declarada `DETERMINISTIC` leyendo una tabla (MySQL lo acepta, pero la
> declaración es incorrecta).

## Triggers

### `TR_VALIDAR_ACTUALIZACION_COMPRA`

`BEFORE UPDATE`. Es **el candado de la cabecera**:

- `TOTAL` cambia sin `@COMPRAS_INTERNO = 1` →
  `ERROR: EL TOTAL DE LA COMPRA SOLO CAMBIA CON SU DETALLE O SU DEVOLUCION.`
- `CANCELADA`/`DEVUELTA` no cambian de estado →
  `ERROR: LA COMPRA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA.`
- a `RECIBIDA` exige `TOTAL > 0` **y** pagos `>= TOTAL` →
  `ERROR: SOLO SE MARCA RECIBIDA UNA COMPRA PAGADA AL 100%.`
- a `ABIERTA` solo desde `RECIBIDA` →
  `ERROR: SOLO SE REABRE UNA COMPRA RECIBIDA.`
- a `CANCELADA` solo desde el SP, desde `ABIERTA` y sin pagos →
  `ERROR: USE SP_CANCELAR_COMPRA; ...` / `ERROR: SOLO SE CANCELA UNA COMPRA ABIERTA.` /
  `ERROR: LA COMPRA TIENE PAGOS; ANULELOS ANTES DE CANCELAR.`
- a `DEVUELTA` solo desde `RECIBIDA` y con `TOTAL = 0` →
  `ERROR: SOLO SE MARCA DEVUELTA UNA COMPRA RECIBIDA.` /
  `ERROR: LA COMPRA NO ESTA DEVUELTA ENTERA; EL TOTAL SIGUE EN PIE.`

### `TR_BLOQUEAR_BORRADO_COMPRA`

`BEFORE DELETE`. Ninguna compra se borra:
`ERROR: LA COMPRA NO SE PUEDE BORRAR; USE SP_CANCELAR_COMPRA PARA ANULARLA.`
De acá cuelgan detalle, pagos, devoluciones e historial.

### `TR_HISTORIAL_ESTADO_COMPRA`

`AFTER INSERT`. Deja la primera fila del historial: `ESTADO_ANTERIOR = NULL`,
`ESTADO_NUEVO = 'ABIERTA'`, `MOTIVO = 'Compra iniciada'`.

### `TR_CAMBIO_ESTADO_COMPRA`

`AFTER UPDATE`. Si cambió el estado, anota `antes → después` en
`HISTORIAL_ESTADOS_COMPRA` con `MOTIVO = 'Estado: <viejo> -> <nuevo>'`. Vale
también para un `UPDATE` directo.

> El empleado del historial es el **dueño de la compra**, no quien ejecuta el
> cambio: `PAGOS_COMPRA` no trae empleado propio.

## Vistas

### `VISTA_REPORTE_COMPRAS`

Compra con nombre del proveedor, fecha, total, factura y estado, de la más
reciente a la más vieja.

### `VISTA_GASTOS_PROVEEDOR`

Por proveedor: `COMPRAS_REALIZADAS` y `GASTO_TOTAL` (`SUM(TOTAL)` con
`IFNULL` a 0), ordenado de mayor gasto a menor. **Excluye `CANCELADA`.**

> `DEVUELTA` **sí** entra en el conteo, pero como su total queda en 0 no infla
> el gasto. `ABIERTA` y `RECIBIDA` cuentan igual.

## Reglas de negocio

- **Solo a proveedores `ACTIVO`** y con empleado válido.
- **El total nunca se edita a mano**: lo calculan el detalle (22) y la
  devolución (19.6).
- **`RECIBIDA` exige pago del 100%** (validado por trigger, no solo por SP).
- **Cancelar revierte stock** y exige que la mercancía siga en depósito.
- **No se cancela con pagos registrados**: primero se anulan.
- **Factura única por proveedor.**
- **Las compras no se borran nunca** (auditoría).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
