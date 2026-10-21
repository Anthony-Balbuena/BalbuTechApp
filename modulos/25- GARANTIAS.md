# Módulo 25 — GARANTIAS

La garantía de cada producto vendido: desde cuándo, hasta cuándo y en qué estado.
**Una sola garantía por línea de venta**, con fecha final siempre posterior a la
inicial.

**Depende de:** `DETALLES_VENTA` (23).
**Es usado por:** `reclamos de garantía` (27) y `ventas.cpp` (alta y consulta).

> **Este archivo aloja además un SP de devoluciones** (`26_SP_RECHAZAR_DEVOLUCION`),
> que por nombre y por tema pertenece al módulo **26**. Funciona, pero vive lejos
> de su tabla.

Fuente: `modulos/25- GARANTIAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### GARANTIAS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_GARANTIA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_DETALLE_VENTA` | `INT` | NOT NULL, FK → `DETALLES_VENTA` **ON DELETE CASCADE** | Línea garantizada. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Desde cuándo corre. |
| `FECHA_FIN` | `DATE` | NOT NULL | Hasta cuándo corre. |
| `ESTADO` | `ENUM('ACTIVA','VENCIDA','CANCELADA')` | NOT NULL, DEFAULT `'ACTIVA'` | Estado. |

**Restricciones:** `UQ_GARANTIA_DETALLE` UNIQUE (`ID_DETALLE_VENTA`) — una
garantía por línea — y `CK_GARANTIA_FECHAS` CHECK (`FECHA_FIN > FECHA_INICIO`).

**Índices:** `IX_GARANTIA_INICIO`, `IX_GARANTIA_FIN` (las que están por vencer o
ya vencieron) e `IX_GARANTIA_ESTADO` (las vigentes).

> **`VENCIDA` nunca se escribe.** Ningún módulo del repo pasa una garantía a
> `VENCIDA`: la vigencia real se decide comparando `FECHA_FIN` con la fecha de
> hoy. El valor del `ENUM` existe, pero es decorativo.
>
> La FK `ON DELETE CASCADE` es letra muerta: las líneas de venta no se borran.

## Procedimientos almacenados

### `SP_REGISTRAR_GARANTIA(P_ID_DETALLE_VENTA, P_DIAS_VALIDEZ)`

**Usada por la app** (`ventas.cpp`). Crea la garantía **contando desde hoy**.

1. detalle inexistente → `ERROR: EL DETALLE DE VENTA NO EXISTE.`
2. línea ya garantizada → `ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.`
3. Inserta con `FECHA_INICIO = CURRENT_DATE` y
   `FECHA_FIN = CURRENT_DATE + P_DIAS_VALIDEZ`.
4. Devuelve `EXITO` / `GARANTÍA REGISTRADA CON ÉXITO.` / `ID_GENERADO`.

> **Carrera cubierta:** las dos sesiones pasan el `COUNT`, pero
> `UQ_GARANTIA_DETALLE` corta a la segunda. Patrón correcto: validar + confiar
> en el índice.
>
> **`P_DIAS_VALIDEZ` no se valida.** Con `0` la fecha final queda **igual** al
> inicio y el `CHECK CK_GARANTIA_FECHAS` aborta con error técnico; con un valor
> negativo, lo mismo. Con `NULL`, el `NOT NULL` de `FECHA_FIN` lo corta. Ningún
> camino devuelve un mensaje amigable.

### `26_SP_RECHAZAR_DEVOLUCION(P_ID_DEVOLUCION, P_MOTIVO_RECHAZO)`

**Usada por la app** (`ventas.cpp`), pero **opera sobre `DEVOLUCIONES`** (26).

1. devolución inexistente → `ERROR: LA DEVOLUCIÓN NO EXISTE.`
2. estado distinto de `PENDIENTE` →
   `ERROR: SOLO SE PUEDEN RECHAZAR DEVOLUCIONES EN ESTADO PENDIENTE.`
3. Deja `ESTADO = 'RECHAZADA'` y **concatena** el motivo:
   `<motivo original> | RECHAZO: <motivo>`. Si el original era `NULL`, guarda
   solo el rechazo (P12, 07/10/2026).

> **Por qué existe este SP:** es la alternativa al paso 3 de
> `25_SP_PROCESAR_DEVOLUCION` (26), que cambia el estado **sin anotar motivo**.
> Rechazar **libera la cuota** (las `RECHAZADA` no cuentan para el tope) y su
> fila **sí se puede borrar** (`TR_BLOQUEAR_BORRADO` solo frena `APROBADA` y
> `REEMBOLSADA`).
>
> **Sin motivo, el motivo se pierde:** `CONCAT('RECHAZO: ', NULL)` da `NULL`, así
> que un `P_MOTIVO_RECHAZO` nulo deja `MOTIVO` en `NULL` en vez de anotar algo.
> No se valida que venga.

## Triggers

### `TR_VALIDAR_FECHAS_GARANTIA` (`BEFORE INSERT`)

Si `FECHA_INICIO` viene en el pasado, **la corrige a hoy en silencio** (no
devuelve error). Es el **único** candado del flujo que autocorrige en vez de
cortar: un inicio pasado nunca queda grabado, pero tampoco se avisa.

## Movidos a otros archivos

- `VISTA_DEVOLUCIONES_PENDIENTES` → **26**.

## Reglas de negocio

- **Una garantía por línea de venta** (UNIQUE).
- **La fecha final siempre es posterior al inicio** (CHECK).
- **La garantía arranca hoy**, no en la fecha de la venta.
- **Un inicio en el pasado se corrige solo**, sin avisar.
- **`VENCIDA` no lo escribe nadie**: la vigencia se evalúa por fecha.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
