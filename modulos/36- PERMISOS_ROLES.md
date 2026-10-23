# Módulo 36 — PERMISOS_ROLES

La matriz de permisos: qué acciones existen (`PERMISOS`) y qué rol puede hacer
cada una (`ROL_PERMISO`). Desde el 20/10/2026 **la base es la única fuente de
verdad**: la app consulta con `FN_TIENE_PERMISO`, no compara nombres de rol en el
código.

**Depende de:** `ROLES` (3) y `USUARIOS` (10).
**Es usado por:** `roles.cpp` (asignar, quitar, listar y validar),
`empleados.cpp` y el resto de los módulos de UI (cada uno pregunta por su
permiso).

Fuente: `modulos/36- PERMISOS_ROLES.sql` · Base: `BALBU_TECH` · Revisado: 23/10/2026.

## Tablas

### PERMISOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PERMISO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `NOMBRE_PERMISO` | `VARCHAR(80)` | NOT NULL, **UNIQUE** | Clave que consulta la app. |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Texto para la UI. |

**Semillas (35, idempotentes con `ON DUPLICATE KEY UPDATE`):**
`GESTIONAR_ROLES`, `USUARIOS_VER`, `USUARIOS_CREAR`, `USUARIOS_EDITAR`,
`USUARIOS_ESTADO`, `USUARIOS_CLAVE`, `EMPLEADOS_VER`, `EMPLEADOS_CREAR`,
`EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`, `JUSTIFICAR_ASISTENCIA`,
`GESTIONAR_PERMISOS_EMPLEADO`, `GESTIONAR_VACACIONES_EMPLEADO`,
`CLIENTES_VER`, `CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`,
`PROVEEDORES_VER`, `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR`,
`PROVEEDORES_ESTADO`, `GESTIONAR_CATEGORIAS`,
`GESTIONAR_MARCAS`, `GESTIONAR_PRODUCTOS`, `GESTIONAR_METODOS_PAGO`,
`GESTIONAR_INVENTARIO`, `GESTIONAR_VENTAS`, `CONSULTAR_HISTORIAL_VENTA`,
`GESTIONAR_COMPRAS`,
`CONSULTAR_REPORTES`, `CONSULTAR_ASISTENCIA`, `CONSULTAR_PRODUCTOS`,
`REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` y `GESTIONAR_CONTRATOS`.

> **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `USUARIOS_CREAR`,
> `USUARIOS_EDITAR`, `USUARIOS_ESTADO` y `USUARIOS_CLAVE`). El viejo
> `GESTIONAR_USUARIOS` **ya no existe**: el import lo borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.

> **El módulo Empleados usa 6 permisos finos** (`EMPLEADOS_VER`,
> `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`,
> `GESTIONAR_PERMISOS_EMPLEADO` y `GESTIONAR_VACACIONES_EMPLEADO`) más
> `GESTIONAR_CONTRATOS` para el bloque de contratos. El viejo
> `GESTIONAR_EMPLEADOS` **ya no existe**: mismo borrado en cascada que
> `GESTIONAR_USUARIOS`. La asistencia **ya no vive acá**: desde el 23/10/2026
> tiene su propio ítem y sus propios permisos (ver más abajo).

> **El módulo Clientes usa 4 permisos finos** (`CLIENTES_VER`, `CLIENTES_CREAR`,
> `CLIENTES_EDITAR` y `CLIENTES_ESTADO`). Los viejos `GESTIONAR_CLIENTES` y
> `CONSULTAR_CLIENTES` **ya no existen**: el import los borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.
>
> **El módulo Proveedores usa 4 permisos finos** (`PROVEEDORES_VER`,
> `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR` y `PROVEEDORES_ESTADO`). El viejo
> `GESTIONAR_PROVEEDORES` **ya no existe**: el import lo borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares. La migración de una base existente es
> el módulo 46, que preserva los roles personalizados que tenían el paraguas.
>
> **`CONSULTAR_HISTORIAL_VENTA` solo habilita `Historial de venta`**: no abre el
> módulo Ventas (eso lo hace `GESTIONAR_VENTAS`) ni da acceso a reportes,
> ganancias o exportación web. La migración de una base existente es el
> módulo 47.
>
> **`CONSULTAR_REPORTES` no da acceso a ningún módulo**: solo filtra opciones una
> vez adentro. **`REGISTRAR_ASISTENCIA` abre el ítem `Asistencia` del menú
> principal** y adentro habilita `Marcar entrada/salida` y `Mi asistencia`.
> **`CONSULTAR_ASISTENCIA`** habilita `Ver asistencia`, `Asistencia del dia` e
> `Historial de asistencia`; **`JUSTIFICAR_ASISTENCIA`**, `Justificar
> asistencia`. `VENDEDOR`, `ALMACEN` y `CONTABILIDAD` solo tienen el primero:
> fichan y ven lo suyo, pero no la asistencia ajena. `VENDEDOR` ya no tiene
> `CONSULTAR_REPORTES`: ve el historial con `CONSULTAR_HISTORIAL_VENTA` y
> Garantías con `GESTIONAR_VENTAS`.

> **El catálogo de permisos no se administra desde la app**: no hay SP de alta,
> edición ni baja. Un permiso nuevo **solo** entra por semilla. Lo que la app sí
> administra es **qué rol lo tiene**.
>
> **Los 35 se consultan en el código**: los de Empleados y Asistencia en
> `empleados.cpp`, los de Clientes en `clientes.cpp`, los de Proveedores en
> `proveedores.cpp`, los de Productos en `productos.cpp` y los de Ventas en
> `ventas.cpp`; el menú principal, en `roles.cpp`. `REGISTRAR_ASISTENCIA` abre el ítem propio `Asistencia` (primero
> del menú), no `Empleados`. `SOLICITAR_PERMISO` lo usa el menú principal
> (`Mis permisos` y `Mis vacaciones`).

### ROL_PERMISO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ROL_NOMBRE` | `VARCHAR(50)` | NOT NULL, PK (compuesta), FK → `ROLES.NOMBRE_ROL` **ON UPDATE CASCADE** | Rol. |
| `ID_PERMISO` | `INT` | NOT NULL, PK (compuesta), FK → `PERMISOS` **ON DELETE CASCADE** | Permiso. |

> **La clave es el nombre del rol, no su ID.** Por eso `ROL_NOMBRE` tuvo que
> pasar de `VARCHAR(30)` a `VARCHAR(50)` para poder atar el FK (09/10/2026).
>
> **`ON UPDATE CASCADE`** es lo que hace que renombrar un rol con
> `SP_ACTUALIZAR_ROL` (3) arrastre sus permisos.
>
> **`ON DELETE CASCADE`** del permiso: borrar un permiso limpia la matriz sin
> avisar.

**Matriz que queda al importar:**

| Rol | Permisos |
|---|---|
| `ADMIN` | **los 35** |
| `GERENTE` | todos **menos** `GESTIONAR_ROLES` y los 5 `USUARIOS_*` (29) |
| `SUBGERENTE` | todos **menos** `GESTIONAR_ROLES`, los 5 `USUARIOS_*`, `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`, `GESTIONAR_PERMISOS_EMPLEADO`, `GESTIONAR_VACACIONES_EMPLEADO` y `GESTIONAR_CONTRATOS` (23) |
| `RRHH` | los 7 finos de Empleados, `GESTIONAR_CONTRATOS`, `CONSULTAR_REPORTES`, `CONSULTAR_ASISTENCIA`, `REGISTRAR_ASISTENCIA`, `JUSTIFICAR_ASISTENCIA` y `SOLICITAR_PERMISO` (12) |
| `VENDEDOR` | `GESTIONAR_VENTAS`, `CLIENTES_VER`, `CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_HISTORIAL_VENTA`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` (10) |
| `ALMACEN` | `GESTIONAR_PRODUCTOS`, `GESTIONAR_CATEGORIAS`, `GESTIONAR_MARCAS`, `GESTIONAR_INVENTARIO`, `GESTIONAR_COMPRAS`, `PROVEEDORES_VER`, `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR`, `PROVEEDORES_ESTADO`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` (12) |
| `CONTABILIDAD` | `CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CLIENTES_VER`, `REGISTRAR_ASISTENCIA` (4) |

### Mapa del submenú de Clientes

El submenú conserva el orden histórico de 6 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Cliente | `CLIENTES_CREAR` |
| 2 | Actualizar Cliente | `CLIENTES_EDITAR` |
| 3 | Cambiar Estado | `CLIENTES_ESTADO` |
| 4 | Buscar Cliente | `CLIENTES_VER` |
| 5 | Listar Clientes | `CLIENTES_VER` |
| 6 | Volver al Menu Principal | *(siempre)* |

### Mapa del submenú de Proveedores

El submenú conserva el orden histórico de 6 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar proveedor | `PROVEEDORES_CREAR` |
| 2 | Actualizar proveedor | `PROVEEDORES_EDITAR` |
| 3 | Activar/Desactivar proveedor | `PROVEEDORES_ESTADO` |
| 4 | Buscar proveedor | `PROVEEDORES_VER` |
| 5 | Listar proveedores | `PROVEEDORES_VER` |
| 6 | Volver al Menu Principal | *(siempre)* |

> **El corte cae donde el módulo solo tenía un permiso de acceso.** Un rol con
> solo `PROVEEDORES_VER` ve 3 opciones (Buscar, Listar, Volver); `ALMACEN`, con
> los cuatro, sigue viendo las 6.

### Mapa del submenú de Empleados

El submenú conserva el orden histórico sin las 5 opciones de asistencia, pero
**numera solo lo visible**. Cada opción pide un permiso; `Volver` es siempre
visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Empleado | `EMPLEADOS_CREAR` |
| 2 | Actualizar Datos | `EMPLEADOS_EDITAR` |
| 3 | Despedir Empleado | `EMPLEADOS_BAJA` |
| 4 | Reactivar Empleado | `EMPLEADOS_BAJA` |
| 5 | Buscar Empleado | `EMPLEADOS_VER` |
| 6 | Listar Empleados | `EMPLEADOS_VER` |
| 7 | Generar contrato | `GESTIONAR_CONTRATOS` |
| 8 | Subir contrato (al firmar) | `GESTIONAR_CONTRATOS` |
| 9 | Ver contratos | `GESTIONAR_CONTRATOS` |
| 10 | Finalizar contrato | `GESTIONAR_CONTRATOS` |
| 11 | Gestionar permisos | `GESTIONAR_PERMISOS_EMPLEADO` |
| 12 | Gestionar vacaciones | `GESTIONAR_VACACIONES_EMPLEADO` |
| 13 | Volver al Menu Principal | *(siempre)* |

> `SUBGERENTE` conserva el ítem `Empleados` con `EMPLEADOS_VER`: ve solo
> `Buscar`, `Listar` y `Volver`. `VENDEDOR` ya no entra a Empleados; ficha desde
> el ítem `Asistencia`.

### Mapa del submenú de Asistencia

El ítem `Asistencia` es el primero del menú principal y se abre con
`REGISTRAR_ASISTENCIA`. Numera solo lo visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Marcar entrada/salida | `REGISTRAR_ASISTENCIA` |
| 2 | Mi asistencia | `REGISTRAR_ASISTENCIA` |
| 3 | Ver asistencia | `CONSULTAR_ASISTENCIA` |
| 4 | Asistencia del dia | `CONSULTAR_ASISTENCIA` |
| 5 | Historial de asistencia | `CONSULTAR_ASISTENCIA` |
| 6 | Justificar asistencia | `JUSTIFICAR_ASISTENCIA` |
| 7 | Volver al Menu Principal | *(siempre)* |

> `ADMIN`, `GERENTE`, `SUBGERENTE` y `RRHH` ven las 7. `VENDEDOR`, `ALMACEN` y
> `CONTABILIDAD` ven 3 (`Marcar`, `Mi asistencia`, `Volver`). `Marcar` usa el
> `ID_EMPLEADO` de `USUARIOS`: nadie marca por otro.

### Mapa del submenú de Productos

El submenú conserva el orden histórico de 7 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Productos | `GESTIONAR_PRODUCTOS` |
| 2 | Actualizar Datos | `GESTIONAR_PRODUCTOS` |
| 3 | Activar/Desactivar Producto | `GESTIONAR_PRODUCTOS` |
| 4 | Buscar Producto | `CONSULTAR_PRODUCTOS` |
| 5 | Consultar Inventario | `CONSULTAR_PRODUCTOS` |
| 6 | Reporte De Stock | `CONSULTAR_PRODUCTOS` |
| 7 | Volver al Menu Principal | *(siempre)* |

> **El corte cae justo donde el módulo solo tenía un permiso de acceso.**
> `CONTABILIDAD` entra a Productos con `CONSULTAR_PRODUCTOS` y hasta el 22/10/2026
> veía igual el alta, la actualización y la baja. `ALMACEN` tiene los dos, así que
> no cambia: sigue viendo las 7.

### Mapa del submenú de Ventas

El submenú conserva el orden histórico de 15 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Venta rapida (carrito) | `GESTIONAR_VENTAS` |
| 2 | Ver venta con IVA | `GESTIONAR_VENTAS` |
| 3 | Cancelar venta | `GESTIONAR_VENTAS` |
| 4 | Anular pago | `GESTIONAR_VENTAS` |
| 5 | Devolucion de venta | `GESTIONAR_VENTAS` |
| 6 | Reporte por rango | `CONSULTAR_REPORTES` |
| 7 | Cierre de caja | `GESTIONAR_VENTAS` |
| 8 | Ganancias | `CONSULTAR_REPORTES` |
| 9 | Cobrar venta | `GESTIONAR_VENTAS` |
| 10 | Reporte por periodo | `CONSULTAR_REPORTES` |
| 11 | Ganancias por periodo | `CONSULTAR_REPORTES` |
| 12 | Garantias | `GESTIONAR_VENTAS` |
| 13 | Historial de venta | `CONSULTAR_HISTORIAL_VENTA` |
| 14 | Exportar datos para la web | `CONSULTAR_REPORTES` |
| 15 | Volver al Menu Principal | *(siempre)* |

> **El corte ahora se ve desde la app**: `VENDEDOR` tiene `GESTIONAR_VENTAS`
> pero ya no `CONSULTAR_REPORTES`, así que ve 10 opciones (las 7 de gestión,
> `Historial de venta`, `Garantías` y `Volver`) y ninguna de reportes ni
> ganancias. `ADMIN`, `GERENTE` y `SUBGERENTE` conservan `CONSULTAR_REPORTES` y
> siguen viendo las 15. Queda fijado en `db/test-menus-por-rol.sh` con VENDEDOR
> y con un rol sintético. `Exportar datos para la web` perdió el chequeo interno
> que tenía dentro del `switch`: ahora la opción ni se muestra sin el permiso.

> **Número fuera de rango no ejecuta nada**: `0`, un negativo o uno mayor que la
> última opción visible muestran `Opcion no valida` y reimprimen el submenú. El
> `0` ya no vuelve atrás en silencio (antes solo pasaba en los submenús; el menú
> principal nunca lo aceptó). Las seis pantallas con el patrón —Asistencia,
> Usuarios, Empleados, Clientes, Productos y Ventas— se comportan igual.

**Migraciones incluidas** (idempotentes; las 3 primeras son `C-3` del
20/10/2026, las 3 últimas del 22/10/2026):
1. `DROP CONSTRAINT IF EXISTS CHK_ROL_NOMBRE` — saca el `CHECK` que limitaba los
   roles a `ADMIN`/`RRHH`/`EMPLEADO`.
2. Recrea el FK del rol con `ON UPDATE CASCADE`.
3. **Borra los pares de `RRHH`** que el set final ya no le da
   (`GESTIONAR_ROLES`, los 5 `USUARIOS_*`, los 4 `CLIENTES_*` finos y
   `GESTIONAR_VENTAS`).
4. **Borra del catálogo `GESTIONAR_USUARIOS`**, el permiso único que reemplazan
   los 5 permisos finos de Usuarios (`ON DELETE CASCADE` limpia sus pares).
5. **Borra del catálogo `GESTIONAR_EMPLEADOS`**, el permiso único que reemplazan
   los 7 permisos finos de Empleados (mismo `ON DELETE CASCADE`).
6. **Borra del catálogo `GESTIONAR_CLIENTES` y `CONSULTAR_CLIENTES`**, los
   permisos viejos que reemplazan los 4 permisos finos de Clientes (mismo
   `ON DELETE CASCADE`).

> **Esos `DELETE` corren en cada import.** Los permisos que el dueño haya cargado
> a mano para `RRHH` **se respetan** (solo borra esos pares), pero si
> alguien vuelve a asignarle `CLIENTES_EDITAR` a `RRHH` desde la app, el
> próximo import se lo saca.

## Procedimientos almacenados

### `SP_ASIGNAR_PERMISO_A_ROL(P_ROL_NOMBRE, P_NOMBRE_PERMISO)`

**Usada por la app** (`roles.cpp`).

- rol inexistente → `ERROR: EL ROL NO EXISTE EN EL SISTEMA.`
- permiso inexistente → `ERROR: EL PERMISO NO EXISTE.`
- Inserta con `ON DUPLICATE KEY UPDATE` (idempotente) y devuelve
  `EXITO: PERMISO <permiso> ASIGNADO A <rol>`.

> No existe camino para **crear** un permiso desde la app: solo se asignan los
> 35 sembrados.

### `SP_QUITAR_PERMISO_A_ROL(P_ROL_NOMBRE, P_NOMBRE_PERMISO)`

**Usada por la app.** Valida rol y permiso y borra el par.

- si el rol no lo tenía → `AVISO: <rol> NO TENIA EL PERMISO <permiso>.`
- si lo tenía → `EXITO: PERMISO <permiso> QUITADO A <rol>.`

> **Aviso, no error**: quitar dos veces es inofensivo.

### `SP_LISTAR_PERMISOS_POR_ROL(P_ROL_NOMBRE)`

**Usada por la app.** Los permisos del rol (`ID_PERMISO`, `NOMBRE_PERMISO`,
`DESCRIPCION`) ordenados por nombre.

> Si el rol no existe devuelve **cero filas**, no un error.

## Funciones

### `FN_TIENE_PERMISO(P_USERNAME, P_ACCION) → BOOLEAN`

**Usada por la app** (`roles.cpp`). `TRUE` si el rol del usuario tiene ese
permiso; `FALSE` si el usuario no existe o no lo tiene.

> **Es la puerta de autorización real del sistema**, y depende de que el nombre
> del permiso coincida **exacto** con el string del `cpp`.
>
> **Declarada `DETERMINISTIC` leyendo cuatro tablas** (misma incorrección que
> `FN_CONTAR_ITEMS_COMPRA` en 19). MySQL lo acepta, pero el declarante es falso y
> puede inducir al optimizador a cachear un resultado que cambia.
>
> **No mira si el usuario está activo**: un usuario dado de baja conserva su rol
> mientras exista la fila, y la función sigue devolviendo `TRUE`.

## Reglas de negocio

- **La base manda**: los permisos se leen de `ROL_PERMISO`, no del nombre del rol
  en el código.
- **`ADMIN` tiene todo**; `GERENTE` todo lo operativo salvo roles y los 5
  permisos de Usuarios (29); `SUBGERENTE` además no toca empleados ni contratos
  (23); `RRHH` conserva personal, contratos y reportes (12).
- **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `CREAR`,
  `EDITAR`, `ESTADO`, `CLAVE`); el submenú muestra solo las acciones habilitadas.
- **El módulo Empleados usa 7 permisos finos**; el submenú muestra solo las
  acciones habilitadas y renumera sobre lo visible.
- **El módulo Clientes usa 4 permisos finos** (`CLIENTES_VER`, `CREAR`,
  `EDITAR`, `ESTADO`); el submenú muestra solo las acciones habilitadas y
  renumera sobre lo visible.
- **`CLIENTES_VER` abre el módulo**; `CLIENTES_CREAR`, `CLIENTES_EDITAR` y
  `CLIENTES_ESTADO` solo habilitan su opción adentro.
- **Productos y Ventas también filtran por permiso**: `GESTIONAR_PRODUCTOS`
  habilita alta/cambio de estado y `CONSULTAR_PRODUCTOS`
  las consultas; en Ventas, `GESTIONAR_VENTAS` habilita operar,
  `CONSULTAR_HISTORIAL_VENTA` solo el historial y
  `CONSULTAR_REPORTES` los reportes, las ganancias y la exportación web.
- **`CONSULTAR_REPORTES` y `REGISTRAR_ASISTENCIA` no abren Empleados**: son
  opciones adentro, no llave del módulo.
- **Renombrar un rol arrastra sus permisos** (`ON UPDATE CASCADE`).
- **Un permiso nuevo solo entra por semilla**; la app solo asigna y quita.
- **Quitar un permiso que no estaba no es error**, es aviso.
- **El import re-aplica la matriz y borra los pares viejos de `RRHH`.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
