# Módulo 21 — VENTAS

Cabecera de cada venta: quién la atendió, a qué cliente, cuándo y cuánto. Los
productos van en `DETALLES_VENTA` (23), los cobros en `PAGOS` (24) y las
devoluciones en `DEVOLUCIONES` (26).

**Depende de:** `EMPLEADOS` (8) y `CLIENTES` (7).
**Es usado por:** detalle (23), pagos (24), garantías (25), devoluciones (26),
reclamos (27), ganancias (38) y lecturas (39).

Fuente: `modulos/21- VENTAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

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

## Limpiezas incluidas (solo `DROP`)

| Objeto | Por qué |
|---|---|
| `21_SP_AGREGAR_PRODUCTO_VENTA` | Duplicaba `SP_AGREGAR_DETALLE_VENTA` (23) **sin** validar dueño de la venta. |
| `TR_CALCULAR_TOTAL_VENTA` | Duplicaba `TR_ACTUALIZAR_TOTAL_VENTA` (23): el total se aplicaba dos veces. |
| `TR_PROCESAR_VENTA` | Duplicaba la auditoría de movimiento (20): stock y `ENTRADA` dobles. |

## Movidos a otros archivos

- `HISTORIAL_ESTADOS_VENTA` y sus dos triggers → **21.5**.
- `VISTA_DETALLE_VENTA` → **23**.

## Reglas de negocio

- **Toda venta nace `EN_PROCESO` con total 0** (vía SP).
- **`REALIZADA` exige cobro del 100%** (validado por trigger, no solo por SP).
- **Cancelar devuelve todo el stock** y exige cero pagos registrados.
- **Solo el dueño de la venta puede cancelarla.**
- **`DEVUELTA` exige que no quede ni una unidad.**
- **La factura es única por cliente.**
- **Las ventas no se borran nunca.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
