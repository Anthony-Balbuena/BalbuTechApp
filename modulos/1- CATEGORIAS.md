# Módulo 1 — CATEGORIAS

Catálogo de categorías de productos. Cada categoría tiene un nombre **único**,
una descripción opcional y un ícono. No se borran: se **desactivan** con un
toggle (`ACTIVO` ↔ `INACTIVO`), así el historial de productos conserva su
categoría.

Es un módulo maestro: no tiene FK salientes ni entrantes declaradas en el
archivo (los productos la referencian por lógica de negocio).

Fuente: `modulos/1- CATEGORIAS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### CATEGORIAS

Una fila por categoría. Motor InnoDB.

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_CATEGORIA` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador de la categoría. |
| `NOMBRE` | `VARCHAR(50)` | NOT NULL, **UNIQUE** | Nombre visible en el catálogo. Único: dos categorías no pueden llamarse igual. |
| `DESCRIPCION` | `VARCHAR(100)` | NULL | Texto corto para la UI. |
| `ICONO_URL` | `VARCHAR(255)` | NULL | URL del ícono que muestra la app. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | DEFAULT `'ACTIVO'` | Estado operativo. Sin `NOT NULL`: la app siempre manda valor y el default cubre el resto. |
| `FECHA_REGISTRO` | `DATETIME` | DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |

**Índice:** `IX_NOMBRE_CATEGORIA` sobre `NOMBRE`. Nota: el `UNIQUE` de
`NOMBRE` ya crea su propio índice, así que este índice no único es redundante
(no rompe nada; candidato a limpieza si algún día se consolida el esquema).

## Procedimientos almacenados

### `SP_INSERTAR_CATEGORIA(P_NOMBRE, P_DESCRIPCION, P_ICONO)`

Da de alta una categoría. **Usada por la app** (`categorias.cpp`).

1. Limpia los textos: `TRIM` y colapsa espacios internos
   (`REGEXP_REPLACE(..., '[[:space:]]+', ' ')`).
2. Valida, en este orden, con `SIGNAL SQLSTATE '45000'`:
   - nombre vacío → `ERROR: EL NOMBRE ES OBLIGATORIO.`
   - nombre > 50 → `ERROR: EL NOMBRE NO PUEDE PASAR DE 50 CARACTERES.`
   - descripción > 100 → `ERROR: LA DESCRIPCION NO PUEDE PASAR DE 100 CARACTERES.`
   - ícono > 255 → `ERROR: EL ICONO NO PUEDE PASAR DE 255 CARACTERES.`
   - nombre repetido → `ERROR: ESTA CATEGORÍA YA EXISTE.`
3. Inserta (`ESTADO` queda en `ACTIVO` por default) y devuelve:
   `EXITO: CATEGORÍA "<nombre>" INSERTADA. ID: <id>`.

Los parámetros son **más anchos** que las columnas (`VARCHAR(200/500/500)`) a
propósito: así el texto largo entra y la rutina lo rechaza con mensaje amable en
vez de que MariaDB corte con el error técnico 1406.

### `SP_ACTUALIZAR_CATEGORIA(P_ID_CATEGORIA, P_NOMBRE, P_DESCRIPCION, P_ICONO)`

Modifica una categoría existente. **Usada por la app**.

- Si el ID no existe → `ERROR: LA CATEGORÍA NO EXISTE.`
- **Lo que llega `NULL` se conserva** (`COALESCE` por campo).
- Nombre: se limpia; si queda vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`;
  si lo usa otra categoría → `ERROR: ESTE NOMBRE YA ESTÁ EN USO.` (excluye el
  propio ID, para no marcarse como duplicada a sí misma); si > 50 →
  `ERROR: EL NOMBRE NO PUEDE PASAR DE 50 CARACTERES.`
- Descripción > 100 e ícono > 255 usan los mismos mensajes de largo que el
  insertar.
- Devuelve `EXITO: CATEGORÍA ID <id> ACTUALIZADA.`

### `SP_TOGGLE_ESTADO_CATEGORIA(P_ID_CATEGORIA)`

Invierte el estado (`ACTIVO` → `INACTIVO` y viceversa). **Usada por la app**
(es la única forma de "borrar": no hay SP de delete). Si el ID no existe →
`ERROR: CATEGORÍA NO ENCONTRADA.` Devuelve
`EXITO: CATEGORÍA "<nombre>" (ID: <id>) HA SIDO <ESTADO>.`

### `SP_BUSCAR_CATEGORIA(P_BUSQUEDA)`

**Usada por la app.** Con `NULL` o cadena vacía devuelve **todas** las
categorías; con texto busca con `LIKE '%<texto>%'` en `NOMBRE` **o**
`DESCRIPCION`. Devuelve `SELECT *`.

> **Nota:** el comentario del archivo la llama `SP_BUSCAR_CATEGORIAS` (plural),
> pero el nombre real de la rutina es singular.

### `1_SP_CATEGORIAS_POR_FECHA(P_FECHA_INICIO, P_FECHA_FIN)`

Devuelve las categorías con `FECHA_REGISTRO BETWEEN` las dos fechas (extremos
inclusive). Pensada para reportes por período. **La app no la llama** (no hay
`CALL` en el código).

### `1_SP_VERIFICAR_CATEGORIA_EXISTE(P_NOMBRE, P_ID_EXCLUIR)`

Devuelve `EXISTE` (0/1): si hay una categoría con ese nombre **ignorando** el
`P_ID_EXCLUIR`. El ID a excluir permite validar un nombre al editar sin que la
propia categoría cuente como duplicada. **La app no la llama** (la validación
de duplicados vive dentro de insertar/actualizar).

> Las rutinas con prefijo `1_` siguen la convención de prefijo por módulo que
> usa el repo en otros archivos; se conservan tal cual.

### `SP_LISTAR_CATEGORIAS()`

**Usada por la app** para poblar el listado. Devuelve solo
`ID_CATEGORIA, NOMBRE, ESTADO`, ordenado por ID.

## Reglas de negocio

- **El nombre es la clave de negocio:** `UNIQUE` en la columna y chequeo de
  duplicado en insertar/actualizar (con exclusión del propio ID al editar).
- **Normalización de espacios:** todo texto entra con `TRIM` y espacios
  internos colapsados a uno solo antes de validar y guardar.
- **Límites con mensaje:** nombre 50, descripción 100, ícono 255. Los
  parámetros de los SP son más anchos para que la validación responda con
  `SIGNAL 45000` en vez de un error técnico de truncado.
- **No hay borrado físico:** desactivar es el equivalente a borrar; el registro
  y su historial quedan.
- **Estado por default `ACTIVO`** al insertar.
- **Mensajes en mayúsculas** con `SIGNAL SQLSTATE '45000'`: la UI los muestra
  tal cual.
- **Sin `USE` hardcodeado:** el archivo deja `-- USE BALBU_TECH` comentado; la
  base la define el `--database` del import.
