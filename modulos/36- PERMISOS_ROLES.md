# Módulo 36 — PERMISOS_ROLES

La matriz de permisos: qué acciones existen (`PERMISOS`) y qué rol puede hacer
cada una (`ROL_PERMISO`). Desde el 20/10/2026 **la base es la única fuente de
verdad**: la app consulta con `FN_TIENE_PERMISO`, no compara nombres de rol en el
código.

**Depende de:** `ROLES` (3) y `USUARIOS` (10).
**Es usado por:** `roles.cpp` (asignar, quitar, listar y validar),
`empleados.cpp` y el resto de los módulos de UI (cada uno pregunta por su
permiso).

> **Absorbe el `44` (14/11/2026):** la migración de roles vive ahora **en este
> mismo archivo**, al final, en la sección «MIGRACION_ROLES (ex módulo 44)». Corre
> después de la matriz y de los diez parches finos, que es el orden que tenían
> como archivos aparte.

Fuente: `modulos/36- PERMISOS_ROLES.sql` · Base: `BALBU_TECH` · Revisado: 18/11/2026.

## Tablas

### PERMISOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_PERMISO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `NOMBRE_PERMISO` | `VARCHAR(80)` | NOT NULL, **UNIQUE** | Clave que consulta la app. |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Texto para la UI. |

**Semillas (idempotentes con `ON DUPLICATE KEY UPDATE`):**
`GESTIONAR_ROLES`, `USUARIOS_VER`, `USUARIOS_CREAR`, `USUARIOS_EDITAR`,
`USUARIOS_ESTADO`, `USUARIOS_CLAVE`, `EMPLEADOS_VER`, `EMPLEADOS_CREAR`,
`EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`, `JUSTIFICAR_ASISTENCIA`,
`GESTIONAR_PERMISOS_EMPLEADO`, `GESTIONAR_VACACIONES_EMPLEADO`,
`GESTIONAR_BONOS_EMPLEADO`, `GESTIONAR_NOMINA`,
`CLIENTES_VER`, `CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`,
`PROVEEDORES_VER`, `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR`,
`PROVEEDORES_ESTADO`, `CATEGORIAS_VER`, `CATEGORIAS_CREAR`,
`CATEGORIAS_EDITAR`, `CATEGORIAS_ESTADO`,
`MARCAS_VER`, `MARCAS_CREAR`, `MARCAS_EDITAR`, `MARCAS_ESTADO`,
`GESTIONAR_PRODUCTOS`,
`METODOS_PAGO_VER`, `METODOS_PAGO_CREAR`, `METODOS_PAGO_EDITAR`,
`METODOS_PAGO_ESTADO`,
`INVENTARIO_VER`, `INVENTARIO_AJUSTAR`, `INVENTARIO_COSTO`, `GESTIONAR_VENTAS`,
`CONSULTAR_CAJA`, `ABRIR_CAJA`, `CERRAR_CAJA`, `CONSULTAR_HISTORIAL_VENTA`,
`COMPRAS_VER`, `COMPRAS_REGISTRAR`, `COMPRAS_PAGAR`, `COMPRAS_CANCELAR`,
`COMPRAS_DEVOLVER`, `COMPRAS_REPORTES`,
`CONSULTAR_REPORTES`, `CONSULTAR_ASISTENCIA`, `CONSULTAR_PRODUCTOS`,
`REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` y `GESTIONAR_CONTRATOS`.

> **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `USUARIOS_CREAR`,
> `USUARIOS_EDITAR`, `USUARIOS_ESTADO` y `USUARIOS_CLAVE`). El viejo
> `GESTIONAR_USUARIOS` **ya no existe**: el import lo borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.

> **El módulo Empleados usa 6 permisos finos** (`EMPLEADOS_VER`,
> `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`,
> `GESTIONAR_PERMISOS_EMPLEADO` y `GESTIONAR_VACACIONES_EMPLEADO`) más
> `GESTIONAR_CONTRATOS` para el bloque de contratos, `GESTIONAR_BONOS_EMPLEADO`
> para la pantalla de bonos (18/11/2026) y `GESTIONAR_NOMINA` para el recibo y
> su pago. El viejo `GESTIONAR_EMPLEADOS` **ya no existe**: mismo borrado en
> cascada que `GESTIONAR_USUARIOS`. La asistencia **ya no vive acá**: desde el
> 23/10/2026 tiene su propio ítem y sus propios permisos (ver más abajo).

> **`GESTIONAR_NOMINA` no reutiliza `GESTIONAR_BONOS_EMPLEADO`** (18/11/2026):
> no es lo mismo cargar y anular plata suelta que cerrar el mes de una persona.
> El permiso nuevo deja la matriz honesta si mañana hay una tabla de nómina de
> verdad. Las tres rutinas del recibo y del pago lo exigen, y el ítem
> «Empleados» del menú principal también lo incluye: si no, un rol solo-nómina
> no vería la puerta.

> **El módulo Clientes usa 4 permisos finos** (`CLIENTES_VER`, `CLIENTES_CREAR`,
> `CLIENTES_EDITAR` y `CLIENTES_ESTADO`). Los viejos `GESTIONAR_CLIENTES` y
> `CONSULTAR_CLIENTES` **ya no existen**: el import los borra del catálogo y el
> `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.
>
> **El módulo Categorías usa 4 permisos finos** (`CATEGORIAS_VER`,
> `CATEGORIAS_CREAR`, `CATEGORIAS_EDITAR` y `CATEGORIAS_ESTADO`). El viejo
> `GESTIONAR_CATEGORIAS` **ya no existe**: lo borra el módulo 49 (idempotente) y
> el `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.
>
> **El módulo Marcas usa 4 permisos finos** (`MARCAS_VER`, `MARCAS_CREAR`,
> `MARCAS_EDITAR` y `MARCAS_ESTADO`). El viejo `GESTIONAR_MARCAS` **ya no
> existe**: lo borra el módulo 50 (idempotente) y el `ON DELETE CASCADE` limpia
> sus pares en `ROL_PERMISO`.
>
> **El módulo Métodos de pago usa 4 permisos finos** (`METODOS_PAGO_VER`,
> `METODOS_PAGO_CREAR`, `METODOS_PAGO_EDITAR` y `METODOS_PAGO_ESTADO`). El viejo
> `GESTIONAR_METODOS_PAGO` **ya no existe**: lo borra el módulo 51 (idempotente)
> y el `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.
>
> **El módulo Compras usa 6 permisos finos** (`COMPRAS_VER`, `COMPRAS_REGISTRAR`,
> `COMPRAS_PAGAR`, `COMPRAS_CANCELAR`, `COMPRAS_DEVOLVER` y `COMPRAS_REPORTES`).
> El viejo `GESTIONAR_COMPRAS` **ya no existe**: lo borra el módulo 52
> (idempotente) y el `ON DELETE CASCADE` limpia sus pares en `ROL_PERMISO`.
> `COMPRAS_REPORTES` habilita las dos opciones de reporte (Reporte por periodo y
> Precios por suplidor). Las altas rápidas dentro de la compra no dependen de
> Compras: el producto exige `GESTIONAR_PRODUCTOS` y el suplidor
> `PROVEEDORES_CREAR`.
>
> **El módulo Inventario usa 3 permisos finos** (`INVENTARIO_VER`,
> `INVENTARIO_AJUSTAR` e `INVENTARIO_COSTO`). El viejo `GESTIONAR_INVENTARIO`
> **ya no existe**: lo borra el módulo 58 (idempotente) y el `ON DELETE CASCADE`
> limpia sus pares en `ROL_PERMISO`.
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
> **Los permisos se consultan en el código**: los de Empleados y Asistencia en
> `empleados.cpp`, los de Clientes en `clientes.cpp`, los de Proveedores en
> `proveedores.cpp`, los de Categorías en `categorias.cpp`, los de Marcas en
> `marcas.cpp`, los de Métodos de pago en `metodos_pago.cpp`, los de Compras en
> `compras.cpp`, los de Inventario en `inventario.cpp`, los de Productos en
> `productos.cpp` y los de Ventas en `ventas.cpp`; el menú principal, en `roles.cpp`. `REGISTRAR_ASISTENCIA` abre
> el ítem propio `Asistencia` (primero del menú), no `Empleados`.
> `SOLICITAR_PERMISO` lo usa el menú principal (`Mis permisos` y
> `Mis vacaciones`).

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

**Matriz que queda al importar** (verificada en `BALBU_TECH_TEST` el
18/11/2026: **63 permisos** y **232 pares** rol-permiso):

| Rol | Permisos |
|---|---|
| `ADMIN` | **los 63** |
| `GERENTE` | todos **menos** `GESTIONAR_ROLES` y los 5 `USUARIOS_*` (57) |
| `SUBGERENTE` | todos **menos** `GESTIONAR_ROLES`, los 5 `USUARIOS_*`, `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`, `EMPLEADOS_BAJA`, `GESTIONAR_PERMISOS_EMPLEADO`, `GESTIONAR_VACACIONES_EMPLEADO`, `GESTIONAR_BONOS_EMPLEADO`, `GESTIONAR_NOMINA` y `GESTIONAR_CONTRATOS` (49) |
| `RRHH` | los 6 finos de Empleados, `GESTIONAR_CONTRATOS`, `GESTIONAR_BONOS_EMPLEADO`, `GESTIONAR_NOMINA`, `CONSULTAR_REPORTES`, `CONSULTAR_ASISTENCIA`, `REGISTRAR_ASISTENCIA`, `JUSTIFICAR_ASISTENCIA` y `SOLICITAR_PERMISO` (14) |
| `VENDEDOR` | `GESTIONAR_VENTAS`, `CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`, `METODOS_PAGO_VER`, `CONSULTAR_HISTORIAL_VENTA`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` (15) |
| `ALMACEN` | `GESTIONAR_PRODUCTOS`, `CATEGORIAS_VER`, `CATEGORIAS_CREAR`, `CATEGORIAS_EDITAR`, `CATEGORIAS_ESTADO`, `MARCAS_VER`, `MARCAS_CREAR`, `MARCAS_EDITAR`, `MARCAS_ESTADO`, `INVENTARIO_VER`, `INVENTARIO_AJUSTAR`, `INVENTARIO_COSTO`, `COMPRAS_VER`, `COMPRAS_REGISTRAR`, `COMPRAS_PAGAR`, `COMPRAS_CANCELAR`, `COMPRAS_DEVOLVER`, `COMPRAS_REPORTES`, `PROVEEDORES_VER`, `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR`, `PROVEEDORES_ESTADO`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`, `SOLICITAR_PERMISO` (26) |
| `CONTABILIDAD` | `CONSULTAR_REPORTES`, `CONSULTAR_PRODUCTOS`, `CLIENTES_VER`, `REGISTRAR_ASISTENCIA` (5) |
| `TECNICO` | `GARANTIAS_AVANZAR`, `GARANTIAS_CONSULTAR` y `CONSULTAR_PRODUCTOS` (3) |

> Total: **232 pares rol-permiso** (63 + 57 + 49 + 14 + 15 + 26 + 5 + 3).
>
> `TECNICO` es el rol del técnico de garantías: entra con su propio usuario
> (`USUARIOS.ID_EMPLEADO`) y solo avanza las reparaciones que tiene asignadas.
> Sus 3 permisos se reparten en la sección de garantías del módulo
> (`GARANTIAS_AVANZAR` también lo tienen ADMIN, GERENTE y SUBGERENTE).
>
> **Las cuentas de esta tabla se midieron contra la base**, no se estimaron. Si
> un import futuro cambia la matriz, esta tabla es la que hay que volver a
> contar.

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

> Desde el 26/10/2026 `VENDEDOR` no tiene `CLIENTES_VER`: ve 4 opciones
> (Agregar, Actualizar, Cambiar Estado y Volver) y puede mantener un cliente
> conocido por ID, pero no buscarlo ni listarlo.

### Mapa del submenú de Proveedores

El submenú conserva el orden histórico de 6 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar proveedor | `PROVEEDORES_CREAR` |
| 2 | Actualizar proveedor | `PROVEEDORES_EDITAR` |
| 3 | Cambiar estado | `PROVEEDORES_ESTADO` |
| 4 | Buscar proveedor | `PROVEEDORES_VER` |
| 5 | Listar proveedores | `PROVEEDORES_VER` |
| 6 | Volver al Menu Principal | *(siempre)* |

> **El corte cae donde el módulo solo tenía un permiso de acceso.** Un rol con
> solo `PROVEEDORES_VER` ve 3 opciones (Buscar, Listar, Volver); `ALMACEN`, con
> los cuatro, sigue viendo las 6.

### Mapa del submenú de Categorías

El submenú conserva el orden histórico de 5 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Categoria | `CATEGORIAS_CREAR` |
| 2 | Actualizar Categoria | `CATEGORIAS_EDITAR` |
| 3 | Activar/Desactivar Categoria | `CATEGORIAS_ESTADO` |
| 4 | Buscar Categoria | `CATEGORIAS_VER` |
| 5 | Volver al Menu Principal | *(siempre)* |

> **Categorías deja de usar el paraguas `GESTIONAR_CATEGORIAS`.** Un rol con
> solo `CATEGORIAS_VER` ve 2 opciones (Buscar, Volver); `ALMACEN`, con los
> cuatro, ve las 5. La migración de una base existente es el módulo 49.

### Mapa del submenú de Marcas

El submenú conserva el orden histórico de 6 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Marca | `MARCAS_CREAR` |
| 2 | Actualizar Marca | `MARCAS_EDITAR` |
| 3 | Cambiar estado | `MARCAS_ESTADO` |
| 4 | Buscar Marca | `MARCAS_VER` |
| 5 | Listar Marcas | `MARCAS_VER` |
| 6 | Volver al Menu Principal | *(siempre)* |

> **Marcas deja de usar el paraguas `GESTIONAR_MARCAS`.** Un rol con solo
> `MARCAS_VER` ve 3 opciones (Buscar, Listar, Volver); `ALMACEN`, con los
> cuatro, ve las 6. La migración de una base existente es el módulo 50.

### Mapa del submenú de Métodos de pago

El submenú conserva el orden histórico de 6 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Agregar Metodo | `METODOS_PAGO_CREAR` |
| 2 | Actualizar Datos | `METODOS_PAGO_EDITAR` |
| 3 | Activar/Desactivar Metodo | `METODOS_PAGO_ESTADO` |
| 4 | Buscar Metodo | `METODOS_PAGO_VER` |
| 5 | Listar Metodos | `METODOS_PAGO_VER` |

> `Volver al Menu Principal` cierra la lista y no pide permiso.
>
> **Métodos de pago deja de usar el paraguas `GESTIONAR_METODOS_PAGO`.** Un rol
> con solo `METODOS_PAGO_VER` ve 3 opciones (Buscar, Listar, Volver);
> `ADMIN`, `GERENTE` y `SUBGERENTE`, con los cuatro, ven las 6. Desde el
> 26/10/2026 `VENDEDOR` solo consulta y ve las 3. La migración de una base
> existente es el módulo 51.

### Mapa del submenú de Compras

El submenú conserva el orden histórico de 8 opciones, pero **numera solo lo
visible**. Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Compra rapida (carrito) | `COMPRAS_REGISTRAR` |
| 2 | Ver compra con IVA | `COMPRAS_VER` |
| 3 | Devolucion de compra | `COMPRAS_DEVOLVER` |
| 4 | Reporte por periodo | `COMPRAS_REPORTES` |
| 5 | Pagar compra | `COMPRAS_PAGAR` |
| 6 | Precios por suplidor | `COMPRAS_REPORTES` |
| 7 | Cancelar compra | `COMPRAS_CANCELAR` |
| 8 | Volver al Menu Principal | *(siempre)* |

> `COMPRAS_REPORTES` cubre las dos opciones de reporte (Reporte por periodo y
> Precios por suplidor). `COMPRAS_VER` solo abre `Ver compra con IVA`: no
> habilita reportes ni pagos.
>
> **Compras deja de usar el paraguas `GESTIONAR_COMPRAS`.** Un rol con solo
> `COMPRAS_VER` ve 2 opciones (Ver compra con IVA y Volver); `ALMACEN`, con los
> seis, ve las 8. La migración de una base existente es el módulo 52.
>
> **El alta rápida dentro de la compra no la habilita Compras**: registrar un
> producto inexistente exige `GESTIONAR_PRODUCTOS` y registrar un suplidor
> inexistente exige `PROVEEDORES_CREAR`. Sin esos permisos la app informa que no
> puede crearlos y no llama al alta rápida.
>
> **Registrar una compra mueve stock por diseño**: `22_SP_AGREGAR_DETALLE_COMPRA`
> suma inventario y `SP_CANCELAR_COMPRA` lo repone. `COMPRAS_REGISTRAR` no
> duplica `INVENTARIO_AJUSTAR`; el efecto es parte del flujo de compra.

### Mapa del submenú de Inventario

El submenú tiene las 3 acciones más `Volver`, y **numera solo lo visible**.
Cada opción pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Ajuste de stock | `INVENTARIO_AJUSTAR` |
| 2 | Ajustar p.compra | `INVENTARIO_COSTO` |
| 3 | Movimientos | `INVENTARIO_VER` |
| 4 | Volver al Menu Principal | *(siempre)* |

> **Inventario deja de usar el paraguas `GESTIONAR_INVENTARIO`** y es el último
> módulo de la Tanda B en migrar. Un rol con solo `INVENTARIO_VER` ve 2 opciones
> (Movimientos y Volver); `ALMACEN`, con los tres, ve las 4. La migración de una
> base existente es el módulo 58.

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
| 12 | Ver auditoria de permisos | `GESTIONAR_PERMISOS_EMPLEADO` |
| 13 | Gestionar vacaciones | `GESTIONAR_VACACIONES_EMPLEADO` |
| 14 | Gestionar bonos | `GESTIONAR_BONOS_EMPLEADO` |
| 15 | Nomina (recibo y pago) | `GESTIONAR_NOMINA` |
| 16 | Volver al Menu Principal | *(siempre)* |

> `SUBGERENTE` conserva el ítem `Empleados` con `EMPLEADOS_VER`: ve solo
> `Buscar`, `Listar` y `Volver`. `VENDEDOR` ya no entra a Empleados; ficha desde
> el ítem `Asistencia`.
>
> El ítem `Empleados` del menú principal se abre con **cualquiera** de sus
> permisos finos (`EMPLEADOS_VER`, `EMPLEADOS_CREAR`, `EMPLEADOS_EDITAR`,
> `EMPLEADOS_BAJA`, `GESTIONAR_PERMISOS_EMPLEADO`,
> `GESTIONAR_VACACIONES_EMPLEADO`, `GESTIONAR_BONOS_EMPLEADO`,
> `GESTIONAR_NOMINA`, `GESTIONAR_CONTRATOS`). Un permiso que no esté en esa
> lista deja la pantalla inalcanzable aunque el rol lo tenga: pasó con
> `GESTIONAR_NOMINA` y se corrigió antes de commitear.

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
> principal nunca lo aceptó). Todos los submenús con el patrón —Asistencia,
> Usuarios, Empleados, Clientes, Proveedores, Categorías, Marcas, Productos,
> Métodos de pago, Ventas, Compras y Caja— se comportan igual.

### Mapa del submenú de Caja

El submenú conserva el orden histórico y **numera solo lo visible**. Cada opción
pide un permiso; `Volver` es siempre visible.

| # | Opción | Permiso |
|---|---|---|
| 1 | Abrir caja | `ABRIR_CAJA` |
| 2 | Estado de la caja | `CONSULTAR_CAJA` |
| 3 | Cerrar caja (cuadre) | `CERRAR_CAJA` |
| 4 | Volver al Menu Principal | *(siempre)* |

`ADMIN`, `GERENTE`, `SUBGERENTE` y `VENDEDOR` tienen los tres permisos y ven las
4 opciones. El vendedor abre su turno al empezar y lo cierra al terminar. El
cierre sigue siendo directo, sin confirmación de un segundo actor: el flujo con
firma del cuadre quedó fuera de esta fase.

> **Caja ya no cuelga de `GESTIONAR_VENTAS`.** Un rol con solo ese permiso deja
> de ver el ítem. El módulo 53 migra los roles existentes; un rol creado después
> necesita `CONSULTAR_CAJA`, `ABRIR_CAJA` o `CERRAR_CAJA`.

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

## Matriz de permisos finos

El módulo es el único dueño de la matriz: absorbe diez módulos que antes
repartían los permisos finos en archivos separados (45, 46, 47, 49, 50, 51, 52,
53, 58 y 62). Cada sección conserva su texto original.

| Sección | Módulo absorbido | Qué agrega |
|---|---|---|
| 1 | [45- PERMISO_CONSULTAR_ASISTENCIA.md](#1-45-permiso-consultar-asistencia) | 45 - Permiso CONSULTAR_ASISTENCIA | `CONSULTAR_ASISTENCIA`, `CONSULTAR_REPORTES`, `EMPLEADOS_VER`, `JUSTIFICAR_ASISTENCIA`, `REGISTRAR_ASISTENCIA` |
| 2 | [46- PERMISOS_PROVEEDORES.md](#2-46-permisos-finos-de-proveedores) | 46 - Permisos finos de Proveedores | `GESTIONAR_PROVEEDORES`, `PROVEEDORES`, `PROVEEDORES_CREAR`, `PROVEEDORES_EDITAR`, `PROVEEDORES_ESTADO`, `PROVEEDORES_VER` |
| 3 | [47- PERMISO_HISTORIAL_VENTA.md](#3-47-permiso-consultar-historial-venta) | 47 - Permiso CONSULTAR_HISTORIAL_VENTA | `CONSULTAR_HISTORIAL_VENTA`, `CONSULTAR_REPORTES`, `GESTIONAR_VENTAS` |
| 4 | [49- PERMISOS_CATEGORIAS.md](#4-49-permisos-finos-de-categor-as) | 49 - Permisos finos de Categorías | `CATEGORIAS`, `CATEGORIAS_CREAR`, `CATEGORIAS_EDITAR`, `CATEGORIAS_ESTADO`, `CATEGORIAS_VER`, `GESTIONAR_CATEGORIAS` |
| 5 | [50- PERMISOS_MARCAS.md](#5-50-permisos-finos-de-marcas) | 50 - Permisos finos de Marcas | `GESTIONAR_MARCAS`, `MARCAS`, `MARCAS_CREAR`, `MARCAS_EDITAR`, `MARCAS_ESTADO`, `MARCAS_VER` |
| 6 | [51- PERMISOS_METODOS_PAGO.md](#6-51-permisos-finos-de-m-todos-de-pago) | 51 - Permisos finos de Métodos de pago | `DELETE`, `GESTIONAR_METODOS_PAGO`, `METODOS_PAGO`, `METODOS_PAGO_CREAR`, `METODOS_PAGO_EDITAR`, `METODOS_PAGO_ESTADO` |
| 7 | [52- PERMISOS_COMPRAS.md](#7-52-permisos-finos-de-compras) | 52 - Permisos finos de Compras | `COMPRAS`, `COMPRAS_CANCELAR`, `COMPRAS_DEVOLVER`, `COMPRAS_PAGAR`, `COMPRAS_REGISTRAR`, `COMPRAS_REPORTES` |
| 8 | [53- PERMISOS_CAJA.md](#8-53-permisos-finos-de-caja) | 53 - Permisos finos de Caja | `ABRIR_CAJA`, `CERRAR_CAJA`, `CONSULTAR_CAJA`, `GESTIONAR_VENTAS`, `TURNO_CAJA` |
| 9 | [58- PERMISOS_INVENTARIO.md](#9-58-permisos-finos-de-inventario) | 58 - Permisos finos de Inventario | `GESTIONAR_INVENTARIO`, `INVENTARIO_AJUSTAR`, `INVENTARIO_COSTO`, `INVENTARIO_VER` |
| 10 | [62- PERMISOS_GARANTIAS.md](#10-62-permisos-finos-de-garantias) | 62 - Permisos finos de Garantias | `BALBU_TECH_TEST`, `GARANTIAS_CONSULTAR`, `GARANTIAS_FINALIZAR`, `GARANTIAS_RECLAMAR`, `GARANTIAS_REGISTRAR`, `GESTIONAR_VENTAS` |

Ninguna sección usa los roles `EMPLEADO` ni `CAJERO`, así que el resultado no
depende del orden entre estos diez parches y la sección `MIGRACION_ROLES` del
final, que solo borra los pares y los roles de esos dos nombres.

El bloque va **al final** del módulo a propósito: primero se crean las tablas,
los 54 permisos base y la matriz de los siete roles; después se reparten los
finos. Es el mismo orden que tenían como archivos aparte.

> **Aviso de despliegue.** Varias secciones borran el permiso paraguas
> (`GESTIONAR_COMPRAS`, `GESTIONAR_PROVEEDORES`, ...). El binario tiene que estar
> desplegado antes: el binario viejo sigue pidiendo el paraguas y el ítem
> desaparece del menú hasta que se actualice. No se pierden datos.

### 1. 45 - Permiso CONSULTAR_ASISTENCIA

##### Qué hace

Separa los reportes de asistencia del permiso general `CONSULTAR_REPORTES` y
habilita el fichaje a todos los roles. La asistencia deja de depender del
módulo Empleados: pasa a un ítem propio del menú principal.

##### Matriz que deja

| Permiso | Roles |
|---|---|
| `REGISTRAR_ASISTENCIA` | ADMIN, GERENTE, SUBGERENTE, RRHH, VENDEDOR, ALMACEN, CONTABILIDAD |
| `CONSULTAR_ASISTENCIA` | ADMIN, GERENTE, SUBGERENTE, RRHH |
| `JUSTIFICAR_ASISTENCIA` | ADMIN, GERENTE, RRHH, SUBGERENTE |
| `EMPLEADOS_VER` | ADMIN, GERENTE, SUBGERENTE, RRHH |

VENDEDOR no recibe `CONSULTAR_ASISTENCIA`: el cajero puede fichar y ver su
propia asistencia, pero no la de todos. Conserva `CONSULTAR_REPORTES` y todos
los reportes de venta.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH_TEST < "modulos/45- PERMISO_CONSULTAR_ASISTENCIA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué no hace

- No borra permisos ni pares rol-permiso.
- No toca datos de empleados, contratos ni asistencia.
- No crea procedimientos almacenados.

---

### 2. 46 - Permisos finos de Proveedores

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_PROVEEDORES` por cuatro permisos
finos, con el mismo corte que Clientes:

| Permiso | Acción |
|---|---|
| `PROVEEDORES_VER` | Buscar y listar |
| `PROVEEDORES_CREAR` | Agregar |
| `PROVEEDORES_EDITAR` | Actualizar |
| `PROVEEDORES_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Proveedores del menú principal
se muestra con cualquiera de los cuatro, y cada opción del submenú pide el
suyo.

##### Matriz que deja

| Rol | Permisos de Proveedores |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `ALMACEN` | los 4 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **34 permisos** y **122 pares rol-permiso**
(ADMIN 34, GERENTE 28, SUBGERENTE 22, RRHH 12, VENDEDOR 10, ALMACEN 12,
CONTABILIDAD 4).

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_PROVEEDORES`; si el módulo corre
antes, el ítem Proveedores desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/46- PERMISOS_PROVEEDORES.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- Cualquier rol personalizado que tuviera `GESTIONAR_PROVEEDORES` recibe los
  cuatro permisos finos antes de que se borre el paraguas.
- Los roles del set final (`ADMIN`, `GERENTE`, `SUBGERENTE`, `ALMACEN`)
  reciben los cuatro aunque el paraguas ya no exista.
- No toca datos de proveedores, compras ni productos.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `PROVEEDORES`.
- No crea procedimientos almacenados.

---

### 3. 47 - Permiso CONSULTAR_HISTORIAL_VENTA

##### Qué hace

Separa el historial de venta del permiso general `CONSULTAR_REPORTES`. La
opción `Historial de venta` del submenú Ventas pasa a pedir
`CONSULTAR_HISTORIAL_VENTA`, así el vendedor conserva el historial aunque no
tenga reportes ni ganancias. `Garantías` no cambia: sigue con
`GESTIONAR_VENTAS`.

Con este cambio, `VENDEDOR` ve **10 opciones** en Ventas: las 7 de gestión,
`Historial de venta`, `Garantías` y `Volver`. Deja de ver `Reporte por rango`,
`Ganancias`, `Reporte por periodo`, `Ganancias por periodo` y
`Exportar datos para la web`.

##### Matriz que deja

| Permiso | Roles |
|---|---|
| `CONSULTAR_HISTORIAL_VENTA` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `CONSULTAR_REPORTES` | ADMIN, GERENTE, SUBGERENTE, RRHH, CONTABILIDAD (VENDEDOR ya no) |

Totales después de la migración: **35 permisos** y **125 pares rol-permiso**
(ADMIN 35, GERENTE 29, SUBGERENTE 23, RRHH 12, VENDEDOR 10, ALMACEN 12,
CONTABILIDAD 4).

`VENDEDOR` cambia un permiso por otro y sigue con 10; `ADMIN`, `GERENTE` y
`SUBGERENTE` suman uno cada uno. Por eso el total pasa de 122 a 125 pares.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `CONSULTAR_REPORTES` para el historial; si el
módulo corre antes, la opción desaparece del submenú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta una opción.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/47- PERMISO_HISTORIAL_VENTA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `VENDEDOR` quedan con el historial; los
  tres primeros también conservan `CONSULTAR_REPORTES`.
- `RRHH` y `CONTABILIDAD` no cambian: conservan `CONSULTAR_REPORTES`.
  `ALMACEN` no tiene ese permiso y tampoco lo necesita.
- No toca datos de ventas, pagos, caja ni garantías.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas de ventas.
- No crea permisos de Garantías: esa opción sigue con `GESTIONAR_VENTAS`.
- No crea procedimientos almacenados.

---

### 4. 49 - Permisos finos de Categorías

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_CATEGORIAS` por cuatro permisos
finos, con el mismo corte que Clientes y Proveedores:

| Permiso | Acción |
|---|---|
| `CATEGORIAS_VER` | Buscar |
| `CATEGORIAS_CREAR` | Agregar |
| `CATEGORIAS_EDITAR` | Actualizar |
| `CATEGORIAS_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Categorías del menú principal se
muestra con cualquiera de los cuatro, y cada opción del submenú pide el suyo.
`Volver` es siempre visible.

##### Matriz que deja

| Rol | Permisos de Categorías |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `ALMACEN` | los 4 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **38 permisos** y **137 pares rol-permiso**
(ADMIN 38, GERENTE 32, SUBGERENTE 26, RRHH 12, VENDEDOR 10, ALMACEN 15,
CONTABILIDAD 4).

El catálogo pasa de 35 a 38: se va un permiso y entran cuatro. Cada uno de los
cuatro roles que tenía el paraguas gana tres pares (los cuatro finos menos el
viejo), así que el total pasa de 125 a 137.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_CATEGORIAS`; si el módulo corre
antes, el ítem Categorías desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/49- PERMISOS_CATEGORIAS.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los cuatro permisos
  finos aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de categorías, productos, marcas ni movimientos de inventario.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `CATEGORIAS`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_CATEGORIAS`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).

---

### 5. 50 - Permisos finos de Marcas

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_MARCAS` por cuatro permisos
finos, con el mismo corte que Clientes, Proveedores y Categorías:

| Permiso | Acción |
|---|---|
| `MARCAS_VER` | Buscar y Listar |
| `MARCAS_CREAR` | Agregar |
| `MARCAS_EDITAR` | Actualizar |
| `MARCAS_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Marcas del menú principal se
muestra con cualquiera de los cuatro, y cada opción del submenú pide el suyo.
`Volver` es siempre visible.

##### Matriz que deja

| Rol | Permisos de Marcas |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `ALMACEN` | los 4 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **41 permisos** y **149 pares rol-permiso**
(ADMIN 41, GERENTE 35, SUBGERENTE 29, RRHH 12, VENDEDOR 10, ALMACEN 18,
CONTABILIDAD 4).

El catálogo pasa de 38 a 41: se va un permiso y entran cuatro. Cada uno de los
cuatro roles que tenía el paraguas gana tres pares (los cuatro finos menos el
viejo), así que el total pasa de 137 a 149.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_MARCAS`; si el módulo corre
antes, el ítem Marcas desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/50- PERMISOS_MARCAS.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los cuatro permisos
  finos aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de marcas, productos, categorías ni movimientos de inventario.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `MARCAS`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_MARCAS`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).

---

### 6. 51 - Permisos finos de Métodos de pago

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_METODOS_PAGO` por cuatro permisos
finos, con el mismo corte que Clientes, Proveedores, Categorías y Marcas:

| Permiso | Acción |
|---|---|
| `METODOS_PAGO_VER` | Buscar y Listar |
| `METODOS_PAGO_CREAR` | Agregar |
| `METODOS_PAGO_EDITAR` | Actualizar |
| `METODOS_PAGO_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Métodos de pago del menú
principal se muestra con cualquiera de los cuatro, y cada opción del submenú
pide el suyo. `Volver` es siempre visible.

##### Matriz que deja

| Rol | Permisos de Métodos de pago |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `VENDEDOR` | solo `METODOS_PAGO_VER` |
| `RRHH` | ninguno |
| `ALMACEN` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales en su primera aplicación (23/10/2026): **44 permisos** y **161 pares
rol-permiso** (ADMIN 44, GERENTE 38, SUBGERENTE 32, RRHH 12, VENDEDOR 13,
ALMACEN 18, CONTABILIDAD 4).

> (26/10/2026) VENDEDOR ya no recibe los cuatro: conserva solo
> `METODOS_PAGO_VER` y el `DELETE` de abajo le quita los tres de gestión. La
> matriz vigente completa está en la tabla «Matriz que queda al importar» de
> este mismo documento.

El catálogo pasa de 41 a 44: se va un permiso y entran cuatro. Cada uno de los
cuatro roles que tenía el paraguas gana tres pares (los cuatro finos menos el
viejo), así que el total pasa de 149 a 161.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_METODOS_PAGO`; si el módulo corre
antes, el ítem Métodos de pago desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/51- PERMISOS_METODOS_PAGO.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE` y `SUBGERENTE` reciben los cuatro permisos finos aunque el
  paraguas ya no exista (base nueva o reimportación del 36).
- (26/10/2026) `VENDEDOR` recibe solo `METODOS_PAGO_VER`: consulta los métodos
  existentes y no los mantiene.
- `RRHH`, `ALMACEN` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de métodos de pago, ventas, pagos ni cierres de caja.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `METODOS_PAGO`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_METODOS_PAGO`,
  el módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).

---

### 7. 52 - Permisos finos de Compras

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_COMPRAS` por seis permisos finos, con
el mismo patrón que Clientes, Proveedores, Categorías, Marcas y Métodos de pago:

| Permiso | Acción |
|---|---|
| `COMPRAS_VER` | Ver compra con IVA |
| `COMPRAS_REGISTRAR` | Compra rápida (carrito) |
| `COMPRAS_PAGAR` | Pagar compra |
| `COMPRAS_CANCELAR` | Cancelar compra |
| `COMPRAS_DEVOLVER` | Devolución de compra |
| `COMPRAS_REPORTES` | Reporte por periodo y Precios por suplidor |

La app deja de usar el permiso viejo: el ítem Compras del menú principal se
muestra con cualquiera de los seis, y cada opción del submenú pide el suyo.
`Volver` es siempre visible.

##### Matriz que deja

| Rol | Permisos de Compras |
|---|---|
| `ADMIN` | los 6 |
| `GERENTE` | los 6 |
| `SUBGERENTE` | los 6 |
| `ALMACEN` | los 6 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **49 permisos** y **181 pares rol-permiso**
(ADMIN 49, GERENTE 43, SUBGERENTE 37, RRHH 12, VENDEDOR 13, ALMACEN 23,
CONTABILIDAD 4).

El catálogo pasa de 44 a 49: se va un permiso y entran seis. Cada uno de los
cuatro roles que tenía el paraguas gana cinco pares (los seis finos menos el
viejo), así que el total pasa de 161 a 181.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_COMPRAS`; si el módulo corre antes,
el ítem Compras desaparece del menú hasta que se despliegue el binario nuevo.
No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/52- PERMISOS_COMPRAS.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los seis permisos finos
  aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de compras, pagos, devoluciones, inventario ni proveedores.
- Las altas rápidas de producto y suplidor siguen exigiendo
  `GESTIONAR_PRODUCTOS` y `PROVEEDORES_CREAR`: el permiso de Compras no las
  habilita por sí solo.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas `COMPRAS`, `DETALLE_COMPRA`, `PAGOS_COMPRA` ni
  `DEVOLUCION_COMPRA`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_COMPRAS`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).

---

### 8. 53 - Permisos finos de Caja

##### Qué hace

Separa el módulo Caja de `GESTIONAR_VENTAS` con tres permisos propios:

| Permiso | Acción |
|---|---|
| `CONSULTAR_CAJA` | Ver el estado del turno abierto |
| `ABRIR_CAJA` | Abrir el turno de la caja |
| `CERRAR_CAJA` | Cerrar el turno y registrar el cuadre |

El ítem Caja del menú principal se muestra con cualquiera de los tres, y cada
opción del submenú pide el suyo. `Volver` es siempre visible.
`GESTIONAR_VENTAS` sigue existiendo y sigue mandando en el módulo Ventas.

> El cierre sigue siendo directo: el vendedor abre, consulta y cierra su turno,
> sin confirmación de un segundo actor. El flujo con firma del cuadre queda
> para una fase posterior.

##### Matriz que deja

| Rol | Permisos de Caja |
|---|---|
| `ADMIN` | los 3 |
| `GERENTE` | los 3 |
| `SUBGERENTE` | los 3 |
| `VENDEDOR` | los 3 |
| `RRHH` | ninguno |
| `ALMACEN` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **52 permisos** y **193 pares rol-permiso**
(ADMIN 52, GERENTE 46, SUBGERENTE 40, RRHH 12, VENDEDOR 16, ALMACEN 23,
CONTABILIDAD 4).

> (26/10/2026) VENDEDOR bajó a 12 permisos y el total a 197 por el ajuste de
> Clientes y Métodos de pago. Los totales de arriba son los de esta migración;
> la matriz vigente está en `36- PERMISOS_ROLES.md`.

El catálogo pasa de 49 a 52: entran tres permisos y cada uno de los cuatro
roles que ya veía Caja gana tres pares, así que el total pasa de 181 a 193.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo pide `GESTIONAR_VENTAS` para el ítem Caja; si el módulo corre
antes, el ítem desaparece del menú hasta que se despliegue el binario nuevo.
No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/53- PERMISOS_CAJA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- Los cuatro roles del set que ya veían Caja reciben los tres permisos finos
  aunque el ítem ya no mire `GESTIONAR_VENTAS`.
- Los roles personalizados que hoy tengan `GESTIONAR_VENTAS` también reciben
  los tres, para que no pierdan el módulo.
- No toca turnos, pagos ni cuadres existentes.

##### Qué no hace

- No borra roles, usuarios ni permisos.
- No modifica `TURNO_CAJA` ni sus procedimientos.
- No agrega estados de cierre ni confirmación por un segundo actor.
- No toca los otros módulos del menú.

---

### 9. 58 - Permisos finos de Inventario

##### Qué hace

Reemplaza el permiso paraguas `GESTIONAR_INVENTARIO` por tres permisos finos,
con el mismo patrón que Clientes, Proveedores, Categorías, Marcas, Métodos de
pago y Compras:

| Permiso | Acción |
|---|---|
| `INVENTARIO_VER` | Movimientos (kardex) |
| `INVENTARIO_AJUSTAR` | Ajuste de stock |
| `INVENTARIO_COSTO` | Ajustar p.compra |

La app deja de usar el permiso viejo: el ítem Inventario del menú principal se
muestra con cualquiera de los tres, y cada opción del submenú pide el suyo.
`Volver` es siempre visible. Es el **último módulo con permiso paraguas de la
Tanda B**.

##### Matriz que deja

| Rol | Permisos de Inventario |
|---|---|
| `ADMIN` | los 3 |
| `GERENTE` | los 3 |
| `SUBGERENTE` | los 3 |
| `ALMACEN` | los 3 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **54 permisos** y **201 pares rol-permiso**
(ADMIN 54, GERENTE 48, SUBGERENTE 42, RRHH 12, VENDEDOR 16, ALMACEN 25,
CONTABILIDAD 4).

> (26/10/2026) VENDEDOR bajó a 12 permisos y el total a 197 por el ajuste de
> Clientes y Métodos de pago. La matriz vigente está en la tabla «Matriz que
> queda al importar» de este documento.

El catálogo pasa de 52 a 54: se va un permiso y entran tres. Cada uno de los
cuatro roles que tenía el paraguas gana dos pares (los tres finos menos el
viejo), así que el total pasa de 193 a 201.

##### Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_INVENTARIO`; si el módulo corre
antes, el ítem Inventario desaparece del menú hasta que se despliegue el binario
nuevo. No se pierden datos: solo se oculta el módulo.

##### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/58- PERMISOS_INVENTARIO.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

##### Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los tres permisos finos
  aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de productos, stock, movimientos ni compras.
- Las compras siguen moviendo stock por diseño: ese efecto no depende de
  `INVENTARIO_AJUSTAR`.

##### Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas de inventario ni los procedimientos de stock.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_INVENTARIO`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).

---

### 10. 62 - Permisos finos de Garantias

##### Que hace

Saca Garantias de `GESTIONAR_VENTAS` y le da cuatro permisos propios, con el
mismo patron que Clientes, Proveedores, Inventario y demas:

| Permiso | Accion |
|---|---|
| `GARANTIAS_REGISTRAR` | Registrar una garantia a mano |
| `GARANTIAS_RECLAMAR` | Abrir un reclamo sobre una garantia vigente |
| `GARANTIAS_FINALIZAR` | Cerrar un reclamo (decision de Gerencia) |
| `GARANTIAS_CONSULTAR` | Ver garantias y reclamos |

El item "Garantias" del submenu de Ventas se muestra con cualquiera de los
cuatro, y cada opcion adentro pide el suyo. `Volver` es siempre visible.

La diferencia clave: **el vendedor atiende y registra, pero no cierra
reclamos**. `VENDEDOR` conserva registrar, reclamar y consultar.

##### Matriz que deja

| Rol | Registrar | Reclamar | Finalizar | Consultar |
|---|:-:|:-:|:-:|:-:|
| `ADMIN` | si | si | si | si |
| `GERENTE` | si | si | si | si |
| `SUBGERENTE` | si | si | si | si |
| `VENDEDOR` | si | si | **no** | si |
| `CONTABILIDAD` | no | no | no | si |
| `RRHH` | no | no | no | no |
| `ALMACEN` | no | no | no | no |

Totales despues de la migracion: **58 permisos** y **213 pares rol-permiso**
(ADMIN 58, GERENTE 52, SUBGERENTE 46, RRHH 12, VENDEDOR 15, ALMACEN 25,
CONTABILIDAD 5). Antes eran 54 permisos y 197 pares.

##### Por que

- `GESTIONAR_VENTAS` es el paraguas de nueve acciones de Ventas. Colgar
  Garantias de el obliga a dar todo el modulo de ventas a quien solo tiene
  que consultar una garantia.
- Contabilidad necesita ver garantias y reclamos para costos, pero no
  registrar ni decidir.
- Cerrar un reclamo es una decision con costo (cambio, devolucion,
  reembolso). El que atiende al cliente no deberia ser el que autoriza.

##### Orden de despliegue

1. Correr el módulo `25` completo (la sección del ex `63` va incluida).
2. Compilar y desplegar el binario nuevo.
3. Correr este modulo.

El binario viejo abre Garantias con `GESTIONAR_VENTAS`; si este modulo corre
antes, el item desaparece del menu hasta desplegar el binario nuevo. No se
pierden datos: solo se oculta el modulo.

##### Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/62- PERMISOS_GARANTIAS.sql"
```

Es idempotente: los permisos usan `ON DUPLICATE KEY UPDATE` y los pares
tambien, asi que correrlo dos veces no duplica nada.

##### Que preserva

- `GESTIONAR_VENTAS` no se borra ni se le quitan pares: lo siguen usando las
  otras nueve acciones de Ventas.
- Los roles que no estan en la matriz no reciben nada.
- No toca datos de ventas, garantias ni reclamos.
- No cambia los otros modulos del menu.

##### Que no hace

- No borra roles ni usuarios.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_VENTAS` y
  esperaba ver Garantias, deja de verla y no recibe los permisos finos.
- No crea procedimientos ni triggers: eso es el modulo 63.

##### Detalle de la app

`roles.cpp` agrega los cuatro permisos al item "Ventas" del menu principal.
Sin eso, `CONTABILIDAD` tendria `GARANTIAS_CONSULTAR` y no podria llegar a
usarlo: el modulo se abriria solo para quien tiene `GESTIONAR_VENTAS`.

##### Verificacion

Aplicado en `BALBU_TECH_TEST` el 30/10/2026, dos veces seguidas sin error:

- Matriz verificada: ADMIN 4, GERENTE 4, SUBGERENTE 4, VENDEDOR 3,
  CONTABILIDAD 1.
- Catalogo en 58 permisos y 213 pares.
- `GESTIONAR_VENTAS` sigue en ADMIN, GERENTE, SUBGERENTE y VENDEDOR.
- `test-menus-por-rol.sh`: el rol sintetico con solo `GESTIONAR_VENTAS` deja
  de ver Garantias (8 opciones en Ventas), y el submenu de Garantias muestra
  5 opciones para ADMIN, 4 para VENDEDOR (sin "Finalizar reclamo") y 2 para
  CONTABILIDAD.
- `test-migracion-roles.sh`: VENDEDOR pasa de 12 a 15 permisos.

---

## Procedimientos almacenados

### `SP_ASIGNAR_PERMISO_A_ROL(P_ROL_NOMBRE, P_NOMBRE_PERMISO)`

**Usada por la app** (`roles.cpp`).

- rol inexistente → `ERROR: EL ROL NO EXISTE EN EL SISTEMA.`
- permiso inexistente → `ERROR: EL PERMISO NO EXISTE.`
- Inserta con `ON DUPLICATE KEY UPDATE` (idempotente) y devuelve
  `EXITO: PERMISO <permiso> ASIGNADO A <rol>`.

> No existe camino para **crear** un permiso desde la app: solo se asignan los
> permisos sembrados.

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
  permisos de Usuarios (48); `SUBGERENTE` además no toca empleados ni contratos
  (42); `RRHH` conserva personal, contratos y reportes (12).
- **El módulo Usuarios usa 5 permisos finos** (`USUARIOS_VER`, `CREAR`,
  `EDITAR`, `ESTADO`, `CLAVE`); el submenú muestra solo las acciones habilitadas.
- **El módulo Empleados usa 7 permisos finos**; el submenú muestra solo las
  acciones habilitadas y renumera sobre lo visible.
- **El módulo Clientes usa 4 permisos finos** (`CLIENTES_VER`, `CREAR`,
  `EDITAR`, `ESTADO`); el submenú muestra solo las acciones habilitadas y
  renumera sobre lo visible.
- **`CLIENTES_VER` abre el módulo**; `CLIENTES_CREAR`, `CLIENTES_EDITAR` y
  `CLIENTES_ESTADO` solo habilitan su opción adentro.
- **El módulo de Categorías usa 4 permisos finos** (`CATEGORIAS_VER`, `CREAR`,
  `EDITAR`, `ESTADO`); el submenú muestra solo las acciones habilitadas y
  renumera sobre lo visible. `CATEGORIAS_VER` abre el ítem del menú principal.
- **El módulo de Marcas usa 4 permisos finos** (`MARCAS_VER`, `CREAR`, `EDITAR`,
  `ESTADO`); el submenú muestra solo las acciones habilitadas y renumera sobre
  lo visible. `MARCAS_VER` abre el ítem del menú principal.
- **El módulo de Métodos de pago usa 4 permisos finos** (`METODOS_PAGO_VER`,
  `CREAR`, `EDITAR`, `ESTADO`); el submenú muestra solo las acciones habilitadas
  y renumera sobre lo visible. `METODOS_PAGO_VER` abre el ítem del menú
  principal.
- **El módulo de Compras usa 6 permisos finos** (`COMPRAS_VER`, `REGISTRAR`,
  `PAGAR`, `CANCELAR`, `DEVOLVER`, `REPORTES`); el submenú muestra solo las
  acciones habilitadas y renumera sobre lo visible. `COMPRAS_REPORTES` cubre las
  dos opciones de reporte. Cualquiera de los seis abre el ítem del menú
  principal.
- **El módulo de Inventario usa 3 permisos finos** (`INVENTARIO_VER`,
  `INVENTARIO_AJUSTAR`, `INVENTARIO_COSTO`); el submenú muestra solo las
  acciones habilitadas y renumera sobre lo visible. Cualquiera de los tres abre
  el ítem del menú principal; con solo `INVENTARIO_VER` queda `Movimientos`.
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

## MIGRACION_ROLES (ex módulo 44)

Migración de roles: absorbida dentro del `36` el 14/11/2026 (ver «Estado de la
documentación» y el `## Log` de `odd/tasks/consolidacion-modulos.md`). El cuerpo
del ex `44` viaja **verbatim**: acá solo se degradaron los encabezados un nivel.

Script de migración, no de esquema: **no crea tablas, procedimientos, triggers ni
vistas**. Deja cualquier base existente en el set final de 7 roles y retira los
dos que el rediseño del 22/10/2026 absorbió.

Set final: `ADMIN`, `GERENTE`, `SUBGERENTE`, `RRHH`, `VENDEDOR`, `ALMACEN`,
`CONTABILIDAD`.

Retirados: `EMPLEADO` (renombrado a `VENDEDOR` en la base del trabajo) y
`CAJERO` (absorbido por `VENDEDOR`).

**Es usado por:** nadie desde la app. Es la última sección de este archivo, así
que corre al final del `36`; también se puede aplicar solo sobre una base ya
poblada.

Fuente: `modulos/36- PERMISOS_ROLES.sql`, sección del ex módulo `44` · Base:
`BALBU_TECH` · Revisado: 22/10/2026 · Fusionado: 14/11/2026.

### Por qué existe

Ninguno de los dos módulos **retira un rol**: el `INSERT IGNORE INTO ROLES` del 3
suma nombres y nunca borra los viejos, y el 36 sí limpia (borra los permisos
paraguas con sus pares y reconstruye la matriz) pero no toca las filas de
`ROLES`. La fila del rol retirado queda huérfana del set final.

Consecuencia en una base vieja: `EMPLEADO` y `CAJERO` sobrevivían como roles
**fuera del set de 7**. Los permisos paraguas que el 36 borra
(`GESTIONAR_EMPLEADOS`, `GESTIONAR_CLIENTES`, `GESTIONAR_USUARIOS`,
`CONSULTAR_CLIENTES`) desaparecen de esos roles por el `ON DELETE CASCADE` de
`FK_ROL_PERMISO_PERMISO`, pero los que sobreviven por nombre
(`GESTIONAR_VENTAS`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`,
`SOLICITAR_PERMISO`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_REPORTES`) siguen
asignados. O sea: el usuario sigue entrando con un menú recortado y a medias, con
un rol que ya no forma parte del modelo y que nadie vuelve a mirar.

El repo no tenía forma de arreglarlo. Según el informe del 22/10/2026, la
migración se aplicó a mano en la base del trabajo con un script que quedó en
`backups/` (gitignored); en este repo no hay ningún script así versionado
(`backups/` solo tiene `pre_asist_v2_20261017_100847.sql`). Este bloque hace ese
trabajo y queda versionado.

### Qué hace, en orden

| Paso | Sentencia | Por qué ese orden |
|---|---|---|
| 1 | `INSERT IGNORE` de los 7 roles | `USUARIOS.ID_ROL` es `NOT NULL`: sin el rol destino, el paso 2 no tiene a dónde mover |
| 2 | `UPDATE USUARIOS` de `EMPLEADO`/`CAJERO` a `VENDEDOR` | `FK_USUARIO_ROL` es `RESTRICT`: con usuarios colgando, el rol no se puede borrar |
| 3 | `DELETE FROM ROL_PERMISO` de los dos roles | `FK_ROL_PERMISO_ROL` es `RESTRICT`: con pares colgando, el rol no se puede borrar |
| 4 | `DELETE FROM ROLES` de los dos roles | recién acá no queda nada que los referencie |
| 5 | `SELECT` de comprobación | tiene que devolver `Roles retirados que quedan: 0` y 7 filas |

Las dos FKs que apuntan a `ROLES` **no tienen `ON DELETE`**: si se invierte el
orden, el `DELETE` falla y la migración queda a medias. Por eso el script va
numerado en ese orden y no se reordena.

> **Corrección al fusionar (14/11/2026):** el texto original decía «la matriz es
> del módulo `36`, que corre antes». Ahora la matriz y esta migración son el
> mismo archivo y el orden se cumple solo: la sección va **al final**. El riesgo
> que anotaba la spec S4 —que un parche fino asignara permisos a `EMPLEADO` o
> `CAJERO` y esta migración los borrara— ya no depende del orden de import: los
> diez parches finos van arriba y la migración abajo, siempre.

### Idempotencia

Se puede correr las veces que haga falta:

- En una base nueva (import desde cero) los pasos 2 a 4 no tocan ninguna fila:
  `EMPLEADO` y `CAJERO` no existen.
- Sobre una base ya migrada, el paso 2 no encuentra usuarios con esos roles y los
  pasos 3 y 4 no encuentran filas.
- Nunca duplica roles (`INSERT IGNORE` sobre `NOMBRE_ROL`, que es único) ni
  permisos.

### Qué NO hace

- **No toca roles personalizados** (`PRUEBA_*` del test, o cualquier rol creado a
  mano): solo actúa sobre los dos nombres retirados.
- **No reparte permisos**: la matriz es de este mismo archivo y va arriba. Los
  usuarios movidos a `VENDEDOR` heredan los 10 permisos de ese rol.
- **No borra empleados ni usuarios**: solo cambia el `ID_ROL` de los que estaban
  en los roles retirados.

### Verificación

```sql
SELECT NOMBRE_ROL FROM ROLES ORDER BY ID_ROL;                    -- 7 filas
SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO','CAJERO');  -- 0
SELECT R.NOMBRE_ROL, COUNT(*) FROM USUARIOS U JOIN ROLES R ON R.ID_ROL=U.ID_ROL
 GROUP BY R.NOMBRE_ROL;                                          -- sin EMPLEADO/CAJERO
```

Test automático: `db/test-migracion-roles.sh` (crea los dos roles retirados con un
usuario cada uno, extrae esta sección del `36`, la corre dos veces y verifica el
resultado).
