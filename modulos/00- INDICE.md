# Índice general — módulos de la base de datos

Los **58 módulos** de `BALBU_TECH`: qué guarda cada uno, qué objetos crea y si la
app lo usa. Cada módulo tiene su documento al lado del `.sql`, con el mismo
nombre.

**El `.sql` es la fuente de verdad; el `.md` lo explica.** Si hay diferencia,
gana el `.sql`.

Última revisión: 25/10/2026 · 58 `.sql` + 58 `.md` · 367 objetos documentados.

## Resumen

| Tipo de objeto | Cantidad |
|---|---|
| Tablas | 43 |
| Procedimientos almacenados | 159 |
| Triggers | 77 |
| Vistas | 23 |
| Funciones | 5 |
| Índices | 60 |
| **Total `CREATE`** | **367** |

## Cómo leer un módulo

1. **Encabezado**: qué es, de qué depende y quién lo usa (con el `cpp` cuando
   aplica).
2. **Tablas**: columna por columna, con tipo, restricciones y para qué sirve.
   Los índices van dentro de la sección de su tabla.
3. **Procedimientos**: firma, validaciones en orden, y los mensajes **exactos**
   que devuelve (para buscarlos en el código).
4. **Triggers**: cuándo disparan, qué escriben y a qué trigger siguen (`FOLLOWS`).
   Los eliminados se listan con el motivo.
5. **Reglas de negocio**: el resumen de comportamiento al final.
6. **Los avisos en cita** (los `> **...**`) son **hallazgos**, no cosas
   arregladas: rarezas, duplicaciones y riesgos que están en el SQL de hoy.

## Mapa de módulos

Leyenda de la columna **App**: ✅ la app llama a sus procedimientos o lee sus
tablas · ◐ usa solo una parte · — **no** la usa.

### Catálogo y maestros

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [CATEGORIAS](<1- CATEGORIAS.md>) | 1T · 7SP | Categorías de producto. | ✅ |
| [MARCAS](<2- MARCAS.md>) | 1T · 7SP | Marcas de producto. | ✅ |
| [METODOS_PAGO](<4-METODOS_PAGO.md>) | 1T · 5SP | Efectivo, tarjeta, transferencia… | ✅ |
| [PROVEEDORES](<5- PROVEEDORES.md>) | 1T · 4SP | Proveedores. | ✅ |
| [CLIENTES](<7- CLIENTES.md>) | 1T · 4SP · 2TR | Clientes. | ✅ |
| [PRODUCTOS](<9- PRODUCTOS.md>) | 1T · 9SP · 1TR | Productos, precio de venta y de compra. | ✅ |
| [PRODUCTO_PROVEEDOR](<40- PRODUCTO_PROVEEDOR.md>) | 1T · 4SP · 1TR | Qué proveedor vende qué producto y a qué costo. | ✅ |

### Inventario y stock

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [INVENTARIO](<17- INVENTARIO.md>) | 1T · 1SP · 1TR · 2V · 1FN | Stock actual, mínimo y ubicación. | ◐ |
| [HISTORIAL_ESTADOS_PRODUCTO](<18- HISTORIAL_ESTADOS_PRODUCTO.md>) | 1T · 1SP · 1TR · 1V | Altas y bajas de producto. | — |
| [MOVIMIENTOS_INVENTARIO](<20- MOVIMIENTOS_INVENTARIO.md>) | 1T · 3SP | Kardex: entradas, salidas, ajustes y devoluciones. | ✅ |
| [HISTORIAL_MOVIMIENTOS_PRODUCTO](<32- HISTORIAL_MOVIMIENTOS_PRODUCTO.md>) | 1T · 3TR | El mismo movimiento, con stock antes y después. | — |

### Compras

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [COMPRAS](<19- COMPRAS.md>) | 1T · 4SP · 4TR · 2V · 1FN | Cabecera de compra al proveedor. | ✅ |
| [HISTORIAL_ESTADOS_COMPRA](<19.1- HISTORIAL_ESTADOS_COMPRA.md>) | 1T | Cambios de estado de la compra. | — |
| [PAGOS_COMPRA](<19.5- PAGOS_COMPRA.md>) | 1T · 4SP · 7TR · 1V | Pagos al proveedor y saldo. | ◐ |
| [DEVOLUCION_COMPRA](<19.6- DEVOLUCION_COMPRA.md>) | 2SP | Devolución de mercancía al proveedor. | ✅ |
| [DETALLE_COMPRA](<22-DETALLE_COMPRA.md>) | 2T · 3SP · 15TR · 1V · 1FN | Líneas de compra, costo vigente y notas de crédito. | ◐ |

### Ventas y postventa

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [VENTAS](<21- VENTAS.md>) | 1T · 3SP · 2TR | Cabecera de venta. | ✅ |
| [HISTORIAL_ESTADOS_VENTA](<21.5- HISTORIAL_ESTADOS_VENTA.md>) | 1T · 1SP · 2TR | Cambios de estado de la venta. | ✅ |
| [DETALLES_VENTA](<23- DETALLE_VENTA.md>) | 1T · 1SP · 6TR · 1V | Líneas de venta y descuento de stock. | ✅ |
| [PAGOS](<24- PAGOS.md>) | 1T · 5SP · 6TR · 1V | Cobros, anulación y reporte de ventas. | ✅ |
| [GARANTIAS](<25- GARANTIAS.md>) | 1T · 2SP · 1TR | Garantías emitidas con una venta. | ✅ |
| [DEVOLUCIONES](<26- DEVOLUCIONES.md>) | 1T · 2SP · 5TR · 2V | Devolución de mercancía del cliente. | ✅ |
| [RECLAMOS_GARANTIAS](<27- RECLAMOS_GARANTIAS.md>) | 1T · 2SP · 3TR | Reclamos sobre una garantía. | ✅ |
| [DETALLE_REPARACIONES](<35- DETALLE_REPARACIONES.md>) | 1T · 1SP | Repuestos de una reparación. | — |
| [GANANCIAS](<38- GANANCIAS.md>) | 1SP · 2V | Ganancia por línea y por mes. | ◐ |
| [LECTURAS_VENTAS](<39- LECTURAS_VENTAS.md>) | 14SP | Las 14 consultas de solo lectura de ventas, compras y caja. | ✅ |

### RRHH y personal

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [EMPLEADOS](<8- EMPLEADOS.md>) | 1T · 10SP · 2TR | Empleados, cargo, salario y estado. | ◐ |
| [USUARIOS](<10- USUARIOS.md>) | 1T · 12SP · 1TR | Cuentas de acceso, atadas a un empleado y un rol. | ✅ |
| [ASISTENCIA_EMPLEADOS](<11-ASISTENCIA_EMPLEADOS.md>) | 1T · 7SP · 1TR | Entrada y salida por día. | ✅ |
| [VACACIONES_EMPLEADOS](<12- VACACIONES_EMPLEADOS.md>) | 1T · 8SP · 2TR | Solicitudes y cupo de vacaciones. | ✅ |
| [PERMISOS_EMPLEADOS](<13- PERMISOS_EMPLEADOS.md>) | 1T · 4SP · 1V | Permisos y ausencias del empleado. | ✅ |
| [BONOS_EMPLEADOS](<14- BONOS_EMPLEADOS.md>) | 1T · 5SP · 2TR · 1V | Bonos y descuentos de nómina. | — |
| [HISTORIAL_LABORAL_EMPLEADO](<15- HISTORIAL_LABORAL_EMPLEADO.md>) | 1T · 1TR | Cambios de cargo y salario. | — |
| [LIQUIDACIONES](<16- LIQUIDACIONES.md>) | 1T · 1SP · 3TR · 2V | Liquidación al despedir. | — |
| [TURNO_CAJA](<41- TURNO_CAJA.md>) | 1T · 3SP | Apertura, cuadre y cierre de caja. | ✅ |
| [CONTRATOS](<42- CONTRATOS.md>) | 1T · 3SP · 1TR | Contratos de trabajo generados en HTML. | ✅ |

### Seguridad, logs y configuración

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [ROLES](<3- ROLES.md>) | 1T · 4SP | Roles del sistema. | ✅ |
| [PERMISOS_ROLES](<36- PERMISOS_ROLES.md>) | 2T · 3SP · 1FN | Permisos y qué rol los tiene. | ✅ |
| [MIGRACION_ROLES](<44- MIGRACION_ROLES.md>) | — | Retira `EMPLEADO` y `CAJERO` y pasa sus usuarios a `VENDEDOR`. | — |
| [PERMISO_CONSULTAR_ASISTENCIA](<45- PERMISO_CONSULTAR_ASISTENCIA.md>) | — | Agrega `CONSULTAR_ASISTENCIA` y lo asigna a ADMIN, GERENTE, SUBGERENTE y RRHH. | — |
| [PERMISOS_PROVEEDORES](<46- PERMISOS_PROVEEDORES.md>) | — | Reemplaza `GESTIONAR_PROVEEDORES` por 4 permisos finos. | — |
| [PERMISO_HISTORIAL_VENTA](<47- PERMISO_HISTORIAL_VENTA.md>) | — | Agrega `CONSULTAR_HISTORIAL_VENTA` y lo asigna a ADMIN, GERENTE, SUBGERENTE y VENDEDOR. | — |
| [PERMISOS_CATEGORIAS](<49- PERMISOS_CATEGORIAS.md>) | — | Reemplaza `GESTIONAR_CATEGORIAS` por 4 permisos finos. | — |
| [PERMISOS_MARCAS](<50- PERMISOS_MARCAS.md>) | — | Reemplaza `GESTIONAR_MARCAS` por 4 permisos finos. | — |
| [PERMISOS_METODOS_PAGO](<51- PERMISOS_METODOS_PAGO.md>) | — | Reemplaza `GESTIONAR_METODOS_PAGO` por 4 permisos finos. | — |
| [PERMISOS_COMPRAS](<52- PERMISOS_COMPRAS.md>) | — | Reemplaza `GESTIONAR_COMPRAS` por 6 permisos finos. | — |
| [PERMISOS_CAJA](<53- PERMISOS_CAJA.md>) | — | Agrega `CONSULTAR_CAJA`, `ABRIR_CAJA` y `CERRAR_CAJA`, separados de `GESTIONAR_VENTAS`. | — |
| [ORDEN_TRIGGER_HISTORIAL_COMPRA](<54- ORDEN_TRIGGER_HISTORIAL_COMPRA.md>) | — | Recrea `TR_HISTORIAL_COMPRA` con `FOLLOWS` para que lea el stock ya sumado. | — |
| [ORDEN_TRIGGERS_RESTANTES](<55- ORDEN_TRIGGERS_RESTANTES.md>) | — | Fija el orden de los triggers de ventas, empleados y productos. | — |
| [AUDITORIA_USUARIOS](<56- AUDITORIA_USUARIOS.md>) | — | Registra quién cambia usuarios y agrega `CAMBIO_USUARIO`. | — |
| [AUDITORIA_SISTEMA_FIX](<57- AUDITORIA_SISTEMA_FIX.md>) | 3SP · 3TR | Recrea los `SP` y triggers del 6: rango indexable, usuario real y `DELETE` de proveedores. | — |
| [CONFIGURACION](<33- CONFIGURACION.md>) | 1T · 1FN | Ajustes: ITBIS, datos de la empresa. | ✅ |
| [AUDITORIA_SISTEMA](<6- AUDITORIA_SISTEMA.md>) | 1T · 3SP · 3TR | Bitácora genérica por tabla y registro. | — |
| [LOG_ACCESOS](<28-LOG_ACCESOS.md>) | 1T · 3SP | Intentos de login. | ✅ |
| [LOG_USUARIOS](<29- LOG_USUARIOS.md>) | 1T · 1SP · 1TR · 1V | Cambios de rol y estado de usuarios. | — |
| [LOG_AUDITORIA_PERMISOS](<30- LOG_AUDITORIA_PERMISOS.md>) | 1T · 1TR | Cambios de estado de los permisos. | — |
| [ASIGNAR RECLAMOS](<34- ASIGNAR RECLAMOS.md>) | 1T · 2SP | Técnico asignado a un reclamo. | — |

### Reportes

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [VISTAS_REPORTES](<43- VISTAS_REPORTES.md>) | 5V | Las cinco vistas del "total con IVA" y los saldos pendientes. | — |

> El 43 se importa **al final**: MariaDB valida las tablas al crear una vista y
> estas leen tablas del 22 y el 26.

## Orden de import

- **El número es el orden.** Los decimales existen porque se agregaron después:
  `19` → `19.1` → `19.5` → `19.6` → `22`.
- **El 43 va último.** Antes vivía en 19/19.5/23/24 y fallaba en una
  reconstrucción desde cero.
- **El import corre con `--force`**: si un `CREATE VIEW` falla, el resto sigue y
  la base queda incompleta **sin avisar**. Revisar la salida cuando se reconstruye
  desde cero.
- **Las cadenas de triggers están declaradas con `FOLLOWS`.** Si se recrea un
  trigger de la cadena, hay que rehacer la cadena entera o el orden se pierde.

## Objetos que viven en otro archivo

El `.sql` donde está el objeto **no siempre es el de su tabla**. Antes de tocar
uno, mirar acá:

| Objeto | Vive en | Pertenece a |
|---|---|---|
| `IX_COMPRA_PROVEEDOR` | 22 | `COMPRAS` |
| `IX_VENTAS_FECHA`, `IX_CLIENTE_NOMBRE` | 23 | `VENTAS`, `CLIENTES` |
| `TR_AUDITORIA_MOVIMIENTO_COMPRA`, `TR_AUDITORIA_BORRADO_COMPRA` | 22 | `DETALLE_COMPRA`, `COMPRAS` |
| `TR_AUDITORIA_MOVIMIENTO_VENTA` | 23 | `DETALLES_VENTA` |
| `TR_HISTORIAL_VENTA`, `TR_HISTORIAL_COMPRA` | 32 | `DETALLES_VENTA`, `DETALLE_COMPRA` |
| `TR_HISTORIAL_DEVOLUCION` | 32 | `DEVOLUCIONES` (26) |
| `TR_MAPA_COMPRA_RECIBIDA` | 40 | `COMPRAS` |
| `SP_PROVEEDOR_ACTIVO` | 40 | `PROVEEDORES` |
| `TR_AUDITORIA_PERFIL_EMPLEADO` | 15 | sigue a `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` (10) |

## Las fórmulas que están repetidas

**El BRUTO** —`TOTAL + ITBIS de líneas − ITBIS devuelto`— es la fórmula más
repetida de la base:

- **Compras**, en 6 objetos: 2 `SP` de `PAGOS_COMPRA` (19.5) y 4 triggers de
  `DETALLE_COMPRA` (22).
- **Ventas**, en 6 objetos: 1 `SP` de `PAGOS` (24) y 5 triggers de `PAGOS` (24).
- **Y otra vez** en las cinco vistas del 43 (dos de compras, tres de ventas).

> Si se cambia el "total con IVA", hay que cambiarlo en **todos** esos lugares.
> No hay una función compartida: la fórmula está copiada.

## Qué no usa la app

Once módulos completos: **6** (auditoría), **14** (bonos),
**15** (historial laboral), **16** (liquidaciones), **18** (historial de estados
de producto), **19.1** (historial de estados de compra), **29** (log de
usuarios), **30** (log de permisos), **32** (historial de stock), **34**
(asignación de reclamos) y **35** (detalle de reparaciones).

> **"No usa" significa que la app no lee ni llama sus objetos**, no que estén
> vacíos. Varios **se llenan solos** por triggers de otros módulos (6, 15, 18,
> 19.1, 29 y 32): borrarlos rompe el negocio que los alimenta.

Parciales, que conviene mirar antes de tocarlos:

- **8 EMPLEADOS**: la app usa 4 de sus 10 `SP` (insertar, actualizar, despedir,
  reactivar) y lee la tabla directo.
- **17 INVENTARIO**: el `SP` de alta no se llama; la tabla sí se usa.
- **19.5 PAGOS_COMPRA**: 2 de 4 `SP` (`SP_REGISTRAR_PAGO_COMPRA` y
  `SP_COMPRAS_PENDIENTES`). Anular un pago y la nota de crédito no tienen pantalla.
- **22 DETALLE_COMPRA**: 1 de 3 `SP` (`22_SP_AGREGAR_DETALLE_COMPRA`); quitar y
  modificar línea no se llaman, y el resto lo mueven los triggers.
- **38 GANANCIAS**: el `SP` de período se usa; las dos vistas, no.

## Dónde buscar qué

| Necesito… | Módulo |
|---|---|
| La tasa de ITBIS vigente | 33 (`FN_TASA_ITBIS`) |
| Quién puede hacer qué | 36 (`PERMISOS_ROLES`) |
| Cuánto stock hay / cómo se movió | 17, 20 y 32 |
| Cuánto falta pagarle al proveedor | 19.5 y la vista del 43 |
| Cuánto falta cobrar de una venta | 24 y las vistas del 43 |
| Revisar un pago que no cuadra | 19.5 (compras) o 24 (ventas) |
| Cuadre de caja del día | 41 |
| Datos de la empresa para un contrato | 33 |
| Historial de un cambio puntual | 6 |

## Estado de la documentación

- **58 de 58** módulos documentados, un `.md` por `.sql`.
- **367 objetos** `CREATE` verificados **nombre por nombre** contra su `.sql`.
- Los `.sql` **no se tocaron** para documentar.
- Los hallazgos están anotados en cada documento y en
  `odd/tasks/documentacion-bd.md`, **sin arreglar**: son deuda técnica
  documentada, no cambios pendientes autorizados.
