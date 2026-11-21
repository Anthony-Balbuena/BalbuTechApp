# PENDIENTES — todo en un solo lugar

> **Único archivo de pendientes del proyecto.** De arriba abajo = prioridad.
> Lo hecho y los detalles largos salieron del repo el 08/11/2026: viven en
> `../BalbuTechApp-fuera-del-repo/` (ver su `LEEME.md`).
> Actualizado: 19/11/2026.

---

## 🔴 P0 — Ahora (bloquea lo que estás haciendo)

### 1. Pruebas de aceptación: recorrido manual y batería automática

Todo se prueba **primero en `BALBU_TECH_TEST`**, con la matriz de permisos
aplicada (la crea `36`; el resto son los módulos de soporte; hoy son **63
permisos**). La viva está al día y la base local de casa (3306) también, con
backups en `backups/`. **La batería son 30 tests, no 12** (ver P2).

**Automático (ya corre, solo hay que ejecutarlo):**

| Comando | Cubre | Esperado |
|---|---|---|
| `bash build.sh` | compila | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh` | SPs que usa la app | 139/0 |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh` | menú principal + submenús de Usuarios, Empleados, Clientes, Proveedores, Categorías, Marcas, Métodos de pago, Asistencia, Productos, Ventas, Garantías, Compras, Caja e Inventario | todos OK |
| `DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave-root> bash db/test-nomina.sh` | nómina: columnas de auditoría, el recibo que no marca nada, el arrastre de bonos, el pago con fecha y actor, el despedido que igual cobra y los frenos | 26/26 |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-nomina-pantalla.sh` | pantalla de nómina de punta a punta: el permiso abre el módulo, el recibo con los 2 bonos, el total y el pago marcado en la base con el usuario de la sesión; responder `n` no marca nada | 11/11 |
| `DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh` | módulo 63: registro automático, autor, fechas y cierre | 11/0 + 3 errores esperados |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-ventas-ver-iva.sh` | «Ver venta con IVA» paginado: contrato de los SP, fallback de página y la pantalla sin volcar facturas | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-cobrar-plazo.sh` | plazo de cobro de 48 h: vigencia de los SP, borradores vacíos y el aviso en rojo de la pantalla | todos OK |
| `DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave-root> bash db/test-compras.sh` | flujo de compras: alta y lineas, la linea cuadra al centavo con la factura, BRUTO y vistas, pagos y estados, devolucion que baja el TOTAL, stock y los tres frenos | 32/32 |
| `DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave-root> bash db/test-historial-garantias-venta.sh` | historial de venta (incluido el paginado nuevo) y ventas garantizables | OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-borradores-barrido.sh` | barrido de borradores vacíos al entrar: cancela el viejo y **no** toca el vacío reciente ni la venta con líneas | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-cierre-atomico.sh` | cierre atómico: si falla la segunda línea, la primera —ya insertada y con stock descontado— se revierte; y el camino feliz sigue igual | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-contrato-borrador.sh` | contrato borrador | 15/15 (hace SQL directo: necesita `DB_ROOT_PASSWORD` en el `.env`) |
| `DB_NAME=BALBU_TECH_TEST bash db/test-contratos-subir.sh` | contratos: subir firmado (SQL directo, transacción + rollback) | todos OK |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-asistencia-propia.sh` | fichar sin pedir ID | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh` | módulo 44 (rol viejo → VENDEDOR) | 11/11 |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-lockout.sh` | módulo 64: bloqueo por 5 fallos / 15 min, sin fila nueva al reintentar bloqueado, `FN_TIENE_PERMISO` con `ESTADO` e índice del log | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-login-servidor.sh` | módulo 65: verificación en el servidor, migración automática al primer login, segundo login, clave mala y hash inaccesible para `balbu_app` | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-permisos-sp.sh` | módulo 66: sin token rechaza, token de VENDEDOR pasa lo suyo y se corta en lo ajeno, rechazo registrado | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh` | login con entrada agotada (no gira ni ensucia `LOG_ACCESOS`) | OK |
| `bash db/aplicar-grants.sh BALBU_TECH_TEST` (dentro del contenedor) o `set -a; . ./.env; set +a; DB_HOST=127.0.0.1 bash db/aplicar-grants.sh BALBU_TECH_TEST` (desde el host) | privilegios mínimos de `balbu_app` (solo `EXECUTE` + lecturas necesarias). **Idempotente**: se puede correr las veces que haga falta | OK |

**Manual, por área:**

> **El test `db/test-menus-por-rol.sh` ya verifica los CONTEOS de opciones** de
> cada menú y submenú entrando a la app con cada rol: eso atrapa rápido una
> opción que se cuela o que desaparece. **No reemplaza este recorrido** — abajo
> está lo que hay que mirar a mano. Los conteos de la lista están corregidos con
> lo que la app muestra hoy; los viejos estaban mal (decían 16 para GERENTE y
> son 15, etc.).

#### 1.1 Sesión y menú principal

- [ ] ADMIN entra y ve **19** opciones.
- [ ] GERENTE ve **15** y **no** aparecen Roles ni Usuarios.
- [ ] SUBGERENTE ve **15**, con Empleados (solo 3: buscar, listar, volver) y Asistencia (7, con Justificar).
- [ ] RRHH ve **5**; VENDEDOR **9**; ALMACEN **10**; CONTABILIDAD **5**.
- [ ] Usuario con `ESTADO = INACTIVO` **no** puede entrar (el login lo rechaza y deja `LOG_ACCESOS` con `INACTIVO`). Desde el módulo 64 `FN_TIENE_PERMISO` también devuelve 0 para esa cuenta.
- [ ] **Bloqueo por fuerza bruta (módulo 64):** cinco fallos del mismo usuario dentro de 15 minutos cierran el acceso con el aviso `Cuenta bloqueada por intentos fallidos`. Cerrar y reabrir la app **no** reinicia el contador. Un intento bloqueado **no** agrega filas en `LOG_ACCESOS` (si agregara, la ventana se correría sola y el bloqueo no vencería nunca). Pasados los 15 minutos, la clave correcta vuelve a entrar.
- [ ] **Cambio en caliente:** con una sesión de VENDEDOR abierta, quitarle desde ADMIN los tres permisos que le quedan de Clientes (`CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`) y volver al menú principal. Clientes desaparece **sin re-login** (el menú consulta `FN_TIENE_PERMISO` en cada vuelta).
- [ ] Al reingresar después de quitar los permisos, la opción sigue ausente.

#### 1.2 Usuarios (solo ADMIN)

- [ ] Crear usuario con rol VENDEDOR y clave; entrar con él.
- [ ] Editar el nombre y el rol; verificar que el menú cambie en el siguiente ingreso.
- [ ] Desactivar la cuenta; el login falla con el aviso correspondiente.
- [ ] Reactivar; el login vuelve a funcionar.
- [ ] Cambiar la clave; la vieja deja de servir y la nueva entra.
- [ ] GERENTE **no** ve el módulo Usuarios.

#### 1.3 Empleados

- [ ] RRHH: crear empleado, editarlo, darlo de baja y reactivarlo.
- [ ] RRHH: gestionar contrato, permiso y vacaciones desde el submenú.
- [ ] RRHH: cobrar la nómina de un empleado con bonos pendientes — el recibo tiene que mostrar el arrastre (bonos de meses anteriores) y el pago tiene que dejar fecha y usuario.
- [ ] SUBGERENTE: no ve «Gestionar bonos» ni «Nómina (recibo y pago)» (los dos permisos quedaron fuera de su rol).
- [ ] SUBGERENTE: entra a Empleados pero solo ve consulta; **no** puede crear, editar ni dar de baja.
- [ ] Un usuario sin ningún permiso `EMPLEADOS_*` no ve el módulo (salvo que tenga `REGISTRAR_ASISTENCIA` o `CONSULTAR_ASISTENCIA`, que abren **Asistencia**, no Empleados).

#### 1.4 Clientes

- [ ] VENDEDOR: solo crear, editar y cambiar estado (4 opciones contando Volver); **no** aparecen Buscar ni Listar.
- [ ] CONTABILIDAD: solo `CLIENTES_VER`; ve la consulta y nada más.
- [ ] Quitar `CLIENTES_ESTADO` a VENDEDOR: la opción desaparece del submenú, **no** queda un hueco y pasa a 3 opciones.

#### 1.5 Proveedores

- [ ] ALMACEN: ver, crear, editar y cambiar estado (6 opciones en el submenú).
- [ ] Sin `PROVEEDORES_CREAR`, la opción de alta desaparece y el resto sigue funcionando.

#### 1.6 Asistencia

- [ ] Los 7 roles pueden **fichar** (`REGISTRAR_ASISTENCIA`).
- [ ] VENDEDOR ve 3 opciones, **sin** reportes.
- [ ] SUBGERENTE ve 7, con Justificar.
- [ ] ADMIN, GERENTE, SUBGERENTE y RRHH ven los reportes (`CONSULTAR_ASISTENCIA`).
- [ ] "Mi asistencia" usa el `ID_EMPLEADO` de la sesión, **no** pide ID a mano.
- [ ] `CONSULTAR_ASISTENCIA` **no** abre Empleados.
- [ ] Justificar una ausencia y ver el cambio en el reporte.

#### 1.7 Productos

- [ ] ALMACEN ve 7 (gestión + consulta).
- [ ] CONTABILIDAD ve 4 (solo consulta).
- [ ] Un rol sin `CONSULTAR_PRODUCTOS` no ve el módulo.
- [ ] `PRUEBA_PROD_GEST` (solo gestión) ve 4 y no ve las de consulta.

#### 1.8 Ventas

- [ ] VENDEDOR ve 10: las 7 de gestión, historial, garantías y volver, **sin** reportes ni exportación.
- [ ] `PRUEBA_VEN_GEST` (sin `CONSULTAR_REPORTES`) ve 8: solo las acciones sobre la venta, **sin** Garantías.
- [ ] **Garantías** ya no cuelga de `GESTIONAR_VENTAS`: se abre con cualquiera de sus 4 permisos (módulo `62`) y el submenú filtra por permiso.
- [ ] ADMIN/GERENTE/SUBGERENTE ven **7** opciones en Garantías (incluye "Registrar avance"); TECNICO 3; VENDEDOR 4 (sin "Finalizar reclamo"); CONTABILIDAD 2 (solo consultar).
- [ ] Un usuario con `GARANTIAS_CONSULTAR` y sin `GESTIONAR_VENTAS` llega a Garantías por el ítem "Ventas" del menú principal.
- [ ] Un VENDEDOR **no** puede finalizar un reclamo.

#### 1.9 Roles

- [ ] Crear un rol nuevo, asignarle `CLIENTES_VER` y entrar con un usuario de ese rol.
- [ ] Quitarle el permiso y verificar que el módulo desaparezca.
- [ ] Borrar el rol: los usuarios que lo tenían no pueden entrar (verificar el mensaje).
- [ ] Renombrar un rol: los permisos lo siguen (`ON UPDATE CASCADE`).

### 2. RRHH: pruebas visuales pendientes

- [ ] **13 Permisos:** solicitar → aprobar uno y rechazar otro → reintentar aprobar el ya aprobado ("solo pendientes") → ver la fila en `LOG_AUDITORIA_PERMISOS`.
- [ ] **12 Vacaciones:** solicitar → aprobar/rechazar → reintentar; una **aprobada** que cubra hoy bloquea la asistencia, una **pendiente o rechazada** no; cupo de 15 días + solapamiento (rechazar libera).
- [ ] **28 Accesos:** entrar/salir y ver las filas.
- [ ] Limpiar los datos de prueba (permisos, vacaciones, log) al terminar.

Cierre: build OK, `check-app-sps` 139/0, visual OK, sin datos de prueba.

### 3. Contratos: cargar los datos de la empresa

- [ ] `UPDATE` sobre `CONFIGURACION` con `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`. Hoy el contrato los imprime como `____________`.
- No existe tabla `EMPRESA` (se creó, el dueño la rechazó y se borró el mismo día). Todo va en `CONFIGURACION`.

---

## 🟠 P1 — Alta prioridad (funcionalidad a medias)

### 4. Contratos: campos legales RD + revisión legal

- [ ] Agregar a la plantilla: nacionalidad, edad, sexo, estado civil, **RNL** (Registro Nacional del Trabajador), lugar de prestación, provincia y municipio. Checklist y fuentes: `Flujos/Contrato de trabajo - requisitos legales RD.md`, hoy fuera del repo.
- [ ] Revisión legal del texto antes de usarlo con personal real (la plantilla ya lo dice al pie).

### 5. RRHH: liquidaciones (módulo 16)

- [ ] **16 Liquidaciones** — **parkeado el 12/11/2026**: el dueño investiga la ley antes de tocar código. La fórmula `SALARIO * AÑOS` es placeholder. Reglas legales verificadas y plan de 6 fases quedaron en memoria (`rrhh/liquidaciones-decision`, `rrhh/liquidaciones-ley-16-92`).

### 6. Decisiones de producto (una vez cada una)

- [ ] **¿RRHH va o no?** (12, 13, 16 y el historial de 15; el 14 y la nómina ya quedaron cableados el 18/11/2026). Con lo ya hecho, va.
- [ ] **¿19 anular pago y quitar/modificar línea?** ¿Pantalla o SQL? *Medido el 12/11 y revalidado el 19/11: 4 SP sin uso (`SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA`, `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA`).*

### 7. Bugs y deuda con impacto

- [ ] **`CONTRATOS.SALARIO` sigue legible** — el flujo de contratos pendientes lo lee directo (`empleados.cpp:114`). Si se quiere cerrar, hay que pasarlo a un SP.
- [ ] **`balbu_app` tiene grants sobre `BALBU_TECH_TEST` en el servidor de producción** — no hace falta ahí; quitarlo cuando el test deje de correr contra la misma instancia.
- [ ] **`SP_ACTUALIZAR_VACACIONES`**: al cablear la edición, validar solapamiento y fecha futura (hoy no lo hace; no es alcanzable desde la UI). **No se borra**: es la base de esa pantalla y el trigger `TR_VALIDAR_LIMITE_VACACIONES_UPDATE` ya cubre el tope anual.

### 8. Hallazgos del mapa de módulos (21/10)

- [ ] **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño (`IF V_TXT + 0 > 0`).
  (21/11/2026) **Sigue pendiente y es un tema aparte**: el dueño eligió la exención de
  ITBIS **por producto** (`PRODUCTOS.EXENTO_ITBIS`, ver `odd/tasks/exencion-itbis.md`),
  que no toca `FN_TASA_ITBIS` ni la tasa global. Bajar la tasa a 0 sigue siendo el otro
  camino, con sus propios 5 SP que duplican la regla.

### 9. Inventario: qué SP y qué trigger no llama nadie (12/11/2026, actualizado el 19/11/2026)

Medido con `bash db/cobertura-modulos.sh` (estático, no abre la base) y cruzado
contra los SP que la app llama y los que esos llaman: **191 definiciones, 191
rutinas distintas y ningún nombre repetido**. De las que la app no llama:

- **33 no las llama nadie**: ni la app, ni otro SP, ni un `CALL` de importación.
- **4 las llama otro SP**: `SP_EXIGIR_PERMISO`, `SP_REGISTRAR_ACCESO`,
  `SP_MARCAR_GARANTIAS_VENCIDAS` y `PARA_ACTUALIZARDATOS`. Son infraestructura
  interna: no se tocan.

- [ ] **¿Qué se borra del inventario de SP y triggers?** Está todo listado y
  clasificado abajo. La decisión es **por grupo**, no por SP suelto.

#### 9.1 Las 33 sin llamador

**a) API sin pantalla — Qt probablemente las quiera, no borrar (27):**

| Módulo | SP |
|---|---|
| 1 Categorías | `1_SP_CATEGORIAS_POR_FECHA` |
| 2 Marcas | `SP_BUSCAR_MARCA`, `SP_LISTAR_MARCAS` |
| 3 Roles | `SP_LISTAR_ROLES` |
| 6 Auditoría | `6_SP_CONSULTAR_HISTORIAL_REGISTRO`, `6_SP_LISTAR_AUDITORIA_GENERAL`, `SP_LIMPIAR_AUDITORIA` |
| 7 Clientes | `SP_LISTAR_CLIENTES` |
| 8 Empleados | `SP_ANIVERSARIOS_MES`, `SP_AUMENTO_POR_CARGO`, `SP_BUSQUEDA_RAPIDA_EMPLEADOS`, `SP_CONSULTAR_EMPLEADOS`, `SP_REPORTE_NOMINA_TOTAL` |
| 9 Productos | `SP_REPORTE_STOCK_CRITICO` |
| 10 Usuarios | `SP_BUSCAR_USUARIOS_FILTRADO` |
| 12 Vacaciones | `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES`, `SP_REPORTE_DIAS_CONSUMIDOS`, `SP_VALIDAR_CUPO_VACACIONES` |
| 17 Inventario | `SP_KARDEX_PRODUCTO`, `SP_KARDEX_TODOS` |
| 19 Compras | `SP_ASIGNAR_FACTURA_COMPRA`, `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA` |
| 21 Ventas | `SP_ASIGNAR_FACTURA_VENTA` |
| 22 Detalle de compra | `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA` |
| 39 Lecturas | `SP_COMPRAS_ULTIMAS` |

**b) Sin cablear a propósito, no es deuda (2):**

| Módulo | SP | Nota |
|---|---|---|
| 14 Bonos empleados | `SP_ACTUALIZAR_BONO` | Corregir el monto de un bono sin rastro es peor que anularlo y volver a registrarlo, que deja historia. |
| 16 Liquidaciones | `SP_REGISTRAR_LIQUIDACION` | Parkeado con el módulo 16 (ítem 5). |

**c) Se quedan por compatibilidad o porque cierran una puerta (4):**

| SP | Dónde | Por qué se queda |
|---|---|---|
| `SP_REPORTE_VENTAS` | 24 | La app usa `_PAGINADO`, pero esta queda "por compatibilidad" (lo dice el `39`) y `check-app-sps.sh` la exige con mapeo `CONSULTAR_REPORTES` |
| `SP_ESTADO_BLOQUEO_LOGIN` | 28 | `check-app-sps.sh` la exige, `test-lockout.sh` la usa y `mapear-permisos.sql` la mapea. Borrarla es decisión de negocio, no de limpieza |
| `SP_OBTENER_LOG_USUARIOS` | 29 | Es el único lector de `LOG_USUARIOS`: si Qt le da pantalla, los triggers dejan de ser huérfanos |
| `SP_ACTUALIZAR_VACACIONES` | 12 | Es la base de la pantalla de edición (ítem 7); le falta la validación, no el uso |

#### 9.2 Triggers que escriben donde nadie lee

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

- [ ] **La batería son 30 tests, no 12, y hay que correrlos todos.** Con el
  `.env` cargado están **los 30 en verde** (verificado el 19/11/2026: 30/30 con
  un solo entorno). Casi todos usan
  `DB_ADMIN_USER`/`DB_ADMIN_PASSWORD`; los dos de SQL directo
  (`test-contrato-borrador`, `test-contratos-subir`) leen `DB_ROOT_PASSWORD`
  (19/11/2026), así que **un solo entorno alcanza para los 30**. Pasales
  `DB_NAME=BALBU_TECH_TEST` explícito: el `.env` trae `DB_NAME=BALBU_TECH` (la
  viva). Los que escriben traen guarda y se niegan a correr sobre `BALBU_TECH`
  (28 de 28 tests con base, verificado el 19/11/2026). **Que estén todos en verde
  es lo que hace que un rojo signifique algo.**
- [ ] **`db/crear-usuarios.sh` no existe**: buscar el comando de provisión de la máquina del trabajo y compararlo con `balbu_app` / `balbu_admin`.
- [ ] **Sidecar `.borrador`** guarda PII en texto plano junto al HTML (registrado y aceptado por el dueño).
- [ ] **`contratos/firmados/`**: sin listado, renombre ni limpieza; la administra RRHH a mano.
- [ ] **P-6**: decidir cablear o retirar lo construido y no cableado. **Al 19/11/2026
  quedan solo liquidaciones (16) y 5 SP del módulo 19** (`SP_ASIGNAR_FACTURA_COMPRA`,
  `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA`,
  `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA`): garantías, reclamos,
  reparaciones, bonos y nómina ya están cableados y probados.
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
  solo. El `54` se **borró** porque era idéntico a la definición que ya trae el `32`.
  Verificado en TEST y en una instalación limpia. `SHOW CREATE TRIGGER` no
  muestra el `FOLLOWS`; el orden real está en
  `information_schema.TRIGGERS.ACTION_ORDER`. Importante para el próximo `import.sh`
  sobre una base existente: el `19` y el `21` son válidos por sí solos, pero dejan el
  catálogo desordenado. No corregir los módulos sin autorización.

---

## 🔵 P3 — Baja / bloqueado

- [ ] **NCF / comprobante fiscal DGII** — **bloqueado** por el trámite en la oficina virtual (autorización + asignación de secuencia). La app no inventa números.
- [ ] **API para la web**: `GET /api/reporte` que llame al mismo SP + `fetch` en `index.html` (hoy la web es estática con simulados).
- [ ] **Lector biométrico** — sin equipo. El corte ya está: `marcarAsistenciaAuto()` toma `sesionActual.idEmpleado`; el modo huella reemplaza esa lectura sin tocar el resto. Falta decidir equipo (define opción A o B).
- [ ] **Permisos por cargo** (reclutamiento 12 vs contrataciones 13/14/15): hoy es convención del flujo, la app no separa roles. Fuera de alcance.
- [ ] **Cierre atómico de la venta a un SP** — solo si algún día aparece un segundo cliente (la Qt app); con el C++ la garantía es de este cliente.
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
| Permisos finos Tanda A y B | 22–23/10, cerrado 12/11 | 63 permisos / 232 pares / 8 roles en las dos bases, sin paraguas; `modulos/36` es el único dueño de la matriz |
| Garantías: flujo completo | 30/10, aplicado en la viva | módulos `62` y `63`; solo falta la prueba manual de §1.8 |
| Historial laboral (cargo ancho) | 12/11, fusionado 14/11 | dentro de `modulos/15` (ex módulo `68`); `db/test-historial-laboral.sh` 14/0 |
| Consolidación de módulos | 12–14/11 | **19 lotes, capa 1 cerrada**; `modulos/` pasó de 70 a **31 `.sql`**; el detalle vive en `odd/tasks/consolidacion-modulos.md` |
| Auditoría de permisos en la viva | 14/11 | sección `AUDITORIA` del `13` + `mapear-permisos.sql`; backup `backups/balbu_tech_antes_auditoria_permisos_20261114_134302.sql` |
| Reclamos y reparaciones cableados | 15/11 | `SP_ASIGNAR_TECNICO_RECLAMO`, `SP_FINALIZAR_RECLAMO` y `SP_REGISTRAR_AVANCE_REPARACION` llamados desde `ventas.cpp` |
| Limpieza de restos SQL (ítem 12c) | 15/11 | 4 SP retirados con su `DROP` y los 2 duplicados con dueño único (`65` y `66`). `cobertura-modulos.sh`: **0 repetidos** |
| P-3 validaciones (errores pintados en verde) | 15/11 | 4 lugares corregidos con el patrón de `caja.cpp`/`accesos.cpp` |
| P-4 venta multi-línea | 15/11 | **A** limpiar `EN_PROCESO`, **B** aviso de 48 h, **C** cierre atómico, **D** barrido de borradores; cada una con su test |
| Definiciones repetidas entre módulos | 15/11 | `SP_CAMBIAR_CLAVE_USUARIO` dueño único el `65`, `SP_LOGIN_AUTENTICAR` el `66` |
| Bonos (módulo 14) cableado | 18/11, aplicado en la viva | pantalla «Empleados → Gestionar bonos» + `GESTIONAR_BONOS_EMPLEADO`; `SP_LISTAR_BONOS` retirado; `db/test-bonos.sh` y `test-bonos-pantalla.sh` |
| Nómina: bonos dentro del sueldo | 18/11, aplicada en la viva | recibo con arrastre + `SP_PAGAR_NOMINA_EMPLEADO` auditado; `db/test-nomina.sh` 26/26 y `test-nomina-pantalla.sh` 11/11 |
| Orden de los triggers de `EMPLEADOS` y de `COMPRAS` | verificado 19/11 | las dos bases quedaron en el orden de una importación limpia (`ACTION_ORDER`) |
| Drift `TEST` ↔ viva en rutinas | verificado 19/11 | 191 rutinas + 6 funciones idénticas en nombre y definición; 0 drift |
| Un solo entorno para la batería + guarda de viva | 19/11 | los 2 tests de SQL directo leen `DB_ROOT_PASSWORD` del `.env`; `test-contratos-subir.sh` y `test-login-eof.sh` ganaron la guarda de "solo TEST" que les faltaba (28 de 28 tests con base ya la tienen) |
| Números del índice y del README corregidos | 19/11 | `modulos/00- INDICE.md` decía 167 SP / 79 triggers / 23 vistas / 383 `CREATE`: remedido da **47 tablas · 191 SP · 82 triggers · 26 vistas · 6 funciones · 59 índices** (medido contra los `.sql` y contra `BALBU_TECH_TEST`). Se corrigieron las 11 celdas por módulo que quedaron viejas. `README-DOCKER.md` decía 59 tablas / 124 SPs / 65 triggers y "47 SPs que la app invoca": ahora 47 / 191 / 82 y 139 |
| Duplicados muertos del módulo 25 retirados | 19/11 | `SP_REGISTRAR_GARANTIA` y `27_SP_REGISTRAR_RECLAMO_GARANTIA` estaban definidos dos veces (2 params y 3 params); el `DROP`+`CREATE` de la sección 4 ganaba, así que la copia vieja era código muerto. Verificado con import desde cero en una base scratch: 47 tablas / 26 vistas / 191 SP / 6 funciones / 82 triggers y las definiciones con **MD5 idéntico** |
| `ALTER` del módulo 25 consolidados en los `CREATE TABLE` | 19/11 | las 13 sentencias (5 `ALTER TABLE` + 5 `PREPARE` de FK/CHECK que los `ALTER` armaban) quedaron declaradas en su tabla: `PRODUCTOS.DIAS_GARANTIA` + su `CHECK` en el módulo `9`; `GARANTIAS` y `RECLAMOS_GARANTIAS` (autor, cierre, fechas y sus FK) en el `25`; `CHK_FECHAS_VALIDAS` y `CHK_CANTIDAD_REPUESTO` en sus `CREATE`. Queda **1** `ALTER` a propósito: el `DROP COLUMN IF EXISTS REPUESTO_UTILIZADO`, que no se puede expresar en un `CREATE TABLE`. Verificado con dos imports desde cero (base vs. consolidado) y **diff vacío** de columnas, tipos, `CHECK`, FK, índices, rutinas y triggers |
| `db/import.sh` falla de verdad | 19/11 | el ítem estaba viejo: **ya salía con 1** ante un error real (probado con un módulo roto: `EXIT CODE = 1`) y también ante un fallo fatal del cliente (`ERROR at line N:`), porque ese texto también empieza con `ERROR`. Reimportar los 31 módulos sobre una base poblada da **97 avisos `1050`/`1061` y 0 errores reales** (hoy son **38, todos `1050`**, tras declarar los índices dentro de su tabla): la reimportación es limpia. `--force` se queda a propósito (sin él, el primer `1050` aborta el archivo y el módulo queda a medio aplicar), documentado en el encabezado |
| `db/import.sh` ahora deja la base lista | 19/11 | **hallazgo real**: `PERMISO_POR_RUTINA` nacía vacía porque nadie corría `db/mapear-permisos.sql`; una base importada desde cero quedaba con **56 rutinas sin mapeo** (`SP_EXIGIR_PERMISO` no encontraba el permiso). Ahora `import.sh` lo corre solo (es idempotente) antes de inyectar guardas, y avisa si `balbu_app` perdió los privilegios por recrear la base. Verificado: import desde cero → `check-app-sps` **139/0, guardas completas, 56 mapeos**, sin ningún paso manual. Batería: **30/30 en verde** |
| P-5: índices dentro de su `CREATE TABLE` | 19/11 | los **59 `CREATE INDEX`** de los módulos quedaron declarados dentro del `CREATE TABLE` de su tabla (como las `FK` y los `CHECK`), en 19 archivos y 27 tablas. Reimportar ya no emite `1061` ni dropea/rebuilda índices sobre una base con datos. `IX_CLIENTE_NOMBRE` pasó del `21` al `7`, dueño de `CLIENTES`. El `DROP INDEX IF EXISTS` que se había probado en el `11` se **revirtió** para dejar una sola regla. Verificado: import desde cero **0 avisos / 0 errores**, esquema **idéntico** a `BALBU_TECH_TEST` (salvo el drift preexistente `EMPLEADOS.CEDULA`); reimport sobre base poblada **38 avisos, todos `1050`, 0 reales** (antes 97); batería **30/30** |
| P-5: rutinas huérfanas y semillas | 19/11 | medido: **0 objetos** en `BALBU_TECH` y `BALBU_TECH_TEST` que ningún módulo declare (tablas, vistas, triggers, SP, funciones) y **0 rutinas duplicadas**. De semilla: **0 `CALL`** sueltos (los 15 que hay están dentro de cuerpos de SP) y los módulos `8`/`16` no tienen ninguna. Quedan 3 `UPDATE` de **backfill** (`13` ×2 y `19` ×1) que son migración de datos, no semilla: no-op en base fresca y ayuda para bases viejas |
| Drift `EMPLEADOS.CEDULA` corregido | 19/11 | el `CREATE TABLE` del `8` pasó de `CEDULA ... UNIQUE` (índice implícito `CEDULA`) a `CONSTRAINT UQ_EMPLEADOS_CEDULA UNIQUE (CEDULA)`, el mismo nombre que ya agrega el parche para bases viejas. Una base fresca ahora nace con **un solo** índice único sobre `CEDULA`, igual que `BALBU_TECH_TEST` y la viva. El parche sigue y en base nueva no hace nada. Verificado: import desde cero **diff vacío** contra `BALBU_TECH_TEST` (174 índices en las dos), reimport **38 avisos, todos `1050`**, batería **30/30** |
| `PROVEEDORES`: índices únicos duplicados limpiados | 19/11 | el `CREATE TABLE` del `5` tenía `TELEFONO ... UNIQUE` / `EMAIL ... UNIQUE` **y** `UQ_PROVEEDOR_TELEFONO` / `UQ_PROVEEDOR_EMAIL`: dos índices únicos por columna. Se sacó el `UNIQUE` inline y quedan los constraints con nombre. Migración idempotente para bases existentes en `db/migraciones/2026-11-19-proveedores-indices-duplicados.sql` (asegura el constraint antes de dropear, así nunca se pierde la unicidad). Aplicada a `TEST` y a la viva. Verificado: un único índice por columna, un `INSERT` duplicado sigue dando `1062` por `UQ_PROVEEDOR_TELEFONO`, import desde cero **diff vacío** contra `TEST` (172 índices), batería **30/30** |
| Drift `TR_BLOQUEAR_BORRADO_VENTA` corregido | 20/11 | **Causa raíz, no era "TEST quedó atrás".** Tres tests — `test-borradores-barrido.sh`, `test-cierre-atomico.sh` y `test-cobrar-plazo.sh` — dropean el trigger para poder borrar sus ventas de prueba y lo vuelven a crear con el cuerpo escrito a mano **de una sola sentencia**, porque su heredoc usa `;` y no pueden meter un `BEGIN ... END` sin tocar el `DELIMITER`. Resultado: **cada corrida de la batería dejaba `BALBU_TECH_TEST` en drift**, y por eso un arreglo manual del trigger no aguanta. Los tres ahora lo recrean con el cuerpo **exacto** que declara `modulos/21` (`BEGIN ... END` + `DELIMITER //`), con un comentario que avisa que ese cuerpo tiene que seguir siendo el del módulo. El ítem además estaba mal medido: decía que la **viva y** `TEST` tenían la versión de una sola sentencia; la viva siempre fue la correcta. Verificado: los 3 tests en verde, `MD5(ACTION_STATEMENT)` de `TEST` igual a la viva y al import desde cero (`ffd13a05…`) **después de la batería completa**, `ACTION_ORDER` en 1 (único de su grupo en `VENTAS BEFORE DELETE`: no hay `FOLLOWS` que romper), `DELETE` real sigue cortando con `1644 / 45000`, batería **30/30** |
| `db/verificar-esquema.sh`: el instrumento que faltaba | 20/11 | el diff que se usaba para cerrar P-5, `CEDULA` y `PROVEEDORES` comparaba tablas, índices, `FK` y `CHECK`, pero **nunca cuerpos**: por eso el drift del trigger pudo vivir sin que nada lo delatara. El script compara en 9 secciones (tablas, columnas, índices, `FK` por columna, reglas de `FK`, `CHECK`, triggers con `ACTION_ORDER` + `MD5` del cuerpo, rutinas y vistas), normaliza el nombre de la base dentro de definiciones, y en modo fresco crea una temporal **con el mismo charset/collation que la base de referencia** (si no, MariaDB 11 hereda `utf8mb4_uca1400_ai_ci` y el reporte se llena de falsos positivos). Salida 0/1/2: idénticas, con diferencias, no pudo trabajar. Verificado: detectó por sí solo el trigger, `TEST` vs viva, y la viva contra un import desde cero |
| `CREATE TABLE` con `COLLATE` fijo | 20/11 | las 47 tablas de los módulos cerraban con `) ENGINE = InnoDB;` a secas, así que heredaban el collation **de la base**. Una base creada con el default de MariaDB 11 (`utf8mb4_uca1400_ai_ci`) producía 47 tablas con otro collation que la viva y `TEST` (`utf8mb4_unicode_ci`): el esquema no era reproducible. Ahora las 47 cierran con `DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`. `LOG_USUARIOS` (módulo `29`) era la única que ni siquiera declaraba `ENGINE`: cerraba con `);` pelado. Verificado: base creada **sin** `COLLATE` (default `utf8mb4_uca1400_ai_ci`), import desde cero **0 avisos / 0 errores**, las **47 tablas** salen `utf8mb4_unicode_ci`, y el esquema queda **idéntico** a `BALBU_TECH_TEST` en las 9 secciones del verificador; reimport sobre base existente **38 avisos, 0 reales** |
| `db/aplicar-grants.sh` idempotente y a prueba de mentira | 20/11 | el script **mentía en dos formas**: (1) `SHOW GRANTS` sin chequear — si fallaba, `GRANTS` quedaba vacío, todos los controles pasaban sin mirar nada y el script imprimía `OK: … verificados`; (2) un `exit 1` dentro del loop dejaba las demás cuentas `balbu_app` sin endurecer. Además **solo andaba dentro del contenedor**: usaba socket fijo, así que desde el host no encontraba el servidor. Ahora: pre-chequeo de conexión, del esquema y de las cuentas (sale 2 si no puede trabajar), `DB_HOST`/`DB_PORT` opcionales para TCP, `DB_APP_USER` respetado (antes `import.sh` lo leía y el script lo ignoraba), `SHOW GRANTS` vacío o fallido es error, y una cuenta mala no saltea las otras. `db/import.sh` ahora imprime el **comando exacto** para reponer los grants (el del contenedor y el del host, listos para copy-paste). Verificado: dos corridas seguidas sobre `TEST` dejan `SHOW GRANTS` **idéntico**; degradando a mano `TEST` (0 grants, `balbu_app` denegado en `CLIENTES` y en `FN_TASA_ITBIS`) el script lo **restaura idéntico a la referencia** (34 líneas) y la app vuelve a andar con `CONTRASENA` todavía denegado; el comando impreso por `import.sh` se ejecutó **tal cual** sobre una base nueva y funcionó; sobre la viva fue **no-op** (34 líneas idénticas antes y después); batería **30/30** (`29 de los 30` tests usan la credencial de la app, así que validan los grants de verdad)  |
| `BALBU_TECH` alineada con el repo | 21/11, aplicada en la viva | `db/migraciones/2026-11-21-alinear-viva-al-repo.sql`: 8 reordenamientos de columnas y 5 diferencias con efecto (`PRODUCTOS.P_COMPRA` con `DEFAULT 0.00`, `LOG_ACCESOS.USUARIO_INTENTADO` sin default, `FK_PRODUCTO_PROVEEDOR` de `CASCADE` a `RESTRICT`, la `FK` de `DETALLES_VENTA` renombrada, las 2 `FK` que le faltaban a `LOG_USUARIOS`) más el `IX_PRODUCTOS_PROVEEDOR` de más. Probada primero en un **clon completo de la viva** (73 objetos, con datos) y recién después aplicada, con respaldo `backups/balbu_tech_antes_alinear_20261121_135208.sql`. Verificado: la viva y un import desde cero quedan **idénticas en las 9 secciones** del verificador (0), los datos **no cambian** (checksum por tabla igual antes y después), es **idempotente** (2 corridas = mismo esquema) y la batería sigue **30/30**. Dos trampas quedan documentadas en el archivo: `MODIFY COLUMN` **borra el `CHECK` de columna** si no se repite (se perdían 3 de 63) y `DROP FOREIGN KEY` **no borra el índice** que usaba la `FK`, así que el nombre de la constraint no cambia si no se suelta el índice antes |

---

## Comandos

```bash
# Con el .env cargado, todo el entorno sale de ahi (DB_ROOT_PASSWORD incluida).
# Los tests de SQL directo ya leen DB_ROOT_PASSWORD: no hace falta pasar claves.

# Build
./build.sh

# SPs que usa la app (debe dar 139/0, siempre contra TEST)
DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh

# Cobertura: que SPs existen y nadie llama (no necesita base de datos)
bash db/cobertura-modulos.sh

# Esquema: ¿la base que corre es la que produce el repo?
# Compara tablas, columnas, índices, FK, CHECK, triggers (cuerpo + ACTION_ORDER),
# rutinas y vistas. Sin BASE_B crea una temporal, importa modulos/ y compara.
set -a; . ./.env; set +a
DB_HOST=127.0.0.1 DB_ADMIN_USER=root DB_ADMIN_PASSWORD="$DB_ROOT_PASSWORD" \
  bash db/verificar-esquema.sh BALBU_TECH
# Dos bases que ya existen (no importa nada, no necesita root):
DB_HOST=127.0.0.1 bash db/verificar-esquema.sh BALBU_TECH BALBU_TECH_TEST

# Menús por rol (sobre TEST)
BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh

# Contrato: UI
DB_NAME=BALBU_TECH_TEST BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=admin BALBU_PASS=<clave-admin> bash db/test-contrato-borrador.sh

# Contratos: SQL
DB_NAME=BALBU_TECH_TEST bash db/test-contratos-subir.sh
```

---

## Referencias

Todo lo que sigue salió del repo el 08/11/2026 y vive en
`../BalbuTechApp-fuera-del-repo/` (ver su `LEEME.md`):

- `Planes/Realizado.md` — lo hecho, con evidencia.
- `Auditoria/` — hallazgos con detalle (18/10 código + BD; 08/10 solo lo abierto).
- `Flujos/` — requisitos legales del contrato, flujo de producto y de BD.
- `Reglas/Reglas de trabajo.md` — cómo se trabaja.
