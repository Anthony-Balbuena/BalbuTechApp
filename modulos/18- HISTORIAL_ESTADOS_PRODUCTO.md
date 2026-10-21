# Módulo 18 — HISTORIAL_ESTADOS_PRODUCTO

Bitácora de los cambios `ACTIVO` ↔ `INACTIVO` de un producto: quién, cuándo, de
qué estado a cuál y por qué. Ningún cambio de estado queda sin rastro.

**Depende de:** `PRODUCTOS` (9) y `EMPLEADOS` (8).

> **La app no usa este módulo**: ni el SP ni la vista aparecen en el código C++.
> **Pero la tabla sí se llena**: la app cambia el estado con
> `SP_TOGGLE_ESTADO_PRODUCTOS` (9), que hace `UPDATE PRODUCTOS SET ESTADO` y
> dispara el trigger. Como nunca se llamó a este SP, las variables de sesión
> están vacías y **todas las filas quedan atribuidas al empleado `1`** con el
> motivo `'Cambio de estado automático'`.

Fuente: `modulos/18- HISTORIAL_ESTADOS_PRODUCTO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### HISTORIAL_ESTADOS_PRODUCTO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` | Producto afectado. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` | Quién hizo el cambio. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL | Estado nuevo. |
| `ESTADO_ANTERIOR` | `ENUM('ACTIVO','INACTIVO')` | NULL | Estado previo (la tabla admite nulos, el trigger nunca los manda). |
| `MOTIVO_CAMBIO` | `VARCHAR(255)` | NULL | Motivo. |
| `FECHA_CAMBIO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |

**Índices:** `HISTORIAL_ESTADOS_PRODUCTO_FECHACAMBIO` (`FECHA_CAMBIO`),
`IX_HISTORIAL_ESTADO_ACTUAL` (`ESTADO`) e `IX_HISTORIAL_ESTADO_ANTERIOR`
(`ESTADO_ANTERIOR`).

> Tres índices para una tabla que en la práctica solo se lee ordenada por fecha.
> Los dos del estado son de baja selectividad: con dos valores posibles, el
> optimizador casi nunca los va a preferir.

## Procedimientos almacenados

### `18_SP_CAMBIAR_ESTADO_PRODUCTO(P_ID_PRODUCTO, P_ID_EMPLEADO, P_NUEVO_ESTADO, P_MOTIVO)`

**La app no lo llama.** Deja el empleado y el motivo en variables de sesión,
hace el `UPDATE` de `PRODUCTOS.ESTADO` y después **limpia** esas variables. El
trigger del módulo lee de ahí.

> **Es el único camino que deja un historial con datos útiles**, y aun así no
> valida nada: producto inexistente devuelve éxito silencioso (el `UPDATE`
> afecta 0 filas), empleado inexistente termina en el `1452` del FK del trigger,
> y cambiar al mismo estado **no escribe historial ni avisa**. **La app no lo
> llama**: el cambio de estado real pasa por `SP_TOGGLE_ESTADO_PRODUCTOS` (9), que
> no setea estas variables.
>
> **No hay `EXIT HANDLER`:** si el `UPDATE` falla, las variables de sesión quedan
> prendidas con el último empleado y motivo, y el próximo cambio de estado por
> otro camino los hereda. Es el mismo patrón riesgoso que `@VENTAS_INTERNO` y
> `@COMPRAS_INTERNO`.
>
> **Sin mensaje de confirmación**: no devuelve fila, ni siquiera un `EXITO`.

## Triggers

### `TR_LOG_CAMBIO_ESTADO_PRODUCTO` (`AFTER UPDATE ON PRODUCTOS`)

Solo si `OLD.ESTADO <> NEW.ESTADO`, inserta la fila con `ESTADO = NEW.ESTADO`,
`ESTADO_ANTERIOR = OLD.ESTADO`, el empleado de la variable de sesión y el motivo.

> **Dos valores de relleno peligrosos:**
> - sin variable, el empleado queda en **`1` hardcodeado**
>   (`IFNULL(@ID_EMPLEADO_ACTUAL, 1)`): si el empleado 1 no existe, el `INSERT`
>   revienta por FK y **el `UPDATE` del producto se cae con él**;
> - sin motivo, queda `'Cambio de estado automático'`, que se confunde con un
>   cambio real hecho por el sistema.
>
> Un `UPDATE PRODUCTOS SET ESTADO = ...` directo **sí pasa** por el trigger: no
> hay candado de estado, a diferencia de compras y ventas.

## Vistas

### `VISTA_ULTIMOS_MOVIMIENTOS`

Los **10** cambios más recientes: `FECHA_CAMBIO`, `PRODUCTO` y `MOTIVO_CAMBIO`.
Usa `JOIN` a `PRODUCTOS`, así que un producto borrado (imposible por FK) quedaría
fuera. **La app no la usa.**

## Reglas de negocio

- **Cada cambio de estado deja una fila**, venga del SP o de un `UPDATE` directo.
- **El empleado responsable sale de una variable de sesión**, con `1` como relleno.
- **El motivo es opcional** y se rellena con un texto genérico.
- **Cambiar al mismo estado no registra nada ni avisa.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
