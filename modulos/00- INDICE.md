# Índice general — módulos de la base de datos

Los **31 módulos** de `BALBU_TECH`: qué guarda cada uno, qué objetos crea y si la
app lo usa. Cada módulo tiene su documento al lado del `.sql`, con el mismo
nombre.

**El `.sql` es la fuente de verdad; el `.md` lo explica.** Si hay diferencia,
gana el `.sql`.

Última revisión: 18/11/2026 · 31 `.sql` + 31 `.md`

> Los totales de la tabla de abajo son los de la revisión del 05/11/2026 y **no**
> se recontaron al fusionar módulos: la fusión no creó ni borró ningún objeto,
> solo movió sentencias de archivo. El conteo de archivos sí es el real.
>
> **(18/11/2026)** Excepción: el `8` y el `14` sí se recontaron contra la base
> al agregar la nómina (14 `SP` y 7 `SP`, respectivamente). El resto sigue sin
> recontar.

> **(14/11/2026) Diecinueve lotes de consolidación de módulos.** Lote 1: los diez parches de permisos
> (`45`, `46`, `47`, `49`, `50`, `51`, `52`, `53`, `58`, `62`) viven dentro de
> `36`. Lote 2 (auditoría): `57` se disolvió en `6`; `56` en `29`; `61` en `7`,
> `9` y `18`; y `30` y `69` en `13`. `55` desapareció sin dejar contenido: sus
> tres triggers eran copias exactas de los que `15`, `18` y `23` ya crean con su
> `FOLLOWS`. Los módulos de auditoría eran **redefiniciones idénticas** de objetos
> que ya existían en su dueño; importados después, solo podían pisar una versión
> buena con una vieja. Lote 3 (compras): `19.5` y `19.6` se fusionaron dentro de
> `19`, que pasa a ser el agregado de compras completo. Ahí no había duplicados:
> eran tres archivos del mismo agregado y sus `SP` ya se llamaban entre sí.
> Lote 4 (historial de estados): `19.1` dentro de `19` y `21.5` dentro de `21`.
> Eran extracciones del 07/10/2026 hechas por simetría entre compras y ventas,
> sin dependencia real; el `.md` del `19.1` ya lo admitía. Con esto no queda
> ningún módulo decimal.
> Lote 5 (detalles): `22` dentro de `19` y `23` dentro de `21`. El detalle solo
> estaba afuera porque `DETALLE_COMPRA` necesita `COMPRAS` creada y
> `DETALLES_VENTA` necesita `VENTAS`; con la cabecera en el mismo archivo, ese
> orden se cumple solo. Los dos eran la mitad del mismo agregado: sus `SP` los
> llama la cabecera y sus triggers escriben en ella.
> Lote 6 (posventa): `27`, `34`, `35` y `63` dentro de `25`. Es una cadena de
> FK sin ramas —`GARANTIAS` → `RECLAMOS_GARANTIAS` → `ASIGNACIONES_RECLAMOS` →
> `DETALLE_REPARACIONES`— y los números ya iban en ese orden. El `63` era el
> parche correctivo que redefinía tres `SP` del `25` y del `27`: ahora el
> reemplazo se lee en el mismo archivo, no a un import de distancia.
> Lote 7 (inventario): `20` dentro de `17`. `MOVIMIENTOS_INVENTARIO` es el
> kardex del stock, la misma familia que `INVENTARIO`, y sus `SP` ya movían la
> tabla del `17`. El `20` no aportaba triggers ni `FOLLOWS`, así que adelantarlo
> al `17` no desarma ninguna cadena de orden.
> Lote 8 (historial de estados): `18` dentro de `9`. El trigger del `18` es
> `AFTER UPDATE ON PRODUCTOS` y declara `FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE`,
> que vive en el `9`: los dos quedan en el mismo archivo, con el líder arriba.
> No entran acá el `32` ni el `40`: sus triggers son `ON` tablas de módulos
> posteriores (`19`/`21`/`26`).
> Lote 9 (mapa producto–proveedor): `40` dentro de `32`. El trigger del `40` es
> `AFTER UPDATE ON COMPRAS` (19), así que tampoco podía ir al `9`; el `32` ya se
> importa después del `26`, o sea después de todas las tablas del `ON` de los dos.
> Juntos por posición, no por tema.
> Lote 10 (login): `67` dentro de `65`. Solo reescribía `SP_CAMBIAR_CLAVE_USUARIO`:
> sin tablas, triggers ni vistas, así que no había `ON` ni `FOLLOWS` que cuidar.
> Desde el 15/11/2026 el `10` ya no define la versión vieja de ese `SP`: el dueño
> único es el `65`.
> Lote 11 (cédula): `59` dentro de `8`. El `ALTER` va al lado de su tabla; el `8`
> ya declara la cédula `UNIQUE` inline, así que el parche solo aporta en bases
> viejas.
> Lote 12 (venta neta): `60` **se borró**. De sus 16 objetos, 14 eran copias
> idénticas de lo que ya definen el `24`, el `21` y el `43`; sus dos `SP` únicos
> (`SP_REPORTE_VENTAS_PAGINADO` y `SP_CONTAR_REPORTE_VENTAS`) pasaron al `39`.
> Lote 13 (orden del historial de compras): `54` **se borró**. Recreaba
> `TR_HISTORIAL_COMPRA` con `FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA`, exactamente lo
> mismo que ya declara el `32`: instalando sin el `54` el catálogo queda
> byte-idéntico y el trigger conserva su orden.
> Lote 14 (cargo ancho): `68` dentro de `15`. El `68` era un `ALTER` idempotente
> sobre `HISTORIAL_LABORAL_EMPLEADO` —la tabla del `15`— que ensanchaba
> `CARGO_ANTERIOR`/`CARGO_NUEVO` de 30 a 50. No creaba objetos: su lugar natural
> es el archivo de su tabla, al lado del `CREATE TABLE` que ya las declara en 50.
> Lote 15 (migración de roles): `44` dentro de `36`. Los módulos que arman la
> matriz solo **agregan** roles; el `44` es el único que los **retira**. Va al
> final del `36`, después de la matriz y de los diez parches finos, que es el
> mismo orden que tenía como archivo aparte.
> Lote 16 (ganancias): `38` dentro de `39`. Los dos `SP` del `39` ya consultaban
> `VW_GANANCIAS` y `VW_GANANCIAS_MENSUAL`; ahora las vistas y su `SP` de reporte
> viven en el mismo archivo. Las vistas quedan al final, después de los `SP` que
> las leen: MariaDB no valida el cuerpo de una rutina al crearla.
> Lote 17 (caja): `41` dentro de `24`. El cuadre del turno se calcula sobre
> `PAGOS`, la tabla del `24`: el `41` la leía de un import de distancia.
> Lote 18 (contratos): `42` dentro de `8`. `CONTRATOS` tiene FK a `EMPLEADOS` y
> su trigger es `AFTER INSERT ON EMPLEADOS`; es el único de ese tipo, así que no
> hay orden que cuidar.
> Lote 19 (bloqueo del login): `64` dentro del `28`, **repartido a su dueño**. De
> sus tres objetos entran dos —el índice de `LOG_ACCESOS` y
> `SP_ESTADO_BLOQUEO_LOGIN`—; la `FN_TIENE_PERMISO` que también traía no entra
> porque el `36` ya define la versión final. El `64` no era un módulo temático
> sino un parche para bases vivas, y cada objeto pertenecía a un módulo distinto.

## Resumen

| Tipo de objeto | Cantidad |
|---|---|
| Tablas | 47 |
| Procedimientos almacenados | 191 |
| Triggers | 82 |
| Vistas | 26 |
| Funciones | 6 |
| Tablas temporales | 1 |
| **Total `CREATE`** | **353** |

Además hay **59 índices**, todos declarados dentro del `CREATE TABLE` de su
tabla (ya no son sentencias `CREATE INDEX` sueltas).

> (19/11/2026) Números remedidos: contando los `CREATE` de los `.sql` y
> cruzados contra la base (**47 tablas / 191 SP / 82 triggers / 26 vistas / 6
> funciones** en `BALBU_TECH_TEST`). Antes decían 167 SP / 79 triggers / 23
> vistas / 383 `CREATE`: quedaron viejos con la consolidación de módulos y el
> cableado de bonos, nómina, garantías y reclamos.
>
> (19/11/2026) Los **59 índices** dejaron de ser sentencias `CREATE INDEX`
> sueltas: se declaran dentro del `CREATE TABLE` de su tabla, como las `FK` y
> los `CHECK`. Por eso el total de `CREATE` baja de **411 a 353**, aunque los
> índices siguen existiendo. La ventaja es que reimportar un módulo ya no emite
> el aviso `1061` (índice duplicado) y no hay que dropear ni reconstruir
> índices sobre una base con datos.

Los módulos de seguridad (`65` y `66`) se aplican después de compilar el binario
nuevo: cambian el login, agregan el token de sesión que la app vieja no manda y
alinean el cambio de clave con ese login.

> (15/11/2026) Limpieza de restos: `1_SP_VERIFICAR_CATEGORIA_EXISTE`,
> `18_SP_CAMBIAR_ESTADO_PRODUCTO`, `SP_INSERTAR_INVENTARIO` y
> `11_SP_REGISTRAR_SALIDA` salieron del proyecto (quedó su `DROP ... IF EXISTS`).
> Y los dos `SP` que estaban definidos en dos módulos —`SP_CAMBIAR_CLAVE_USUARIO`
> y `SP_LOGIN_AUTENTICAR`— quedaron con un solo dueño: `65` y `66`.

## Cómo leer un módulo

1. **Encabezado**: qué es, de qué depende y quién lo usa (con el `cpp` cuando
   aplica).
2. **Tablas**: columna por columna, con tipo, restricciones y para qué sirve.
   Los índices van dentro de la sección de su tabla. Toda tabla cierra con
   `) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;`:
   sin el `COLLATE` explícito la tabla hereda el de la **base**, y una base
   creada con el default de MariaDB 11 (`utf8mb4_uca1400_ai_ci`) sale con otro
   collation que la de producción.
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
| [CATEGORIAS](<1- CATEGORIAS.md>) | 1T · 6SP | Categorías de producto. | ✅ |
| [MARCAS](<2- MARCAS.md>) | 1T · 5SP | Marcas de producto. | ✅ |
| [METODOS_PAGO](<4-METODOS_PAGO.md>) | 1T · 5SP | Efectivo, tarjeta, transferencia… | ✅ |
| [PROVEEDORES](<5- PROVEEDORES.md>) | 1T · 4SP | Proveedores. | ✅ |
| [CLIENTES](<7- CLIENTES.md>) | 1T · 4SP · 2TR | Clientes. | ✅ |
| [PRODUCTOS](<9- PRODUCTOS.md>) | 2T · 17SP · 2TR · 1V | Productos, precio de venta y de compra, más el historial de estados (absorbe el 18). | ✅ |

### Inventario y stock

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [INVENTARIO](<17- INVENTARIO.md>) | 2T · 6SP · 1TR · 2V · 1FN | Stock actual, mínimo y ubicación, más el kardex de movimientos (absorbe el 20). | ◐ |
| [HISTORIAL_MOVIMIENTOS_PRODUCTO](<32- HISTORIAL_MOVIMIENTOS_PRODUCTO.md>) | 2T · 4SP · 4TR | El mismo movimiento, con stock antes y después; más el mapa producto–proveedor (absorbe el 40). | ◐ |

### Compras

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [COMPRAS](<19- COMPRAS.md>) | 5T · 13SP · 26TR · 4V · 2FN | Agregado completo: cabecera, pagos y notas de crédito, detalle, devoluciones al proveedor e historial de estados (absorbe el 19.5, el 19.6, el 19.1 y el 22). | ✅ |

### Ventas y postventa

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [VENTAS](<21- VENTAS.md>) | 3T · 4SP · 10TR · 1V | Cabecera, detalle e historial de estados (absorbe el 21.5 y el 23). | ✅ |
| [PAGOS](<24- PAGOS.md>) | 2T · 8SP · 6TR · 1V | Cobros, anulación, reporte de ventas y la caja por turno (absorbe el 41). | ✅ |
| [GARANTIAS](<25- GARANTIAS.md>) | 4T · 13SP · 5TR | Garantía, reclamo, asignación, reparación y el flujo completo (absorbe el 27, el 34, el 35 y el 63; 13 rutinas distintas). | ✅ |
| [DEVOLUCIONES](<26- DEVOLUCIONES.md>) | 1T · 2SP · 5TR · 2V | Devolución de mercancía del cliente. | ✅ |
| [LECTURAS_VENTAS](<39- LECTURAS_VENTAS.md>) | 30SP · 2V | Las consultas de solo lectura de ventas, compras y caja (absorbe el reporte paginado del 60 y las ganancias del 38). | ✅ |

### RRHH y personal

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [EMPLEADOS](<8- EMPLEADOS.md>) | 2T · 14SP · 3TR | Empleados, cargo, salario y estado, el `UNIQUE` de cédula (absorbe el 59), los contratos (absorbe el 42) y la nómina: recibo con los bonos del mes y su pago. | ◐ |
| [USUARIOS](<10- USUARIOS.md>) | 1T · 8SP · 1TR | Cuentas de acceso, atadas a un empleado y un rol. | ✅ |
| [ASISTENCIA_EMPLEADOS](<11-ASISTENCIA_EMPLEADOS.md>) | 1T · 6SP · 1TR | Entrada y salida por día. | ✅ |
| [VACACIONES_EMPLEADOS](<12- VACACIONES_EMPLEADOS.md>) | 1T · 8SP · 2TR | Solicitudes y cupo de vacaciones. | ✅ |
| [PERMISOS_EMPLEADOS](<13- PERMISOS_EMPLEADOS.md>) | 2T · 6SP · 3TR · 2V | Permisos y ausencias del empleado, y su bitácora de auditoría (absorbe el 30 y el 69). | ✅ |
| [BONOS_EMPLEADOS](<14- BONOS_EMPLEADOS.md>) | 1T · 7SP · 2TR · 1V | Bonos y descuentos de nómina; pantalla de gestión con permiso propio y pagador auditado. | ✅ |
| [HISTORIAL_LABORAL_EMPLEADO](<15- HISTORIAL_LABORAL_EMPLEADO.md>) | 1T · 1TR · 2 ALTER | Cambios de cargo y salario. | — |
| [LIQUIDACIONES](<16- LIQUIDACIONES.md>) | 1T · 1SP · 3TR · 2V | Liquidación al despedir. | — |

### Seguridad, logs y configuración

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [ROLES](<3- ROLES.md>) | 1T · 4SP | Roles del sistema. | ✅ |
| [PERMISOS_ROLES](<36- PERMISOS_ROLES.md>) | 2T · 3SP · 1FN | Permisos y qué rol los tiene. Único dueño de la matriz: absorbe los permisos finos de asistencia, proveedores, historial de venta, categorías, marcas, métodos de pago, compras, caja, inventario y garantías (antes 45, 46, 47, 49, 50, 51, 52, 53, 58 y 62) y la migración de roles (antes 44). | ✅ |
| [LOGIN_SERVIDOR](<65- LOGIN_SERVIDOR.md>) | 1T · 2SP | Verificación de la clave en el servidor con pepper; migración automática del formato viejo, y el cambio de clave en ese formato (absorbe el 67). | ✅ |
| [SESIONES_GUARDAS](<66- SESIONES_GUARDAS.md>) | 3T · 3SP · 1FN · 1IDX | Token de sesión de 12 h y guarda de permiso dentro de cada `SP` (`PERMISO_POR_RUTINA`, `LOG_PERMISO_SP`). | ✅ |
| [CONFIGURACION](<33- CONFIGURACION.md>) | 1T · 1FN | Ajustes: ITBIS, datos de la empresa. | ✅ |
| [AUDITORIA_SISTEMA](<6- AUDITORIA_SISTEMA.md>) | 1T · 3SP · 3TR | Bitácora genérica por tabla y registro (absorbe el 57). | — |
| [LOG_ACCESOS](<28-LOG_ACCESOS.md>) | 1T · 4SP · 1IDX | Intentos de login y el bloqueo por fuerza bruta (absorbe el 64). | ✅ |
| [LOG_USUARIOS](<29- LOG_USUARIOS.md>) | 1T · 1SP · 1TR · 1V | Cambios de rol, estado y nombre de usuario, con el actor (absorbe el 56). | — |

### Reportes

| Módulo | Objetos | Qué guarda | App |
|---|---|---|---|
| [VISTAS_REPORTES](<43- VISTAS_REPORTES.md>) | 7V | Las vistas del "total con IVA" y los saldos pendientes. | — |

> El 43 se importa **al final**: MariaDB valida las tablas al crear una vista y
> estas leen tablas del 19 y el 26.

## Orden de import

- **El número es el orden.** Ya no quedan decimales: el import va `19` → `21`.
- **El 43 va último.** Antes vivía en 19/21/24 y fallaba en una
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
| `IX_CLIENTE_NOMBRE` | 21 | `CLIENTES` (7) |
| `TR_HISTORIAL_VENTA`, `TR_HISTORIAL_COMPRA` | 32 | `DETALLES_VENTA` (21), `DETALLE_COMPRA` (19) |
| `TR_HISTORIAL_DEVOLUCION` | 32 | `DEVOLUCIONES` (26) |
| `TR_MAPA_COMPRA_RECIBIDA` | 32 | `COMPRAS` |
| `SP_PROVEEDOR_ACTIVO` | 32 | `PROVEEDORES` |
| `TR_AUDITORIA_PERFIL_EMPLEADO` | 15 | sigue a `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` (10) |

## Las fórmulas que están repetidas

**El BRUTO** —`TOTAL + ITBIS de líneas − ITBIS devuelto`— es la fórmula más
repetida de la base:

- **Compras**, en 6 objetos: 2 `SP` de `PAGOS_COMPRA` (19) y 4 triggers de
  `DETALLE_COMPRA` (19).
- **Ventas**, en 6 objetos: 1 `SP` de `PAGOS` (24) y 5 triggers de `PAGOS` (24).
- **Y otra vez** en las cinco vistas del 43 (dos de compras, tres de ventas).

> Si se cambia el "total con IVA", hay que cambiarlo en **todos** esos lugares.
> No hay una función compartida: la fórmula está copiada.

## Qué no usa la app

Cuatro módulos completos, que la app no lee ni llama: **6** (auditoría), **15**
(historial laboral), **16** (liquidaciones) y **29** (log de usuarios).

> El **14** (bonos) salió de esta lista el 18/11/2026, cuando se cableó su
> pantalla; el **32** (historial de stock) salió antes: la app no lee su tabla,
> pero **sí** llama cuatro de sus `SP` (los del mapa producto–proveedor).

> Las asignaciones de reclamos y el detalle de reparaciones (ex `34` y `35`) viven
> ahora dentro del `25`. La app tampoco los usa: de ese módulo llama solo la
> garantía y el reclamo.

> **"No usa" significa que la app no lee ni llama sus objetos**, no que estén
> vacíos. Varios **se llenan solos** por triggers de otros módulos (6, 15 y 29): borrarlos rompe el negocio que los alimenta.

Parciales, que conviene mirar antes de tocarlos:

- **8 EMPLEADOS**: la app usa 9 de sus 14 `SP` (los 4 de gestión de empleado,
  el recibo y el pago de nómina, y los 3 de contratos) y lee la tabla directo.
  Quedan sin llamador `SP_REPORTE_NOMINA_TOTAL`, `SP_CONSULTAR_EMPLEADOS`,
  `SP_AUMENTO_POR_CARGO`, `SP_ANIVERSARIOS_MES` y `SP_BUSQUEDA_RAPIDA_EMPLEADOS`.
- **17 INVENTARIO**: el `SP` de alta no se llama; la tabla y el kardex sí se usan.
- **19 COMPRAS**: de sus 4 `SP` de pagos se usan 2 (`SP_REGISTRAR_PAGO_COMPRA`
  y `SP_COMPRAS_PENDIENTES`). Anular un pago y la nota de crédito no tienen
  pantalla. Las dos devoluciones sí se usan. Del detalle (ex `22`), de sus 3
  `SP` solo se llama `22_SP_AGREGAR_DETALLE_COMPRA`: quitar y modificar línea no
  tienen pantalla, y el resto lo mueven los triggers.
- **21 VENTAS**: el detalle (ex `23`) tiene un solo `SP`, y se usa.
- **32 HISTORIAL_MOVIMIENTOS_PRODUCTO**: de sus 4 `SP` —el mapa producto–proveedor—
  la app llama los cuatro; la tabla de historial de stock no la lee nadie.
- **38 GANANCIAS**: el `SP` de período se usa; las dos vistas, no.

## Dónde buscar qué

| Necesito… | Módulo |
|---|---|
| La tasa de ITBIS vigente | 33 (`FN_TASA_ITBIS`) |
| Quién puede hacer qué | 36 (`PERMISOS_ROLES`) |
| Cuánto stock hay / cómo se movió | 17 y 32 |
| Cuánto falta pagarle al proveedor | 19 y la vista del 43 |
| Cuánto falta cobrar de una venta | 24 y las vistas del 43 |
| Revisar un pago que no cuadra | 19 (compras) o 24 (ventas) |
| Cuadre de caja del día | 41 |
| Datos de la empresa para un contrato | 33 |
| Historial de un cambio puntual | 6 |

## Estado de la documentación

- **31 de 31** módulos documentados, un `.md` por `.sql`.
- **353 sentencias** `CREATE` en los `.sql`, que dan **47 tablas · 191 SP · 82
  triggers · 26 vistas · 6 funciones · 1 tabla temporal** (19/11/2026), más
  **59 índices** declarados dentro del `CREATE TABLE` de su tabla. Antes eran
  411 `CREATE` porque cada índice era una sentencia `CREATE INDEX` aparte. El
  conteo viejo (372) era de la revisión del 05/11/2026, antes de la
  consolidación de módulos y del cableado de bonos, nómina, garantías y
  reclamos: la fusión sí movió objetos.
- Los `.sql` **no se tocaron** para documentar.
- Los hallazgos están anotados en cada documento, **sin arreglar**: son deuda
  técnica documentada, no cambios pendientes autorizados.
