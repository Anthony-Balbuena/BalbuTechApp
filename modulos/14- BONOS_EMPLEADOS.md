# Módulo 14 — BONOS_EMPLEADOS

Bonos, horas extra y bonificaciones de empleados: fecha, tipo
(`DOBLE_SUELDO`, `HORAS_EXTRA`, `BONIFICACION`), monto y estado
(`PENDIENTE`, `PAGADO`, `ANULADO`). El monto debe ser **> 0** y hay un tope de
**100000** por bono.

También es donde aterriza el **bono automático del 1%** que genera una venta
cobrada (lo crea el trigger `TR_AUTO_FINALIZAR_VENTA` del módulo 24).

**Depende de:** `EMPLEADOS` (8).

> **La app no gestiona bonos todavía** (no hay `CALL` a estos SP en el C++),
> pero los bonos de venta **sí se crean** por trigger desde el cobro.

Fuente: `modulos/14- BONOS_EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### BONOS_EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_BONO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Beneficiario. |
| `FECHA` | `DATE` | NOT NULL | Fecha del bono. |
| `TIPO_BONO` | `ENUM('DOBLE_SUELDO','HORAS_EXTRA','BONIFICACION')` | NOT NULL | Tipo. |
| `MONTO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Monto. Tope lógico 100000 (SP). |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Detalle. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta. |
| `ESTADO` | `ENUM('PENDIENTE','PAGADO','ANULADO')` | NOT NULL, DEFAULT `'PENDIENTE'` | Estado. |

**Índices:** `IX_BONO_EMPLEADO`, `IX_BONO_FECHA`, `IX_BONO_TIPO`,
`IX_BONO_ESTADO`.

**Restos de migración en el archivo:** un `SELECT * FROM BONOS_EMPLEADOS;`
suelto y un `ALTER TABLE ... MODIFY ESTADO ENUM(...) NOT NULL DEFAULT
'PENDIENTE'` idempotente. Se ejecutan en cada import (ruido, sin efecto).

## Procedimientos almacenados

### `SP_REGISTRAR_BONO(P_ID_EMPLEADO, P_FECHA, P_TIPO_BONO, P_MONTO, P_DESCRIPCION)`

- Empleado inexistente → `ERROR: EMPLEADO NO ENCONTRADO.`
- Monto `> 100000` → `ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.`
- Tipo fuera del ENUM → `ERROR: TIPO DE BONO DESCONOCIDO.`
- Inserta y devuelve
  `EXITO: BONO DE $<monto> REGISTRADO A: <nombre> (ID: <id>).`

> No valida monto `<= 0` (lo corta el CHECK con error técnico) ni fecha
> futura. Solo el trigger bloquea fechas viejas.

### `SP_ACTUALIZAR_BONO(P_ID_BONO, P_NUEVO_MONTO, P_NUEVA_DESCRIPCION)`

- ID inexistente → `ERROR: BONO NO ENCONTRADO.`
- Monto `NULL` o `<= 0` → `ERROR: EL MONTO DEBE SER MAYOR A CERO.`
- Monto `> 100000` → `ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.`
- Actualiza monto y descripción (la descripción **se pisa**, incluso con
  `NULL`: no usa `COALESCE`).
- Devuelve `EXITO: BONO ACTUALIZADO CORRECTAMENTE.`

> Si el bono ya está `PAGADO` o `ANULADO`, el trigger
> `TR_BLOQUEAR_CAMBIO_BONO` corta el update con
> `ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.`

### `SP_PAGAR_BONO(P_ID_BONO)`

- No existe → `ERROR: EL BONO NO EXISTE.`
- Ya `PAGADO` → `AVISO: ESTE BONO YA HABIA SIDO PAGADO ANTERIORMENTE.`
- `ANULADO` → `ERROR: NO SE PUEDE PAGAR UN BONO QUE ESTA ANULADO.`
- Pasa a `PAGADO` y devuelve
  `EXITO: EL BONO CON ID <id> HA SIDO MARCADO COMO PAGADO.`

### `SP_ANULAR_BONO(P_ID_BONO)`

- No existe → `ERROR: EL BONO NO EXISTE.`
- Ya `PAGADO` → `ERROR: NO SE PUEDE ANULAR UN BONO QUE YA FUE PAGADO.`
- Ya `ANULADO` → `AVISO: ESTE BONO YA ESTABA ANULADO.`
- Pasa a `ANULADO` y devuelve
  `EXITO: EL BONO CON ID <id> FUE ANULADO CORRECTAMENTE.`

### `SP_LISTAR_BONOS(P_ESTADO)`

Lista los bonos con `NOMBRE_EMPLEADO`; con estado filtra por él, con
`NULL`/vacío trae todos; ordena por fecha descendente.

## Triggers

### `TR_VALIDAR_FECHA_BONO`

`BEFORE INSERT`. Fecha anterior a `CURDATE() - 60 DAY` →
`ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 60 DÍAS.`

> El comentario del archivo documenta que se dio de baja un trigger huérfano
> de la BD viva (`14_TR_VALIDAR_FECHA_BONO`, 30 días) que tapaba a este; el
> respaldo quedó en `/tmp/opencode/backup/pre_drop_14trig.txt`.

### `TR_BLOQUEAR_CAMBIO_BONO`

`BEFORE UPDATE`. Si el bono **no** está `PENDIENTE`, no permite cambiar
`ESTADO`, `MONTO`, `TIPO_BONO` ni `ID_EMPLEADO`:
`ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.`

> El monto de un bono pagado alimenta el cierre de caja y es historia: por eso
> se congela. Un `PENDIENTE` sí se puede editar.

### Trigger eliminado: `TR_CALCULAR_BONO_VENTA`

Solo queda el `DROP`. Creaba el bono del 1% **al agregar el producto**, antes
de cobrar, y cancelar la venta no lo borraba. Ahora lo crea
`TR_AUTO_FINALIZAR_VENTA` (módulo 24) cuando se paga el total de la venta.

## Vistas

### `VISTA_TOTAL_BONOS_POR_EMPLEADO`

`ID_EMPLEADO`, `NOMBRE`, `TOTAL_BONIFICADO`, `CANTIDAD_BONOS`, para **todos**
los empleados (`LEFT JOIN`).

> **Nota:** el comentario dice que incluye a los que no tienen bonos "en
> cero", pero `SUM(B.MONTO)` sin filas devuelve **`NULL`**, no 0. Si se usa
> para reportes, conviene `IFNULL(SUM(...), 0)`. `CANTIDAD_BONOS` sí da 0.

## Reglas de negocio

- **Monto > 0** (CHECK) y **tope de 100000** por bono (SP).
- **Tipo válido** del ENUM.
- **No se cargan bonos con más de 60 días de antigüedad.**
- **Un bono pagado o anulado es inmutable.**
- **Solo un `PENDIENTE` se paga o se anula**; un pagado no se anula y un
  anulado no se paga.
- **Bono automático de venta:** 1% de la venta cobrada, creado por el trigger
  del módulo 24.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
