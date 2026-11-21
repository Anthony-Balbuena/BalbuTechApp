# Módulo 9 — PRODUCTOS

Catálogo central de productos: nombre, descripción, precio de venta y de
compra, código único, marca, categoría, proveedor preferido e imagen. Es el
módulo del que cuelga medio sistema: inventario, compras, ventas, garantías y
devoluciones lo referencian.

**Depende de:** `MARCAS` (2), `CATEGORIAS` (1) y `PROVEEDORES` (5), por FK.
**Es referenciado por:** `INVENTARIO` (17), `DETALLE_COMPRA` (19),
`DETALLES_VENTA` (21), `PRODUCTO_PROVEEDOR` (32), entre otros.

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
| `ES_REPUESTO` | `TINYINT(1)` | NOT NULL, DEFAULT `0` | Repuesto de garantía: producto del catálogo que **no se vende**. Única fuente de verdad del destino del repuesto. |
| `FECHA_CREACION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |
| `ID_MARCA` | `INT` | NOT NULL, FK → `MARCAS` | Marca. |
| `ID_CATEGORIA` | `INT` | NOT NULL, FK → `CATEGORIAS` | Categoría. |
| `ID_PROVEEDOR` | `INT` | NOT NULL, FK → `PROVEEDORES` | Proveedor **preferido** (el mapa completo vive en `PRODUCTO_PROVEEDOR`). |
| `IMAGEN` | `VARCHAR(255)` | NULL | URL/ruta de imagen. (La BD viva la tenía como `IMAGEN`; se unificó con ese nombre.) |
| `DIAS_GARANTIA` | `INT` | NULL, DEFAULT `NULL`, CHECK `>= 0` | Días de garantía automática al confirmar la venta. `NULL` o `0` = sin garantía. (19/11/2026: la columna se declara acá; antes se agregaba con un `ALTER` desde el módulo 25.) |
| `EXENTO_ITBIS` | `TINYINT(1)` | NOT NULL, DEFAULT `0` | Exento de ITBIS: sus líneas de **venta** y de **compra** no llevan impuesto. `0` = gravado (lo de siempre). Única fuente de verdad de la exención. (21/11/2026: va al final a propósito, para que un `ALTER ... AFTER DIAS_GARANTIA` deje una base vieja con el mismo orden de columnas que un import desde cero.) |

**Restricciones de tabla:**
- `UQ_PRODUCTO_NOMBRE_MARCA` UNIQUE (`NOMBRE`, `ID_MARCA`): no se repite el
  nombre dentro de la misma marca.
- `CK_PRODUCTO_DIAS_GARANTIA` CHECK (`DIAS_GARANTIA` es `NULL` o `>= 0`).
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

### `SP_MARCAR_PRODUCTO_EXENTO(P_ID_PRODUCTO, P_EXENTO)` — (21/11/2026)

**Usada por la app** (`productos.cpp`, alta y edición). Marca o desmarca la exención
de ITBIS de un producto.

- `P_EXENTO` se **normaliza**: `1` marca exento; cualquier otro valor (o `NULL`) deja
  el producto gravado, que es el comportamiento de siempre.
- ID inexistente → `ERROR: EL PRODUCTO NO EXISTE.`
- Devuelve `PRODUCTO: "<nombre>" - ITBIS: EXENTO|GRAVADO`.

Existe como rutina aparte **a propósito**: `SP_INSERTAR_PRODUCTO` y
`SP_ACTUALIZAR_PRODUCTOS` ya tienen sus llamadores y este flag es ortogonal al alta y
a la edición del catálogo. Un producto nuevo nace gravado (`EXENTO_ITBIS DEFAULT 0`) y
se marca desde esta rutina. Permiso: `GESTIONAR_PRODUCTOS`, exigido.

### `SP_CONSULTAR_PRODUCTOS_FILTRADO(P_BUSQUEDA)`

**Usada por la app** (`productos.cpp`, `ventas.cpp`, `compras.cpp`,
`inventario.cpp`). Devuelve
`ID_PRODUCTO, CODIGO, NOMBRE, MARCA, CATEGORIA, PRECIO, P_COMPRA, ESTADO,
STOCK, PROVEEDOR, ID_PROVEEDOR, EXENTO_ITBIS`, ordenado por ID.

- Sin filtro → todos.
- Texto → `LIKE` por nombre, **código exacto** o ID numérico
  (`REGEXP '^[0-9]+$'`).
- `STOCK` sale de `LEFT JOIN INVENTARIO`: un producto sin fila de inventario
  aparece con `STOCK` `NULL`, no con 0.

### `SP_CONSULTAR_PRODUCTOS_PAGINADO(P_BUSQUEDA, P_PAGINA, P_POR_PAGINA)`

**Usada por la app** (`productos.cpp` → "Buscar Producto", 08/11/2026).

Mismas columnas y mismo criterio de búsqueda que
`SP_CONSULTAR_PRODUCTOS_FILTRADO`, pero devuelve **una página**: `LIMIT
P_POR_PAGINA OFFSET (P_PAGINA-1)*P_POR_PAGINA`.

- `P_PAGINA` nulo o `< 1` → 1. `P_POR_PAGINA` nulo o `< 1` → 10.
- Existe por el recorte de privilegios del 03/11: `balbu_app` **no** tiene
  `SELECT` sobre `PRODUCTOS`, así que la pantalla no puede paginar con un
  `SELECT` directo. El `LIMIT` tiene que vivir dentro del `SP` `DEFINER`.
- Permiso: `CONSULTAR_PRODUCTOS`.

### `SP_CONTAR_PRODUCTOS_FILTRADOS(P_BUSQUEDA)`

**Usada por la app** (`productos.cpp`, 08/11/2026). Devuelve `COUNT(*) AS TOTAL`
con el mismo `WHERE` que el paginado.

Sin este conteo la pantalla no sabe cuántas páginas hay: el paginador lo usa
para armar "Página 1 de 2" y habilitar/deshabilitar "siguiente". Permiso:
`CONSULTAR_PRODUCTOS`.

> Si cambia el criterio de búsqueda en `SP_CONSULTAR_PRODUCTOS_FILTRADO` hay
> que cambiarlo en **los tres**: el filtrado, el paginado y el conteo.

### `SP_CONSULTAR_INVENTARIO(P_FILTRO)`

**Usada por la app** (`productos.cpp`, `ventas.cpp`, `compras.cpp`). Lista
solo productos **`ACTIVO`** con stock, mínimo, ubicación, precio y costo.
Filtra por nombre, código, categoría o ID numérico.

(21/11/2026) Devuelve también `EXENTO_ITBIS`: la pantalla de venta lista sin recargo
el producto exento.

Calcula `ESTATUS_STOCK`:
- `IFNULL(STOCK_ACTUAL, 0) = 0` → **`AGOTADO`** (incluye productos sin fila
  de inventario);
- `STOCK_ACTUAL <= STOCK_MINIMO` → **`CRÍTICO`**;
- `STOCK_ACTUAL <= STOCK_MINIMO * 2` → **`STOCK BAJO`**;
- resto → **`OK`**.

### `SP_CONSULTAR_INVENTARIO_PAGINADO(P_FILTRO, P_PAGINA, P_POR_PAGINA)`

(08/11/2026) Una página de `SP_CONSULTAR_INVENTARIO`, mismas columnas y mismo
filtro. La usa "Productos > Consultar Inventario". Permiso:
`CONSULTAR_PRODUCTOS`.

### `SP_CONTAR_INVENTARIO(P_FILTRO)`

`COUNT(*)` con el mismo filtro y el mismo `ESTADO = 'ACTIVO'`, para el
paginador de la consulta.

### `SP_REPORTE_STOCK_CRITICO_PAGINADO(P_PAGINA, P_POR_PAGINA)`

(08/11/2026) Una página del reporte de stock crítico, mismo orden
(`CANTIDAD_FALTANTE DESC`). Permiso: `CONSULTAR_PRODUCTOS`.

### `SP_CONTAR_STOCK_CRITICO()`

Cuántos productos están en o bajo su mínimo, para el paginador del reporte.

### `SP_REPORTE_STOCK_CRITICO()`

**La app ya no la llama** (08/11/2026): "Reporte De Stock" pasó a
`SP_REPORTE_STOCK_CRITICO_PAGINADO` + `SP_CONTAR_STOCK_CRITICO`. Se conserva el
procedimiento, sin uso.

Lista los productos con `STOCK_ACTUAL <= STOCK_MINIMO`, con
`CANTIDAD_FALTANTE = STOCK_MINIMO - STOCK_ACTUAL`, del más urgente al menos.
Solo lee de `INVENTARIO` (un producto sin fila no aparece en este reporte).

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

> (08/11/2026) La app ya no la llama: el listado de edición va por
> `PARA_ACTUALIZARDATOS_PAGINADO` + `SP_CONTAR_PRODUCTOS`. Queda por
> compatibilidad.

### `PARA_ACTUALIZARDATOS_PAGINADO(P_PAGINA, P_POR_PAGINA)`

(08/11/2026) Una página del listado de edición: `ID_PRODUCTO`, `PRODUCTO`,
`PRECIO`, `ID_CATEGORIA`, `CATEGORIA`, `ID_MARCA`, `MARCA`. Permiso:
`GESTIONAR_PRODUCTOS`, el mismo que ya exigía `PARA_ACTUALIZARDATOS`.

(21/11/2026) Devuelve también `EXENTO_ITBIS` (al final): la pantalla de edición lo
muestra en la lista y desde ahí se marca o desmarca con `SP_MARCAR_PRODUCTO_EXENTO`.

### `SP_CONTAR_PRODUCTOS()`

`COUNT(*)` de `PRODUCTOS`, para el paginador de la edición.

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
`TABLA_AFECTADA = 'PRODUCTOS'`, `ACCION = 'UPDATE'`, y `VALOR_ANTERIOR` /
`VALOR_NUEVO` con `Precio venta anterior: <x>` / `Precio venta nuevo: <y>`.

El autor se resuelve con
`IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER())`:
primero el usuario de la sesión de la app; si no hay, el de MySQL. Hasta el
12/11/2026 guardaba `USER()` a secas, que es siempre `balbu_app`.

> No audita cambios de nombre, stock, costo ni estado: **solo precio de
> venta**.
>
> **Es el trigger líder de `PRODUCTOS`.** `TR_LOG_CAMBIO_ESTADO_PRODUCTO` (sección
> «HISTORIAL_ESTADOS_PRODUCTO (ex módulo 18)», al final de este mismo archivo)
> declara `FOLLOWS` sobre este, así que el orden es precio primero e historial de
> estado después. Los dos viven ahora en el mismo archivo: esta definición tiene
> que quedar **arriba**.

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
  precios vive en `PRODUCTO_PROVEEDOR` (32).
- **Auditoría de precio de venta** vía trigger.
- **Exención de ITBIS por producto** (21/11/2026): `EXENTO_ITBIS = 1` significa que
  sus líneas de venta y de compra no llevan impuesto. Es una propiedad del
  **catálogo**, no de la línea: si el mismo producto se vendiera gravado y exento
  según el cliente, este diseño no alcanza. La venta (`SP_AGREGAR_DETALLE_VENTA`) no
  cobra ITBIS y la compra (`22_SP_AGREGAR_DETALLE_COMPRA`, `SP_MODIFICAR_LINEA_COMPRA`)
  trata el precio escrito como **neto**. Las devoluciones prorratean el ITBIS desde la
  línea guardada (foto histórica), no desde la tasa vigente: si no, devolverían un
  impuesto que nunca se cobró. La tasa de empresa en `0 %` es un tema aparte
  (`FN_TASA_ITBIS`), no se mezcla con esto.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## HISTORIAL_ESTADOS_PRODUCTO (ex módulo 18)

Bitácora de estados absorbida dentro del `9` el 14/11/2026 (ver el `## Log` de
`odd/tasks/consolidacion-modulos.md`). El cuerpo del ex `18` viaja **verbatim**:
acá solo se degradaron los encabezados un nivel.

Bitácora de los cambios `ACTIVO` ↔ `INACTIVO` de un producto: quién, cuándo, de
qué estado a cuál y por qué. Ningún cambio de estado queda sin rastro.

**Depende de:** `PRODUCTOS` (esta misma sección, arriba) y `EMPLEADOS` (8).

> **La app no llama el SP ni la vista de este módulo.** **Pero la tabla sí se
> llena**: la app cambia el estado con `SP_TOGGLE_ESTADO_PRODUCTOS` (9), que hace
> `UPDATE PRODUCTOS SET ESTADO` y dispara el trigger. Desde el 12/11/2026 la app
> deja `@ID_EMPLEADO_ACTUAL` y `@MOTIVO_CAMBIO` en la conexión al cambiar el
> estado (`productos.cpp`), así que la fila queda con el empleado real. Sin
> sesión, el empleado queda `NULL`, no `1`.

Fuente: `modulos/9- PRODUCTOS.sql`, sección del ex módulo `18` · Base:
`BALBU_TECH` · Revisado: 20/10/2026 · Fusionado: 14/11/2026.

### Tablas

#### HISTORIAL_ESTADOS_PRODUCTO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PRODUCTO` | `INT` | NOT NULL, FK → `PRODUCTOS` | Producto afectado. |
| `ID_EMPLEADO` | `INT` | NULL, FK → `EMPLEADOS` | Quién hizo el cambio. `NULL` = no se sabe. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL | Estado nuevo. |
| `ESTADO_ANTERIOR` | `ENUM('ACTIVO','INACTIVO')` | NULL | Estado previo (la tabla admite nulos, el trigger nunca los manda). |
| `MOTIVO_CAMBIO` | `VARCHAR(255)` | NULL | Motivo. |
| `FECHA_CAMBIO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |

**Índices:** `HISTORIAL_ESTADOS_PRODUCTO_FECHACAMBIO` (`FECHA_CAMBIO`),
`IX_HISTORIAL_ESTADO_ACTUAL` (`ESTADO`) e `IX_HISTORIAL_ESTADO_ANTERIOR`
(`ESTADO_ANTERIOR`).

> **`ID_EMPLEADO` es `NULL` a propósito** (12/11/2026). Antes era `NOT NULL` y
> el trigger caía a `IFNULL(@ID_EMPLEADO_ACTUAL, 1)`: todo cambio sin sesión
> quedaba firmado por el empleado 1, que es un dato falso, no un dato vacío.
> Peor: si el empleado 1 no existía, el `INSERT` del trigger reventaba por FK y
> **se caía el `UPDATE` del producto**. El módulo trae el `ALTER ... MODIFY ...
> NULL` idempotente para las bases que ya tenían la columna `NOT NULL`.
>
> Tres índices para una tabla que en la práctica solo se lee ordenada por fecha.
> Los dos del estado son de baja selectividad: con dos valores posibles, el
> optimizador casi nunca los va a preferir.

### Procedimientos almacenados

#### `18_SP_CAMBIAR_ESTADO_PRODUCTO` — ELIMINADO el 15/11/2026

Cambiaba el estado del producto y dejaba empleado y motivo en variables de
sesión para que el trigger los registrara. Nadie la llamaba: el cambio real
pasa por `SP_TOGGLE_ESTADO_PRODUCTOS`, que no setea esas variables. Se retiró
como resto del ítem 12c de `PENDIENTES.md`; en su lugar quedó un `DROP ... IF
EXISTS` para limpiar las bases que ya la tenían.

### Triggers

#### `TR_LOG_CAMBIO_ESTADO_PRODUCTO` (`AFTER UPDATE ON PRODUCTOS`)

Solo si `OLD.ESTADO <> NEW.ESTADO`, inserta la fila con `ESTADO = NEW.ESTADO`,
`ESTADO_ANTERIOR = OLD.ESTADO`, el empleado de `@ID_EMPLEADO_ACTUAL` (sin
fallback: si no hay sesión queda `NULL`) y el motivo de `@MOTIVO_CAMBIO`.

> Declara `FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE`, el trigger de precio del
> módulo 9, que vive **más arriba en este mismo archivo**: ese corre primero. El
> `FOLLOWS` exige que el líder ya exista, así que hay que mantener ese orden
> dentro del archivo.
>
> **Desde que se retiró el SP, nadie setea esas variables**: el historial se
> llena con `NULL` y con el motivo `'Cambio de estado automático'`. El trigger
> se conserva porque la tabla la va a usar el día que se cablee el historial
> (ítem 12.2 de `PENDIENTES.md`).
>
> Un `UPDATE PRODUCTOS SET ESTADO = ...` directo **sí pasa** por el trigger: no
> hay candado de estado, a diferencia de compras y ventas.

### Vistas

#### `VISTA_ULTIMOS_MOVIMIENTOS`

Los **10** cambios más recientes: `FECHA_CAMBIO`, `PRODUCTO` y `MOTIVO_CAMBIO`.
Usa `JOIN` a `PRODUCTOS`, así que un producto borrado (imposible por FK) quedaría
fuera. **La app no la usa.**

### Reglas de negocio

- **Cada cambio de estado deja una fila**, venga del SP o de un `UPDATE` directo.
- **El empleado responsable sale de una variable de sesión**; sin sesión queda
  `NULL`, nunca un empleado inventado.
- **El motivo es opcional** y se rellena con un texto genérico.
- **Cambiar al mismo estado no registra nada ni avisa.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

