# Módulo 24 — PAGOS

Cada cobro recibido por una venta: cuánto, cuándo, con qué método y **quién
cobró**. Puede haber varios pagos por venta (parciales o completos) y, cuando la
suma cubre el bruto, **la venta pasa sola a `REALIZADA`** y nace el bono del 1 %.

**Depende de:** `VENTAS` (21), `DETALLES_VENTA` (23), `METODOS_PAGO` (4),
`EMPLEADOS` (8), `DEVOLUCIONES` (26) y `BONOS_EMPLEADOS` (14).
**Es usado por:** `ventas.cpp` (cobro, anulación, listado, cierre de caja y
reporte del período).

> **Este archivo también aloja los reportes de ventas** (`SP_REPORTE_VENTAS`,
> `SP_CIERRE_CAJA`, `SP_REPORTE_PERIODO`), movidos desde el viejo
> `37- REPORTES_VENTAS.sql` el 12/10/2026: leen `PAGOS`, así que viven en este
> flujo. Los nombres de SP y vista **no cambiaron**.

Fuente: `modulos/24- PAGOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## El concepto que manda: se cobra el BRUTO

```
BRUTO = VENTAS.TOTAL
      + SUM(DETALLES_VENTA.MONTO_ITBIS)
      - SUM(DEVOLUCIONES.MONTO_ITBIS_REEMBOLSADO
            de las devoluciones APROBADA o REEMBOLSADA)
```

`VENTAS.TOTAL` guarda la **base** (suma de subtotales, ya con descuento de
línea); el ITBIS se suma al cobrar y el ITBIS devuelto se resta. Es el mismo
bruto de `VISTA_VENTA_CON_IVA` (43) y de `SP_REPORTE_PERIODO`.

> **Solo se resta el ITBIS devuelto, no el subtotal devuelto.** Devolver
> mercancía **no baja** `VENTAS.TOTAL` (ningún trigger lo recalcula): al cerrar
> el cobro se sigue exigiendo la base completa. En la práctica no estalla porque
> las devoluciones se registran sobre ventas ya `REALIZADA` (cobradas), pero es
> una asimetría real frente a compras, donde la devolución **sí** baja el `TOTAL`.
>
> La fórmula del bruto está **duplicada en 6 lugares**: `SP_ANULAR_PAGO` y los
> 5 triggers de `PAGOS`. `24_SP_REGISTRAR_PAGO` no la calcula: delega el tope en
> `TR_VALIDAR_MONTO_PAGO`.

## Tablas

### PAGOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PAGO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_VENTA` | `INT` | NOT NULL, FK → `VENTAS` **ON DELETE CASCADE** | Venta cobrada. |
| `ID_METODO_PAGO` | `INT` | NOT NULL, FK → `METODOS_PAGO` | Método. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | **Quién cobró** (P8, 06/10/2026). |
| `MONTO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Lo que **se aplica** a la venta. |
| `MONTO_RECIBIDO` | `DECIMAL(10,2)` | NULL, CHECK `>= MONTO` | Lo que el cliente **entregó**, para el vuelto (P9, 07/10/2026). |
| `FECHA` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |

**Índice:** `IX_PAGOS_FECHA` (reportes de caja y cierre del día). El acceso por
venta ya lo cubre el índice del FK.

> **`MONTO` ≠ `MONTO_RECIBIDO`.** `MONTO` salda la venta; si el cliente entrega
> 500 por un total de 320, `MONTO = 320` y `MONTO_RECIBIDO = 500`. El `CHECK`
> impide recibir menos de lo cobrado; `NULL` significa "no aplica".
>
> La FK `ON DELETE CASCADE` es letra muerta: las ventas no se borran.

## Procedimientos almacenados

### `24_SP_REGISTRAR_PAGO(P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO, P_ID_EMPLEADO, P_MONTO_RECIBIDO)`

**Usada por la app** (`ventas.cpp`). Sin parámetro de salida: devuelve una fila
de mensaje.

1. venta inexistente → `ERROR: LA VENTA NO EXISTE.`
2. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
3. método inexistente → `ERROR: EL METODO DE PAGO NO EXISTE.`
4. monto nulo o `<= 0` → `ERROR: EL MONTO DEBE SER MAYOR A CERO.`
5. `MONTO_RECIBIDO` menor al monto → `ERROR: EL MONTO RECIBIDO ES MENOR QUE EL PAGO.`

Inserta con `MONTO_RECIBIDO = IFNULL(param, MONTO)` y devuelve
`EXITO: TOTAL A PAGAR <monto>, RECIBIDO <recibido>, DEVUELTO <vuelto>. REGISTRADO POR EL EMPLEADO: <nombre>`.

> **El estado y el tope no los mira el SP**, los mira el trigger
> `TR_VALIDAR_MONTO_PAGO` dentro del mismo `INSERT`. Separación deliberada:
> validaciones de datos en el SP, reglas de negocio en el candado.
>
> **No lleva `DEFAULT`:** MariaDB no soporta valores por defecto en parámetros
> de procedures; la app manda siempre los 5 argumentos.
>
> **No abre transacción ni bloquea la venta:** es un solo `INSERT` y el cierre
> automático ocurre en un trigger de la misma sentencia.

### `SP_ANULAR_PAGO(P_ID_PAGO, P_ID_EMPLEADO)`

**Usada por la app** (`ventas.cpp`). Es el **único camino** para deshacer un
cobro.

1. empleado inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
2. pago inexistente → `ERROR: EL PAGO NO EXISTE.`
3. venta `CANCELADA`/`DEVUELTA` (o inexistente) →
   `ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).`
4. **Borra** el pago y recalcula lo cobrado.
5. Si estaba `REALIZADA` y dejó de estarlo: la vuelve a `EN_PROCESO` y borra el
   bono `PENDIENTE` de esa venta
   (`DESCRIPCION = 'Comisión por venta #<id>'`).
6. Devuelve `EXITO: PAGO #<id> ANULADO (<monto>). COBRADO DE LA VENTA #<id>: <pagado>`
   (+ ` - SE RETIRO EL BONO DEL 1%` si lo quitó).

> **Transacción propia:** abre una solo si `@@in_transaction = 0`; anidada no la
> cierra y deja decidir al de arriba. El `EXIT HANDLER` hace `ROLLBACK` solo en
> el caso propio, con `RESIGNAL`.
>
> **Bono ya aprobado no se toca:** solo borra el `PENDIENTE`; si nómina ya lo
> pagó, se deja y lo resuelve nómina.
>
> **Borrado físico**, no anulación lógica: el rastro queda en
> `HISTORIAL_ESTADOS_VENTA`, no del pago.
>
> Con la venta reabierta y sin pagos, ya califica para `SP_CANCELAR_VENTA`
> (ese era el bloqueo del paso 3 de allá).

## Triggers

### `TR_VALIDAR_MONTO_PAGO` (`BEFORE INSERT`)

El **freno de la cadena de cobro**:
- venta distinta de `EN_PROCESO` →
  `ERROR: LA VENTA NO ESTA ABIERTA PARA RECIBIR PAGOS.`
- `cobrado + nuevo > BRUTO` →
  `ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.`

> **Nunca mira `MONTO_RECIBIDO`**: el vuelto no afecta el tope, solo `MONTO`.
>
> **Exige `EN_PROCESO`, no "distinto de cancelada"**: una venta ya `REALIZADA`
> tampoco acepta un segundo pago, ni siquiera uno de 0.

### `TR_AUTO_FINALIZAR_VENTA` (`AFTER INSERT`)

El **cierre de la cadena**: si la venta está `EN_PROCESO` y `cobrado >= BRUTO`,
la pasa a `REALIZADA` y en el mismo instante inserta en `BONOS_EMPLEADOS`:
`TIPO_BONO = 'BONIFICACION'`, `MONTO = ROUND(SUBTOTAL × 0,01, 2)`,
`DESCRIPCION = 'Comisión por venta #<id>'`, `ESTADO = 'PENDIENTE'`.

> **El bono es sobre el `SUBTOTAL`, no sobre el bruto** (sin ITBIS), y a nombre
> del **empleado de la venta**, no del que cobra.
>
> **Antídoto contra el doble bono:** la condición `V_ESTADO = 'EN_PROCESO'`; un
> pago extra ya no vuelve a crearlo.
>
> **Nace al cobrar, no al vender**: agregar productos no genera bono.

### `TR_VALIDAR_BORRADO_PAGO` (`BEFORE DELETE`)

Solo deja borrar con la venta en `EN_PROCESO` o `REALIZADA`; si está
`CANCELADA`, `DEVUELTA` o no existe:
`ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).`

### `TR_RECALCULAR_ESTADO_PAGO_BORRADO` (`AFTER DELETE`)

Recalcula el bruto y mueve el estado **en los dos sentidos**: reabre si estaba
`REALIZADA` y dejó de estarlo (borrando el bono pendiente), y cierra con bono si
quedó cubierta. Mismo trabajo que `SP_ANULAR_PAGO`, a propósito: vale también
para un `DELETE` directo.

### `TR_VALIDAR_UPDATE_PAGO` (`BEFORE UPDATE`)

Un pago **no cambia de venta** (`ERROR: EL PAGO NO CAMBIA DE VENTA.`), no admite
venta `CANCELADA`/`DEVUELTA` y no permite que la suma con el cambio aplicado
(`cobrado − OLD.MONTO + NEW.MONTO`) supere el bruto
(`ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.`).

> No revalida el signo: de eso se encarga el `CHECK MONTO > 0` de la tabla.

### `TR_RECALCULAR_ESTADO_PAGO_UPDATE` (`AFTER UPDATE`)

Solo si cambió `MONTO`. Cierra con bono cuando la venta queda cubierta y reabre
(borrando el bono pendiente) cuando deja de estarlo, para que un `UPDATE` directo
no deje la venta mintiendo.

## Vistas

### `VISTA_RESUMEN_PAGOS`

Pago con nombre del método, empleado que cobró, monto, recibido, **vuelto**
(`MONTO_RECIBIDO − MONTO`) y fecha.

> Usa `JOIN` (no `LEFT JOIN`): un pago con método o empleado inexistente
> desaparecería del resumen. Los FK lo impiden, así que en la práctica es
> completo. **La app no la usa.**

## Reportes (movidos del 37)

### `SP_REPORTE_VENTAS(P_FECHA_INICIO, P_FECHA_FIN)`

**Usada por la app.** Listado de ventas del rango (día final **completo**,
`< fin + 1 día`), leído de `VW_REPORTE_VENTAS` (43), del más reciente al más
viejo. Rango invertido → `ERROR: LA FECHA INICIAL NO PUEDE SER MAYOR A LA FINAL.`

> No valida nulos: con `NULL` el `WHERE` no devuelve nada y el `SIGNAL` no
> dispara (la comparación da `NULL`).

### `SP_CIERRE_CAJA(P_FECHA)`

**Usada por la app.** Cierre de **un día**, con **3 result sets**:
1. **Resumen:** `VENTAS_DEL_DIA`, `MONTO_REALIZADO` (solo `REALIZADA`, a bruto)
   y `COBRADO` (suma de `PAGOS` del día, sin importar la venta).
2. **Por estado:** `ESTADO`, `CANTIDAD`, `MONTO` (a bruto).
3. **Por método de pago:** `METODO`, `OPERACIONES`, `COBRADO`, de mayor a menor.

- `P_FECHA` nula → `ERROR: INGRESE LA FECHA DEL CIERRE.`

> **No cuadra una caja física:** `COBRADO` suma **todos** los pagos de la
> ventana de tiempo, sin filtrar por turno ni por caja. El turno real vive en
> `TURNO_CAJA` (41), que tiene su propio cuadre.
>
> `MONTO_REALIZADO` y `COBRADO` pueden no coincidir aunque todo cuadre: una
> venta de ayer cobrada hoy cae en días distintos.

### `SP_REPORTE_PERIODO(P_DESDE, P_HASTA)`

**Usada por la app.** Ventas `REALIZADA` en un rango **inclusive** por
`DATE(FECHA)`. Una fila: `TRANSACCIONES`, `SUBTOTAL`, `ITBIS` (líneas **menos**
ITBIS devuelto) y `BRUTO`.

- fechas nulas → `ERROR: DEBE INDICAR DESDE Y HASTA.`
- `DESDE > HASTA` → `ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.`

> Es el espejo exacto de `SP_REPORTE_PERIODO_COMPRA` (19). No devuelve
> ganancia: eso es `38- GANANCIAS.sql`.

## Reglas de negocio

- **Se cobra el BRUTO** (base + ITBIS − ITBIS devuelto).
- **`REALIZADA` es automática** al cubrir el bruto, y se revierte sola si deja de
  estarlo.
- **El bono del 1 % nace con la venta cerrada**, sobre el subtotal, y se borra si
  la venta se reabre y el bono sigue `PENDIENTE`.
- **`MONTO` es lo aplicado; `MONTO_RECIBIDO` lo entregado**; el vuelto sale de la
  diferencia.
- **Solo una venta `EN_PROCESO` recibe pagos.**
- **Un pago se anula borrándolo**, y solo pasa por `SP_ANULAR_PAGO` o un `DELETE`
  con la venta viva.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
