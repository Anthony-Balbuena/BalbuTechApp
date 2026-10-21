# Módulo 4 — METODOS_PAGO

Catálogo de métodos de pago (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`,
`DEPOSITO`, ...). El nombre es **único** y no puede quedar vacío. No se
borran: se desactivan con un toggle.

Lo consumen la caja de ventas y la de compras para armar el selector de pago.

Fuente: `modulos/4-METODOS_PAGO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### METODOS_PAGO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_METODO_PAGO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador del método. |
| `NOMBRE` | `VARCHAR(50)` | NOT NULL, **UNIQUE** | Nombre visible en los selects. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo. |

**Restricción:** `CK_METODO_NOMBRE` → `CHAR_LENGTH(TRIM(NOMBRE)) > 0` (un
nombre de solo espacios no entra ni por SQL directo).

**Migración incluida:** `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ESTADO ...`
(P-auditoria #2). Es idempotente y existe para bases viejas creadas sin la
columna; en una base fresca no hace nada. El toggle y la app la exigen
`NOT NULL`.

> **Nota:** el `SELECT` de `SP_INSERTAR_METODO_PAGO` no incluye `ESTADO`;
> después del `ALTER`, una base migrada arranca con el default `'ACTIVO'`.

## Procedimientos almacenados

### `SP_INSERTAR_METODO_PAGO(P_NOMBRE)`

**Usada por la app** (`metodos_pago.cpp`).

1. Limpia el nombre (`TRIM` + colapso de espacios internos).
2. Valida con `SIGNAL 45000`:
   - vacío → `ERROR: EL NOMBRE DEL MÉTODO DE PAGO ES OBLIGATORIO.`
   - repetido → `ERROR: ESTE MÉTODO DE PAGO YA EXISTE.`
3. Inserta y devuelve
   `EXITO: MÉTODO DE PAGO "<nombre>" INSERTADO. ID: <id>`.

### `SP_ACTUALIZAR_METODO_PAGO(P_ID_METODO, P_NOMBRE)`

**Usada por la app.**

- ID inexistente → `ERROR: EL MÉTODO DE PAGO NO EXISTE.`
- `P_NOMBRE` `NULL` → conserva el actual (`COALESCE`).
- Nombre vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
- Nombre usado por otro método → `ERROR: ESTE MÉTODO YA EXISTE.`
- Devuelve `EXITO: MÉTODO DE PAGO ID <id> ACTUALIZADO.`

### `SP_LISTAR_METODOS_PAGO()`

Devuelve `ID_METODO_PAGO, NOMBRE` **ordenado por ID**. La usan
`ventas.cpp` y `compras.cpp` para llenar los selects de pago.

> **Nota:** el comentario del archivo dice "ordenados por nombre", pero el
> `ORDER BY` real es por `ID_METODO_PAGO ASC` (orden de alta).

### `SP_BUSCAR_METODOS_PAGO(P_BUSQUEDA)`

**Usada por la app** (`metodos_pago.cpp`). Con `NULL` o vacío devuelve todos;
con texto, `LIKE '%<texto>%'` sobre `NOMBRE`. Devuelve
`ID_METODO_PAGO, NOMBRE` **ordenado por ID** (el comentario del código marca
ese orden como intencional: la UI muestra 1, 2, 3...).

### `SP_TOGGLE_ESTADO_METODO_PAGO(P_ID_METODO)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`; es la única forma de
"borrar". ID inexistente → `ERROR: MÉTODO DE PAGO NO ENCONTRADO.` Devuelve
`EXITO: MÉTODO "<nombre>" (ID: <id>) HA SIDO <ESTADO>.`

> **Nota:** a diferencia de las otras rutinas del archivo, esta **no** tiene
> `DROP PROCEDURE IF EXISTS` antes del `CREATE`. En una base existente un
> reimporte sin recrear la base fallaría con "procedure already exists"; el
> import normal recrea el esquema, así que no afecta.

## Datos iniciales (seed)

Al final hay **4 `CALL SP_INSERTAR_METODO_PAGO(...)`**: `EFECTIVO`,
`TARJETA`, `TRANSFERENCIA`, `DEPOSITO`.

> **No idempotente:** al reimportar sobre una base que ya los tiene, cada
> `CALL` responde `ERROR: ESTE MÉTODO DE PAGO YA EXISTE.` y el import lo
> reporta como sentencia con error (con `--force` continúa).

## Reglas de negocio

- **Nombre único** (`UNIQUE` + chequeo en insertar/actualizar excluyendo el
  propio ID).
- **Nombre no vacío** aun por SQL directo (`CK_METODO_NOMBRE`).
- **Normalización de espacios** antes de validar y guardar.
- **No hay borrado físico:** solo toggle de estado.
- **Mensajes en mayúsculas** vía `SIGNAL SQLSTATE '45000'`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
