# PENDIENTES — todo en un solo lugar

> **Único archivo de pendientes del proyecto.** De arriba abajo = prioridad.
> Lo hecho vive en `Realizado.md`; los detalles largos, en `Auditoria/` y `Flujos/`.
> Actualizado: 30/10/2026.

---

## 🔴 P0 — Ahora (bloquea lo que estás haciendo)

### 1. Permisos finos: Tanda B cerrada en TEST y en la viva

Estado: **TEST migrado; la viva pendiente de los módulos 62 y 63** (30/10/2026: 7 roles, **58 permisos**, matriz **58/52/46/12/15/25/5 = 213 pares** en TEST; `test-menus-por-rol.sh` OK en TEST, `check-app-sps` 99/0 en TEST). Backup vivo previo: `backups/107-antes-permisos-inventario-20261027_123943.sql`. El 27/10 se re-aplicaron `36` y `58`: el estado real anterior era 52 permisos / 193 pares y VENDEDOR con 16, no 54/197. Usuarios, Empleados, Clientes, Proveedores, Asistencia, Productos, Ventas, Categorías, Marcas, Métodos de pago, Compras, Caja e Inventario ya están cerrados; **no queda ningún módulo con permiso paraguas**. El detalle con evidencia vive en `Realizado.md`. VENDEDOR ya no ve reportes ni ganancias: el historial tiene permiso propio (`CONSULTAR_HISTORIAL_VENTA`). VENDEDOR quedó en 15 permisos: no busca ni lista clientes (`CLIENTES_VER`), de Métodos de pago solo conserva `METODOS_PAGO_VER`, y en Garantías registra, reclama y consulta pero **no** finaliza.

- [x] ~~**Inventario**: migrar sus tres acciones a permisos finos.~~ Hecho en TEST el 27/10 con `INVENTARIO_VER`, `INVENTARIO_AJUSTAR` e `INVENTARIO_COSTO` (módulo `58`).
- [x] ~~**Aplicar el `58` en la viva** con backup previo.~~ Hecho el 27/10 con backup `backups/107-antes-permisos-inventario-20261027_123943.sql`.

**Estimación de esfuerzo (26/10):** ya no quedan módulos con paraguas; la Tanda B está cerrada.

- **Inventario** cerrado: `INVENTARIO_VER` abre Movimientos, `INVENTARIO_AJUSTAR` el ajuste de stock e `INVENTARIO_COSTO` el precio de compra. Cualquiera de los tres abre el ítem del menú.
- **Caja** ya quedó cerrada en esta tanda: permisos propios (`CONSULTAR_CAJA`, `ABRIR_CAJA`, `CERRAR_CAJA`), módulo `53` aplicado en TEST y VENDEDOR conserva los tres.
- **Ventas** ya está cerrado, Garantías incluida: el módulo `62` le dio cuatro permisos propios y el submenú ya no despacha por número fijo. Falta aplicarlo en la viva.
- Lo que sigue son los P1/P2 (garantías, RRHH, deuda técnica), no permisos finos.

**Patrón** (referencia: `clientes.cpp`, el más chico y limpio):

- enum de acciones + vector `{etiqueta, permiso, accion}`; `permiso` vacío = siempre visible.
- Lista filtrada con `tienePermiso()` y **despacho por `accion`**, nunca por número absoluto.
- Numerar sobre lo visible (sin huecos); no repetir `tienePermiso` dentro de cada `case`.
- Incluir `roles.h` en el `.cpp`.
- En `roles.cpp`, `{}` significa **siempre visible** (no usar vector vacío para "todos").

**Por módulo:** proponer permisos (`X_VER`, `X_CREAR`, `X_EDITAR`, `X_ESTADO`), aplicar el patrón, actualizar `roles.cpp`, `modulos/36- PERMISOS_ROLES.sql/.md` y `db/test-menus-por-rol.sh`; probar en `BALBU_TECH_TEST` y **recién después** la viva con backup previo.

**Trampas ya encontradas:**

- `FN_TIENE_PERMISO` no valida cuentas `INACTIVO` (un usuario dado de baja sigue devolviendo `TRUE`).
- `REGISTRAR_ASISTENCIA` **ya no abre Empleados**: desde el 23/10/2026 abre el
  ítem propio `Asistencia` (primero del menú). `CONSULTAR_ASISTENCIA` filtra los
  reportes; VENDEDOR, ALMACEN y CONTABILIDAD solo fichan y ven lo suyo.
  **Resuelto** (ver `Realizado.md`, 23/10).
- El cliente `mariadb` dentro de `docker compose exec` pierde las comillas dobles del SQL (usar archivo `.sql` o here-doc).
- `db/import.sh` no dropea la base; y el `DROP` borra el grant de `balbu_app` (hay que volver a otorgarlo).
- `ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE` es ambiguo si el `SELECT` también lee `ROL_PERMISO`.

### 2. Pruebas de aceptación: todo lo hecho (Tanda A y B)

Todo se prueba **primero en `BALBU_TECH_TEST`**, con la matriz de 58 permisos aplicada (`36`, `44`, `45`, `46`, `47`, `49`, `50`, `51`, `52`, `53`, `58`, `62`, `63`, `64`, `65`, `66`). (03/11/2026) La viva quedó al día: se aplicaron `62`, `63`, `64`, `65` y `66` con backups previos `backups/balbu_tech_antes_t2_20261103_152050.sql`, `backups/balbu_tech_antes_login_srv_20261103_163105.sql` y `backups/balbu_tech_antes_guardas_20261103_165608.sql`; `check-app-sps` 102/0 con cobertura de guardas completa en ambas bases. (05/11/2026) La base local de casa (3306) también quedó al día: `63`, `64`, `65`, `66` y `62` en `BALBU_TECH`, y `64`, `65` y `66` en TEST, con backups `backups/BALBU_TECH_antes_62-66_casa_20261105_004038.sql` y `backups/BALBU_TECH_TEST_antes_62-66_casa_20261105_004038.sql`; `EXIGIR = 1` en 169 rutinas de la viva y 161 en TEST, y la batería completa en verde. Detalle en `Realizado.md`.

**Automático (ya corre, solo hay que ejecutarlo):**

| Comando | Cubre | Esperado |
|---|---|---|
| `bash build.sh` | compila | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/check-app-sps.sh` | SPs que usa la app | 102/0 |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh` | menú principal + submenús de Usuarios, Empleados, Clientes, Proveedores, Categorías, Marcas, Métodos de pago, Asistencia, Productos, Ventas, Garantías, Compras, Caja e Inventario | todos OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh` | módulo 63: registro automático, autor, fechas y cierre | 11/0 + 3 errores esperados |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST DB_USER=... DB_PASSWORD=... bash db/test-contrato-borrador.sh` | contrato borrador | 15/15 |
| `BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=... BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-asistencia-propia.sh` | fichar sin pedir ID | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh` | módulo 44 (rol viejo → VENDEDOR) | 11/11 |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-lockout.sh` | módulo 64: bloqueo por 5 fallos / 15 min, sin fila nueva al reintentar bloqueado, `FN_TIENE_PERMISO` con `ESTADO` e índice del log | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-login-servidor.sh` | módulo 65: verificación en el servidor, migración automática al primer login, segundo login, clave mala y hash inaccesible para `balbu_app` | OK |
| `BALBU_PASS=... DB_NAME=BALBU_TECH_TEST bash db/test-permisos-sp.sh` | módulo 66: sin token rechaza, token de VENDEDOR pasa lo suyo y se corta en lo ajeno, rechazo registrado | OK |
| `DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh` | login con entrada agotada (no gira ni ensucia `LOG_ACCESOS`) | OK |
| `docker compose cp db/grant-minimos.sql db:/tmp/ && docker compose cp db/aplicar-grants.sh db:/tmp/ && docker compose exec -T db bash /tmp/aplicar-grants.sh BALBU_TECH_TEST` | privilegios mínimos de `balbu_app` (solo `EXECUTE` + lecturas necesarias) | OK |

**Manual, por área:**

#### 2.1 Sesión y menú principal

- [ ] ADMIN entra y ve **19** opciones.
- [ ] GERENTE ve **16** y **no** aparecen Roles ni Usuarios.
- [ ] SUBGERENTE ve **16**, con Empleados (solo 3: buscar, listar, volver) y Asistencia (7, con Justificar).
- [ ] RRHH ve **6**; VENDEDOR **10**; ALMACEN **11**; CONTABILIDAD **5**.
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
- [ ] ADMIN/GERENTE/SUBGERENTE ven 5 opciones en Garantías; VENDEDOR 4 (sin "Finalizar reclamo"); CONTABILIDAD 2 (solo consultar).
- [ ] Un usuario con `GARANTIAS_CONSULTAR` y sin `GESTIONAR_VENTAS` llega a Garantías por el ítem "Ventas" del menú principal.

#### 2.9 Roles

- [ ] Crear un rol nuevo, asignarle `CLIENTES_VER` y entrar con un usuario de ese rol.
- [ ] Quitarle el permiso y verificar que el módulo desaparezca.
- [ ] Borrar el rol: los usuarios que lo tenían no pueden entrar (verificar el mensaje).
- [ ] Renombrar un rol: los permisos lo siguen (`ON UPDATE CASCADE`).

#### 2.10 Migración de roles (módulo 44)

- [ ] En TEST, el test automático ya lo cubre (11/11).
- [ ] En la viva, confirmar que no quedan roles `EMPLEADO` ni `CAJERO` y que sus usuarios pasaron a `VENDEDOR`:

```sql
SELECT NOMBRE_ROL FROM ROLES ORDER BY NOMBRE_ROL;
SELECT COUNT(*) FROM USUARIOS U LEFT JOIN ROLES R ON R.ID_ROL = U.ID_ROL WHERE R.ID_ROL IS NULL;
```

Ambas deben dar 7 roles y 0 usuarios huérfanos.

### 3. RRHH: pruebas visuales pendientes

- [ ] **13 Permisos:** solicitar → aprobar uno y rechazar otro → reintentar aprobar el ya aprobado ("solo pendientes") → ver la fila en `LOG_AUDITORIA_PERMISOS`.
- [ ] **12 Vacaciones:** solicitar → aprobar/rechazar → reintentar; una **aprobada** que cubra hoy bloquea la asistencia, una **pendiente o rechazada** no; cupo de 15 días + solapamiento (rechazar libera).
- [ ] **28 Accesos:** entrar/salir y ver las filas.
- [ ] Limpiar los datos de prueba (permisos, vacaciones, log) al terminar.

Cierre: build OK, `check-app-sps` 99/0, visual OK, sin datos de prueba.

### 4. Contratos: cargar los datos de la empresa

- [ ] `UPDATE` sobre `CONFIGURACION` con `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`. Hoy el contrato los imprime como `____________`.
- No existe tabla `EMPRESA` (se creó, el dueño la rechazó y se borró el mismo día). Todo va en `CONFIGURACION`.

---

## 🟠 P1 — Alta prioridad (funcionalidad a medias)

### 5. Contratos: campos legales RD + revisión legal

- [ ] Agregar a la plantilla: nacionalidad, edad, sexo, estado civil, **RNL** (Registro Nacional del Trabajador), lugar de prestación, provincia y municipio. Checklist y fuentes: `Flujos/Contrato de trabajo - requisitos legales RD.md`.
- [ ] Revisión legal del texto antes de usarlo con personal real (la plantilla ya lo dice al pie).

### 6. Garantías: estructurar el flujo (implementado en TEST, falta la viva)

Estado: **implementado en TEST el 30/10/2026** con los módulos `62`
(`PERMISOS_GARANTIAS`) y `63` (`GARANTIAS_FLUJO`); falta aplicarlo en la viva
con backup previo y orden explícita. El diseño de abajo se cumplió completo:
autor y fechas, validación por fecha, `VENCIDA`, consultas y registro
**automático** al confirmar la venta (la opción que quedaba abierta). Queda
sin hacer el módulo `34` (`ASIGNACIONES_RECLAMOS`, asignar técnicos).

**Permisos nuevos (4):**

| Permiso | Roles |
|---|---|
| `GARANTIAS_REGISTRAR` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `GARANTIAS_RECLAMAR` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `GARANTIAS_FINALIZAR` | ADMIN, GERENTE, SUBGERENTE |
| `GARANTIAS_CONSULTAR` | los 4 + CONTABILIDAD |

La diferencia clave: **el vendedor ya no cierra reclamos**. Atiende y registra, pero la decisión queda en Gerencia. VENDEDOR conserva `GARANTIAS_REGISTRAR` y `GARANTIAS_RECLAMAR`.

**Datos (módulo 63, idempotente):**

- `GARANTIAS`: `ID_EMPLEADO` (quién registró) y `FECHA_REGISTRO`.
- `RECLAMOS_GARANTIAS`: `ID_EMPLEADO`, `ID_EMPLEADO_CIERRE` y `FECHA_CIERRE`.
- `PRODUCTOS.DIAS_GARANTIA` (NULL/0 = sin garantía automática; los 49
  productos existentes quedan en NULL).

**SPs:**

- `SP_REGISTRAR_GARANTIA(detalle, dias, idEmpleado)`.
- `27_SP_REGISTRAR_RECLAMO_GARANTIA(garantia, descripcion, idEmpleado)`; validar `CURRENT_DATE BETWEEN FECHA_INICIO AND FECHA_FIN`, no solo `ESTADO`.
- `27_SP_FINALIZAR_RECLAMO_TOTAL(reclamo, idEmpleado)`; validar que el estado sea `PENDIENTE` o `APROBADO`.
- `SP_CONSULTAR_GARANTIAS`, `SP_CONSULTAR_RECLAMOS` y `SP_LINEAS_VENTA_CON_GARANTIA`.
- `SP_MARCAR_GARANTIAS_VENCIDAS`, invocado por `SP_CONSULTAR_GARANTIAS`
  antes de listar (no hay scheduler).

**UI:**

- Registrar: pedir **ID de venta** y listar sus detalles, en vez de pedir el ID de detalle.
- Reclamar y finalizar: listar lo que corresponde, no pedir IDs de memoria.

**Decisión tomada:** registro **automático al confirmar la venta** con los días
del producto (`TR_REGISTRAR_GARANTIA_VENTA`); el alta manual queda como
respaldo para ventas viejas.

**Cierre hecho en TEST:** build, `check-app-sps` 99/0, test de menús, `test-garantias.sh` 11/0 y `test-migracion-roles.sh` OK. Falta la prueba manual con VENDEDOR en la viva (no debe poder finalizar) y aplicar `63` → binario → `62` con backup previo.

### 7. RRHH: módulos que faltan

- [ ] **14 Bonos** — pantalla mínima (listar, pagar, anular). El 1% ya lo genera el trigger de 24.
- [ ] **15 Historial laboral** — `CARGO_ANTERIOR/NUEVO VARCHAR(30)` vs `EMPLEADOS.CARGO VARCHAR(50)`: ampliar a 50 y migrar.
- [ ] **30 Auditoría de permisos** — trigger activo; falta el lector y decidir si guarda el actor (hoy no lo tiene).
- [ ] **16 Liquidaciones** — **no tocar todavía**: la fórmula `SALARIO * AÑOS` es placeholder y "Despedir" vs "Liquidar" no cierra. Decidir el flujo de negocio primero.

### 8. Decisiones de producto (una vez cada una)

- [ ] **¿RRHH va o no?** (12, 13, 14, 16 y el historial de 15). Con lo ya hecho, va.
- [ ] **¿28 LOG_ACCESOS?** Ya está cableado y commiteado; solo falta la prueba visual (P0).
- [ ] **¿34 ASIGNAR RECLAMOS?** Cablear el flujo o borrarlo con su tabla.
- [ ] **¿35 DETALLE_REPARACIONES?** ¿Repuesto con stock o texto libre?
- [ ] **¿19.5 anular pago y 22 quitar/modificar línea?** ¿Pantalla o SQL?

### 9. Bugs y deuda con impacto

- [x] **Los permisos eran solo el menú (A6 de la auditoría)** — 03/11/2026: `balbu_app` tenía `SELECT/INSERT/UPDATE/DELETE` sobre todas las tablas, así que cualquier cliente con la clave del `.env` cambiaba roles, leía sueldos o borraba ventas sin pasar por el menú. Ahora solo tiene `EXECUTE`, lecturas puntuales y `UPDATE` a nivel de columna de `CONTRATOS.RUTA_DOCUMENTO`. Script: `db/grant-minimos.sql` + `db/aplicar-grants.sh` (corre con root). Rollback: `db/rollback-grants.sql`. Aplicado en TEST y en la viva. (05/11/2026) El script endurece **todas** las cuentas `balbu_app` del servidor, no solo `@'%'`: fuera del contenedor la app entra como `@'localhost'` y esa cuenta conservaba el DML amplio, o sea que el recorte no tenía efecto.
- [x] **Los hashes ya no son legibles por la app** — 03/11/2026, módulo `65- LOGIN_SERVIDOR.sql`: la verificación PBKDF2 se movió al servidor (`SP_LOGIN_PARAMETROS` + `SP_LOGIN_AUTENTICAR`). La app deriva y manda solo el derivado; el valor guardado es `SHA2(pepper || derivado)` y el pepper vive en `SECRETO_SISTEMA`, sin grants para `balbu_app`. Los usuarios migran solos en el primer login (`CONTRASENA` → NULL). `SELECT CONTRASENA` y `SELECT * FROM SECRETO_SISTEMA` como `balbu_app` fallan con `1143`/`1142`. Regresión: `db/test-login-servidor.sh`.
- [x] **El permiso se valida dentro de los SPs** — 03/11/2026, módulo `66- SESIONES_GUARDAS.sql`: el login emite un token (`SESIONES`) y la app lo deja en `@TOKEN_SESION`; `FN_USUARIO_SESION()` lo resuelve y `SP_EXIGIR_PERMISO('RUTINA')` corta si el rol no tiene el permiso de `PERMISO_POR_RUTINA`. Guardas inyectadas en 162 procedimientos con `db/injectar-guardas.py` (se reaplica solo al final de `db/import.sh`). (05/11/2026) La exigencia quedó prendida en las dos bases: **169 rutinas en `BALBU_TECH`** y **161 en `BALBU_TECH_TEST`**; `SP_CAMBIAR_CONTRASENA` queda sin mapear a propósito y las dos rutinas de la viva que el heurístico no reconocía (`11_SP_REGISTRAR_ENTRADA`, `SP_ELIMINAR_BONO`) ya tienen permiso. Regresión: `db/test-permisos-sp.sh`. Pendiente: validar el mapeo con uso real (una escritura por módulo mirando `LOG_PERMISO_SP`) y que el token de 12 h no se renueva por actividad.
- [x] **`SP_CAMBIAR_CONTRASENA` eliminado** — 05/11/2026: sin caller, sin mapeo y con el módulo `65` su verificación de clave vieja ya no podía funcionar (comparaba `CONTRASENA`, que queda en `NULL`). El cambio de clave real es `SP_CAMBIAR_CLAVE_USUARIO` (módulo `67`). Se quitó del módulo `10` y se dropeó en las dos bases.
- [x] **El cambio de clave estaba roto desde el módulo 65** — 05/11/2026, módulo `67- CAMBIO_CLAVE_SERVIDOR.sql`: `SP_CAMBIAR_CLAVE_USUARIO` escribía SHA256 en `CONTRASENA` y el login compara `CLAVE_SERVIDOR`, así que la clave nueva no entraba y la vieja seguía viva. Ahora recibe `pbkdf2$...`, escribe `SALT_LOGIN`/`ITER_LOGIN`/`CLAVE_SERVIDOR` con pepper, deja `CONTRASENA` en `NULL` y cierra las sesiones del usuario. La app manda el derivado también al dar de alta (`registrarUsuario`), que antes guardaba SHA256 y dejaba al usuario sin migración posible. Solo `USUARIOS_CLAVE` (ADMIN). Regresión: `db/test-cambio-clave.sh`. Aplicado en las dos bases.
- [ ] **`CONTRATOS.SALARIO` sigue legible** — el flujo de contratos pendientes lo lee directo. Si se quiere cerrar, hay que pasarlo a un SP.
- [ ] **`balbu_app` tiene grants sobre `BALBU_TECH_TEST` en el servidor de producción** — no hace falta ahí; quitarlo cuando el test deje de correr contra la misma instancia.

- [ ] **Venta multi-línea atómica** (P-4 de la auditoría).
- [ ] **P-3 validaciones**: 8 errores pintados en verde, advertencia de precio descartada y monto de la liquidación tomado del cliente.
- [x] **Costo fantasma al cancelar una compra** — cerrado el 29/10/2026: `FN_COSTO_COMPRA_VIGENTE` y `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` están en TEST y en la viva; 0 discrepancias reales en ambas.
- [x] **`EMPLEADOS.CEDULA` sin `UNIQUE`** — módulo 59 aplicado en TEST y en la viva el 29/10/2026 (backup 108); el duplicado se rechaza con `1062` en ambas.
- [x] **Rotar la clave del administrador** — 29/10/2026: `seed-admin.sh` ya no tiene clave por defecto (exige el argumento o `BALBU_PASS`, mínimo 8 caracteres); la viva se rotó y el login quedó verificado en PBKDF2. La de `root` ya se había rotado el 19/10.
- [ ] **`SP_ACTUALIZAR_VACACIONES`**: al cablear la edición, validar solapamiento y fecha futura (hoy no lo hace; no es alcanzable desde la UI).
- [ ] **Drift TEST ↔ viva en asistencia**: la viva tiene `11_SP_REGISTRAR_ENTRADA` y TEST no; además TEST tenía dos que a la viva le faltaban. Diffear definiciones antes de copiar, no asumir cuál es la buena.
- [ ] **Barrido del resto de los `while` con `leerDatoSeguro`** (el 18/10 solo se tocó `contrato.cpp`; los bucles con EOF pueden girar sin fin).

### 10. Hallazgos del mapa de módulos (21/10)

- [ ] **El BRUTO** (`TOTAL + ITBIS − ITBIS devuelto`) está copiado en 6 objetos por flujo (compras y ventas) más las 5 vistas del 43. Extraer una función compartida.
- [x] **Devolver mercancía no baja el subtotal** — cerrado en TEST y viva el 29/10/2026 (backup 109) con el módulo 60: `VW_VENTA_NETA` centraliza el neto y lo usan reportes, cierre de caja y topes de pago. El sexto lugar era `TR_VALIDAR_ACTUALIZACION_VENTA` (21), que comparaba el pago contra el subtotal y no contra el bruto neto.
- [x] **`VENCIDA` de GARANTIAS nunca se escribe** — cerrado el 30/10/2026 con el módulo 63: `SP_MARCAR_GARANTIAS_VENCIDAS` escribe el estado y el reclamo valida por fecha, así que una garantía vencida ya no se puede reclamar (`db/test-garantias.sh`, caso `VENCIDA_NO_RECLAMA`). Aplicado en TEST y en la viva.
- [x] **El 18 atribuye todo al empleado 1** y el 29 guarda `ID_USUARIO_ADMIN` en `NULL`: la auditoría no dice quién fue. — cerrado el 30/10/2026: el 56 arregló el actor de usuarios y el 61 el de clientes y productos, aplicado en TEST y en la viva (backup 112). En TEST `test-auditoria-producto.sh` 5/5 y en la viva la prueba con `ROLLBACK` dio 3/3 sin dejar datos.
- [ ] **`FN_TASA_ITBIS` no permite 0 %**: cae al 18 por diseño.

---

## 🟡 P2 — Media (reproducibilidad y limpieza)

- [ ] **P-5**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas, y sacar de los módulos el `UPDATE`, los `SELECT *` y los `CALL` de semilla.
- [ ] **`db/import.sh`** sigue con `--force` (ahora cuenta los `^ERROR` y avisa): hacerlo fallar de verdad.
- [ ] **Consolidar los `ALTER` de 25** dentro del `CREATE TABLE`; `DROP IF EXISTS` en los `CREATE` del módulo 11.
- [ ] **3 tests shell** pendientes y notas obsoletas del índice (`modulos/00- INDICE.md`).
- [ ] **`db/crear-usuarios.sh` no existe**: buscar el comando de provisión de la máquina del trabajo y compararlo con `balbu_app` / `balbu_admin`.
- [x] **`.atl/` entró en `d623ac0`** — resuelto: `de93561` lo sacó del control de versiones y `72bdedd` lo agregó a `.gitignore`.
- [ ] **Sidecar `.borrador`** guarda PII en texto plano junto al HTML (registrado y aceptado por el dueño).
- [ ] **`contratos/firmados/`**: sin listado, renombre ni limpieza; la administra RRHH a mano.
- [ ] **P-6**: decidir cablear o retirar lo construido y no cableado (garantías, reclamos, reparaciones, bonos manuales).

---

## 🔵 P3 — Baja / bloqueado

- [ ] **NCF / comprobante fiscal DGII** — **bloqueado** por el trámite en la oficina virtual (autorización + asignación de secuencia). La app no inventa números.
- [ ] **API para la web**: `GET /api/reporte` que llame al mismo SP + `fetch` en `index.html` (hoy la web es estática con simulados).
- [ ] **Lector biométrico** — sin equipo. El corte ya está: `marcarAsistenciaAuto()` toma `sesionActual.idEmpleado`; el modo huella reemplaza esa lectura sin tocar el resto. Falta decidir equipo (define opción A o B).
- [ ] **Permisos por cargo** (reclutamiento 12 vs contrataciones 13/14/15): hoy es convención del flujo, la app no separa roles. Fuera de alcance.
- [ ] Borrar la rama `backup-casa-20-10` (después del merge).

---

## ✅ Planes cerrados (por si buscás el detalle)

| Plan | Cuándo | Dónde quedó |
|---|---|---|
| Generar contrato (borrador) | 19/10 | `Realizado.md` — 3ª parte |
| Registrar contrato firmado (fases 1–8) | 19/10 | `Realizado.md` — 4ª parte |
| C-3: permisos administrables | 20/10 | commit del 20/10 |
| Set final de 7 roles | 22/10 | commit `22b2f8e` |
| Permisos finos (Tanda A y B) | 22–23/10 | `Realizado.md` — 23/10 |
| Asistencia v1 y v2 | 16–17/10 | `Realizado.md` |
| Flujo de compras / ventas | 08/10 | `Realizado.md` |
| Observaciones SQL | 09/10 | cerrado salvo "consolidar ALTER" (P2) |

---

## Comandos

```bash
# Build
./build.sh

# SPs que usa la app (debe dar 99/0)
DB_HOST=127.0.0.1 bash db/check-app-sps.sh

# Menús por rol (sobre TEST)
BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS='<clave-admin>' DB_NAME=BALBU_TECH_TEST bash db/test-menus-por-rol.sh

# Contrato: UI
DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=<clave-root> BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=admin BALBU_PASS=<clave-admin> bash db/test-contrato-borrador.sh

# Contratos: SQL
DB_PASSWORD=<clave-root> DB_NAME=BALBU_TECH_TEST bash db/test-contratos-subir.sh
```

---

## Referencias

- `Realizado.md` — lo hecho, con evidencia.
- `Auditoria/` — hallazgos con detalle (18/10 código + BD; 08/10 solo lo abierto).
- `Flujos/` — requisitos legales del contrato, flujo de producto y de BD.
- `Reglas/Reglas de trabajo.md` — cómo se trabaja.
