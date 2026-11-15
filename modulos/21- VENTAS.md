# Módulo 21 — VENTAS

Cabecera de cada venta: quién la atendió, a qué cliente, cuándo y cuánto. Los
productos van en `DETALLES_VENTA` (este módulo), los cobros en `PAGOS` (24) y
las devoluciones en `DEVOLUCIONES` (26).

**Depende de:** `EMPLEADOS` (8) y `CLIENTES` (7).
**Es usado por:** detalle (este módulo), pagos (24), garantías y reclamos
(25), devoluciones (26), ganancias (38) y lecturas (39).

> **(13/11/2026) Absorbe el módulo `21.5`.** El historial de estados estaba en
> un archivo aparte por simetría con el `19.1` de compras, sin ninguna razón
> de dependencia. Ahora tabla, `ALTER`, índice, sus dos triggers y
> `SP_HISTORIAL_VENTA` viven en este archivo.
>
> **(14/11/2026) Absorbe el módulo `23`.** El detalle estaba separado de su
> cabecera por el orden de import, no por diseño: `DETALLES_VENTA` necesita
> `VENTAS` creada. Con el archivo único ese orden se cumple solo, y los triggers
> del detalle quedan al lado de los que mueven el total de la venta.

Fuente: `modulos/21- VENTAS.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

## Tablas

### VENTAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_VENTA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo se abrió. |
| `ESTADO` | `ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA')` | NOT NULL, DEFAULT `'EN_PROCESO'` | Estado. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quien atiende (y dueño de la venta). |
| `ID_CLIENTE` | `INT` | NOT NULL, FK → `CLIENTES` | Cliente. |
| `TOTAL` | `DECIMAL(12,2)` | NOT NULL, CHECK `>= 0` | Total. **Sin `DEFAULT`**: el alta lo manda explícito (0). **Solo lo mueve el detalle.** |
| `FACTURA` | `VARCHAR(30)` | NULL | Nro. de factura del cliente (opcional). |

**Índices:** `IX_VENTAS_CLIENTE`, `IX_VENTAS_EMPLEADO` y
`UQ_VENTA_FACTURA` **UNIQUE (`ID_CLIENTE`, `FACTURA`)**.

> Igual que en compras: la factura no se repite **dentro del mismo cliente**, y
> los `NULL` no colisionan (varias ventas sin factura conviven).
>
> **Ojo con `TOTAL`:** a diferencia de `COMPRAS`, no tiene `DEFAULT 0.00`. Un
> `INSERT` directo que lo omita falla por `NOT NULL`.

### Máquina de estados

```
EN_PROCESO ──(cobro al 100%)──> REALIZADA ──(todo devuelto)──> DEVUELTA
     │                              │
     └──(SP_CANCELAR_VENTA)──> CANCELADA   └──(anulación de pago)──> EN_PROCESO
```

`CANCELADA` y `DEVUELTA` son **terminales**.

### HISTORIAL_ESTADOS_VENTA

Bitácora de los cambios de estado de cada venta (`EN_PROCESO`, `REALIZADA`,
`CANCELADA`, `DEVUELTA`): quién, cuándo y hacia dónde pasó. Se escribe **solo
por triggers**, así que también registra un `UPDATE` directo.

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL_ESTADO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_VENTA` | `INT` | NOT NULL, FK → `VENTAS` | Venta afectada. |
| `ESTADO_ANTERIOR` | `ENUM(...)` | NULL, CHECK en el dominio | `NULL` en la fila de nacimiento. |
| `ESTADO_NUEVO` | `ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA')` | NOT NULL, CHECK | Estado al que pasó. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Dueño de la venta (no quien ejecutó el cambio). |
| `MOTIVO` | `VARCHAR(100)` | NOT NULL | Texto del cambio. |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento. |

**Índice:** `IX_HIST_ESTADO_VENTA_FECHA` sobre `FECHA`. El acceso por venta ya
lo cubre el índice del FK.

**Migración incluida:** `ALTER TABLE ... MODIFY` de los dos estados de
`VARCHAR(20)` a `ENUM(...)`, re-ejecutable. Los `CHECK`
(`CK_HIST_VENTA_ANTERIOR`, `CK_HIST_VENTA_NUEVO`) restringen el dominio aunque
el tipo fuera `VARCHAR`.

## Procedimientos almacenados

### `21_SP_INICIAR_VENTA(P_ID_EMPLEADO, P_ID_CLIENTE, OUT P_ID_VENTA_GENERADO)`

**Usada por la app** (`ventas.cpp`).

- empleado inexistente → `ERROR: EMPLEADO NO EXISTE.`
- cliente inexistente → `ERROR: CLIENTE NO EXISTE.`
- Inserta `EN_PROCESO` con `TOTAL = 0.00`, deja el ID en el `OUT` y devuelve
  `EXITO: VENTA #<id> INICIADA.`

> No valida que el empleado esté `ACTIVO` (sí el proveedor en compras).

### `SP_CANCELAR_VENTA(P_ID_VENTA, P_ID_EMPLEADO)`

**Usada por la app.** Cancela y **devuelve todo el stock**, en una transacción.

1. venta inexistente → `ERROR: LA VENTA NO EXISTE.`
2. empleado distinto del dueño →
   `ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.`
3. no está `EN_PROCESO` → `ERROR: SOLO SE PUEDEN CANCELAR VENTAS EN PROCESO.`
4. tiene pagos →
   `ERROR: LA VENTA TIENE PAGOS REGISTRADOS, NO SE PUEDE CANCELAR.`

**Efectos:** repone stock (`+CANTIDAD` por producto), anota `ENTRADA` en
`MOVIMIENTOS_INVENTARIO`, escribe `HISTORIAL_MOVIMIENTOS_PRODUCTO` con
stock antes/después, y deja la venta en `CANCELADA` con `@VENTAS_INTERNO = 1`.
Devuelve `EXITO: VENTA #<id> CANCELADA Y STOCK RESTITUIDO.`

> **Concurrencia:** `SELECT ... FOR UPDATE` sobre la venta; doble cancelación
> simultánea se serializa.
>
> **Dos capas de la misma regla:** el paso 4 repite lo que el candado
> `TR_VALIDAR_ACTUALIZACION_VENTA` exige, pero con mensaje amigable.
>
> **Efecto colateral:** reponer stock puede disparar la alerta de stock mínimo
> del trigger del módulo 17.
>
> **Única puerta a `CANCELADA`.** El `EXIT HANDLER` apaga la bandera antes de
> `RESIGNAL` (P11), porque las variables de usuario no vuelven con `ROLLBACK`.

### `SP_ASIGNAR_FACTURA_VENTA(P_ID_VENTA, P_FACTURA)`

**La app no la llama.**

- factura vacía → `ERROR: LA FACTURA NO PUEDE ESTAR VACIA.`
- venta inexistente → `ERROR: LA VENTA NO EXISTE.`
- `CANCELADA`/`DEVUELTA` → `ERROR: LA VENTA ESTA CANCELADA O DEVUELTA.`
- factura repetida en el cliente →
  `ERROR: ESA FACTURA YA EXISTE PARA ESTE CLIENTE.`
- Asigna con `TRIM` y devuelve
  `EXITO: FACTURA <nro> ASIGNADA A LA VENTA #<id>.`

> Traduce el choque de carrera del índice (`SQLSTATE 23000`) al mismo mensaje
> amigable, igual que su espejo de compras.

### `SP_HISTORIAL_VENTA(P_ID_VENTA)`

**Usada por la app** (`ventas.cpp`). Solo lectura: devuelve `FECHA`,
`ESTADO_ANTERIOR`, `ESTADO_NUEVO`, `EMPLEADO` y `MOTIVO`, del más nuevo al más
viejo (`ORDER BY ID_HISTORIAL_ESTADO DESC`). `P_ID_VENTA = 0` lista el
historial de todas las ventas.

## Triggers

### `TR_BLOQUEAR_BORRADO_VENTA`

`BEFORE DELETE`. **Las ventas no se borran**:
`ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.`
Corta antes de que el `CASCADE` llegue al detalle.

### `TR_VALIDAR_ACTUALIZACION_VENTA`

`BEFORE UPDATE`. El candado de la cabecera:

- `TOTAL` cambia sin `@VENTAS_INTERNO = 1` →
  `ERROR: EL TOTAL DE LA VENTA SOLO CAMBIA CON SU DETALLE.`
- `CANCELADA`/`DEVUELTA` no cambian de estado →
  `ERROR: LA VENTA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA.`
- a `REALIZADA` exige `OLD.ESTADO = 'EN_PROCESO'`, `TOTAL > 0` y cobros
  `>= TOTAL` → `ERROR: SOLO SE MARCA REALIZADA UNA VENTA COBRADA AL 100%.`

> **Acá se compara contra `TOTAL` (la base), no contra el bruto.** El cierre
> automático de `PAGOS` (24) exige cubrir **base + ITBIS**; este candado, en
> cambio, deja marcar `REALIZADA` a mano con solo la base cobrada. Los dos
> caminos no piden lo mismo: el automático cobra el ITBIS, el manual no.
- a `EN_PROCESO` (reapertura) solo desde `REALIZADA` →
  `ERROR: SOLO SE REABRE UNA VENTA REALIZADA.`
- a `CANCELADA` exige bandera, `EN_PROCESO` y cero pagos →
  `ERROR: USE SP_CANCELAR_VENTA; LA CANCELACION REVERSIA EL STOCK.` /
  `ERROR: SOLO SE CANCELA UNA VENTA EN PROCESO.` /
  `ERROR: LA VENTA TIENE PAGOS; ANULELOS ANTES DE CANCELAR.`
- a `DEVUELTA` exige `REALIZADA` y **que no quede ninguna unidad sin
  devolver** (compara cada línea contra `DEVOLUCIONES` en estado `APROBADA` o
  `REEMBOLSADA`) →
  `ERROR: LA VENTA NO ESTA DEVUELTA ENTERA; QUEDAN UNIDADES.`

> **Riesgo vigilado (documentado en el archivo):** la bandera `@VENTAS_INTERNO`
> es una variable de sesión y el par `SET 1 / SET 0` no es atómico frente a
> errores. Si un `UPDATE` interno falla sin que nadie la apague, queda prendida
> en la sesión y un `UPDATE` a pelo posterior se colaría. Está demostrado en
> `Pruebas/test_blindaje_p3.sql`. `SP_CANCELAR_VENTA` ya tiene `EXIT HANDLER`;
> el riesgo sigue para cualquier otro camino que la levante.
>
> **Código defensivo:** la rama `SOLO SE REABRE UNA VENTA REALIZADA` es
> **inalcanzable** con estos 4 estados (pasar a `EN_PROCESO` desde
> `EN_PROCESO` no es cambio, y `CANCELADA`/`DEVUELTA` las corta el primer `IF`).

### `TR_HISTORIAL_ESTADO_VENTA`

`AFTER INSERT`. Deja la fila de nacimiento: `ESTADO_ANTERIOR = NULL`,
`ESTADO_NUEVO = NEW.ESTADO`, `MOTIVO = 'Venta iniciada'`.

### `TR_CAMBIO_ESTADO_VENTA`

`AFTER UPDATE`. Si cambió el estado, anota `antes → después` en
`HISTORIAL_ESTADOS_VENTA` con `MOTIVO = 'Estado: <viejo> -> <nuevo>'`. Vale
también para un `UPDATE` directo.

**Orden:** `TR_REGISTRAR_GARANTIA_VENTA` (25) declara
`FOLLOWS TR_CAMBIO_ESTADO_VENTA`, así que este tiene que existir primero. Se
cumple solo porque el `21` se importa antes que el `25`.

> Una cancelación deja **2 filas** de historial (nacimiento + cancelación).
> Verificado en `Pruebas/test_blindaje_p3.sql`.

## Limpiezas incluidas (solo `DROP`)

| Objeto | Por qué |
|---|---|
| `21_SP_AGREGAR_PRODUCTO_VENTA` | Duplicaba `SP_AGREGAR_DETALLE_VENTA` (este módulo) **sin** validar dueño de la venta. |
| `TR_CALCULAR_TOTAL_VENTA` | Duplicaba `TR_ACTUALIZAR_TOTAL_VENTA` (este módulo): el total se aplicaba dos veces. |
| `TR_PROCESAR_VENTA` | Duplicaba la auditoría de movimiento (20): stock y `ENTRADA` dobles. |

## Reglas de negocio

- **Toda venta nace `EN_PROCESO` con total 0** (vía SP).
- **`REALIZADA` exige cobro del 100%** (validado por trigger, no solo por SP).
- **Cancelar devuelve todo el stock** y exige cero pagos registrados.
- **Solo el dueño de la venta puede cancelarla.**
- **`DEVUELTA` exige que no quede ni una unidad.**
- **La factura es única por cliente.**
- **Las ventas no se borran nunca.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## Detalles de venta (ex módulo 23)

Las líneas de cada venta: producto, cantidad, precio, descuento de línea y los
snapshots de ITBIS y ganancia. De acá cuelga el movimiento de stock y el total
de la venta.

**Depende de:** `VENTAS` (arriba, en este archivo), `PRODUCTOS` (9),
`INVENTARIO` (17), `CONFIGURACION` (ITBIS) y `EMPLEADOS` (8).
**Es usado por:** pagos (24), garantías y reclamos (25), devoluciones (26),
ganancias (38) y lecturas (39).

Fuente: `modulos/21- VENTAS.sql`, seccion DETALLES_VENTA · Revisado: 14/11/2026.

### Tablas

#### DETALLES_VENTA

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

### Procedimientos almacenados

#### `SP_AGREGAR_DETALLE_VENTA(P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, P_ID_EMPLEADO, P_DESCUENTO_PCT)`

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
> garantía real es el descuento condicional del trigger (módulo 21) y, en
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

### Triggers

#### Orden declarado

| Momento | Orden |
|---|---|
| `BEFORE INSERT` | `TR_BLOQUEAR_VENTA_FINALIZADA` → `TR_VALIDAR_STOCK_DETALLE_VENTA` |
| `AFTER INSERT` | `TR_AUDITORIA_MOVIMIENTO_VENTA` → `TR_ACTUALIZAR_TOTAL_VENTA` → `TR_HISTORIAL_VENTA` (32) |
| `BEFORE UPDATE` | `TR_BLOQUEAR_UPDATE_DETALLE_VENTA` |
| `BEFORE DELETE` | `TR_BLOQUEAR_BORRADO_DETALLE_VENTA` |

> La cadena completa del `AFTER INSERT` termina en `TR_HISTORIAL_VENTA`
> (módulo 32), que anota el antes/después del stock **después** de que el total
> ya se actualizó. Está declarado con `FOLLOWS TR_ACTUALIZAR_TOTAL_VENTA`.

#### `TR_BLOQUEAR_VENTA_FINALIZADA` (`BEFORE INSERT`)

- venta inexistente → `ERROR: LA VENTA NO EXISTE.`
- venta `REALIZADA`, `CANCELADA` o `DEVUELTA` →
  `ERROR: NO SE PUEDEN AGREGAR PRODUCTOS A UNA VENTA QUE YA NO ESTA ABIERTA.`

#### `TR_VALIDAR_STOCK_DETALLE_VENTA` (`BEFORE INSERT`)

- producto sin fila en `INVENTARIO` →
  `ERROR: EL PRODUCTO NO TIENE REGISTRO EN INVENTARIO.`
- stock menor a la cantidad → `ERROR: STOCK INSUFICIENTE.`

> También es red, no garantía: lee sin candado. Si la lectura queda vieja,
> corta el descuento condicional del `AFTER INSERT` o el `1020`.

#### `TR_AUDITORIA_MOVIMIENTO_VENTA` (`AFTER INSERT`)

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

#### `TR_ACTUALIZAR_TOTAL_VENTA` (`AFTER INSERT`, `FOLLOWS` la auditoría)

`TOTAL = TOTAL + NEW.SUBTOTAL` con `@VENTAS_INTERNO = 1` y `EXIT HANDLER` que
apaga la bandera antes de `RESIGNAL` (P11).

#### `TR_BLOQUEAR_UPDATE_DETALLE_VENTA` (`BEFORE UPDATE`)

**Ninguna línea se edita**:
`ERROR: LA LINEA DE UNA VENTA NO SE PUEDE EDITAR.`
Si el cajero se equivocó, se cancela la venta y se rehace.

#### `TR_BLOQUEAR_BORRADO_DETALLE_VENTA` (`BEFORE DELETE`)

**Ninguna línea se borra**, ni siquiera `EN_PROCESO`:
`ERROR: LA LINEA DE UNA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA.`

> **Diferencia clave con compras:** allá existe `SP_QUITAR_DETALLE_COMPRA` y se
> puede sacar una línea; acá **no hay ninguna vía** para quitar o editar una
> línea. El único camino es cancelar la venta completa. Cancelar repone el stock
> pero **deja las líneas** como evidencia.

### Vistas

#### `VISTA_DETALLE_VENTA`

Líneas con `FACTURA` de la venta, nombre del producto, cantidad, precio y
subtotal. **La app no la usa.**

### Reglas de negocio

- **Un producto, una línea por venta** (UNIQUE).
- **El precio sale del maestro**, no lo elige el cajero.
- **Descuento por línea entre 0 y 100 %**, y baja también el ITBIS y la ganancia.
- **El stock se descuenta con comprobación atómica**: nunca queda negativo.
- **Las líneas no se editan ni se borran**: se cancela la venta.
- **La ganancia es un snapshot** al momento de vender; si el costo se desconoce,
  queda `NULL`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

