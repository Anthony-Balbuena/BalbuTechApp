# PENDIENTES — todo en un solo lugar

> **Único archivo de pendientes del proyecto.** De arriba abajo = prioridad.
> Lo hecho y los detalles largos salieron del repo el 08/11/2026: viven en
> `../BalbuTechApp-fuera-del-repo/` (ver su `LEEME.md`).
> Actualizado: 15/11/2026.

---

## 🔴 P0 — Ahora (bloquea lo que estás haciendo)

### 1. Permisos finos (Tanda A y B) — ✅ cerrado el 12/11/2026

Verificado contra las dos bases el 15/11/2026: **61 permisos, 226 pares en las
dos bases, 8 roles**, ningún módulo con permiso paraguas y 0 usuarios
huérfanos. El `36` es el único dueño de la matriz. (Los números viejos de acá
—58/213/7— quedaron atrás cuando el flujo de garantías sumó 3 permisos y el rol
`TECNICO`.) Detalle en la tabla de cerrados.

### 2. Pruebas de aceptación: todo lo hecho (Tanda A y B)

Todo se prueba **primero en `BALBU_TECH_TEST`**, con la matriz de permisos aplicada (la crea `36`; el resto son los módulos de soporte; hoy son 61 permisos). (03/11/2026) La viva quedó al día: se aplicaron `62`, `63`, `64`, `65` y `66` con backups previos `backups/balbu_tech_antes_t2_20261103_152050.sql`, `backups/balbu_tech_antes_login_srv_20261103_163105.sql` y `backups/balbu_tech_antes_guardas_20261103_165608.sql`; `check-app-sps` 123/0 con cobertura de guardas completa en ambas bases. (05/11/2026) La base local de casa (3306) también quedó al día: `63`, `64`, `65`, `66` y `62` en `BALBU_TECH`, y `64`, `65` y `66` en TEST, con backups `backups/BALBU_TECH_antes_62-66_casa_20261105_004038.sql` y `backups/BALBU_TECH_TEST_antes_62-66_casa_20261105_004038.sql`; `EXIGIR = 1` en 169 rutinas de la viva y 161 en TEST, y la batería de entonces en verde. **Ojo: esa «batería completa» eran 12 tests de 25; ver P2.** Detalle en `Realizado.md`, hoy fuera del repo.

**Automático (ya corre, solo hay que ejecutarlo):**

| Comando | Cubre | Esperado |
|---|---|---|
| `bash build.sh` | compila | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh` | SPs que usa la app | 131/0 |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh` | menú principal + submenús de Usuarios, Empleados, Clientes, Proveedores, Categorías, Marcas, Métodos de pago, Asistencia, Productos, Ventas, Garantías, Compras, Caja e Inventario | todos OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh` | módulo 63: registro automático, autor, fechas y cierre | 11/0 + 3 errores esperados |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-ventas-ver-iva.sh` | «Ver venta con IVA» paginado: contrato de los SP, fallback de página y la pantalla sin volcar facturas | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-cobrar-plazo.sh` | plazo de cobro de 48 h: vigencia de los SP, borradores vacíos y el aviso en rojo de la pantalla | todos OK |
| `DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave-root> bash db/test-historial-garantias-venta.sh` | historial de venta (incluido el paginado nuevo) y ventas garantizables | OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-borradores-barrido.sh` | barrido de borradores vacíos al entrar: cancela el viejo y **no** toca el vacío reciente ni la venta con líneas | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-cierre-atomico.sh` | cierre atómico: si falla la segunda línea, la primera —ya insertada y con stock descontado— se revierte; y el camino feliz sigue igual | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=<clave-root> bash db/test-contrato-borrador.sh` | contrato borrador | 15/15 (`balbu_app` no sirve: el test hace SQL directo y corta avisando) |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-asistencia-propia.sh` | fichar sin pedir ID | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh` | módulo 44 (rol viejo → VENDEDOR) | 11/11 |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-lockout.sh` | módulo 64: bloqueo por 5 fallos / 15 min, sin fila nueva al reintentar bloqueado, `FN_TIENE_PERMISO` con `ESTADO` e índice del log | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-login-servidor.sh` | módulo 65: verificación en el servidor, migración automática al primer login, segundo login, clave mala y hash inaccesible para `balbu_app` | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-permisos-sp.sh` | módulo 66: sin token rechaza, token de VENDEDOR pasa lo suyo y se corta en lo ajeno, rechazo registrado | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh` | login con entrada agotada (no gira ni ensucia `LOG_ACCESOS`) | OK |
| `docker compose cp db/grant-minimos.sql db:/tmp/ && docker compose cp db/aplicar-grants.sh db:/tmp/ && docker compose exec -T db bash /tmp/aplicar-grants.sh BALBU_TECH_TEST` | privilegios mínimos de `balbu_app` (solo `EXECUTE` + lecturas necesarias) | OK |

**Manual, por área:**

> **Casi todo esto ya lo cubre `db/test-menus-por-rol.sh`**, que entra a la app
> con cada rol y **cuenta las opciones** del menú principal y de cada submenú, y
> verifica que estén las etiquetas esperadas. Los números de la lista vieja
> estaban desactualizados; estos son los que verifica el test y los que valen:
>
> | Rol | Opciones en el menú principal |
> |---|---|
> | ADMIN | 19 |
> | GERENTE | 15 |
> | SUBGERENTE | 15 |
> | RRHH | 5 |
> | VENDEDOR | 9 |
> | ALMACEN | 10 |
> | CONTABILIDAD | 5 |
>
> Por área, también automático: Usuarios (un rol de solo `USUARIOS_VER` ve solo
> consulta), Empleados (SUBGERENTE 3, solo lectura), Clientes (VENDEDOR 4 sin
> buscar ni listar; CONTABILIDAD 3), Proveedores (ALMACEN 6), Categorías (ALMACEN
> 5), Marcas (ALMACEN 6), Métodos de pago, Asistencia (VENDEDOR 3 sin reportes;
> SUBGERENTE 7 con Justificar), Productos (ALMACEN 7; CONTABILIDAD 4; un rol de
> solo gestión 4), Ventas (VENDEDOR 10; uno sin reportes ni garantías 8),
> Garantías **por permiso** (ADMIN/GERENTE/SUBGERENTE, VENDEDOR, TECNICO,
> CONTABILIDAD), Compras, Caja e Inventario.

#### 2.1 Lo que queda manual de verdad (permisos y cambio en caliente)

- [ ] **Cambio en caliente:** con una sesión de VENDEDOR abierta, quitarle desde ADMIN los tres permisos de Clientes (`CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`) y volver al menú principal. Clientes desaparece **sin re-login** (el menú consulta `FN_TIENE_PERMISO` en cada vuelta).
- [ ] Al reingresar después de quitarlos, la opción sigue ausente.
- [ ] Quitar `CLIENTES_ESTADO` a VENDEDOR: la opción desaparece del submenú, **no** queda un hueco y pasa a 3 opciones.
- [ ] Sin `PROVEEDORES_CREAR`, la opción de alta desaparece y el resto sigue funcionando.
- [ ] Un rol sin `CONSULTAR_PRODUCTOS` no ve Productos; uno sin ningún `EMPLEADOS_*` no ve Empleados (salvo `REGISTRAR_ASISTENCIA`/`CONSULTAR_ASISTENCIA`, que abren **Asistencia**).
- [ ] `CONSULTAR_ASISTENCIA` **no** abre Empleados.
- [ ] ADMIN, GERENTE, SUBGERENTE y RRHH ven los reportes de Asistencia.
- [ ] Justificar una ausencia y ver el cambio en el reporte.
- [ ] Un usuario con `GARANTIAS_CONSULTAR` y sin `GESTIONAR_VENTAS` llega a Garantías por el ítem «Ventas» del menú principal.
- [ ] Usuario con `ESTADO = INACTIVO` **no** puede entrar (el login lo rechaza y deja `LOG_ACCESOS` con `INACTIVO`); desde el módulo 64 `FN_TIENE_PERMISO` también devuelve 0.

> Ya **no** hace falta a mano, lo cubren los tests automáticos: los conteos de
> opciones por rol, el bloqueo por fuerza bruta (5 fallos / 15 min →
> `db/test-lockout.sh`), el cambio de clave (`db/test-cambio-clave.sh`), fichar
> sin pedir ID (`db/test-asistencia-propia.sh`), la migración de roles
> (`db/test-migracion-roles.sh`) y la auditoría de permisos
> (`db/test-auditoria-permisos.sh`).

#### 2.2 Usuarios, Empleados y Roles: las acciones (los menús ya son automáticos)

- [ ] Crear usuario con rol VENDEDOR y clave; entrar con él.
- [ ] Editar el nombre y el rol; verificar que el menú cambie en el siguiente ingreso.
- [ ] Desactivar la cuenta; el login falla con el aviso correspondiente.
- [ ] Reactivar; el login vuelve a funcionar.
- [ ] RRHH: crear empleado, editarlo, darlo de baja y reactivarlo.
- [ ] RRHH: gestionar contrato, permiso y vacaciones desde el submenú.
- [ ] **Roles:** crear un rol nuevo, asignarle `CLIENTES_VER` y entrar con un usuario de ese rol; después quitarle el permiso y verificar que el módulo desaparezca.
- [ ] Borrar el rol: los usuarios que lo tenían no pueden entrar (verificar el mensaje).
- [ ] Renombrar un rol: los permisos lo siguen (`ON UPDATE CASCADE`).

#### 2.3 Migración de roles (módulo 44) — ✅ verificado en la viva el 15/11/2026

La viva quedó en **8 roles** (los 7 del rediseño —ADMIN, GERENTE, SUBGERENTE,
RRHH, VENDEDOR, ALMACEN, CONTABILIDAD— más **TECNICO**, que agregó el flujo de
garantías), con **0 usuarios huérfanos** y **0 roles `EMPLEADO`/`CAJERO`**. TEST
está igual. El test automático lo cubre (11/11).

### 3. RRHH: pruebas visuales pendientes

- [ ] **13 Permisos:** solicitar → aprobar uno y rechazar otro → reintentar aprobar el ya aprobado ("solo pendientes") → ver la fila en `LOG_AUDITORIA_PERMISOS`.
- [ ] **12 Vacaciones:** solicitar → aprobar/rechazar → reintentar; una **aprobada** que cubra hoy bloquea la asistencia, una **pendiente o rechazada** no; cupo de 15 días + solapamiento (rechazar libera).
- [ ] **28 Accesos:** entrar/salir y ver las filas.
- [ ] Limpiar los datos de prueba (permisos, vacaciones, log) al terminar.

Cierre: build OK, `check-app-sps` 131/0, visual OK, sin datos de prueba.

### 4. Contratos: cargar los datos de la empresa

- [ ] `UPDATE` sobre `CONFIGURACION` con `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`. Hoy el contrato los imprime como `____________`.
- No existe tabla `EMPRESA` (se creó, el dueño la rechazó y se borró el mismo día). Todo va en `CONFIGURACION`.

---

## 🟠 P1 — Alta prioridad (funcionalidad a medias)

### 5. Contratos: campos legales RD + revisión legal

- [ ] Agregar a la plantilla: nacionalidad, edad, sexo, estado civil, **RNL** (Registro Nacional del Trabajador), lugar de prestación, provincia y municipio. Checklist y fuentes: `Flujos/Contrato de trabajo - requisitos legales RD.md`, hoy fuera del repo.
- [ ] Revisión legal del texto antes de usarlo con personal real (la plantilla ya lo dice al pie).

### 6. Garantías — ✅ aplicado en TEST y en la viva (30/10, confirmado 12/11)

Módulos `62` y `63`: 4 permisos `GARANTIAS_*`, 7 SP, `TR_REGISTRAR_GARANTIA_VENTA`
y registro automático al confirmar la venta. Único pendiente: la prueba manual
con VENDEDOR de §2.8 (no debe poder finalizar un reclamo). Lo que queda sin
cablear es el módulo `34` (ítem 8).

### 7. RRHH: módulos que faltan

- [ ] **14 Bonos** — pantalla mínima (listar, pagar, anular). El 1% ya lo genera el trigger de 24. *Medido el 12/11 con `db/cobertura-modulos.sh`: la app no llama ninguno de sus 5 SP.*
- [x] **Auditoría de permisos — ✅ aplicada en la viva el 14/11/2026.** La bitácora
  está completa y probada en TEST (`db/test-auditoria-permisos.sh` 19/0) y vive
  **dentro del módulo `13`**: guarda el actor, audita alta/cambio/baja y agrega la
  vista `VIEW_HISTORIAL_PERMISOS` con sus 2 SP de lectura, sin permiso nuevo (usa
  `GESTIONAR_PERMISOS_EMPLEADO`). La viva no la tenía, así que
  `SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO` y `SP_CONTAR_AUDITORIA_PERMISOS`
  —que `permisos.cpp` ya llama— faltaban y la pantalla "Empleados → Ver auditoría
  de permisos" estaba rota en producción. **Arreglado**: se aplicó la sección
  `AUDITORIA` del `13` (`sed -n '248,$p'`), con backup
  `backups/balbu_tech_antes_auditoria_permisos_20261114_134302.sql`, y después
  `db/mapear-permisos.sql`. `check-app-sps.sh` contra `BALBU_TECH`:
  **Faltantes 0 (123), guardas completas, 41 mapeos**. La tabla del log pasó de 5
  a las 9 columnas de una instalación limpia, el trigger viejo
  `TR_LOG_GESTION_PERMISO` se retiró y quedaron los tres por evento. Humo en la
  viva con transacción revertida: `ALTA` → `CAMBIO_ESTADO` → `BAJA`, el
  `ON DELETE SET NULL` de `FK_LOG_PERMISO` deja el `ID_PERMISO` en NULL y
  sobreviven `ID_EMPLEADO`/`TIPO_PERMISO`, la vista y el `SP` paginado devuelven
  las tres filas, cero residuo. **Se aplicó solo la sección de auditoría, no el
  módulo entero**: los demás objetos del `13` ya estaban al día en la viva y
  reimportarlos habría recreado sus 4 `SP` sin las guardas de permiso. El ensayo
  en seco del mapeo (sobre una copia restaurada del backup) mostró que cambia
  exactamente 2 filas y respeta los 178 `EXIGIR = 1`.
- [ ] **16 Liquidaciones** — **parkeado el 12/11/2026**: el dueño investiga la ley antes de tocar código. La fórmula `SALARIO * AÑOS` es placeholder. Reglas legales verificadas y plan de 6 fases quedaron en memoria (`rrhh/liquidaciones-decision`, `rrhh/liquidaciones-ley-16-92`).

### 8. Decisiones de producto (una vez cada una)

- [ ] **¿RRHH va o no?** (12, 13, 14, 16 y el historial de 15). Con lo ya hecho, va.
- [ ] **¿Asignaciones de reclamos?** (tabla `ASIGNACIONES_RECLAMOS` y sus 2 SP, ex módulo `34`, hoy dentro del `25`). Cablear el flujo o borrarlos con su tabla. *Medido el 12/11: ninguno de sus 2 SP lo llama nadie; revalidado el 14/11 tras la fusión.*
- [ ] **¿Detalle de reparaciones?** (tabla `DETALLE_REPARACIONES` y su SP, ex módulo `35`, hoy dentro del `25`). ¿Repuesto con stock o texto libre? *Medido el 12/11: su único SP no lo llama nadie; revalidado el 14/11 tras la fusión.*
- [ ] **¿19 anular pago y quitar/modificar línea?** ¿Pantalla o SQL? *Medido el 12/11: 4 SP sin uso; el «22» es hoy la sección del detalle dentro del `19`.*

### 9. Bugs y deuda con impacto

- [ ] **`CONTRATOS.SALARIO` sigue legible** — el flujo de contratos pendientes lo lee directo. Si se quiere cerrar, hay que pasarlo a un SP.
- [ ] **`balbu_app` tiene grants sobre `BALBU_TECH_TEST` en el servidor de producción** — no hace falta ahí; quitarlo cuando el test deje de correr contra la misma instancia.
- [x] **P-3 validaciones — errores pintados en verde: ✅ cerrado el 15/11/2026.**
  Eran **4**, no 5: `ventas.cpp:313`, `compras.cpp:172`, `compras.cpp:275` y
  `compras.cpp:728`. El `empleados.cpp:440` de esta lista era en realidad la
  **441** y **ya estaba bien** (usa salida temprana). Los otros dos que aparecen
  al barrer el código (`permisos.cpp`, `vacaciones.cpp`) pasan por un helper
  `mensajeDeError()` que sí chequea. Se aplicó el patrón de `caja.cpp`/
  `accesos.cpp` en los 4 lugares y la **prueba end-to-end está hecha**: la app
  corre dentro de la batería (los tests de pantalla entran, navegan y salen).
- [x] **Definiciones repetidas entre módulos: ✅ cerrado el 15/11/2026.**
  Eran 8; las fusiones de módulos dejaron **2**, y hoy no queda ninguna:
  `SP_CAMBIAR_CLAVE_USUARIO` tenía dueño doble (10 vs 65) y `SP_LOGIN_AUTENTICAR`
  también (65 vs 66). Se retiró la copia vieja de cada par —la del `10` escribía
  `CONTRASENA` con el hash del cliente y la del `65` no tenía token—, así que el
  dueño único es el `65` para la primera y el `66` para la segunda.
  `bash db/cobertura-modulos.sh` lo reporta como "Definiciones repetidas: ninguna".
- [ ] **`SP_ACTUALIZAR_VACACIONES`**: al cablear la edición, validar solapamiento y fecha futura (hoy no lo hace; no es alcanzable desde la UI). **No se borra**: es la base de esa pantalla y el trigger `TR_VALIDAR_LIMITE_VACACIONES_UPDATE` ya cubre el tope anual.
- [ ] **Drift TEST ↔ viva en asistencia**: la viva tiene `11_SP_REGISTRAR_ENTRADA` y TEST no; además TEST tenía dos que a la viva le faltaban. Diffear definiciones antes de copiar, no asumir cuál es la buena.

### 10. Hallazgos del mapa de módulos (21/10)

- [ ] **El BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) está copiado en 6 objetos por flujo (compras y ventas) más las 5 vistas del 43. Extraer una función compartida.
- [ ] **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño.

### 11. Verificar antes de creer — ✅ resuelto el 15/11/2026

Acá vivía **P-4**, la última afirmación que no se había podido verificar. Se midió
y se cerró completa (las cuatro opciones, con sus tests). **No queda nada
pendiente en esta sección.**

- [x] **P-4 venta multi-línea: ✅ cerrado el 15/11/2026.** Las cuatro opciones
  quedaron resueltas: **A** limpiar las ventas `EN_PROCESO` de la viva,
  **B** aviso de antigüedad a las 48 h, **C** cierre **atómico** de la venta y
  **D** barrido de borradores vacíos al entrar. Cada una con su test propio; el
  detalle y las decisiones están en la tabla de cerrados.
  Lo único que queda como decisión futura es **cuándo pasar el cierre atómico a
  un SP**, y solo si algún día aparece un segundo cliente (la Qt app): con el
  C++ la garantía es de este cliente.

### 12. Inventario: qué SP y qué trigger no llama nadie (12/11/2026, actualizado el 15/11/2026)

Medido con `bash db/cobertura-modulos.sh` (estático, no abre la base) y cruzado
contra los SP que la app llama y los que esos llaman: **188 definiciones, 188
rutinas distintas y ningún nombre repetido**. De las que la app no llama:

- **38 no las llama nadie**: ni la app, ni otro SP, ni un `CALL` de importación.
- **4 las llama otro SP**: `SP_EXIGIR_PERMISO`, `SP_REGISTRAR_ACCESO`,
  `SP_MARCAR_GARANTIAS_VENCIDAS` y `PARA_ACTUALIZARDATOS`. Son infraestructura
  interna: no se tocan.

> (15/11/2026) El conteo de hoy es **188/38**. Pasó por 189/39 cuando entraron
> los 5 SP nuevos del paginado de ventas; después **`SP_HISTORIAL_VENTA` (21) se
> retiró** (su único uso era la pantalla «Historial de venta», que ahora usa
> `SP_HISTORIAL_VENTA_PAGINADO`), así que volvió a 188. El test
> `db/test-historial-garantias-venta.sh` se migró al SP paginado en vez de
> quedarse verificando una rutina muerta.

- [ ] **¿Qué se borra del inventario de SP y triggers?** Está todo listado y
  clasificado abajo. La decisión es **por grupo**, no por SP suelto.

#### 12.1 Las 38 sin llamador

**a) API sin pantalla — Qt probablemente las quiera, no borrar:**

| Módulo | SP |
|---|---|
| 19 Compras | `SP_ASIGNAR_FACTURA_COMPRA` |
| 21 Ventas | `SP_ASIGNAR_FACTURA_VENTA` |
| 19 Pagos de compra | `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA` |
| 22 Detalle de compra | `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA` |
| 17 Inventario (ex 20) | `SP_KARDEX_PRODUCTO`, `SP_KARDEX_TODOS` |
| 8 Empleados | `SP_ANIVERSARIOS_MES`, `SP_AUMENTO_POR_CARGO`, `SP_BUSQUEDA_RAPIDA_EMPLEADOS`, `SP_CONSULTAR_EMPLEADOS`, `SP_GENERAR_RECIBO_EMPLEADO`, `SP_REPORTE_NOMINA_TOTAL` |
| 12 Vacaciones | `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES`, `SP_REPORTE_DIAS_CONSUMIDOS`, `SP_VALIDAR_CUPO_VACACIONES` |
| 9 Productos | `SP_REPORTE_STOCK_CRITICO` |
| 1 Categorías | `1_SP_CATEGORIAS_POR_FECHA` |
| 2 Marcas | `SP_BUSCAR_MARCA`, `SP_LISTAR_MARCAS` |
| 3 Roles | `SP_LISTAR_ROLES` |
| 7 Clientes | `SP_LISTAR_CLIENTES` |
| 10 Usuarios | `SP_BUSCAR_USUARIOS_FILTRADO` |
| 39 Lecturas | `SP_COMPRAS_ULTIMAS` |

**b) Módulos enteros sin uso — decidir si se cablean o se borran:**

| Módulo | SP | Nota |
|---|---|---|
| 14 Bonos empleados | `SP_REGISTRAR_BONO`, `SP_ACTUALIZAR_BONO`, `SP_ANULAR_BONO`, `SP_PAGAR_BONO`, `SP_LISTAR_BONOS` | Los 5. El 1 % de ventas lo genera un trigger; la pantalla no existe. |
| 34 Asignar reclamos | `SP_ASIGNAR_TECNICO_RECLAMO`, `SP_FINALIZAR_RECLAMO` | Sin cablear (ítem 8). |
| 35 Detalle reparaciones | `SP_REGISTRAR_AVANCE_REPARACION` | Sin cablear (ítem 8). |

**c) Restos y duplicados — RESUELTO el 15/11/2026:**

Se revisaron los 8 y se partieron por lo que realmente son, no por "candidatos":

**Borrados (4)** — sin llamador y con reemplazo ya en su lugar. La definición
salió del módulo y quedó un `DROP PROCEDURE IF EXISTS` con el motivo, para que
una base que ya la tenía quede limpia al reimportar:

| SP | Dónde | Por qué |
|---|---|---|
| `1_SP_VERIFICAR_CATEGORIA_EXISTE` | 1 | Lo valida el `UNIQUE` de `CATEGORIAS.NOMBRE` |
| `18_SP_CAMBIAR_ESTADO_PRODUCTO` | 9 | El cambio pasa por `SP_TOGGLE_ESTADO_PRODUCTOS` |
| `SP_INSERTAR_INVENTARIO` | 17 | El alta la hace `20_SP_REGISTRAR_AJUSTE_INVENTARIO` |
| `11_SP_REGISTRAR_SALIDA` | 11 | Lo reemplazó el fichaje del 66 |

**Se quedan (4)** — borrarlas rompería algo o cerraría una puerta abierta:

| SP | Dónde | Por qué se queda |
|---|---|---|
| `SP_REPORTE_VENTAS` | 24 | La app usa `_PAGINADO`, pero esta queda "por compatibilidad" (lo dice el `39`) y `check-app-sps.sh` la exige con mapeo `CONSULTAR_REPORTES` |
| `SP_ESTADO_BLOQUEO_LOGIN` | 28 | `check-app-sps.sh` la exige, `test-lockout.sh` la usa y `mapear-permisos.sql` la mapea. Borrarla es decisión de negocio, no de limpieza |
| `SP_OBTENER_LOG_USUARIOS` | 29 | Es el único lector de `LOG_USUARIOS`: si Qt le da pantalla, los triggers dejan de ser huérfanos |
| `SP_ACTUALIZAR_VACACIONES` | 12 | Es la base de la pantalla de edición (ítem 9); le falta la validación, no el uso |

Resultado medido entonces: `bash db/cobertura-modulos.sh` pasó de **42 sin uso de
190** a **38 sin uso de 184**, y de 2 nombres repetidos a **ninguno**. (Hoy son
**39 sin uso de 189**: entraron los SP nuevos y `SP_HISTORIAL_VENTA`; ver arriba.)

**d) Liquidaciones:** `SP_REGISTRAR_LIQUIDACION` — parkeado, no se toca.

#### 12.2 Triggers que escriben donde nadie lee

Criterio: la tabla destino no la nombra la app, ni la lee un SP alcanzable desde
la app, ni la lee una vista que esos SP consulten. **15 triggers distintos, en 6
tablas:**

| Tabla destino | Triggers | Módulos |
|---|---|---|
| `AUDITORIA_SISTEMA` | `TR_AUDIT_PROVEEDORES_INSERT/UPDATE/DELETE`, `TR_AUDIT_CLIENTES_INSERT/UPDATE`, `TR_AUDITORIA_PRODUCTOS_UPDATE` | 6, 7, 9 |
| `HISTORIAL_MOVIMIENTOS_PRODUCTO` | `TR_HISTORIAL_COMPRA`, `TR_HISTORIAL_VENTA`, `TR_HISTORIAL_DEVOLUCION` | 32 |
| `HISTORIAL_ESTADOS_COMPRA` | `TR_HISTORIAL_ESTADO_COMPRA`, `TR_CAMBIO_ESTADO_COMPRA` | 19 |
| `LOG_USUARIOS` | `TRG_AUDITORIA_USUARIOS`, `17_TR_VALIDAR_STOCK_MINIMO` | 29, 17 |
| `HISTORIAL_ESTADOS_PRODUCTO` | `TR_LOG_CAMBIO_ESTADO_PRODUCTO` | 9 |
| `HISTORIAL_LABORAL_EMPLEADO` | `TR_AUDITORIA_PERFIL_EMPLEADO` | 15, 55 |

Matiz importante: `LOG_USUARIOS` y `AUDITORIA_SISTEMA` **sí** tienen SP de lectura
(`SP_OBTENER_LOG_USUARIOS`, los `6_*`), pero esos SP tampoco se llaman. Si Qt les
da pantalla, los triggers dejan de ser huérfanos. La decisión es de negocio: son
bitácoras, y cada venta o compra pagando su costo puede ser un precio razonable.

---

## 🟡 P2 — Media (reproducibilidad y limpieza)

- [x] **La clave del usuario `admin` en TEST no coincide con la del `.env`: ✅ cerrado el 15/11/2026.**
  Se re-sembró con `db/seed-admin.sh` sobre `BALBU_TECH_TEST`, con backup previo
  `backups/balbu_tech_test_antes_seed_admin_20261115_115456.sql`. El seed deja
  `CONTRASENA` con el hash PBKDF2 y limpia `SALT_LOGIN`/`ITER_LOGIN`/
  `CLAVE_SERVIDOR`, así que el primer login lo migra al formato del `65`.
  `test-menus-por-rol.sh` volvió a verde en los seis casos ADMIN, y
  `test-asistencia-propia.sh` ya no depende de `CONTRASENA` ni del orden: deriva
  la clave de `BALBU_PASS` con `db/lib-clave-prueba.sh` (antes copiaba el hash
  del admin, que el primer login deja en `NULL`).
- [x] **`test-contrato-borrador.sh` daba falso negativo con `DB_USER=balbu_app`: ✅ cerrado el 15/11/2026.**
  Ese test hace SQL directo y `balbu_app` solo tiene `EXECUTE`, así que el
  `DELETE`/`INSERT` del marcador `302998878xx` fallaba en silencio (estaba
  tapado con `2>/dev/null`), dejaba filas y la corrida siguiente abortaba con
  «BASE SUCIA»; el caso 14 fallaba con «estado ''» porque la fila nunca se
  había creado. Ahora sondea el permiso al arrancar con un
  `DELETE ... WHERE 1 = 0` y corta con el comando exacto
  (`DB_USER=root DB_PASSWORD=<DB_ROOT_PASSWORD>`). Con root: **15/15**.
- [ ] **`db/import.sh` no dropea la base** y un `DROP` se lleva el grant de
  `balbu_app`: hay que volver a otorgarlo con `db/aplicar-grants.sh`.
- [ ] **Un test roto de la batería: `db/test-contratos-subir.sh` (15/11/2026).**
  Su caso «HAY MAS DE UN EMPLEADO CON ESA CEDULA» es **imposible de armar**:
  intenta insertar dos `EMPLEADOS` con la misma cédula, pero
  `UQ_EMPLEADOS_CEDULA` es **UNIQUE** y el `INSERT` muere con `1062`. El test
  quedó obsoleto cuando se agregó el índice. Hay que decidir si ese error sigue
  teniendo sentido (¿puede existir el caso con el índice puesto?) o se retira el
  caso. Además **no tiene el guard de la base viva** (`if [ "$DB" = "BALBU_TECH" ]`)
  que sí tienen los demás; su default es `BALBU_TECH_TEST`, así que hoy no es
  peligroso, pero conviene agregárselo.
- [ ] **`DB_PASSWORD` significa dos cosas distintas según el test (15/11/2026).**
  Los tests que conectan como la app (`test-permisos-sp`, `test-cambio-clave`)
  leen `APP_PASS="${DB_APP_PASSWORD:-${DB_PASSWORD:-}}"`, o sea que esperan la
  clave de **`balbu_app`**. Los que hacen SQL directo (`test-contrato-borrador`,
  `test-contratos-subir`) usan `PASS="${DB_PASSWORD:-}"` con
  `USER="${DB_USER:-root}"`, o sea la de **root**. **No hay un entorno único
  para todos**: con `DB_PASSWORD`=root fallan los primeros, y con la de la app
  fallan los segundos. Se resuelve pasando `DB_APP_PASSWORD` explícito (es la
  primera opción y ya está soportada). Conviene documentarlo en la tabla de
  comandos o renombrar la variable en los tests que faltan.
- [ ] **La batería real son 25 tests, no 12.** Hasta el 15/11 se corrían solo los
  de la tabla de arriba y se reportaba como «batería completa». Corridos los 25
  con el entorno completo (`DB_APP_PASSWORD` incluido): **24 en verde, 1 en rojo**
  (`test-contratos-subir`, arriba). Ojo con dos cosas: casi todos usan
  `DB_ADMIN_USER`/`DB_ADMIN_PASSWORD`, y **varios default a `BALBU_TECH`**, así
  que hay que pasarles `DB_NAME=BALBU_TECH_TEST` explícito.
- [ ] **El cliente `mariadb` dentro de `docker compose exec` pierde las comillas
  dobles del SQL.** Usar archivo `.sql` o here-doc.
- [ ] **P-5**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas, y sacar de los módulos el `UPDATE` y los `CALL` de semilla. Los `SELECT *` sueltos ya no están: se sacaron del `43` y del `14` (15/11/2026).
- [ ] **`db/import.sh`** sigue con `--force` (ahora cuenta los `^ERROR` y avisa): hacerlo fallar de verdad.
- [ ] **Consolidar los `ALTER` de 25** dentro del `CREATE TABLE`; `DROP IF EXISTS` en los `CREATE` del módulo 11.
- [ ] **3 tests shell** pendientes y notas obsoletas del índice (`modulos/00- INDICE.md`).
- [ ] **`db/crear-usuarios.sh` no existe**: buscar el comando de provisión de la máquina del trabajo y compararlo con `balbu_app` / `balbu_admin`.
- [ ] **Sidecar `.borrador`** guarda PII en texto plano junto al HTML (registrado y aceptado por el dueño).
- [ ] **`contratos/firmados/`**: sin listado, renombre ni limpieza; la administra RRHH a mano.
- [ ] **P-6**: decidir cablear o retirar lo construido y no cableado (garantías, reclamos, reparaciones, bonos manuales).
- [ ] **Orden de los tres triggers `AFTER UPDATE` de `EMPLEADOS` invertido (13/11/2026).**
  En TEST y en la viva quedaron `TR_AUDITORIA_PERFIL_EMPLEADO`=1 y
  `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION`=3, al revés que en una importación limpia
  (`DESACTIVAR`=1, `PERFIL`=2, `INVALIDAR_SESION`=3). No lo introdujo la fusión de
  auditoría: es drift viejo, el mismo que existía el módulo `55` para tapar, pero al
  revés. Se arregla **reimportando el módulo `15`**, que recrea `TR_AUDITORIA_PERFIL_EMPLEADO`
  con su `FOLLOWS` y lo reordena (verificado en una base scratch). No aplicar sin
  autorización del dueño: toca las dos bases y no es urgente, porque las tres acciones
  son independientes y el orden no cambia el resultado observable hoy.
- [ ] **Reimportar el `19` o el `21` desarma cinco cadenas de `FOLLOWS` (14/11/2026).**
  Los módulos `19` y `21` son ahora agregados completos: reimportarlos recrea sus
  triggers propios **y** los del detalle, y todos se van al final de su grupo. Las
  cadenas declaradas con `FOLLOWS` que se rompen son:
  - `COMPRAS` `AFTER UPDATE` (3): `TR_CAMBIO_ESTADO_COMPRA` (19) →
    `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` (19) → `TR_MAPA_COMPRA_RECIBIDA` (32).
  - `VENTAS` `AFTER UPDATE` (2): `TR_CAMBIO_ESTADO_VENTA` (21) →
    `TR_REGISTRAR_GARANTIA_VENTA` (63).
  - `DETALLE_COMPRA` `AFTER INSERT` (5): `TR_CALCULAR_TOTAL_COMPRA` →
    `TR_ACTUALIZAR_STOCK_COMPRA` → `TR_AUDITORIA_MOVIMIENTO_COMPRA` →
    `TR_ACTUALIZAR_COSTO_COMPRA` → `TR_HISTORIAL_COMPRA` (32).
  - `DETALLE_COMPRA` `AFTER DELETE` (4): `TR_RECALCULAR_TOTAL_COMPRA` →
    `TR_ACTUALIZAR_STOCK_BORRADO_COMPRA` → `TR_AUDITORIA_BORRADO_COMPRA` →
    `TR_RECALCULAR_COSTO_BORRADO_COMPRA`.
  - `DETALLES_VENTA` `AFTER INSERT` (3): `TR_AUDITORIA_MOVIMIENTO_VENTA` →
    `TR_ACTUALIZAR_TOTAL_VENTA` → `TR_HISTORIAL_VENTA` (32).
  **Se restaura reimportando en orden `32`, `40` y `63`**: cada uno declara el
  `FOLLOWS` sobre el trigger que se corrió y se recrea detrás, así el orden vuelve
  solo. (14/11/2026) El `54` salió de la lista: se **borró** porque era idéntico a
  la definición que ya trae el `32`, y reimportar el `32` solo ya restaura el orden.
  Verificado en TEST y en una instalación limpia. `SHOW CREATE TRIGGER` no
  muestra el `FOLLOWS`; el orden real está en
  `information_schema.TRIGGERS.ACTION_ORDER`. Importante para el próximo `import.sh`
  sobre una base existente: el `19` y el `21` son válidos por sí solos, pero dejan el
  catálogo desordenado. No corregir los módulos sin autorización.
- [ ] **La cadena de compras tiene un orden distinto en la viva (13/11/2026).**
  TEST y la viva pueden tener 1=RECALCULAR, 2=MAPA, 3=CAMBIO si alguien reimportó el
  `19`. La instalación limpia da 1=CAMBIO, 2=RECALCULAR, 3=MAPA. Se corrige con el
  mismo reimport de arriba; si hiciera falta sola, un `drop`+`create` de los tres en
  orden. No es urgente: los tres leen el mismo `NEW.ESTADO` y no dependen del resultado
  del anterior.

---

## 🔵 P3 — Baja / bloqueado

- [ ] **NCF / comprobante fiscal DGII** — **bloqueado** por el trámite en la oficina virtual (autorización + asignación de secuencia). La app no inventa números.
- [ ] **API para la web**: `GET /api/reporte` que llame al mismo SP + `fetch` en `index.html` (hoy la web es estática con simulados).
- [ ] **Lector biométrico** — sin equipo. El corte ya está: `marcarAsistenciaAuto()` toma `sesionActual.idEmpleado`; el modo huella reemplaza esa lectura sin tocar el resto. Falta decidir equipo (define opción A o B).
- [ ] **Permisos por cargo** (reclutamiento 12 vs contrataciones 13/14/15): hoy es convención del flujo, la app no separa roles. Fuera de alcance.
- [ ] Borrar la rama `backup-casa-20-10` (después del merge).

---

## ✅ Planes cerrados (por si buscás el detalle)

El detalle de la columna "Dónde quedó" vive en `Realizado.md`, que salió del
repo: está en `../BalbuTechApp-fuera-del-repo/`.

| Plan | Cuándo | Dónde quedó |
|---|---|---|
| Generar contrato (borrador) | 19/10 | `Realizado.md` — 3ª parte |
| Registrar contrato firmado (fases 1–8) | 19/10 | `Realizado.md` — 4ª parte |
| C-3: permisos administrables | 20/10 | commit del 20/10 |
| Set final de 7 roles | 22/10 | commit `22b2f8e` |
| Asistencia v1 y v2 | 16–17/10 | `Realizado.md` |
| Flujo de compras / ventas | 08/10 | `Realizado.md` |
| Observaciones SQL | 09/10 | cerrado salvo "consolidar ALTER" (P2) |
| Permisos finos Tanda A y B | 22–23/10, cerrado 12/11 | 61 permisos / 226 pares en las dos bases (las matrices quedaron idénticas el 15/11), sin paraguas; `modulos/36` es el único dueño de la matriz. (Eran 58/213/7 roles al cerrarse; el flujo de garantías sumó 3 permisos y el rol `TECNICO`) |
| Garantías: flujo completo | 30/10, aplicado en la viva | módulos `62` y `63`; solo falta la prueba manual de §2.8 |
| Historial laboral (cargo ancho) | 12/11, fusionado 14/11 | dentro de `modulos/15` (ex módulo `68`); `db/test-historial-laboral.sh` 14/0 |
| Consolidación de módulos | 12–14/11 | **19 lotes, capa 1 cerrada**; `modulos/` pasó de 70 a **31 `.sql`**; el detalle vive en `odd/tasks/consolidacion-modulos.md` |
| Limpieza de restos SQL (ítem 12c) | 15/11 | 4 SP retirados con su `DROP` (`1_SP_VERIFICAR_CATEGORIA_EXISTE`, `18_SP_CAMBIAR_ESTADO_PRODUCTO`, `SP_INSERTAR_INVENTARIO`, `11_SP_REGISTRAR_SALIDA`) y los 2 duplicados con dueño único (`65` y `66`). `cobertura-modulos.sh`: **38 sin uso de 184, 0 repetidos** (hoy 39 de 189) |
| Batería de aceptación en TEST | 15/11 | Los **25** `db/test-*.sh` corridos con el entorno completo: **24 en verde, 1 en rojo** (`test-contratos-subir`, caso obsoleto por `UQ_EMPLEADOS_CEDULA`; ver P2). La tabla de comandos de arriba solo listaba 12 y se reportaba como «batería completa»: corregido el 15/11. Admin de TEST re-sembrado con backup `backups/balbu_tech_test_antes_seed_admin_20261115_115456.sql`; dos tests corregidos porque daban falso negativo (copiaban `CONTRASENA` y usaban `balbu_app` para SQL directo) |
| «Ver venta con IVA» paginado | 15/11 | La pantalla listaba las 20 últimas ventas e imprimía la factura **completa** de las 20: una venta vieja quedaba inalcanzable y tapaba la terminal. Ahora lista de 10 en 10 (`SP_VENTAS_ULTIMAS_PAGINADO` + `SP_CONTAR_VENTAS_ULTIMAS`, mapeados a `GESTIONAR_VENTAS`) y el detalle se pide por ID. `SP_VENTAS_ULTIMAS` se conserva: la usa «Cancelar venta». Test nuevo `db/test-ventas-ver-iva.sh`, con RED observado revirtiendo solo el `.cpp` |
| Limpieza de las ventas `EN_PROCESO` de la viva | 15/11 | Las 4 se resolvieron: #15 cobrada, #8 cancelada (por el dueño), #17 y #18 (vacías) canceladas por `SP_CANCELAR_VENTA`. Quedan 0. Backup `backups/balbu_tech_viva_antes_cancelar_ventas_20261115_142026.sql` |
| Plazo de cobro de 48 h (P-4, opción B) | 15/11 | Decisión del dueño: **48 h**. `VISTA_VENTAS_PENDIENTES_PAGO` (43) suma `FECHA` y `HORAS_ABIERTA`; «Cobrar venta en proceso» marca en rojo las vencidas y avisa cuántas retienen stock. `SP_VENTAS_BORRADOR_VIEJO(48)` (39) cubre el caso que la vista no ve (borradores vacíos, saldo 0). Test `db/test-cobrar-plazo.sh`. De paso se corrigió que 3 rutinas nuevas habían quedado con `EXIGIR = 0` (guarda en modo auditoría): ahora las 180 exigen |
| SP nuevos aplicados a la **viva** | 15/11 | Módulos `39` y `43` + `mapear-permisos.sql` en `BALBU_TECH`, con backup `backups/balbu_tech_antes_sp_paginado_20261115_151029.sql`. Viva: **193 procedimientos** en ese momento, `check-app-sps` contra la viva **131/0**, mapeo 48. Los 3 SP nuevos y el historial paginado responden. Lo que quedaba desalineado se cerró después ese mismo día: ver la fila «Limpieza y permisos de la viva» |
| Cierre atómico de venta (P-4, opción C) | 15/11 | `cerrarVenta` envuelve cabecera + líneas + stock en una transacción (`TransaccionVenta`, RAII). El rollback devuelve el stock solo, así que se retiró la compensación con `SP_CANCELAR_VENTA` al fallar una línea. El ID del cliente se pide antes de abrir la transacción y la factura se imprime después del commit. Se hizo en el C++ y no como SP porque se midió que ni los dos SP del flujo ni el trigger de stock commitean por dentro. Test `db/test-cierre-atomico.sh`, que fuerza el fallo de la segunda línea con el carrito armado |
| Trigger drift de compras ARREGLADO (por accidente) | 15/11 | Un `bash db/import.sh` corrió **completo contra la viva** por error (el `.env` exporta `DB_NAME=BALBU_TECH` y faltó el override). Consecuencia real: el orden de las cadenas de `COMPRAS UPDATE` y `DETALLE_COMPRA INSERT` quedó **igual al de una instalación limpia** —o sea, el import las **corrigió**, no las rompió—, se cayeron los tombstones (que era lo buscado) y 4 rutinas quedaron sin guarda (el script aborta antes de inyectarlas con `set -e`). Las 4 se reinjectaron. Verificado contra una instalación limpia: **triggers, procedimientos y tablas idénticos**. Datos intactos salvo los 3 pares de `GARANTIAS_AVANZAR`. Backup previo: `backups/balbu_tech_antes_reparar_follows_20261115_192257.sql` |
| `SP_HISTORIAL_VENTA` retirado | 15/11 | No tenía `LIMIT`: devolvía el historial completo. La app ya usaba `SP_HISTORIAL_VENTA_PAGINADO` (39), así que quedó sin llamador. Tombstone en el `21` + `DROP` en las dos bases + fila de mapeo huérfana borrada; `db/test-historial-garantias-venta.sh` migrado al paginado. Repo y bases en **188 procedimientos** |
| Limpieza y permisos de la viva (15/11/2026) | 15/11 | **Tres cierres:** (1) los 4 tombstones retirados de `BALBU_TECH` —189 rutinas, igual que el repo—; (2) las 2 rutinas de auditoría de permisos quedaron con `EXIGIR = 1` (`EXIGIR = 0` pasó de 2 a **0** en las dos bases); (3) `GARANTIAS_AVANZAR` para ADMIN/GERENTE/SUBGERENTE. Backup `backups/balbu_tech_antes_limpieza_y_permisos_20261115_191222.sql` y el de TEST del mismo timestamp |
| `GARANTIAS_AVANZAR` faltaba en la matriz del `36` | 15/11 | **El diagnóstico inicial estaba al revés.** `SP_REGISTRAR_AVANCE_REPARACION` exige `GARANTIAS_AVANZAR` en la guarda ANTES de su autorización, y esa autorización deja que quien tiene `GARANTIAS_ASIGNAR` actúe en nombre de otro: con el permiso solo en TECNICO, **en la viva NADIE podía registrar un avance de reparación** (ni la opción se veía). El módulo `36` era el incompleto, no TEST. Corregido en el `36` y aplicado a la viva; las matrices de las dos bases quedaron **idénticas** (226 pares cada una, 61 permisos) |
| Barrido de borradores vacíos (P-4, opción D) | 15/11 | Decisión del dueño: alcance **acotado**. Al entrar a la app se cancelan **solo** las ventas `EN_PROCESO` **sin líneas** con más de 48 h. No retienen stock, no se pueden cobrar, y nadie trabaja en algo sin líneas. **Nunca toca una venta con líneas** (puede ser un apartado legítimo). Reusa `SP_VENTAS_BORRADOR_VIEJO` + `SP_CANCELAR_VENTA`, sin SQL nuevo; avisa cuántas canceló. Test `db/test-borradores-barrido.sh` |
| «Historial de venta» paginado | 15/11 | `SP_HISTORIAL_VENTA` (21) **no tenía `LIMIT`**: devolvía el historial completo (30 filas hoy en la viva, sin tope). Se agregaron `SP_HISTORIAL_VENTA_PAGINADO` y `SP_CONTAR_HISTORIAL_VENTA` en el `39`, con `P_ID_VENTA = 0` = todas. Pantalla de 10 en 10 con `mostrarPaginadoSPCon`. El `COUNT` lleva el mismo `JOIN` que el `SELECT` para que las páginas cuadren. Aserciones agregadas a `db/test-historial-garantias-venta.sh` |
| Auditoría de permisos en la viva | 14/11 | sección `AUDITORIA` del `13` + `mapear-permisos.sql`; `check-app-sps` contra la viva 123/0 (hoy 131/0); backup `backups/balbu_tech_antes_auditoria_permisos_20261114_134302.sql` |

---

## Comandos

```bash
# Build
./build.sh

# SPs que usa la app (debe dar 131/0, siempre contra TEST)
DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh

# Cobertura: que SPs existen y nadie llama (no necesita base de datos)
bash db/cobertura-modulos.sh

# Menús por rol (sobre TEST)
BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh

# Contrato: UI
DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=<clave-root> BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=admin BALBU_PASS=<clave-admin> bash db/test-contrato-borrador.sh

# Contratos: SQL
DB_PASSWORD=<clave-root> DB_NAME=BALBU_TECH_TEST bash db/test-contratos-subir.sh
```

---

## Referencias

Todo lo que sigue salió del repo el 08/11/2026 y vive en
`../BalbuTechApp-fuera-del-repo/` (ver su `LEEME.md`):

- `Planes/Realizado.md` — lo hecho, con evidencia.
- `Auditoria/` — hallazgos con detalle (18/10 código + BD; 08/10 solo lo abierto).
- `Flujos/` — requisitos legales del contrato, flujo de producto y de BD.
- `Reglas/Reglas de trabajo.md` — cómo se trabaja.
