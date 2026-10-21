# Módulo 9 — PRODUCTOS

Catálogo central de productos: nombre, descripción, precio de venta y de
compra, código único, marca, categoría, proveedor preferido e imagen. Es el
módulo del que cuelga medio sistema: inventario, compras, ventas, garantías y
devoluciones lo referencian.

**Depende de:** `MARCAS` (2), `CATEGORIAS` (1) y `PROVEEDORES` (5), por FK.
**Es referenciado por:** `INVENTARIO` (17), `DETALLE_COMPRA` (22),
`DETALLE_VENTA` (23), `PRODUCTO_PROVEEDOR` (40), entre otros.

Fuente: `modulos/9- PRODUCTOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### PRODUCTOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PRODUCTO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL | Nombre visible. |
| `DESCRIPCION` | `VARCHAR(255)` | NOT NULL | Descripción. El SP exige mínimo 10 caracteres. |
| `PRECIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Precio de **venta**. |
| `P_COMPRA` | `DECIMAL(10,2)` | NOT NULL, DEFAULT `0.00`, CHECK `>= 0` | Precio de **compra**. Nace en 0 = pendiente de cargar el real. |
| `CODIGO` | `VARCHAR(20)` | NOT NULL, **UNIQUE** | Código/barcode. Se normaliza a mayúsculas. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo. |
| `FECHA_CREACION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |
| `ID_MARCA` | `INT` | NOT NULL, FK → `MARCAS` | Marca. |
| `ID_CATEGORIA` | `INT` | NOT NULL, FK → `CATEGORIAS` | Categoría. |
| `ID_PROVEEDOR` | `INT` | NOT NULL, FK → `PROVEEDORES` | Proveedor **preferido** (el mapa completo vive en `PRODUCTO_PROVEEDOR`). |
| `IMAGEN` | `VARCHAR(255)` | NULL | URL/ruta de imagen. (La BD viva la tenía como `IMAGEN`; se unificó con ese nombre.) |

**Restricciones de tabla:**
- `UQ_PRODUCTO_NOMBRE_MARCA` UNIQUE (`NOMBRE`, `ID_MARCA`): no se repite el
  nombre dentro de la misma marca.
- `FK_PRODUCTO_MARCA`, `FK_PRODUCTO_CATEGORIA`, `FK_PRODUCTO_PROVEEDOR`.

**Índices:** `IX_PRODUCTOS_MARCA` y `IX_PRODUCTOS_CATEGORIA` para listados y
reportes por marca/categoría.

## Procedimientos almacenados

### `SP_INSERTAR_PRODUCTO(P_NOMBRE, P_DESCRIPCION, P_COMPRA, P_PRECIO, P_CODIGO, P_ID_MARCA, P_ID_CATEGORIA, P_ID_PROVEEDOR, P_IMAGEN)`

**Usada por la app** (`productos.cpp`, `compras.cpp`).

**Limpieza:** nombre y descripción `TRIM` + colapso de espacios; código
`UPPER(TRIM(...))`.

**Validaciones en orden (`SIGNAL 45000`):**
1. proveedor `NULL` → `ERROR: DEBE INDICAR ID_PROVEEDOR.`
2. proveedor inexistente → `ERROR: EL PROVEEDOR NO EXISTE.`
3. marca inexistente → `ERROR: LA MARCA NO EXISTE.`
4. categoría inexistente → `ERROR: LA CATEGORÍA NO EXISTE.`
5. código repetido → `ERROR: EL CÓDIGO YA ESTÁ REGISTRADO EN OTRO PRODUCTO.`
6. nombre repetido en la misma marca →
   `ERROR: YA EXISTE UN PRODUCTO CON ESE NOMBRE EN ESA MARCA.`
7. precio `NULL` o `<= 0` → `ERROR: EL PRECIO DEBE SER MAYOR A CERO.`
8. precio de compra `NULL` o negativo → se normaliza a 0; solo rechaza
   `ERROR: EL PRECIO DE COMPRA NO PUEDE SER NEGATIVO.`
9. nombre vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
10. descripción de menos de **10** caracteres →
    `ERROR: DESCRIPCIÓN DEMASIADO CORTA (MÍNIMO 10 CARACTERES).`

Inserta y devuelve
`EXITO: PRODUCTO "<nombre>" REGISTRADO CORRECTAMENTE.` (sin ID).

> **Nota:** el mínimo de descripción se mide con `LENGTH()` (bytes), no con
> `CHAR_LENGTH()`: un texto con acentos cuenta más de un byte por letra.

### `SP_ACTUALIZAR_PRODUCTOS(P_ID_PRODUCTO, P_NOMBRE, P_DESCRIPCION, P_PRECIO, P_CODIGO, P_ID_MARCA, P_ID_CATEGORIA, P_ID_PROVEEDOR, P_IMAGEN, P_COSTO)`

**Usada por la app** (`productos.cpp`, `inventario.cpp`). Actualización
parcial: todo parámetro `NULL` conserva el valor actual (`COALESCE`).

- ID inexistente → `ERROR: EL PRODUCTO NO EXISTE.`
- Nombre vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
- Descripción vacía (`''`) → se trata como "no enviada" y **conserva** la
  anterior; entre 1 y 9 caracteres →
  `ERROR: DESCRIPCION DEMASIADO CORTA (MINIMO 10 CARACTERES).`
- Código de otro producto → `ERROR: ESTE CÓDIGO YA PERTENECE A OTRO PRODUCTO.`
- Precio `<= 0` → `ERROR: EL PRECIO DEBE SER MAYOR A CERO.`
- Costo negativo → `ERROR: EL PRECIO DE COMPRA NO PUEDE SER NEGATIVO.`
- Marca/categoría/proveedor inexistente → los mismos mensajes del alta.
- Nombre duplicado en la marca **efectiva** (combinando lo enviado y lo
  actual) → `ERROR: YA EXISTE OTRO PRODUCTO CON ESE NOMBRE EN ESA MARCA.`
- Devuelve `EXITO: EL PRODUCTO "<nombre>" FUE ACTUALIZADO. (CÓDIGO: <código>)`.

### `SP_TOGGLE_ESTADO_PRODUCTOS(P_ID_PRODUCTO)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`. ID inexistente →
`ERROR: EL PRODUCTO NO EXISTE.` Devuelve
`PRODUCTO: "<nombre>" - CAMBIO DE: <estado anterior> A: <estado nuevo>`
(no usa el prefijo `EXITO:`).

### `SP_CONSULTAR_PRODUCTOS_FILTRADO(P_BUSQUEDA)`

**Usada por la app** (`productos.cpp`, `ventas.cpp`, `compras.cpp`,
`inventario.cpp`). Devuelve
`ID_PRODUCTO, CODIGO, NOMBRE, MARCA, CATEGORIA, PRECIO, P_COMPRA, ESTADO,
STOCK, PROVEEDOR, ID_PROVEEDOR`, ordenado por ID.

- Sin filtro → todos.
- Texto → `LIKE` por nombre, **código exacto** o ID numérico
  (`REGEXP '^[0-9]+$'`).
- `STOCK` sale de `LEFT JOIN INVENTARIO`: un producto sin fila de inventario
  aparece con `STOCK` `NULL`, no con 0.

### `SP_CONSULTAR_INVENTARIO(P_FILTRO)`

**Usada por la app** (`productos.cpp`, `ventas.cpp`, `compras.cpp`). Lista
solo productos **`ACTIVO`** con stock, mínimo, ubicación, precio y costo.
Filtra por nombre, código, categoría o ID numérico.

Calcula `ESTATUS_STOCK`:
- `IFNULL(STOCK_ACTUAL, 0) = 0` → **`AGOTADO`** (incluye productos sin fila
  de inventario);
- `STOCK_ACTUAL <= STOCK_MINIMO` → **`CRÍTICO`**;
- `STOCK_ACTUAL <= STOCK_MINIMO * 2` → **`STOCK BAJO`**;
- resto → **`OK`**.

### `SP_REPORTE_STOCK_CRITICO()`

**Usada por la app** (`productos.cpp`). Lista los productos con
`STOCK_ACTUAL <= STOCK_MINIMO`, con `CANTIDAD_FALTANTE = STOCK_MINIMO -
STOCK_ACTUAL`, del más urgente al menos. Solo lee de `INVENTARIO` (un producto
sin fila no aparece en este reporte).

### `PARA_INSERTAR_PRODUCTO()`

**Usada por la app** (`productos.cpp`, `compras.cpp`) para llenar los selects
del alta. Devuelve **3 result sets** en orden: categorías, marcas y
proveedores (todos ordenados por ID).

> **Nota:** el archivo tiene un comentario `/*Este procedure lo quite para
> mejorarlo*/` justo arriba del `CREATE`, pero la rutina **sí existe** y está
> en uso. El comentario quedó desactualizado.

### `PARA_ACTUALIZARDATOS()`

**Usada por la app** (`productos.cpp`). Devuelve producto, precio, categoría
y marca para la pantalla de edición.

> **Nota:** al final de la definición hay un `CALL PARA_ACTUALIZARDATOS();`
> suelto que se ejecuta **en cada import** y vuelca toda la tabla como result
> set. Es ruido de desarrollo, inocuo para el import.

### `PARA_ACTIVARODESACTIVAR_PROC()`

**Usada por la app** (`productos.cpp`). Devuelve
`ID_PRODUCTO, NOMBRE, ESTADO` ordenado por ID, para la pantalla de
activar/desactivar en bloque.

## Triggers

### `TR_AUDITORIA_PRODUCTOS_UPDATE`

`AFTER UPDATE ON PRODUCTOS`. Solo cuando **cambia el precio de venta**
(`OLD.PRECIO <> NEW.PRECIO`) inserta en `AUDITORIA_SISTEMA`:
`TABLA_AFECTADA = 'PRODUCTOS'`, `ACCION = 'UPDATE'`, `USUARIO_SISTEMA =
USER()`, y `VALOR_ANTERIOR` / `VALOR_NUEVO` con
`Precio venta anterior: <x>` / `Precio venta nuevo: <y>`.

> No audita cambios de nombre, stock, costo ni estado: **solo precio de
> venta**. Usa `USER()` (no `CURRENT_USER()` como los triggers de CLIENTES).

## Sentencias de migración y verificación (histórico)

Al final del archivo quedan sentencias sueltas que se ejecutan en **cada
import** (no están dentro de rutinas):

- `SELECT`s de verificación sobre `PRODUCTOS` y `PROVEEDORES`.
- `ALTER TABLE PRODUCTOS ADD COLUMN IF NOT EXISTS ID_PROVEEDOR ...`,
  `MODIFY COLUMN ID_PROVEEDOR INT NOT NULL DEFAULT 1`, luego
  `ALTER COLUMN ID_PROVEEDOR DROP DEFAULT` y `MODIFY ... NOT NULL`.
  Son restos de la migración que agregó el proveedor; en una base fresca son
  idempotentes y no cambian el resultado final.
- `DESCRIBE PRODUCTOS` y un `SELECT * FROM PRODUCTOS`.

Es el estilo histórico del repo (como las versiones viejas comentadas): no se
borran sin una limpieza acordada.

## Reglas de negocio

- **Código único** global; se guarda en mayúsculas.
- **Nombre único dentro de la misma marca** (UNIQUE compuesto + chequeo en
  los SP con mensaje amigable).
- **Precio de venta > 0**; **precio de compra >= 0** (0 = pendiente o
  bonificado).
- **Descripción mínima de 10 caracteres** al alta; en la edición, vacío
  significa "conservar".
- **Marca, categoría y proveedor deben existir** (FK + validación previa en
  los SP).
- **No hay borrado físico:** toggle de estado.
- **Proveedor preferido** en `ID_PROVEEDOR`; el historial de proveedores y
  precios vive en `PRODUCTO_PROVEEDOR` (40).
- **Auditoría de precio de venta** vía trigger.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
