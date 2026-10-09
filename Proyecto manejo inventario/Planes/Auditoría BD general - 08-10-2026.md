# Auditoría general de la BD — 08/10/2026

> Solo lectura: no se tocó código ni datos. Verificado contra la BD viva `BALBU_TECH`.
> Seguimiento 08/10/2026 (tarde): corregidos y probados en vivo **1, 2, 3, 5, 7**. Pendientes: **4, 6, 8**.
> Seguimiento 08/10/2026 (noche): **8/8 corregidos** — se suman **4, 6, 8**, todos probados en vivo.

## 🔴 Errores reales (fallan SIEMPRE al ejecutarse)

1. **`SP_TOGGLE_ESTADO_MARCA`** — `2- MARCAS.sql:123`: alterna `'ACTIVO'/'INACTIVO'`, pero `MARCAS.ESTADO` es `ENUM('ACTIVA','INACTIVA')` → ERROR 1265. El toggle de marcas es imposible. ✅ **CORREGIDO 08/10**: toggle a `'ACTIVA'/'INACTIVA'`; probado en vivo (ACTIVA→INACTIVA→ACTIVA).
2. **`SP_TOGGLE_ESTADO_METODO_PAGO`** — `4-METODOS_PAGO.sql:142`: hace `UPDATE METODOS_PAGO SET ESTADO=…`, pero la tabla **no tiene columna ESTADO** → Unknown column. ✅ **CORREGIDO 08/10**: columna `ESTADO ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO'` agregada (CREATE + migración `ADD COLUMN IF NOT EXISTS`); toggle probado en vivo ida y vuelta.
3. **`SP_ASIGNAR_TECNICO_RECLAMO`** — `34- ASIGNAR RECLAMOS.sql:96`: pone `ESTADO='EN_PROCESO'`, pero `RECLAMOS_GARANTIAS.ESTADO` es `('PENDIENTE','APROBADO','RECHAZADO','CERRADO')` → ERROR 1265. Además `TR_FINALIZAR_RECLAMO_APROBADO` nunca ve ese estado. ✅ **CORREGIDO 08/10**: eliminado el `UPDATE` inválido (el reclamo queda `PENDIENTE`; el avance vive en `ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION`); probado e2e con cadena completa (asignación en `EN_PROCESO`).
4. **`SP_ASIGNAR_PERMISO_A_ROL` / `FN_TIENE_PERMISO`** — `36- PERMISOS_ROLES.sql:110,169,181`: leen tabla `USUARIOS_SISTEMA`, que **no existe** (lo real es `USUARIOS` + `ROLES`).
5. **`SP_REGISTRAR_ASISTENCIA`** — `11-ASISTENCIA_EMPLEADOS.sql:100`: inserta en tabla `ASISTENCIA`, que **no existe** (lo real es `ASISTENCIA_EMPLEADOS` con otras columnas). ✅ **CORREGIDO 08/10**: `ENTRADA` crea la fila (`PRESENTE`), `SALIDA` pone `HORA_SALIDA`; probado en vivo (fila + hora).
6. **`27_SP_FINALIZAR_RECLAMO_TOTAL`** — `27- RECLAMOS_GARANTIAS.sql:117`: inserta en `LOG_AUDITORIA`, que **no existe** (existen `AUDITORIA_SISTEMA`, `LOG_USUARIOS`, `LOG_AUDITORIA_PERMISOS`) → siempre ROLLBACK.
7. **SP de `28-LOG_ACCESOS.sql:45`** — usa `U.NOMBRE_USUARIO`, pero la columna real es `USUARIOS.USUARIO`. ✅ **CORREGIDO 08/10**: `U.USUARIO`; `CALL SP_REPORTAR_ACCESOS()` corre limpio.
8. **`sp_obtener_categorias_marcas`** — `Mejoras_extras.sql:4`: lee `categorias`/`marcas` minúsculas con columnas que no existen (real: `CATEGORIAS(ID_CATEGORIA,NOMBRE)`, `MARCAS(ID_MARCA,NOMBRE)`). ✅ **CORREGIDO 08/10**: archivo eliminado (`git rm`) — SP sin llamadas en todo el repo, excluido del import y roto; su función la cubren `SP_BUSCAR_CATEGORIA`/`SP_BUSCAR_MARCA`. Nota: `mostrarCategoriasYMarcas()` (`database.cpp:48`, C++) también está muerta y apunta a tablas singulares inexistentes — pendiente fuera de alcance SQL.

## 🟡 Gemelos en BD (mismo propósito, dos nombres)

- **IDÉNTICOS** (candidatos a borrar, previa revisión de uso en C++): `SP_HISTORIAL_PERMISOS_EMPLEADO` = `13_SP_HISTORIAL_PERMISOS_EMPLEADO`; `27_SP_FINALIZAR_RECLAMO_TOTAL` = `35_SP_FINALIZAR_RECLAMO_TOTAL`.
- **DIFERENTES** (comparar cuerpo antes de tocar): `SP_BUSCAR_CATEGORIAS` vs `1_SP_BUSCAR_CATEGORIAS`; `SP_TOGGLE_ESTADO_CATEGORIA` vs `1_SP_TOGGLE_ESTADO_CATEGORIA`; `SP_TOGGLE_ESTADO_PROVEEDOR` vs `5_SP_TOGGLE_ESTADO_PROVEEDOR`.
- `VERANTESDEINSERT`: sin hits en repo → probable muerto (verificar en BD).

## 🟢 Mejoras (no rompen, pero conviene)

- **Sin transacción/handler:** casi todos los SPs fuera de compras/ventas escriben a pelo. Críticos multi-statement: `SP_ASIGNAR_TECNICO_RECLAMO`, `SP_FINALIZAR_RECLAMO`, `SP_REGISTRAR_LIQUIDACION`, `20_SP_REGISTRAR_AJUSTE_INVENTARIO`, `SP_REGISTRAR_GARANTIA`, `26_SP_RECHAZAR_DEVOLUCION`, `SP_REGISTRAR_AVANCE_REPARACION`.
- **Sin FK:** `PRODUCTOS.ID_PROVEEDOR` (huérfanos posibles), `LOG_USUARIOS(ID_USUARIO,ID_USUARIO_ADMIN)`, `ROL_PERMISO(ROL_NOMBRE)` vs `ROLES` (CHECK en vez de FK).
- **Sin CHECK/ENUM:** `HISTORIAL_ESTADOS_COMPRA/VENTA.ESTADO_* VARCHAR(20)` admite estados inválidos; `DETALLE_REPARACIONES.ESTADO_AVANCE` sin ENUM.
- **Contraseñas:** `USUARIOS.CONTRASENA` migrada a 512 pero params de SPs en `VARCHAR(255)` → trunca el hash.
- **Triggers sin orden explícito** (orden = creación, frágil al recargar): `DETALLES_VENTA AFTER INSERT ×3`, `DEVOLUCIONES AFTER UPDATE ×3`, `EMPLEADOS AFTER UPDATE ×2`.
- **Tablas sin BEFORE:** `RECLAMOS_GARANTIAS` (estados y DELETE libres), `DEVOLUCIONES` sin BEFORE INSERT, `VACACIONES/BONOS/LIQUIDACIONES` sin control en UPDATE.
- `PROVEEDORES.TELEFONO/EMAIL UNIQUE` anulables → varios NULL burlan la unicidad.

## ✅ Sano (verificado en vivo)

- Cero huérfanos, cero duplicados (marcas/productos/proveedores), cero precios ≤ 0, cero stock negativo.
- Ningún trigger fantasma en BD (los `DROP` de limpieza sí corrieron).
- Flujos de compras y ventas: blindados y probados.
- 5 productos sin fila en `INVENTARIO` → por diseño (se crea al comprar).


Anthony
## ✅ Revisión 09/10/2026 — los 8 corregidos están bien

Verificado objeto por objeto en los archivos traídos del trabajo:

| # | Arreglo | Veredicto |
|---|---|---|
| 1 | Toggle MARCAS → ACTIVA/INACTIVA | ✅ Bien, valida existencia |
| 2 | Columna ESTADO en MÉTODOS_PAGO + toggle | ✅ Bien (`ADD COLUMN IF NOT EXISTS` válido) |
| 3 | Técnico de reclamo sin `EN_PROCESO` | ✅ Bien (el avance vive en la asignación) |
| 4 | Permiso-a-rol + `FN_TIENE_PERMISO` vía `USUARIOS→ROLES` | ✅ Bien (`ID_ROL` existe con FK; la PK compuesta sostiene el `ON DUPLICATE KEY`) |
| 5 | Asistencia a tabla/columnas reales | ✅ Bien (respeta el UNIQUE por día) |
| 6 | Reclamo → `AUDITORIA_SISTEMA` | ✅ Bien (columnas y `ENUM UPDATE` válidos) |
| 7 | Accesos con `U.USUARIO` | ✅ Bien (`LEFT JOIN`, no pierde filas) |
| 8 | Borrado `Mejoras_extras.sql` | ✅ Bien (el SP roto ya no está en archivos) |

Barrido nuevo completo: **cero referencias rotas** a tablas/vistas en ningún `.sql`, **ENUMs consistentes** (`EN_PROCESO` solo en ventas/asignaciones, ningún `ACTIVO` en MARCAS), tablas archivos↔BD 40/40.

## 📝 Mejoras a realizar (pendientes)

1. `SP_ASIGNAR_TECNICO_RECLAMO`: validar que el empleado exista + impedir doble asignación EN_PROCESO del mismo reclamo.
2. Asistencia: SALIDA sin ENTRADA devuelve "ÉXITO" falso → mensaje amable; doble ENTRADA da error técnico de duplicado → capturar el 1062 con mensaje amable.
3. `sp_obtener_categorias_marcas` **sigue vivo en la BD local** (el archivo se borró pero la rutina quedó cargada) → `DROP` pendiente.
4. `ROL_PERMISO.ROL_NOMBRE` sin FK a `ROLES`; `USUARIOS.CONTRASENA` en VARCHAR(255) vs hash PBKDF2 de 512.

## 🔧 Ejecución 09/10/2026 — mejoras realizadas (archivos + BD, con pruebas)

- **#1 `SP_ASIGNAR_TECNICO_RECLAMO`** (`34`): valida empleado + impide doble asignación en curso. Cargado y probado (4 casos + residuos 0).
- **#2 Asistencia** (`11`): `SP_REGISTRAR_ASISTENCIA` rechaza doble ENTRADA y SALIDA sin ENTRADA; `11_SP_REGISTRAR_SALIDA` igual. Cargados y probados (5 casos + residuos 0).
- **#3 `sp_obtener_categorias_marcas`**: `DROP` ejecutado en BD (el archivo ya se había borrado).
- **#4a Contraseñas**: `USUARIOS.CONTRASENA` → 512 en CREATE + params de `SP_INSERTAR_USUARIO` y `SP_CAMBIAR_CONTRASENA`. Probado con hash de 512 (largo 512, cambio ok, residuos 1).
- **Arreglos del trabajo cargados a la BD local**: `SP_TOGGLE_ESTADO_MARCA`, `SP_TOGGLE_ESTADO_METODO_PAGO` (+ columna `ESTADO` con backfill ACTIVO), `SP_ASIGNAR_PERMISO_A_ROL`, `FN_TIENE_PERMISO`, `27_SP_FINALIZAR_RECLAMO_TOTAL`, `SP_REPORTAR_ACCESOS`. Suite `/tmp/opencode/t_workfixes.sql`: toggles ida/vuelta, errores amables, finalizar con auditoría — todo verde, residuos exactos.
- **Extra**: `27_SP_FINALIZAR_RECLAMO_TOTAL` traía `START/COMMIT/ROLLBACK` incondicionales + cerraba reclamos inexistentes con auditoría fantasma → blindado al patrón fase I + guard `RECLAMO NO ENCONTRADO`.
- ⚠️ **#4b PENDIENTE DE DECISIÓN**: `ROL_PERMISO` usa `ADMIN/RRHH/EMPLEADO` pero `ROLES` tiene `ROLE_ADMIN/ROLE_GERENTE/ROLE_INV_AUDITOR/ROLE_VENDEDOR`. Con estos datos `FN_TIENE_PERMISO` devuelve 0 siempre y `SP_ASIGNAR_PERMISO_A_ROL` no puede tener éxito nunca (verificado en vivo). Hay que alinear un lado.

## ✅ Cierre 09/10/2026 — #4b alineación de roles con el C++

- El C++ manda: compara `ADMIN`/`RRHH`/`EMPLEADO` hardcodeados (listas que calcan `ROL_PERMISO`). Se renombró `ROLES`: `ROLE_ADMIN`→`ADMIN`, `ROLE_GERENTE`→`RRHH`, `ROLE_VENDEDOR`→`EMPLEADO` (mapeo aprobado). `ROLE_INV_AUDITOR` queda para decidir después (nadie lo usa).
- `ROL_PERMISO.ROL_NOMBRE` → VARCHAR(50) + FK `FK_ROL_PERMISO_ROL` → `ROLES(NOMBRE_ROL)` (archivo y BD).
- Verificado: `FN_TIENE_PERMISO('abalbuena','GESTIONAR_ROLES')` pasó de 0 a **1**; SP asigna duplicados sin duplicar y altas reales (con limpieza); CHECK + FK rechazan nombres fantasmas; `abalbuena` ahora cae en la rama ADMIN del menú C++.
- Estado final mejoras: #1 ✅ #2 ✅ #3 ✅ #4a ✅ #4b ✅. Pendiente futuro: destino de `ROLE_INV_AUDITOR`.

## 📋 Plan de mejoras (09/10/2026) — pendiente de ejecución

### Plan 1 — Rápido y seguro
- [x] 1.1 Borrar 6 rutinas muertas ✅ **Hecho 09/10/2026** (0 llamadas en BD/C++/web; respaldo `pre_mejoras_rutinas.sql`) en BD (`1_SP_BUSCAR_CATEGORIAS`, `1_SP_TOGGLE_ESTADO_CATEGORIA`, `13_SP_HISTORIAL_PERMISOS_EMPLEADO`, `5_SP_TOGGLE_ESTADO_PROVEEDOR`, `35_SP_FINALIZAR_RECLAMO_TOTAL`, `VERANTESDEINSERT`). Nadie las llama (C++/web); hay respaldo.
- ⏭️ ~~1.2 Destino de `ROLE_INV_AUDITOR`~~ → **DIFERIDO a la etapa C++ por orden del usuario (09/10/2026)** — no es tarea de BD.
- [x] 1.3 FK `PRODUCTOS.ID_PROVEEDOR` ✅ **Hecho 09/10/2026** (la BD ya lo tenía y muerde —1452 verificado—; se agregó al `CREATE TABLE` del archivo para BD nuevas) (0 huérfanos verificados).

### Plan 2 — Blindaje mediano
- [x] 2.1 Patrón fase I ✅ **Hecho 09/10/2026** (`SP_FINALIZAR_RECLAMO` + guards, `SP_REGISTRAR_LIQUIDACION`, `20_SP_REGISTRAR_AJUSTE`; los otros 3 son de 1 escritura = atómicos, sin cambios; suite `t_p21.sql` verde) multi-statement (`SP_FINALIZAR_RECLAMO`, `SP_REGISTRAR_LIQUIDACION`, `20_SP_REGISTRAR_AJUSTE_INVENTARIO`, `SP_REGISTRAR_GARANTIA`, `26_SP_RECHAZAR_DEVOLUCION`, `SP_REGISTRAR_AVANCE_REPARACION`).
- [x] 2.2 BEFORE faltantes ✅ **Hecho 09/10/2026** (5 triggers nuevos: `TR_VALIDAR_CAMBIO_RECLAMO`, `TR_VALIDAR_CUOTA_DEVOLUCION`, `TR_VALIDAR_LIMITE_VACACIONES_UPDATE`, `TR_BLOQUEAR_CAMBIO_BONO`, `TR_VALIDAR_LIQUIDACION` + `TR_BLOQUEAR_CAMBIO_LIQUIDACION`; suites `t_p22*.sql` verdes, residuos 0) (`RECLAMOS_GARANTIAS`, `DEVOLUCIONES` al INSERT, `VACACIONES`/`BONOS`/`LIQUIDACIONES` al UPDATE).
- [x] 2.3 `TR_BLOQUEAR_ASISTENCIA_INAPROPIADA` ✅ **Hecho 09/10/2026** (`NEW.FECHA`; probado: fecha pasada en vacaciones bloquea, hoy pasa; se revirtió un `replaceAll` que tocó el SP — ahí `CURDATE()` está bien): usar `NEW.FECHA` en vez de `CURDATE()`.

### Plan 3 — Diseño (después)
- [x] 3.1 `ACTION_ORDER` explícito ✅ **Hecho 09/10/2026** (FOLLOWS en 4 triggers: total e historial de venta, marcar e historial de devolución; recreados sueltos vuelven a su puesto 2/3 solos; flujo de venta verificado 10→6; suites `t_p31.sql`) en cadenas de ventas/devoluciones.
- [x] 3.2 Candados chicos ✅ **Hecho 09/10/2026** (CHECKs en los 2 historiales de estados + ENUM en `DETALLE_REPARACIONES.ESTADO_AVANCE` + validación amable en su SP; suite `t_p32.sql`; NOT NULL de proveedores **descartado** a propósito) de proveedores + `CHECK` en historiales de estados.

## ✅ Plan 1 parcial 09/10/2026 (sin 1.2, a pedido)

- 1.1 y 1.3 cerrados y probados. 1.2 (`ROLE_INV_AUDITOR`) queda para después.

## ✅ Plan 2 cerrado 09/10/2026

Todo probado en `ROLLBACK` con residuos 0. Lección: el `replaceAll` muerde — un reemplazo global tocó 2 líneas del SP que estaban bien y se revirtió verificando línea por línea.

## ✅ Plan 3 cerrado 09/10/2026 — auditoría completa

Todos los planes (1, 2, 3) y las mejoras 1-4 ejecutados y probados. Residuos 0 en cada suite. Pendientes fuera de BD: `ROLE_INV_AUDITOR`, push de git.

## 📝 Flujo registrar producto — detalles a corregir (09/10/2026)

→ Mudado a su archivo propio: `Flujos/Flujo - Registrar producto.md` (flujo + P1–P4 ejecutados ✅).

## 📋 Plan SQL (09/10/2026) — solo SQL, sin C++ ni web

- [ ] **P9 — vuelto**: lógica en `24_SP_REGISTRAR_PAGO` (aceptar monto > total con `P_MONTO_RECIBIDO`, calcular vuelto y definir dónde se registra).
- [ ] **E2E SQL Partes 2/4/5**: suites reproducibles estilo `test_blindaje_p3.sql` para cobro/cierre, cancelación y devoluciones/garantías.
- [ ] **`ACTION_ORDER`**: verificar `DEVOLUCIONES` (×3 AFTER UPDATE) y `EMPLEADOS` (×2); poner `FOLLOWS` donde falte, como en `DETALLES_VENTA`.
- [ ] **Params `VARCHAR(255)` vs hash PBKDF2**: `USUARIOS.CONTRASENA` es 512 pero los params de SPs que la tocan están en 255 → trunca el hash. Revisar y unificar.
- [ ] **Gemelos**: decidir duplicados (`SP_HISTORIAL_PERMISOS_EMPLEADO`, `27_` vs `35_SP_FINALIZAR_RECLAMO_TOTAL`, etc.).
- [ ] **Endurecimiento** (por tandas): transacciones/handlers en SPs multi-statement, CHECKs/ENUMs (`HISTORIAL_ESTADOS_*`, `ESTADO_AVANCE`), BEFOREs faltantes, `PROVEEDORES` UNIQUE anulables.
- [ ] **Seeds de catálogo**: `CATEGORIAS` importa vacía (upstream quitó los seeds). Restaurar en `.sql` o extender `seed-admin.sh`.
