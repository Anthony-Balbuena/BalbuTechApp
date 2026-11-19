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

Todo se prueba **primero en `BALBU_TECH_TEST`**, con la matriz de permisos aplicada (la crea `36`; el resto son los módulos de soporte; hoy son 63 permisos). (03/11/2026) La viva quedó al día: se aplicaron `62`, `63`, `64`, `65` y `66` con backups previos `backups/balbu_tech_antes_t2_20261103_152050.sql`, `backups/balbu_tech_antes_login_srv_20261103_163105.sql` y `backups/balbu_tech_antes_guardas_20261103_165608.sql`; `check-app-sps` 123/0 con cobertura de guardas completa en ambas bases. (05/11/2026) La base local de casa (3306) también quedó al día: `63`, `64`, `65`, `66` y `62` en `BALBU_TECH`, y `64`, `65` y `66` en TEST, con backups `backups/BALBU_TECH_antes_62-66_casa_20261105_004038.sql` y `backups/BALBU_TECH_TEST_antes_62-66_casa_20261105_004038.sql`; `EXIGIR = 1` en 169 rutinas de la viva y 161 en TEST, y la batería de entonces en verde. **Ojo: esa «batería completa» eran 12 tests de 25; ver P2.** Detalle en `Realizado.md`, hoy fuera del repo.

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
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=<clave-root> bash db/test-contrato-borrador.sh` | contrato borrador | 15/15 (`balbu_app` no sirve: el test hace SQL directo y corta avisando) |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-asistencia-propia.sh` | fichar sin pedir ID | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh` | módulo 44 (rol viejo → VENDEDOR) | 11/11 |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-lockout.sh` | módulo 64: bloqueo por 5 fallos / 15 min, sin fila nueva al reintentar bloqueado, `FN_TIENE_PERMISO` con `ESTADO` e índice del log | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-login-servidor.sh` | módulo 65: verificación en el servidor, migración automática al primer login, segundo login, clave mala y hash inaccesible para `balbu_app` | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-permisos-sp.sh` | módulo 66: sin token rechaza, token de VENDEDOR pasa lo suyo y se corta en lo ajeno, rechazo registrado | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh` | login con entrada agotada (no gira ni ensucia `LOG_ACCESOS`) | OK |
| `docker compose cp db/grant-minimos.sql db:/tmp/ && docker compose cp db/aplicar-grants.sh db:/tmp/ && docker compose exec -T db bash /tmp/aplicar-grants.sh BALBU_TECH_TEST` | privilegios mínimos de `balbu_app` (solo `EXECUTE` + lecturas necesarias) | OK |

**Manual, por área:**

> **El test `db/test-menus-por-rol.sh` ya verifica los CONTEOS de opciones** de
> cada menú y submenú entrando a la app con cada rol: eso atrapa rápido una
> opción que se cuela o que desaparece. **No reemplaza este recorrido** — abajo
> está lo que hay que mirar a mano. Los conteos de la lista están corregidos con
> lo que la app muestra hoy; los viejos estaban mal (decían 16 para GERENTE y
> son 15, etc.).

#### 2.1 Sesión y menú principal

- [ ] ADMIN entra y ve **19** opciones.
- [ ] GERENTE ve **15** y **no** aparecen Roles ni Usuarios.
- [ ] SUBGERENTE ve **15**, con Empleados (solo 3: buscar, listar, volver) y Asistencia (7, con Justificar).
- [ ] RRHH ve **5**; VENDEDOR **9**; ALMACEN **10**; CONTABILIDAD **5**.
- [ ] Usuario con `ESTADO = INACTIVO` **no** puede entrar (el login lo rechaza y deja `LOG_ACCESOS` con `INACTIVO`). Desde el módulo 64 `FN_TIENE_PERMISO` también devuelve 0 para esa cuenta.
- [ ] **Bloqueo por fuerza bruta (módulo 64):** cinco fallos del mismo usuario dentro de 15 minutos cierran el acceso con el aviso `Cuenta bloqueada por intentos fallidos`. Cerrar y reabrir la app **no** reinicia el contador. Un intento bloqueado **no** agrega filas en `LOG_ACCESOS` (si agregara, la ventana se correría sola y el bloqueo no vencería nunca). Pasados los 15 minutos, la clave correcta vuelve a entrar.
- [ ] **Cambio en caliente:** con una sesión de VENDEDOR abierta, quitarle desde ADMIN los tres permisos que le quedan de Clientes (`CLIENTES_CREAR`, `CLIENTES_EDITAR`, `CLIENTES_ESTADO`) y volver al menú principal. Clientes desaparece **sin re-login** (el menú consulta `FN_TIENE_PERMISO` en cada vuelta).
- [ ] Al reingresar después de quitar los permisos, la opción sigue ausente.

#### 2.2 Usuarios (solo ADMIN)

- [ ] Crear usuario con rol VENDEDOR y clave; entrar con él.
- [ ] Editar el nombre y el rol; verificar que el menú cambie en el siguiente ingreso.
- [ ] Desactivar la cuenta; el login falla con el aviso correspondiente.
- [ ] Reactivar; el login vuelve a funcionar.
- [ ] Cambiar la clave; la vieja deja de servir y la nueva entra.
- [ ] GERENTE **no** ve el módulo Usuarios.

#### 2.3 Empleados

- [ ] RRHH: crear empleado, editarlo, darlo de baja y reactivarlo.
- [ ] RRHH: gestionar contrato, permiso y vacaciones desde el submenú.
- [ ] RRHH: cobrar la nómina de un empleado con bonos pendientes — el recibo tiene que mostrar el arrastre (bonos de meses anteriores) y el pago tiene que dejar fecha y usuario.
- [ ] SUBGERENTE: no ve «Gestionar bonos» ni «Nómina (recibo y pago)» (los dos permisos quedaron fuera de su rol).
- [ ] SUBGERENTE: entra a Empleados pero solo ve consulta; **no** puede crear, editar ni dar de baja.
- [ ] Un usuario sin ningún permiso `EMPLEADOS_*` no ve el módulo (salvo que tenga `REGISTRAR_ASISTENCIA` o `CONSULTAR_ASISTENCIA`, que abren **Asistencia**, no Empleados).

#### 2.4 Clientes

- [ ] VENDEDOR: solo crear, editar y cambiar estado (4 opciones contando Volver); **no** aparecen Buscar ni Listar.
- [ ] CONTABILIDAD: solo `CLIENTES_VER`; ve la consulta y nada más.
- [ ] Quitar `CLIENTES_ESTADO` a VENDEDOR: la opción desaparece del submenú, **no** queda un hueco y pasa a 3 opciones.

#### 2.5 Proveedores

- [ ] ALMACEN: ver, crear, editar y cambiar estado (6 opciones en el submenú).
- [ ] Sin `PROVEEDORES_CREAR`, la opción de alta desaparece y el resto sigue funcionando.

#### 2.6 Asistencia

- [ ] Los 7 roles pueden **fichar** (`REGISTRAR_ASISTENCIA`).
- [ ] VENDEDOR ve 3 opciones, **sin** reportes.
- [ ] SUBGERENTE ve 7, con Justificar.
- [ ] ADMIN, GERENTE, SUBGERENTE y RRHH ven los reportes (`CONSULTAR_ASISTENCIA`).
- [ ] "Mi asistencia" usa el `ID_EMPLEADO` de la sesión, **no** pide ID a mano.
- [ ] `CONSULTAR_ASISTENCIA` **no** abre Empleados.
- [ ] Justificar una ausencia y ver el cambio en el reporte.

#### 2.7 Productos

- [ ] ALMACEN ve 7 (gestión + consulta).
- [ ] CONTABILIDAD ve 4 (solo consulta).
- [ ] Un rol sin `CONSULTAR_PRODUCTOS` no ve el módulo.
- [ ] `PRUEBA_PROD_GEST` (solo gestión) ve 4 y no ve las de consulta.

#### 2.8 Ventas

- [ ] VENDEDOR ve 10: las 7 de gestión, historial, garantías y volver, **sin** reportes ni exportación.
- [ ] `PRUEBA_VEN_GEST` (sin `CONSULTAR_REPORTES`) ve 8: solo las acciones sobre la venta, **sin** Garantías.
- [ ] **Garantías** ya no cuelga de `GESTIONAR_VENTAS`: se abre con cualquiera de sus 4 permisos (módulo `62`) y el submenú filtra por permiso.
- [ ] ADMIN/GERENTE/SUBGERENTE ven **7** opciones en Garantías (incluye "Registrar avance"); TECNICO 3; VENDEDOR 4 (sin "Finalizar reclamo"); CONTABILIDAD 2 (solo consultar).
- [ ] Un usuario con `GARANTIAS_CONSULTAR` y sin `GESTIONAR_VENTAS` llega a Garantías por el ítem "Ventas" del menú principal.

#### 2.9 Roles

- [ ] Crear un rol nuevo, asignarle `CLIENTES_VER` y entrar con un usuario de ese rol.
- [ ] Quitarle el permiso y verificar que el módulo desaparezca.
- [ ] Borrar el rol: los usuarios que lo tenían no pueden entrar (verificar el mensaje).
- [ ] Renombrar un rol: los permisos lo siguen (`ON UPDATE CASCADE`).

#### 2.10 Migración de roles (módulo 44) — ✅ verificado en la viva el 15/11/2026

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

- [x] **14 Bonos — ✅ cableado y probado en TEST el 18/11/2026.** Pantalla «Empleados
  → Gestionar bonos» (`bonos.cpp`) con listar paginado por estado, pagar, anular y
  registrar; permiso nuevo `GESTIONAR_BONOS_EMPLEADO` (ADMIN, GERENTE y RRHH;
  SUBGERENTE no). El 1 % lo sigue generando el trigger de 24. `SP_LISTAR_BONOS` se
  retiró (lo reemplazó el par paginado) y `SP_ACTUALIZAR_BONO` queda sin cablear a
  propósito. Tests: `db/test-bonos.sh` (18 comprobaciones + 7 frenos),
  `db/test-bonos-pantalla.sh` y el caso nuevo de `db/test-menus-por-rol.sh`.
  **Aplicado en la viva el 18/11/2026**, con backup previo
  `backups/balbu_tech_antes_bonos_20261118_214014.sql` (704 K, 47 tablas, 188 SP,
  6 funciones, 82 triggers, 26 vistas) y el orden obligatorio
  `14 → 36 → mapear-permisos → injectar-guardas → check-app-sps`. Resultado:
  `check-app-sps` contra `BALBU_TECH` da **Faltantes 0 (136), guardas completas,
  53 mapeos**; permisos 61 → 62; `SP_CONTAR_BONOS('PENDIENTE')` devuelve **11** y
  el paginado trae los 11 bonos por **$10.330,00**; la vista pasó a devolver
  `0` (no `NULL`) para quien no tiene bonos y sigue sumando 10330.00. Nada más se
  movió: 47 tablas, 26 vistas, 6 funciones y 82 triggers iguales al backup, y
  `SP_LISTAR_BONOS` es el único SP retirado. **Queda verlo con los ojos**: abrir
  «Empleados → Gestionar bonos» con `abalbuena` y confirmar los 11; el humo por la
  app no se puede hacer desde acá porque el `BALBU_USER` del `.env` es `admin`
  (de TEST) y en la viva el admin es `abalbuena`. **Al probarla apareció un bug de
  verdad** (18/11/2026): con más de una página, el paginador redibujaba la tabla
  entera en silencio ante cualquier tecla que no fuera `N`/`P`, así que tipear el
  número de una fila parecía colgar la pantalla. `paginacion.h` ahora avisa
  («Tecla no valida: N siguiente, P anterior, Enter para continuar.») y vuelve a
  pedir la tecla **sin** redibujar; el prompt dice `[Enter] continuar` y no
  `elegir`, porque no se elige una fila: se sale al menú. El arreglo cubre a las 6
  pantallas que comparten el paginador. Test de regresión en
  `db/test-bonos-pantalla.sh` (fuerza 2 páginas, tecla inválida y `N`).
- [x] **Nómina — recibo y pago de los bonos dentro del sueldo — ✅ aplicada en la viva el 18/11/2026** (probada en TEST primero). Cierra un agujero de plata: «pagar un bono» solo hacía `UPDATE ESTADO='PAGADO'`, sin fecha ni actor, así que no había forma de responder *cuándo y quién* le pagó a un empleado. Decisión del dueño: **el bono se paga dentro del sueldo del mes**, no aparte (opción A), y el recibo **arrastra** los `PENDIENTE` de cualquier mes — la nómina de octubre nunca se corrió y esos 7 bonos por $7.175 no los levantaría ningún mes.
  - **Módulo 14:** `FECHA_PAGO DATE NULL` + `PAGADO_POR VARCHAR(50) NULL` (nombre de usuario, como `AUDITORIA_SISTEMA.USUARIO_SISTEMA`: si se borra la cuenta, el bono igual dice quién pagó), en el `CREATE TABLE` y con `ALTER` idempotente por `INFORMATION_SCHEMA`; `SP_PAGAR_BONO` los escribe con `FN_USUARIO_SESION()` (sin sesión quedan `NULL`, no se inventa); `SP_LISTAR_BONOS_PENDIENTES_EMPLEADO` nuevo; `TR_BLOQUEAR_CAMBIO_BONO` ahora también congela fecha y pagador (con `<=>`, porque un `<>` contra `NULL` no frenaba nada).
  - **Módulo 8:** `SP_GENERAR_RECIBO_EMPLEADO` suma `CANTIDAD_BONOS_PENDIENTES`, `TOTAL_BONOS_PENDIENTES` y `TOTAL_A_PAGAR`, **no marca nada** (un recibo no es un pago: marcar al imprimir dejaría bonos pagados sin que salga plata) y ya no exige `ACTIVO` (un despedido con bonos pendientes igual cobra; sin eso la pantalla no tenía salida); `SP_PAGAR_NOMINA_EMPLEADO` nuevo, que es el acto de pago, por empleado (no masivo) y con confirmación `s/n`.
  - **`SUELDO_BRUTO` y SFS/AFP no cambian de base:** el bono se suma **después** del neto. Si cotiza o es gravable lo define el contador; el recibo no afirma nada previsional y el sistema **no** paga sueldos (no hay tabla de nómina).
  - **Módulo 36:** permiso nuevo `GESTIONAR_NOMINA` (ADMIN, GERENTE y RRHH; SUBGERENTE no) en vez de reutilizar `GESTIONAR_BONOS_EMPLEADO`; las 3 rutinas mapeadas a ese permiso con `EXIGIR = 1`; `GESTIONAR_NOMINA` agregado a la lista del ítem «Empleados» de `roles.cpp` (sin eso la pantalla existía pero nadie llegaba).
  - **Pantalla:** `nomina.cpp`/`nomina.h`, «Empleados → Nómina (recibo y pago)»; lista paginada, recibo con el detalle de bonos y el total.
  - **Tests:** `db/test-nomina.sh` (26 comprobaciones; **RED verificado con las definiciones viejas: 9 fallos**) y `db/test-nomina-pantalla.sh` (11, incluida «responder `n` no marca nada»). **Batería completa: 30/30 verdes, 0 rojos.** `check-app-sps` en TEST: Faltantes 0 (139), guardas completas, 56 mapeos.
  - **Bug encontrado al cablear la pantalla:** leer el `ResultSet` de un `CALL` sin `res.reset()` + `drenarResultados()` deja la conexión envenenada y la consulta siguiente muere con `Commands out of sync`; el patrón quedó documentado en el `.md` del 8.
  - **Aplicado en la viva el 18/11/2026**, con backup previo `backups/balbu_tech_antes_nomina_20261118_230720.sql` (708 K) **probado restaurando**: la copia carga en una base scratch y devuelve las mismas 47 tablas, 26 vistas, 195 rutinas, 82 triggers, 62 permisos y 11 bonos. Se aplicó con `--database=BALBU_TECH` explícito, en el orden obligatorio `14 → 8 → 36 → mapear-permisos → injectar-guardas → check-app-sps`. Sin un solo error inesperado (los 6 `^ERROR` son idempotencia: 1050 tabla existe y 1061 índice/columna duplicada).
  - **Qué se movió, medido contra las huellas de antes**: por hash de definición, **2 SP nuevos** (`SP_PAGAR_NOMINA_EMPLEADO`, `SP_LISTAR_BONOS_PENDIENTES_EMPLEADO`), **3 objetos modificados** (`SP_GENERAR_RECIBO_EMPLEADO`, `SP_PAGAR_BONO`, `TR_BLOQUEAR_CAMBIO_BONO`) y **nada más**: cero vistas, cero triggers ajenos, cero rutinas de otros módulos. Inventario: 195 → **197 rutinas**, 62 → **63 permisos**, 229 → **232 pares** (los +3 son ADMIN, GERENTE y RRHH), 47 tablas y 82 triggers iguales.
  - **Comprobado con los datos reales**: `check-app-sps` contra `BALBU_TECH` da **Faltantes 0 (139), guardas completas, 56 mapeos**; las 3 rutinas quedaron mapeadas a `GESTIONAR_NOMINA` con `EXIGIR = 1` y con la guarda dentro de la definición; `balbu_app` sin sesión es rechazado con `ERROR: SESION INVALIDA O VENCIDA.` y el rechazo queda en `LOG_PERMISO_SP`; el recibo de los 2 empleados con pendientes devuelve el arrastre (emp 1: 9 bonos por $8.275; emp 6: 1 bono por $55 → **$8.330**); pagarle a alguien sin pendientes contesta `AVISO` y no escribe; el trigger nuevo rechaza reescribir la auditoría (`ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.`); y la huella de `BONOS_EMPLEADOS` (`crc=29735795882`, 11 bonos, $10.330) quedó **idéntica** después de todas las sondas. `balbu_app` ya tenía `EXECUTE` a nivel esquema, así que no hizo falta ningún grant nuevo.
  - **El bono ID 4 ($2.000) que se pagó a mano** sigue con `FECHA_PAGO` y `PAGADO_POR` en `NULL`: no se rellenan con datos inventados.
  - **Queda verlo con los ojos** (no se puede automatizar desde acá: el `BALBU_USER` del `.env` es `admin`, de TEST, y en la viva el admin es `abalbuena`): entrar con `abalbuena`, abrir «Empleados → Nómina (recibo y pago)», mirar el recibo del empleado 1 (9 bonos) y el del 6 (1 bono), y recién ahí decidir si se paga. El binario nuevo es `./output/app`; si el de la viva es otro, hay que recompilar con `bash build.sh`.
  - **Lo que NO se pudo correr**: la review nativa de Gentle AI. Con el interruptor encendido y el tier `high`, las dos lentes devolvieron `opencode_review_transport_relay_refused (reason: provider_failed)` (fallo del proveedor del modelo, no de Gentle AI) y no se reintentó más: no hay recibo de review ni aprobación, y la entrega sigue siendo decisión del dueño. La transacción quedó atada (linaje `review-740301e62eb157a8`) por si se quiere reintentar.
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

- [ ] **¿RRHH va o no?** (12, 13, 16 y el historial de 15; el 14 y la nómina ya quedaron cableados el 18/11/2026). Con lo ya hecho, va.
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

### 12. Inventario: qué SP y qué trigger no llama nadie (12/11/2026, actualizado el 18/11/2026)

Medido con `bash db/cobertura-modulos.sh` (estático, no abre la base) y cruzado
contra los SP que la app llama y los que esos llaman: **191 definiciones, 191
rutinas distintas y ningún nombre repetido**. De las que la app no llama:

- **33 no las llama nadie**: ni la app, ni otro SP, ni un `CALL` de importación.
- **4 las llama otro SP**: `SP_EXIGIR_PERMISO`, `SP_REGISTRAR_ACCESO`,
  `SP_MARCAR_GARANTIAS_VENCIDAS` y `PARA_ACTUALIZARDATOS`. Son infraestructura
  interna: no se tocan.

> (15/11/2026) El conteo de hoy es **188/38**. Pasó por 189/39 cuando entraron
> los 5 SP nuevos del paginado de ventas; después **`SP_HISTORIAL_VENTA` (21) se
> retiró** (su único uso era la pantalla «Historial de venta», que ahora usa
> `SP_HISTORIAL_VENTA_PAGINADO`), así que volvió a 188. El test
> `db/test-historial-garantias-venta.sh` se migró al SP paginado en vez de
> quedarse verificando una rutina muerta.
>
> (18/11/2026) **189/34 al cablear los bonos (módulo 14).** Entraron
> `SP_LISTAR_BONOS_PAGINADO` y `SP_CONTAR_BONOS`, salió `SP_LISTAR_BONOS`
> (reemplazado por el paginado), y los 3 de escritura más el par nuevo pasaron a
> tener llamador: la pantalla «Empleados → Gestionar bonos». De los 5 que
> estaban sin uso queda **uno solo, `SP_ACTUALIZAR_BONO`, sin cablear a
> propósito**: corregir el monto de un bono sin rastro es peor que anularlo y
> volver a registrarlo, que deja historia. No es deuda: es una decisión.
>
> (18/11/2026) **191/33 al cablear la nómina (módulos 8 y 14).** Entraron
> `SP_PAGAR_NOMINA_EMPLEADO` y `SP_LISTAR_BONOS_PENDIENTES_EMPLEADO` (los dos con
> llamador desde la pantalla de nómina) y `SP_GENERAR_RECIBO_EMPLEADO` pasó de
> huérfano a tener pantalla, así que salió del grupo **a**. El `191` coincide con
> lo que `db/injectar-guardas.py` encuentra en la base, y eso es la contraprueba
> de que el conteo estático no se quedó corto.

- [ ] **¿Qué se borra del inventario de SP y triggers?** Está todo listado y
  clasificado abajo. La decisión es **por grupo**, no por SP suelto.

#### 12.1 Las 33 sin llamador

**a) API sin pantalla — Qt probablemente las quiera, no borrar:**

| Módulo | SP |
|---|---|
| 19 Compras | `SP_ASIGNAR_FACTURA_COMPRA` |
| 21 Ventas | `SP_ASIGNAR_FACTURA_VENTA` |
| 19 Pagos de compra | `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA` |
| 22 Detalle de compra | `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA` |
| 17 Inventario (ex 20) | `SP_KARDEX_PRODUCTO`, `SP_KARDEX_TODOS` |
| 8 Empleados | `SP_ANIVERSARIOS_MES`, `SP_AUMENTO_POR_CARGO`, `SP_BUSQUEDA_RAPIDA_EMPLEADOS`, `SP_CONSULTAR_EMPLEADOS`, `SP_REPORTE_NOMINA_TOTAL` |
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
| 14 Bonos empleados | `SP_ACTUALIZAR_BONO` | **Cableado el 18/11/2026**: la pantalla «Empleados → Gestionar bonos» usa registrar, pagar, anular y el listado paginado; la nómina (8) usa el detalle de pendientes. Queda sólo `SP_ACTUALIZAR_BONO` sin uso, **a propósito** (corregir el monto sin rastro es peor que anular y volver a registrar). |
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
**38 sin uso de 188**. Ver arriba.)

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

- [ ] **`db/import.sh` no dropea la base** y un `DROP` se lleva el grant de
  `balbu_app`: hay que volver a otorgarlo con `db/aplicar-grants.sh`.
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
- [ ] **La batería son 30 tests, no 12, y hay que correrlos todos.** Hasta el
  15/11 se corrían solo los de la tabla de arriba y se reportaba como «batería
  completa». Con el entorno completo (`DB_APP_PASSWORD` incluido) están **los 30
  en verde** (18/11/2026: entraron `test-nomina.sh` y `test-nomina-pantalla.sh`).
  Ojo con dos cosas al correrlos: casi todos usan
  `DB_ADMIN_USER`/`DB_ADMIN_PASSWORD`, y **varios default a `BALBU_TECH`**, así
  que hay que pasarles `DB_NAME=BALBU_TECH_TEST` explícito. Además,
  `test-contrato-borrador.sh` y `test-contratos-subir.sh` hacen SQL directo y
  **no leen `DB_ADMIN_*`: exigen `DB_USER=root DB_PASSWORD=<clave de root>`
  explícitos** (el `.env` trae `DB_USER=balbu_app`, y con ese usuario fallan con
  «INSERT command denied», no con un error de credencial: se ven como rojo de
  código cuando es de invocación). **Que estén todos en verde es lo que hace que
  un rojo signifique algo.**
- [ ] **El cliente `mariadb` dentro de `docker compose exec` pierde las comillas
  dobles del SQL.** Usar archivo `.sql` o here-doc.
- [ ] **P-5**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas, y sacar de los módulos el `UPDATE` y los `CALL` de semilla. Los `SELECT *` sueltos ya no están: se sacaron del `43` y del `14` (15/11/2026).
- [ ] **`db/import.sh`** sigue con `--force` (ahora cuenta los `^ERROR` y avisa): hacerlo fallar de verdad.
- [ ] **Consolidar los `ALTER` de 25** dentro del `CREATE TABLE`; `DROP IF EXISTS` en los `CREATE` del módulo 11.
- [ ] **3 tests shell** pendientes y notas obsoletas del índice (`modulos/00- INDICE.md`).
- [ ] **`db/crear-usuarios.sh` no existe**: buscar el comando de provisión de la máquina del trabajo y compararlo con `balbu_app` / `balbu_admin`.
- [ ] **Sidecar `.borrador`** guarda PII en texto plano junto al HTML (registrado y aceptado por el dueño).
- [ ] **`contratos/firmados/`**: sin listado, renombre ni limpieza; la administra RRHH a mano.
- [ ] **P-6**: decidir cablear o retirar lo construido y no cableado. **Al 18/11/2026
  quedan solo liquidaciones (16) y 5 SP del módulo 19** (`SP_ASIGNAR_FACTURA_COMPRA`,
  `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA`,
  `SP_MODIFICAR_LINEA_COMPRA`, `SP_QUITAR_DETALLE_COMPRA`): garantías, reclamos,
  reparaciones, bonos y nómina ya están cableados y probados.
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
| Limpieza de restos SQL (ítem 12c) | 15/11 | 4 SP retirados con su `DROP` (`1_SP_VERIFICAR_CATEGORIA_EXISTE`, `18_SP_CAMBIAR_ESTADO_PRODUCTO`, `SP_INSERTAR_INVENTARIO`, `11_SP_REGISTRAR_SALIDA`) y los 2 duplicados con dueño único (`65` y `66`). `cobertura-modulos.sh`: **38 sin uso de 184, 0 repetidos** (hoy 38 de 188) |
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
