# Módulo 5 — PROVEEDORES

Maestro de proveedores: nombre obligatorio; teléfono y email **opcionales
pero únicos si se usan**; dirección opcional. Todo proveedor arranca
`ACTIVO` y se desactiva con toggle (no hay borrado).

Es referenciado por `PRODUCTOS.ID_PROVEEDOR` (proveedor preferido) y por
`PRODUCTO_PROVEEDOR` (mapa producto–proveedor, módulo 40).

Fuente: `modulos/5- PROVEEDORES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### PROVEEDORES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PROVEEDOR` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador del proveedor. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL | Razón social / nombre. **No es único**: puede repetirse (se distinguen por teléfono/email/ID). |
| `TELEFONO` | `VARCHAR(15)` | UNIQUE, NULL | Teléfono. Único si está cargado; `NULL` permitido y repetible. |
| `EMAIL` | `VARCHAR(100)` | UNIQUE, NULL | Email. Único si está cargado; `NULL` repetible. |
| `DIRECCION` | `VARCHAR(120)` | NULL | Dirección física. |
| `FECHA_REGISTRO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo. |

**Índices:** `IX_PROVEEDOR_NOMBRE` (búsquedas por nombre) e
`IX_PROVEEDOR_ESTADO` (filtrar activos en listados/reportes).

> **Nota:** `TELEFONO` y `EMAIL` declaran `UNIQUE` dos veces: inline en la
> columna y como `CONSTRAINT UQ_PROVEEDOR_TELEFONO` / `UQ_PROVEEDOR_EMAIL`.
> MariaDB crea un índice único por cada declaración, así que quedan índices
> duplicados sobre las mismas columnas. No rompe nada; candidato a limpieza
> al consolidar el esquema.

## Procedimientos almacenados

### `SP_INSERTAR_PROVEEDOR(P_NOMBRE, P_TELEFONO, P_EMAIL, P_DIRECCION)`

**Usada por la app** (`proveedores.cpp` y `compras.cpp`).

**Limpieza previa:**
- nombre y dirección: `TRIM` + colapso de espacios internos;
- teléfono: se quitan espacios, paréntesis y guiones
  (`REGEXP_REPLACE(P_TELEFONO, '[[:space:]()\-]', '')`);
- email: `LOWER` y se quitan espacios.

**Validaciones (`SIGNAL 45000`):**
- nombre `NULL` o vacío → `ERROR: EL NOMBRE DEL PROVEEDOR NO PUEDE ESTAR VACÍO.`
- teléfono no `NULL` y vacío → `ERROR: EL TELÉFONO NO PUEDE ESTAR VACÍO.`
- teléfono ya registrado → `ERROR: EL TELÉFONO YA ESTÁ REGISTRADO.`
- email no `NULL` y vacío → `ERROR: EL EMAIL NO PUEDE ESTAR VACÍO.`
- email ya registrado → `ERROR: EL EMAIL YA ESTÁ REGISTRADO.`

Inserta y devuelve
`EXITO: PROVEEDOR "<nombre>" INSERTADO. ID: <id>`.

### `SP_ACTUALIZAR_PROVEEDOR(P_ID_PROVEEDOR, P_NOMBRE, P_TELEFONO, P_EMAIL, P_DIRECCION)`

**Usada por la app.** Actualización parcial: lo que llega `NULL` se conserva
(`COALESCE` por campo).

- ID inexistente → `ERROR: EL PROVEEDOR NO EXISTE.`
- Nombre vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
- Teléfono que pertenece a **otro** proveedor →
  `ERROR: EL TELÉFONO YA PERTENECE A OTRO PROVEEDOR.`
- Email de otro proveedor → `ERROR: EL EMAIL YA PERTENECE A OTRO PROVEEDOR.`
- Una cadena vacía (`''`) **no** borra el dato: se valida como "vacío" y
  responde error. Para dejar sin teléfono/email hay que hacerlo por SQL
  directo (`NULL`), la app no lo ofrece.
- Devuelve `EXITO: DATOS ACTUALIZADOS PARA EL PROVEEDOR ID: <id>`.

### `SP_TOGGLE_ESTADO_PROVEEDOR(P_ID_PROVEEDOR)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`. ID inexistente →
`ERROR: PROVEEDOR NO ENCONTRADO.` Devuelve
`EXITO: PROVEEDOR "<nombre>" (ID: <id>) HA SIDO <ESTADO>.`

### `SP_LISTAR_PROVEEDORES(P_FILTRO)`

**Usada por la app** (también como búsqueda: no hay `SP_BUSCAR_PROVEEDOR`).
Devuelve `ID_PROVEEDOR, NOMBRE, TELEFONO, EMAIL, DIRECCION, ESTADO`
(sin fecha), ordenado por ID. Con filtro vacío/`NULL` trae todos; con texto
busca `LIKE '%<texto>%'` en **nombre o teléfono**.

## Reglas de negocio

- **Nombre obligatorio**, pero **no único**.
- **Teléfono y email únicos cuando existen**; `NULL` es válido y se puede
  repetir (varios proveedores sin email).
- **Normalización:** teléfono sin espacios/paréntesis/guiones; email en
  minúsculas y sin espacios.
- **No hay borrado físico:** solo toggle de estado.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
