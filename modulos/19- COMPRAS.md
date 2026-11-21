# Módulo 19 — COMPRAS

El agregado **compras** completo: la cabecera (`COMPRAS`), los **pagos y notas
de crédito** (`PAGOS_COMPRA`), los dos `SP` de **devolución al proveedor** y las
vistas de compras. Los productos comprados van en `DETALLE_COMPRA` y las
devoluciones al proveedor en `DEVOLUCION_COMPRA`, las dos en este mismo módulo.

**Depende de:** `PROVEEDORES` (5), `EMPLEADOS` (8) y `METODOS_PAGO` (4).
**Es usado por:** `DETALLE_COMPRA` y `DEVOLUCION_COMPRA` (este módulo),
las vistas del 43 y el cierre de caja (41).
**Es usado por la app:** `compras.cpp` (iniciar compra, cancelar, pagar, compras
pendientes, devoluciones) y `caja.cpp` (cierre).

> **(12/11/2026) Absorbe los módulos `19.5` y `19.6`.** Eran dos archivos que no
> tenían sentido por separado: pagos y devoluciones son parte del mismo agregado
> y sus `SP` ya estaban enlazados con esta cabecera. No se creó ni borró ningún
> objeto: solo se movió texto. Los triggers de `DEVOLUCION_COMPRA` siguen en el
> `22` porque necesitan su tabla.
>
> **(14/11/2026) Absorbe el módulo `22`.** Con el `19` ya convertido en el
> agregado completo, el `22` era la mitad del mismo agregado: su tabla la usan
> los `SP` de acá y sus triggers escriben en `COMPRAS`. Mover el detalle antes
> de la cabecera no era posible por la FK, así que el archivo separado tenía una
> única razón de existir: el orden de import. Ahora está todo en un archivo, en
> el orden correcto.

Fuente: `modulos/19- COMPRAS.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

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

### HISTORIAL_ESTADOS_COMPRA

Bitácora de los cambios de estado de cada compra: quién, cuándo y hacia dónde
pasó. Se escribe **solo por triggers**, así que también registra un `UPDATE`
directo.

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL_ESTADO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_COMPRA` | `INT` | NOT NULL, FK → `COMPRAS` | Compra afectada. |
| `ESTADO_ANTERIOR` | `ENUM(...)` | NULL, CHECK en el dominio | `NULL` en la fila de nacimiento. |
| `ESTADO_NUEVO` | `ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA')` | NOT NULL, CHECK | Estado al que pasó. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Dueño de la compra (no quien ejecutó el cambio). |
| `MOTIVO` | `VARCHAR(100)` | NOT NULL | Texto del cambio. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento. |

**Índice:** `IX_HIST_ESTADO_FECHA` sobre `FECHA`. El acceso por compra ya lo
cubre el índice del FK.

**Migración incluida:** `ALTER TABLE ... MODIFY` de los dos estados de
`VARCHAR(20)` a `ENUM(...)`, re-ejecutable, para bases creadas antes del
cambio. Los `CHECK` (`CK_HIST_ESTADO_ANTERIOR`, `CK_HIST_ESTADO_NUEVO`)
restringen el dominio aunque el tipo fuera `VARCHAR`.

> **(13/11/2026) Absorbe el módulo `19.1`.** La tabla, su índice y su `ALTER`
> eran el último resto de una extracción del 07/10/2026 hecha "por
> consistencia" con el `21.5`, no por dependencia. Los dos triggers ya vivían
> acá desde antes, así que el archivo separado solo partía en dos el mismo
> agregado. Ahora la tabla se crea **antes** de los triggers que la escriben.

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
- **El total nunca se edita a mano**: lo calculan el detalle y la devolución,
  los dos en este módulo.
- **`RECIBIDA` exige pago del 100%** (validado por trigger, no solo por SP).
- **Cancelar revierte stock** y exige que la mercancía siga en depósito.
- **No se cancela con pagos registrados**: primero se anulan.
- **Factura única por proveedor.**
- **Las compras no se borran nunca** (auditoría).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

## Pagos a proveedores: `PAGOS_COMPRA` (ex módulo 19.5)

Pagos a proveedores por una compra, más las **notas de crédito** (descuentos o
devoluciones que bajan la deuda). Un pago puede ser parcial o total y, cuando
la suma cubre el total, **la compra pasa sola a `RECIBIDA`**.

**Depende de:** `COMPRAS`, `METODOS_PAGO` (4), `EMPLEADOS` (8),
`DETALLE_COMPRA` y `DEVOLUCION_COMPRA` (este módulo).
**Es usado por:** `caja.cpp`/`compras.cpp` (registro de pago, compras
pendientes) y el cierre de caja.

Fuente: `modulos/19- COMPRAS.sql`, seccion PAGOS_COMPRA · Revisado: 12/11/2026.

### El concepto que manda: se paga el BRUTO

El tope de pago es el **BRUTO**: `COMPRAS.TOTAL` (la base) **+** el ITBIS de las
líneas **−** el ITBIS devuelto de las devoluciones `PROCESADA`. Por eso una
compra con `TOTAL = 100` e ITBIS de 18 exige **118** de pagos para quedar
`RECIBIDA`.

> **(15/11/2026) La fórmula ya NO vive acá.** Estaba escrita a mano en **siete**
> lugares de este módulo (2 SP y 4 triggers, uno de ellos en dos ramas), y cada
> copia podía desincronizarse de las demás y de las vistas. Ahora **los siete
> leen `VW_COMPRA_NETA`** (43), la misma vista que usan `VISTA_COMPRA_CON_IVA` y
> `VISTA_COMPRAS_PENDIENTES_PAGO`.
>
> Es exactamente lo que **ventas ya hacía**: su ruta de escritura (21 y 24) lee
> `BRUTO_NETO` de `VW_VENTA_NETA`. Compras se faltaba.
>
> **Para cambiar el BRUTO ahora se cambia en `VW_COMPRA_NETA` y nada más:** los
> siete puntos de este módulo y las tres vistas lo heredan. El test
> `db/test-compras.sh` (33 comprobaciones) cubre el flujo entero, así que un
> cambio mal hecho en esa fórmula tiene red.
>
> **Ojo con el orden del import:** este módulo **lee una vista del 43**, que
> corre después. Funciona porque MariaDB no valida el cuerpo de un trigger al
> crearlo, solo al ejecutarlo, y en una base nueva no hay filas de `PAGOS_COMPRA`
> durante el import. Es la misma dependencia que ventas ya tiene.

### Tablas

#### PAGOS_COMPRA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PAGO_COMPRA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_COMPRA` | `INT` | NOT NULL, FK → `COMPRAS` | Compra pagada. |
| `ID_METODO_PAGO` | `INT` | NULL, FK → `METODOS_PAGO` | Método; **`NULL` en notas de crédito** (no hay plata moviéndose). |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quien paga o firma. Si llega `NULL`, el trigger pone al dueño de la compra. |
| `TIPO` | `ENUM('PAGO','NOTA_CREDITO')` | NOT NULL, DEFAULT `'PAGO'` | Naturaleza del movimiento. |
| `MONTO` | `DECIMAL(10,2)` | NOT NULL, CHECK `<> 0` | Positivo en `PAGO`, **negativo** en `NOTA_CREDITO`. |
| `OBSERVACION` | `VARCHAR(100)` | NULL | Motivo; **obligatorio** en notas de crédito. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |

**Índices:** `IX_PAGOS_COMPRA_COMPRA` (estado de cuenta de una compra) e
`IX_PAGOS_COMPRA_FECHA` (cierre de caja y reportes del día).

**Bloque de migración** (idempotente, para bases viejas): agrega
`ID_EMPLEADO`/`TIPO`/`OBSERVACION` si faltan, **rellena** `ID_EMPLEADO` con el
dueño de la compra, lo pasa a `NOT NULL`, hace `ID_METODO_PAGO` nullable y
reemplaza el `CHECK MONTO > 0` por `MONTO <> 0` (redefiniendo la columna, porque
en esta versión de MariaDB el `CHECK` inline no se puede borrar con
`DROP CONSTRAINT`).

> El `ALTER ... ADD CONSTRAINT FK_PAGO_COMPRA_EMPLEADO` está **comentado**: en
> una base donde el `CREATE` sí corrió, el FK ya existe y el `ALTER` tira el
> `1826` (nombre duplicado). Inofensivo, pero ensuciaba el log.

### Procedimientos almacenados

#### `SP_REGISTRAR_PAGO_COMPRA(P_ID_COMPRA, P_ID_METODO_PAGO, P_MONTO, P_ID_EMPLEADO)`

**Usada por la app** (`compras.cpp`). `P_ID_EMPLEADO` es opcional.

1. Compra inexistente → `ERROR: LA COMPRA NO EXISTE.`
2. `CANCELADA` → `ERROR: LA COMPRA ESTA CANCELADA.`
3. `RECIBIDA` → `ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).`
4. `DEVUELTA` → `ERROR: LA COMPRA ESTA DEVUELTA.`
5. Método inexistente → `ERROR: EL METODO DE PAGO NO EXISTE.`
6. Monto nulo o `<= 0` → `ERROR: EL MONTO DEBE SER MAYOR A CERO.`
7. `pagado + monto > BRUTO` →
   `ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.`
8. Empleado informado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
9. Inserta el `PAGO` (el trigger `TR_AUTO_RECIBIR_COMPRA` puede cerrar la
   compra) y devuelve
   `EXITO: PAGO DE <monto> REGISTRADO PARA LA COMPRA #<id>` +
   ` - COMPRA SALDADA (RECIBIDA).` si quedó saldada.

> **Concurrencia:** el `SELECT` de la compra usa `FOR UPDATE`, así dos pagos
> simultáneos no pasan juntos la validación 7 (evita pagar de más por carrera).
>
> `P_ID_EMPLEADO` `NULL` es válido: lo completa `TR_AUTOCOMPLETAR_EMPLEADO_PAGO`.

#### `SP_ANULAR_PAGO_COMPRA(P_ID_PAGO_COMPRA, P_ID_EMPLEADO)`

**La app no la llama** hoy (necesaria para poder cancelar una compra con pagos).

1. Empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
2. Pago inexistente → `ERROR: EL PAGO NO EXISTE.`
3. Compra `CANCELADA` → `ERROR: LA COMPRA ESTA CANCELADA, NO ADMITE CAMBIOS DE PAGO.`
4. Compra `DEVUELTA` → `ERROR: LA COMPRA ESTA DEVUELTA, NO ADMITE CAMBIOS DE PAGO.`
5. **Borra** la fila, recalcula lo pagado y, si estaba `RECIBIDA` y dejó de
   estar saldada, la vuelve a `ABIERTA`.
6. Devuelve `EXITO: PAGO #<id> ANULADO (<monto>). PAGADO DE LA COMPRA #<id>: <pagado>`
   (o `NOTA DE CREDITO #...` si era una nota).

> **Borrado físico**, no anulación lógica: el pago desaparece. El rastro queda
> en los triggers de historial de estados de la compra, no del pago.

#### `SP_REGISTRAR_NOTA_CREDITO_COMPRA(P_ID_COMPRA, P_MONTO, P_OBSERVACION, P_ID_EMPLEADO)`

**La app no la llama.** El monto se recibe **positivo** y se guarda como
`-ABS(monto)`.

1. Compra inexistente → `ERROR: LA COMPRA NO EXISTE.`
2. `CANCELADA` o `DEVUELTA` →
   `ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE NOTAS DE CREDITO.`
3. Monto nulo o `<= 0` → `ERROR: EL MONTO DE LA NOTA DEBE SER MAYOR A CERO.`
4. Observación vacía → `ERROR: LA NOTA DE CREDITO REQUIERE UNA OBSERVACION.`
5. Empleado informado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
6. Inserta con `TIPO = 'NOTA_CREDITO'`, `ID_METODO_PAGO = NULL` y devuelve
   `EXITO: NOTA DE CREDITO DE <monto> REGISTRADA CONTRA LA COMPRA #<id> (PAGADO: <pagado>).`

> **Hueco conocido:** no valida que la nota deje el saldo pagado en negativo.
> Una nota mayor a lo pagado se acepta y deja `SUM(MONTO) < 0`; no hay tope
> contra el BRUTO ni contra lo efectivamente pagado.
>
> El trigger `TR_AUTO_RECIBIR_COMPRA` **reabre** la compra si la nota la deja
> sin saldar.

#### `SP_COMPRAS_PENDIENTES()`

**Usada por la app** ("Cobrar compra"). Devuelve las **20** compras más
recientes desde `VISTA_COMPRAS_PENDIENTES_PAGO` (módulo 43) con
`ID_COMPRA, PROVEEDOR, ESTADO, PAGADO, SALDO`. Es el espejo de
`SP_VENTAS_PENDIENTES` (39).

### Triggers

#### `TR_AUTOCOMPLETAR_EMPLEADO_PAGO`

`BEFORE INSERT`. Si `NEW.ID_EMPLEADO IS NULL`, lo setea al dueño de la compra.
Si la compra no existe:
`ERROR: LA COMPRA NO EXISTE, NO SE QUIEN DEJAR COMO RESPONSABLE.`

#### `TR_VALIDAR_PAGO_COMPRA`

`BEFORE INSERT`. La red de seguridad para inserts directos:
- compra `CANCELADA` → `ERROR: LA COMPRA ESTA CANCELADA.`
- `RECIBIDA` **y monto positivo** → `ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).`
  (una nota negativa **sí** entra: es plata que vuelve)
- `DEVUELTA` → `ERROR: LA COMPRA ESTA DEVUELTA.`
- monto 0 → `ERROR: EL MONTO NO PUEDE SER CERO.`
- signo incoherente con el tipo →
  `ERROR: EL MONTO Y EL TIPO NO COINCIDEN (LA NOTA DE CREDITO ES NEGATIVA).`
- `pagado + monto > BRUTO` →
  `ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.`

#### `TR_AUTO_RECIBIR_COMPRA`

`AFTER INSERT`. Doble sentido:
- si `ABIERTA`, `BRUTO > 0` y `pagado >= BRUTO` → **`RECIBIDA`**;
- si `RECIBIDA` y `pagado < BRUTO` → **`ABIERTA`** (una nota de crédito dejó la
  compra a medias).

> No crea bonos: los bonos son por **ventas**, no por compras.

#### `TR_VALIDAR_BORRADO_PAGO_COMPRA`

`BEFORE DELETE`. Con la compra `CANCELADA`, `DEVUELTA` o inexistente:
`ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE CAMBIOS DE PAGO.`

#### `TR_RECALCULAR_ESTADO_PAGO_COMPRA`

`AFTER DELETE`. Recalcula y mueve el estado en los dos sentidos: si se borró un
pago y quedó sin saldar → `ABIERTA`; si se borró una **nota de crédito** y
quedó saldada → `RECIBIDA`.

> Duplica la lógica del paso 6 de `SP_ANULAR_PAGO_COMPRA`, a propósito: así
> vale también si el `DELETE` no pasó por el SP.

#### `TR_VALIDAR_UPDATE_PAGO_COMPRA`

`BEFORE UPDATE`. Un pago **no cambia de compra**
(`ERROR: EL PAGO NO CAMBIA DE COMPRA.`), no admite compra `CANCELADA`/`DEVUELTA`,
no admite monto 0, exige coherencia signo/tipo y no permite que la suma con el
cambio aplicado (`pagado - OLD.MONTO + NEW.MONTO`) supere el BRUTO.

#### `TR_RECALCULAR_ESTADO_PAGO_COMPRA_UPDATE`

`AFTER UPDATE`. Solo si cambió `MONTO` o `TIPO`, recalcula y mueve el estado
igual que al insertar. Mismo cuerpo que `TR_AUTO_RECIBIR_COMPRA`, para que un
`UPDATE` directo no deje la compra mintiendo.

### Vistas

#### `VISTA_RESUMEN_PAGOS_COMPRA`

Pagos con `TIPO`, nombre del método, empleado, monto, observación y fecha.
`LEFT JOIN` a `METODOS_PAGO` porque las notas de crédito no traen método.

### Reglas de negocio

- **Se paga el BRUTO** (base + ITBIS − ITBIS devuelto), no la base.
- **`RECIBIDA` es automática** al cubrir el BRUTO, y se revierte sola si deja
  de estarlo.
- **Solo una compra `ABIERTA` recibe pagos positivos**; `CANCELADA` y `DEVUELTA`
  no admiten ningún movimiento.
- **Nota de crédito:** monto negativo, sin método de pago, **con motivo
  obligatorio**.
- **Todo pago tiene responsable**: si no lo mandan, es el dueño de la compra.
- **Un pago se anula borrándolo** (no hay anulación lógica).
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

## Devoluciones al proveedor (ex módulo 19.6)

Devoluciones de mercancía al proveedor. Flujo en **dos pasos**: primero se
**registra** la intención (queda `PENDIENTE`, sin tocar stock ni totales) y
después se **procesa** (`PROCESADA` devuelve la mercancía; `RECHAZADA` no toca
nada). Solo se devuelve de una compra **`RECIBIDA`**.

**Depende de:** `DETALLE_COMPRA` y `COMPRAS` (este módulo), `EMPLEADOS` (8) y
`CONFIGURACION` (para la tasa de ITBIS).
**La tabla `DEVOLUCION_COMPRA`, sus índices y sus 3 triggers están más abajo en
este archivo**, en la sección del detalle, porque necesitan `DETALLE_COMPRA` ya
creada.

**Orden de carga:** dentro de este módulo, después del detalle, y antes de `20`.

Fuente: `modulos/19- COMPRAS.sql`, seccion DEVOLUCION_COMPRA · Revisado: 12/11/2026.

### Procedimientos almacenados

#### `SP_REGISTRAR_DEVOLUCION_COMPRA(P_ID_DETALLE_COMPRA, P_ID_EMPLEADO, P_CANTIDAD, P_MOTIVO, P_CONDICION_PRODUCTO, OUT P_ID_DEVOLUCION_GENERADO)`

**Usada por la app** (`compras.cpp`). Deja la devolución en **`PENDIENTE`**.

**Validaciones en orden:**
1. cantidad nula o `<= 0` → `ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.`
2. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
3. detalle inexistente → `ERROR: EL DETALLE DE LA COMPRA NO EXISTE.`
4. compra no `RECIBIDA` →
   `ERROR: LA COMPRA NO ESTA RECIBIDA; SOLO SE DEVUELVE MERCANCIA DE UNA COMPRA RECIBIDA.`
5. cantidad mayor a lo comprado menos lo ya devuelto (pendiente + procesado) →
   `ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES REGISTRADAS DE ESTE PRODUCTO).`

**Cálculo y guardado:**
`SUBTOTAL_DEVUELTO = cantidad × PRECIO_UNITARIO` y
`MONTO_ITBIS_DEVUELTO` prorrateado desde la **línea guardada**:
`ROUND(MONTO_ITBIS × cantidad_devuelta / cantidad_comprada, 2)`. Devuelve el ID por el
`OUT` y `EXITO: DEVOLUCION #<id> REGISTRADA (PENDIENTE).`

> (21/11/2026) **Antes se recalculaba con la tasa vigente** y además exigía que la tasa
> existiera (paso 6, `ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.`); las dos cosas se
> quitaron. Con una tasa cambiada después de comprar, el recálculo devolvía un ITBIS
> distinto al registrado, y con un producto exento (`MONTO_ITBIS = 0`) devolvía un
> crédito fiscal que el suplidor nunca cobró. La línea guardada ya es el registro de lo
> que se pagó — el mismo criterio que usa la ganancia devuelta.
>
> **Concurrencia:** el `SELECT` del detalle usa `FOR UPDATE` sobre
> `DETALLE_COMPRA` y `COMPRAS`, y así dos devoluciones simultáneas del mismo
> producto no pasan juntas la validación del paso 5 (evita devolver de más por
> carrera). Es el blindaje explícito del 07/10/2026.
>
> **`P_CONDICION_PRODUCTO`** es `ENUM('BUENO','DANADO','USADO')`; no se valida
> el `MOTIVO` (puede venir `NULL`).
>
> La devolución **no** descuenta nada todavía: eso pasa al procesarla.

#### `SP_PROCESAR_DEVOLUCION_COMPRA(P_ID_DEVOLUCION_COMPRA, P_NUEVO_ESTADO, P_MOTIVO_RECHAZO)`

**Usada por la app.** `P_NUEVO_ESTADO` es `ENUM('PROCESADA','RECHAZADA')`.

- Devolución inexistente → `ERROR: LA DEVOLUCION NO EXISTE.`
- Ya procesada (cualquier estado distinto de `PENDIENTE`) →
  `ERROR: ESTA DEVOLUCION YA FUE PROCESADA.`
- Actualiza el estado y devuelve
  `EXITO: DEVOLUCION #<id> <ESTADO>.`

**Efectos por estado** (los hace el trigger `TR_PROCESAR_DEVOLUCION_COMPRA`,
más abajo en este archivo, así que valen también en un `UPDATE` directo):
- **`PROCESADA`**: baja stock, anota `SALIDA` en `MOVIMIENTOS_INVENTARIO`,
  escribe `HISTORIAL_MOVIMIENTOS_PRODUCTO` y **baja el `TOTAL`** de la compra;
  si se devolvió todo, la compra queda `DEVUELTA`.
- **`RECHAZADA`**: **no** toca stock, total ni bitácora. Solo deja rastro del
  motivo.

**Motivo del rechazo (P12C, 07/10/2026):** al rechazar, el `MOTIVO` original se
conserva y se le agrega el motivo del rechazo como
`<motivo original> | RECHAZO: <motivo>`, recortado con `LEFT(..., 200)` porque
la columna es `VARCHAR(200)`. Si no se manda motivo queda `NO ESPECIFICADO`. A
`PROCESADA` no se le toca el motivo.

> **Concurrencia:** el `SELECT ... FOR UPDATE` serializa dos procesamientos
> simultáneos; el segundo encuentra la devolución ya no `PENDIENTE` y falla con
> el mensaje correcto.
>
> **Firma con 3 parámetros:** la versión vieja de 2 parámetros quedó
> comentada en el archivo. MariaDB no admite valores `DEFAULT` en parámetros de
> procedures, así que los llamados pasan `NULL` explícito cuando no hay motivo.

### Tabla, triggers y vistas

Están más abajo en este archivo, en la sección del detalle: `DEVOLUCION_COMPRA`
(con `SUBTOTAL_DEVUELTO` y `MONTO_ITBIS_DEVUELTO`), sus índices y los triggers
`TR_PROCESAR_DEVOLUCION_COMPRA`, `TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA` y
`TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA`.

### Reglas de negocio

- **Solo se devuelve de una compra `RECIBIDA`.**
- **No se devuelve más de lo comprado**, contando pendientes y procesadas.
- **Registrar no mueve stock**; procesar sí.
- **Una devolución se procesa una sola vez** (`PENDIENTE` → `PROCESADA`/`RECHAZADA`).
- **El ITBIS devuelto se congela** con la tasa vigente al registrar.
- **Un rechazo deja rastro** del motivo, sin efectos sobre stock ni totales.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Detalle de compra y devoluciones al proveedor (ex módulo 22)

Las líneas de cada compra (qué producto, cuánta cantidad y a qué precio) más
todo lo que cuelga de ellas: stock, total, costo del producto, bitácora y
devoluciones. También aloja la tabla **`DEVOLUCION_COMPRA`** y sus triggers,
porque necesitan `DETALLE_COMPRA` ya creada.

**Depende de:** `COMPRAS` (arriba, en este archivo), `PRODUCTOS` (9),
`INVENTARIO` (17), `CONFIGURACION` (ITBIS) y `EMPLEADOS` (8).
**Es usado por:** los `SP` de compras y devoluciones (más arriba), movimientos
de inventario (20) y el mapa compra-recibida (40).

Fuente: `modulos/19- COMPRAS.sql`, seccion DETALLE_COMPRA · Revisado: 14/11/2026.

### El ITBIS de la línea

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

### Tablas

#### DETALLE_COMPRA

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

> > `IX_COMPRA_PROVEEDOR` está **sobre `COMPRAS(ID_PROVEEDOR)`**: el índice es de
> la cabecera, pero se crea acá porque necesita datos que solo existen cuando
> hay detalle. Funciona, pero vive lejos de su tabla.

> La FK `ON DELETE CASCADE` es letra muerta en la práctica: `COMPRAS` tiene un
> trigger que prohíbe borrar compras.

#### DEVOLUCION_COMPRA

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

### Procedimientos almacenados

#### `22_SP_AGREGAR_DETALLE_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO)`

**Usada por la app** (`compras.cpp`). `P_PRECIO` es el precio **de factura (con
ITBIS)**.

> (21/11/2026) **Excepción — producto exento:** si el producto tiene
> `EXENTO_ITBIS = 1`, el suplidor no cobra impuesto, así que `P_PRECIO` se toma como
> **neto** y `MONTO_ITBIS` se guarda en `0.00` (no se desglosa). Desglosarlo inventaría
> un crédito fiscal inexistente.

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

#### `SP_QUITAR_DETALLE_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO)`

**La app no la llama.** Saca una línea de una compra `ABIERTA`.

- línea inexistente → `ERROR: EL PRODUCTO NO ESTA EN ESTA COMPRA.`
- compra no `ABIERTA` → `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
- stock insuficiente →
  `ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).`
- Borra la línea (los efectos los hacen los triggers de `DELETE`) y devuelve
  `EXITO: PRODUCTO #<id> QUITADO DE LA COMPRA #<id>.`

#### `SP_MODIFICAR_LINEA_COMPRA(P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO)`

**La app no la llama.** Corrige cantidad o precio de una línea de una compra
`ABIERTA`. **No hace `UPDATE`** (está prohibido por trigger): **borra la línea
vieja e inserta la nueva**, así los mismos triggers reajustan stock, total,
bitácora y costo. `P_PRECIO` es de factura, con el mismo cálculo de ITBIS.

> (21/11/2026) **Misma excepción que el alta:** si el producto es exento
> (`EXENTO_ITBIS = 1`), `P_PRECIO` se toma como neto y `MONTO_ITBIS` queda en `0.00`.

Valida producto en la compra, compra `ABIERTA`, cantidad y precio positivos y
producto `ACTIVO`. Devuelve `EXITO: LINEA MODIFICADA.` (+ la advertencia de
margen si aplica).

> **Consecuencias del borrar-y-reescribir:** el `ID_DETALLE_COMPRA` cambia (la
> línea es nueva), y el stock se devuelve y se vuelve a sumar. Las devoluciones
> apuntan a líneas de compras `RECIBIDA`, que este SP no puede tocar, así que no
> hay riesgo de dejar una devolución huérfana.

### Vistas y funciones

#### `VISTA_DETALLE_COMPRA`

Líneas con nombre del producto, cantidad, precio y subtotal. **La app no la
usa.**

#### `FN_COSTO_COMPRA_VIGENTE(P_ID_PRODUCTO)`

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

### Triggers de `DETALLE_COMPRA`

#### Orden declarado (20/10/2026)

| Momento | Orden |
|---|---|
| `BEFORE INSERT` | `TR_BLOQUEAR_COMPRA_CERRADA` |
| `AFTER INSERT` | `TR_CALCULAR_TOTAL_COMPRA` → `TR_ACTUALIZAR_STOCK_COMPRA` → `TR_AUDITORIA_MOVIMIENTO_COMPRA` → `TR_ACTUALIZAR_COSTO_COMPRA` |
| `BEFORE UPDATE` | `TR_BLOQUEAR_UPDATE_DETALLE_COMPRA` |
| `BEFORE DELETE` | `TR_BLOQUEAR_BORRADO_COMPRA_CERRADA` |
| `AFTER DELETE` | `TR_RECALCULAR_TOTAL_COMPRA` → `TR_ACTUALIZAR_STOCK_BORRADO_COMPRA` → `TR_AUDITORIA_BORRADO_COMPRA` → `TR_RECALCULAR_COSTO_BORRADO_COMPRA` |

El orden está declarado con `FOLLOWS`; antes dependía del orden **accidental**
de creación (`information_schema.TRIGGERS.ACTION_ORDER`).

#### `TR_BLOQUEAR_COMPRA_CERRADA` (`BEFORE INSERT`)

Compra no `ABIERTA` → `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
Reemplaza al viejo `TR_BLOQUEAR_COMPRA_CANCELADA`, que solo cubría `CANCELADA`.

#### `TR_CALCULAR_TOTAL_COMPRA` (`AFTER INSERT`)

Prende `@COMPRAS_INTERNO = 1`, hace `TOTAL = TOTAL + NEW.SUBTOTAL` y lo apaga.
El `EXIT HANDLER` **apaga la bandera antes de `RESIGNAL`** (P11C, 07/10/2026):
las variables de usuario **no** se revierten con `ROLLBACK`.

#### `TR_ACTUALIZAR_STOCK_COMPRA` (`AFTER INSERT`)

Suma la cantidad a `INVENTARIO.STOCK_ACTUAL`; si el producto no tiene fila, la
crea con `STOCK_MINIMO = 5` y `UBICACION = 'ALMACEN_PRINCIPAL'`
(`INSERT ... ON DUPLICATE KEY UPDATE`), así no se pierde una entrada por falta
de registro de inventario.

#### `TR_AUDITORIA_MOVIMIENTO_COMPRA` (`AFTER INSERT`)

Anota en `MOVIMIENTOS_INVENTARIO` una `ENTRADA` con el empleado de la compra y
la observación `Compra registrada ID: <id>`.

#### `TR_ACTUALIZAR_COSTO_COMPRA` (`AFTER INSERT`)

`PRODUCTOS.P_COMPRA = FN_COSTO_COMPRA_VIGENTE(producto)` (la última compra
válida manda).

#### `TR_BLOQUEAR_UPDATE_DETALLE_COMPRA` (`BEFORE UPDATE`)

**Ninguna línea se edita nunca**:
`ERROR: LA LINEA DE UNA COMPRA NO SE PUEDE EDITAR; USE SP_MODIFICAR_LINEA_COMPRA.`

#### `TR_BLOQUEAR_BORRADO_COMPRA_CERRADA` (`BEFORE DELETE`)

- compra no `ABIERTA` →
  `ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).`
- stock insuficiente →
  `ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).`

#### `TR_RECALCULAR_TOTAL_COMPRA` (`AFTER DELETE`)

Recalcula `TOTAL` como `SUM(SUBTOTAL)` de lo que queda (0 si no queda nada). Usa
el mismo candado interno.

#### `TR_ACTUALIZAR_STOCK_BORRADO_COMPRA` (`AFTER DELETE`)

Resta la cantidad del stock y, **en el mismo trigger**, escribe **una** fila de
`HISTORIAL_MOVIMIENTOS_PRODUCTO` con `STOCK_ANTERIOR`/`STOCK_NUEVO` y
observación `Producto quitado de la compra`. Van juntos a propósito: así el
antes/después sale siempre bien.

#### `TR_AUDITORIA_BORRADO_COMPRA` (`AFTER DELETE`)

Anota la `SALIDA` en `MOVIMIENTOS_INVENTARIO` con el empleado de la compra.

#### `TR_RECALCULAR_COSTO_BORRADO_COMPRA` (`AFTER DELETE`)

Recalcula `P_COMPRA` con la compra válida anterior, o 0 si no queda ninguna.

#### Trigger eliminado: `TR_PROCESAR_COMPRA`

Solo queda el `DROP`. Sumaba el stock **dos veces** y registraba la `ENTRADA` dos
veces (una con empleado fijo 1). Lo que hacía ya lo cubren
`TR_ACTUALIZAR_STOCK_COMPRA` y `TR_AUDITORIA_MOVIMIENTO_COMPRA`.

### Triggers de `DEVOLUCION_COMPRA`

#### `TR_PROCESAR_DEVOLUCION_COMPRA` (`AFTER UPDATE`)

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

#### `TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA` (`BEFORE UPDATE`)

Si `OLD.ESTADO <> 'PENDIENTE'` y cambia estado, cantidad, subtotal o línea:
`ERROR: LA DEVOLUCION YA FUE PROCESADA O RECHAZADA; SU FILA NO CAMBIA.`
Mientras sigue `PENDIENTE` deja editar la cantidad, pero re-valida el cupo
(comprado − otras devoluciones vigentes):
`ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES DE ESTE PRODUCTO).`

#### `TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA` (`BEFORE DELETE`)

Una devolución `PROCESADA` no se borra:
`ERROR: LA DEVOLUCION PROCESADA NO SE BORRA; EL STOCK Y EL TOTAL YA SE MOVIERON.`
`PENDIENTE` y `RECHAZADA` sí se pueden descartar.

### Trigger sobre `COMPRAS`

#### `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` (`AFTER UPDATE ON COMPRAS`)

Cuando una compra pasa a `CANCELADA`, recalcula `P_COMPRA` de **todos** sus
productos con `FN_COSTO_COMPRA_VIGENTE`.

> **Cadena de orden:** corre `FOLLOWS TR_CAMBIO_ESTADO_COMPRA` y **antes** de
> `TR_MAPA_COMPRA_RECIBIDA` (módulo 32). Si se recrea cualquier trigger de la
> cadena sin rehacer los `FOLLOWS`, el orden se pierde: la cadena completa se
> rehace de una vez.

### Reglas de negocio

- **Un producto, una línea por compra** (UNIQUE).
- **El cliente paga el BRUTO**; la base guarda el neto y el ITBIS por línea.
- **Ninguna línea se edita**: se quita y se vuelve a agregar.
- **Solo compras `ABIERTA` aceptan altas, bajas o modificaciones de líneas.**
- **El stock se mueve solo**: entra al agregar, sale al quitar.
- **No se puede quitar mercancía ya vendida** (stock insuficiente).
- **El total y el costo se recalculan solos**, nunca a mano.
- **Una compra cancelada no deja costo fantasma** en el producto.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

