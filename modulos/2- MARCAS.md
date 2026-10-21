# Módulo 2 — MARCAS

Catálogo de marcas de productos. Cada marca tiene un nombre **único** y un
estado **`ACTIVA` / `INACTIVA`** (ojo: en femenino, a diferencia de casi todo
el resto de la base, que usa `ACTIVO` / `INACTIVO`). No se borran: se
desactivan con un toggle.

El módulo no declara FK: los productos referencian la marca por
`PRODUCTOS.ID_MARCA`.

Fuente: `modulos/2- MARCAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### MARCAS

Una fila por marca. Motor InnoDB (el comentario del archivo lo justifica por
FK y transacciones, aunque este archivo no declara ninguna FK).

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_MARCA` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador de la marca. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL, **UNIQUE** | Nombre visible. Único: no puede haber dos marcas iguales. |
| `ESTADO` | `ENUM('ACTIVA','INACTIVA')` | NOT NULL, DEFAULT `'ACTIVA'` | Estado operativo. **Femenino** (ver nota en el toggle). |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |

## Procedimientos almacenados

### `SP_INSERTAR_MARCA(P_NOMBRE)`

Da de alta una marca. **Usada por la app** (`marcas.cpp`).

1. Limpia el nombre con `TRIM` y colapsa espacios internos
   (`REGEXP_REPLACE(..., '[[:space:]]+', ' ')`).
2. Valida con `SIGNAL SQLSTATE '45000'`:
   - vacío → `ERROR: EL NOMBRE DE LA MARCA ES OBLIGATORIO.`
   - repetido → `ERROR: ESTA MARCA YA EXISTE.`
3. Inserta y devuelve `EXITO: MARCA "<nombre>" INSERTADA. ID: <id>`.

> **Nota:** el parámetro es `VARCHAR(50)` aunque la columna admite 100. Un
> nombre de 51 a 100 caracteres puede cortarse al entrar al SP según el
> `sql_mode`. Inconsistencia de tamaños, no un bug en uso normal.

### `SP_ACTUALIZAR_MARCA(P_ID_MARCA, P_NOMBRE)`

Cambia el nombre de una marca existente. **Usada por la app**.

- Si el ID no existe → `ERROR: LA MARCA NO EXISTE.`
- Si `P_NOMBRE` es `NULL`, conserva el actual (`COALESCE`).
- Nombre nuevo vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
- Nombre usado por otra marca (excluyendo la propia) → `ERROR: ESTA MARCA YA EXISTE.`
- Devuelve `EXITO: MARCA ID <id> ACTUALIZADA.`

### `SP_BUSCAR_MARCA(P_BUSQUEDA)`

**Usada por la app.** Con `NULL` o cadena vacía devuelve todas las marcas;
con texto busca por coincidencia parcial en `NOMBRE`
(`LIKE '%<texto>%'`). Devuelve `SELECT *`.

### `SP_TOGGLE_ESTADO_MARCA(P_ID_MARCA)`

Invierte el estado (`ACTIVA` ↔ `INACTIVA`). **Usada por la app**; es la única
forma de "borrar". Si el ID no existe → `ERROR: MARCA NO ENCONTRADA.`
Devuelve `EXITO: MARCA "<nombre>" (ID: <id>) HA SIDO <ESTADO>.`

> **Nota histórica (está en el `.sql`):** el `UPDATE` usa los literales
> femeninos (`'ACTIVA'` / `'INACTIVA'`). Con `'ACTIVO'` la columna ENUM
> devolvía `ERROR 1265` y el toggle fallaba. Por eso el ENUM femenino es
> intencional y no debe "normalizarse" sin migrar el dato.

### `2_SP_OBTENER_MARCA(P_ID)`

Devuelve la fila completa de la marca con ese ID. **La app no la llama** (no
hay `CALL` en el código).

### `2_SP_LISTAR_MARCAS(P_SOLO_ACTIVAS)`

Lista marcas: si `P_SOLO_ACTIVAS = 1`, solo las `ACTIVA`; si no, todas.
**La app no la llama** (usa `SP_LISTAR_MARCAS`).

> Las rutinas con prefijo `2_` siguen la convención de prefijo por módulo del
> repo.

### `SP_LISTAR_MARCAS()`

**Usada por la app** (`marcas.cpp:listarMarcas`). Devuelve
`ID_MARCA, NOMBRE, ESTADO` ordenado por ID.

## Datos iniciales (seed)

Al final del archivo hay **10 `CALL SP_INSERTAR_MARCA(...)`**: `ASUS`, `MSI`,
`LOGITECH`, `RAZER`, `HP`, `WESTERN DIGITAL`, `IPHONE`, `XIAOMI`, `JBL`,
`RED MAGIC`.

> **Importante:** el seed **no es idempotente**. Al reimportar sobre una base
> que ya tiene esas marcas, cada `CALL` dispara `ERROR: ESTA MARCA YA EXISTE.`
> y el import lo reporta como sentencia con error (con `--force` sigue y
> termina; la base queda bien). Es el comportamiento esperado del seed
> basado en SP, no un fallo del módulo.

## Reglas de negocio

- **Nombre único** (columna `UNIQUE` + chequeo en insertar/actualizar con
  exclusión del propio ID al editar).
- **Normalización de espacios:** todo nombre entra con `TRIM` y espacios
  internos colapsados a uno.
- **No hay borrado físico:** desactivar es el equivalente a borrar.
- **Estado en femenino** (`ACTIVA`/`INACTIVA`): no confundir con el
  `ACTIVO`/`INACTIVO` del resto de la base; el toggle depende de esos
  literales.
- **Mensajes en mayúsculas** con `SIGNAL SQLSTATE '45000'`: la UI los muestra
  tal cual.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
