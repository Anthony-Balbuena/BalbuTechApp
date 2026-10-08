# Plan — Flujo de compras (BalbuTechApp)

> **Estado:** ✅ **COMPLETO** (08/10/2026) — blindaje total + P11C/P12C + extracción `19.1` + **Partes 1, 2, 3, 4, 5 y 7 cerradas** + **residuos #426/#464 cancelados** (nueva línea base: contexto compras §27). Parte 6 (C++) fuera de alcance: no se toca.
> **Fecha:** 07/10/2026
> **Alcance:** **solo SQL** (BD `BALBU_TECH` y sus módulos `.sql`); no se trabaja en C++ ni en `Pagina_Web` (igual que el flujo de ventas).
> **Siguiente acción:** ninguna — flujo de compras cerrado en SQL. *Residuos cancelados el 08/10/2026 con visto bueno (§27).*
> **Plan de ventas:** aparte, cerrado — ver `Plan - Flujo de Ventas.md` / `Pendientes - Flujo de ventas.md`.

---

## 1. Dónde vive el flujo de compras

| Archivo | Aporta al flujo |
|---|---|
| `19- COMPRAS.sql` | Tabla `COMPRAS`, `19_SP_INICIAR_COMPRA`, `SP_CANCELAR_COMPRA`, `SP_ASIGNAR_FACTURA_COMPRA`, candado `TR_VALIDAR_ACTUALIZACION_COMPRA`, bloqueos, `VISTA_REPORTE_COMPRAS`, `VISTA_GASTOS_PROVEEDOR` *(el historial de estados se mudó a `19.1`, 07/10/2026)* |
| `19.1- HISTORIAL_ESTADOS_COMPRA.sql` | Tabla `HISTORIAL_ESTADOS_COMPRA` + `IX_HIST_ESTADO_FECHA` + `TR_HISTORIAL_ESTADO_COMPRA` (nacimiento) + `TR_CAMBIO_ESTADO_COMPRA` (cambios) — **nuevo archivo** (07/10/2026), espejo de `21.5- HISTORIAL_ESTADOS_VENTA.sql`; sale de `19`, que quedó con 3 punteros |
| `22-DETALLE_COMPRA.sql` | Tabla `DETALLE_COMPRA`, `22_SP_AGREGAR_DETALLE_COMPRA`, `SP_QUITAR_DETALLE_COMPRA`, `SP_MODIFICAR_LINEA_COMPRA`, `TR_CALCULAR_TOTAL_COMPRA`, `TR_RECALCULAR_TOTAL_COMPRA`, `VISTA_DETALLE_COMPRA` |
| `19.5- PAGOS_COMPRA.sql` | Tabla `PAGOS_COMPRA`, pagos/nota de crédito, auto-recibir, 6 triggers, 2 vistas |
| `19.6- DEVOLUCION_COMPRA.sql` | Tabla `DEVOLUCION_COMPRA`, registro/procesar, triggers de reintegro y bloqueo |
| `20- MOVIMIENTOS_INVENTARIO.sql` | `TR_AUDITORIA_MOVIMIENTO_COMPRA` (bitácora de ENTRADA) |
| `32- HISTORIAL_MOVIMIENTOS_PRODUCTO.sql` | `TR_HISTORIAL_COMPRA` (stock antes/después) |

**Ruta feliz:** `19_SP_INICIAR_COMPRA` → `22_SP_AGREGAR_DETALLE_COMPRA` (stock ENTRADA por trigger) → `SP_REGISTRAR_PAGO_COMPRA` (al cubrir el total, trigger → `RECIBIDA`) → opcional `SP_ASIGNAR_FACTURA_COMPRA`.

**Estado de la BD (07/10/2026):** 5 tablas creadas; COMPRAS 2 (residuos, ver abajo), PAGOS_COMPRA 0, DEVOLUCION_COMPRA 0, DETALLE_COMPRA 2. Orden de triggers de `COMPRAS`/`DETALLE_COMPRA` **verificado OK** (stock → auditoría → total → historial).

## 2. Divisiones en partes (espejo del flujo de ventas)

| # | Parte | Alcance | Estado | Complejidad |
|---|---|---|---|---|
| **1** | Núcleo: abrir compra y agregar productos | `19_SP_INICIAR_COMPRA`, `22_SP_AGREGAR_DETALLE_COMPRA`, `TR_CALCULAR_TOTAL_COMPRA`, `TR_ACTUALIZAR_STOCK_COMPRA` | ✅ **Cerrada (07/10/2026)** | Baja |
| **2** | Cobro y recepción automática | `SP_REGISTRAR_PAGO_COMPRA`, `SP_ANULAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA`, `TR_AUTO_RECIBIR_COMPRA` | ✅ **Cerrada (07/10/2026)** | Media |
| **3** | Blindajes (candados y bandera) | `TR_VALIDAR_ACTUALIZACION_COMPRA`, `@COMPRAS_INTERNO`, orden de triggers, historial de estados | ✅ **Cerrada (07/10/2026)** | Media-alta |
| **4** | Cancelación y reversión de stock | `SP_CANCELAR_COMPRA` (ya trae `EXIT HANDLER`) | ✅ **Cerrada (07/10/2026)** | Media |
| **5** | Devoluciones a proveedor | `19.6- DEVOLUCION_COMPRA.sql` | ✅ **Cerrada (08/10/2026)** | Media-alta |
| **6** | Módulo C++ | — | ⛔ **Fuera de alcance (solo SQL)** | — |
| **7** | Reportes | `VISTA_REPORTE_COMPRAS`, `VISTA_GASTOS_PROVEEDOR`, integración con cierre de caja | ✅ **Cerrada (08/10/2026)** | Media |

**Orden:** 1 → 2 → 3 → 4 → 5 → 7. Cada parte con el formato del skill `Explicar_codigo.md` si se pide explicación; si no, ejecución directa con pruebas en `ROLLBACK`, residuos 0 y registro en contexto + Obsidian.

## 3. Hallazgos ya detectados (reconocimiento 07/10/2026)

1. ✅ **P11C — bandera sin handler (RESUELTO 07/10/2026):** `TR_CALCULAR_TOTAL_COMPRA` (`22:316`) y `TR_RECALCULAR_TOTAL_COMPRA` (`22:337`) no tenían `EXIT HANDLER` → si el `UPDATE COMPRAS.TOTAL` fallaba, `@COMPRAS_INTERNO` quedaba prendida en la sesión y un `UPDATE` a pelo se colaba (riesgo **demostrado** en ventas, P11). *Aplicado el patrón P11 (`SET @COMPRAS_INTERNO = 0` + `RESIGNAL`) en esos 2 triggers **y además en `TR_PROCESAR_DEVOLUCION_COMPRA` (19.6)**, que también prende la bandera en su paso 4. Recarga con `ACTION_ORDER` preservado (total 3 / historial 4).*
2. ✅ **P12C — rechazo sin motivo (RESUELTO 07/10/2026):** `SP_PROCESAR_DEVOLUCION_COMPRA` (`19.6:152`) cambiaba a `RECHAZADA` **sin registrar ningún motivo** (ni siquiera tenía parámetro). *Aplicado: param opcional `P_MOTIVO_RECHAZO VARCHAR(200) DEFAULT NULL` que concatena al `MOTIVO` original (`IFNULL` → `NO ESPECIFICADO`, `LEFT 200`); los llamados viejos de 2 argumentos siguen valiendo y `PROCESADA` no toca `MOTIVO`. Ver §5.*
3. ⚪ **Residuos en BD:** compras **#426** y **#464** (ABIERTA, 4 uds de producto 20 cada una, 04/10) con su bitácora. **No se tocan sin visto bueno** — decidir si se cancelan (con `SP_CANCELAR_COMPRA`) o se ignoran.
4. 📋 **Pendientes de documentación** (contexto compras, sección 4): bloques de descripción faltantes en ~27 archivos, ~45 índices y ~85 SPs sin bloque — tarea masiva aparte de este flujo.

## 4. Historial de sesiones previas (contextos)

El contexto `contexto tabla compras.txt` ya trae 18 secciones (03-04/10/2026): limpieza de redundancias, cierre de compras (paquetito B), pagos (C), estado DEVUELTA (D), vista gastos (E), factura+quitar línea (F), historial de estados (G), no-borrado (H), transacciones en SPs (I), nota de crédito reabre (J), candado de cabecera (fases 1+2). **Este plan reanuda desde ahí** con pruebas de extremo a extremo y los fixes P11C/P12C.

## 5. Sesión 07/10/2026 — Blindaje total + extracción 19.1 + Parte 1 (HECHOS ✅)

Antes de la Parte 1 se ejecutó el blindaje completo pedido ("todos los poderes") sobre `19`, `19.5`, `19.6` y `22` (9 objetos recargados):

- **P11C**: `EXIT HANDLER` que apaga `@COMPRAS_INTERNO` en `TR_CALCULAR_TOTAL_COMPRA`, `TR_RECALCULAR_TOTAL_COMPRA` y `TR_PROCESAR_DEVOLUCION_COMPRA`.
- **P12C**: `SP_PROCESAR_DEVOLUCION_COMPRA` gana `P_MOTIVO_RECHAZO VARCHAR(200) DEFAULT NULL`; al rechazar anota `original | RECHAZO: motivo` en `MOTIVO` (`LEFT 200`); firma vieja de 2 args válida.
- **Transacción propia + handler** (`V_PROPIA_TRANSACCION`, `ROLLBACK` + `RESIGNAL`, `COMMIT`, patrón fase I) en los 5 SPs que no la tenían: `SP_REGISTRAR_PAGO_COMPRA`, `SP_REGISTRAR_NOTA_CREDITO_COMPRA`, `SP_REGISTRAR_DEVOLUCION_COMPRA`, `SP_PROCESAR_DEVOLUCION_COMPRA`, `SP_ASIGNAR_FACTURA_COMPRA`.
- **Carreras cerradas con `FOR UPDATE`**: no exceder el total con pagos simultáneos, no devolver de más, doble proceso de devolución serializado.
- **`1062` traducido**: `SP_ASIGNAR_FACTURA_COMPRA` devuelve "ESA FACTURA YA EXISTE PARA ESTE PROVEEDOR." con `GET DIAGNOSTICS` (carrera real probada con 2 sesiones).
- **`ACTION_ORDER` preservado** al recargar (total 3 / historial 4 en INSERT; lección P11 de ventas).

**Pruebas 07/10/2026 — 100% verde, residuos 0:**
- Fase A (`test_blindaje_compras_A.sql`): ruta feliz núcleo → cobro → nota de crédito → 3 devoluciones en `START TRANSACTION…ROLLBACK` (P12C con/sin motivo, PROCESADA, doble proceso, bandera 0).
- Fase B (`test_blindaje_compras_B.sql`): los 5 SPs con txn propia fallan y `@@in_transaction` vuelve a 0 tras cada error.
- T5: carrera del `1062` a 2 sesiones → mensaje amigable.
- Línea base final intacta: COMPRAS 2, DETALLE 2, PAGOS 0, DEVOLUCIONES 0, stock prod 20 = 8, bitácora 2, historial 2, bandera 0.

**Registro**: contexto compras §19 + contexto devolucion compra §8; respaldos `show_pre_blindaje_*` y `pre_blindaje_*` en `/tmp/opencode/backup/`.

**Extracción del archivo `19.1` (HECHO ✅, 07/10/2026):**
- `HISTORIAL_ESTADOS_COMPRA` (tabla + `IX_HIST_ESTADO_FECHA` + `TR_HISTORIAL_ESTADO_COMPRA` + `TR_CAMBIO_ESTADO_COMPRA`) se mudó de `19- COMPRAS.sql` al nuevo `19.1- HISTORIAL_ESTADOS_COMPRA.sql` (espejo de `21.5- HISTORIAL_ESTADOS_VENTA.sql`); `19` quedó con 3 punteros `--` que apuntan al archivo nuevo. Solo archivos: la BD no cambió. Registro: contexto compras §20 + contexto historial estados compra §7.

**Parte 1 — Núcleo (CERRADA ✅, 07/10/2026):**
- Suite `/tmp/opencode/test_p1_nucleo_compras.sql` corrida dentro de `START TRANSACTION … ROLLBACK`: nacimiento de la compra (ABIERTA, TOTAL 0, fila en `HISTORIAL_ESTADOS_COMPRA`), cadena AFTER INSERT (stock 8→12, bitácora ENTRADA, historial 8→12, TOTAL), rama de `INVENTARIO` sin fila (producto 1 creado con STOCK_MINIMO 5 + advertencia de margen 13000 ≥ 12000), 7 errores amigables sin escritura parcial y puerta `TR_BLOQUEAR_COMPRA_CERRADA` (compra RECIBIDA → INSERT directo rechazado). **Todas las casillas en 1; residuos = línea base exacta.** Registro: contexto compras §21.

**Parte 2 — Cobro (CERRADA ✅, 07/10/2026):**
- Suite `/tmp/opencode/test_p2_cobro_compras.sql` en `START TRANSACTION … ROLLBACK`: pago parcial (sigue ABIERTA y sin fila nueva de historial), pago que salda → **RECIBIDA sola** por `TR_AUTO_RECIBIR_COMPRA` (mensaje "... COMPRA SALDADA (RECIBIDA)."), nota de crédito guardada en negativo que la **reabre sola** a ABIERTA, `SP_ANULAR_PAGO_COMPRA` (borra + recalcula + reabre), UPDATE y DELETE directos sobre `PAGOS_COMPRA` recalculando el estado, 10 errores amigables sin escritura, e historial de estados = 11 filas al final (2 base + nacimiento + 4 idas a RECIBIDA + 4 reaperturas). **Todas las casillas en 1; residuos = línea base exacta.** Registro: contexto compras §22. *Pendiente cruzado:* `TR_VALIDAR_BORRADO_PAGO_COMPRA` y pagos a compra CANCELADA se prueban en las Partes 4 y 5.

**Parte 3 — Blindajes (CERRADA ✅, 07/10/2026):**
- Suite `/tmp/opencode/test_p3_blindajes_compras.sql` en `START TRANSACTION … ROLLBACK`: candados de `COMPRAS` a pelo (TOTAL, ESTADO en sus 4 variantes, DELETE), candado de línea de `DETALLE` (UPDATE y DELETE con stock insuficiente), candados de `PAGOS` (INSERT que excede + 4 UPDATE prohibidos), capas internas del candado probando `@COMPRAS_INTERNO` prendida (pasa) y apagada (rechaza), reapertura RECIBIDA→ABIERTA anotada por `TR_CAMBIO_ESTADO_COMPRA`, `SP_QUITAR_DETALLE_COMPRA` recalculando TOTAL con bandera 1→0, y **ACTION_ORDER real en `information_schema`** (INSERT: stock→bitácora→total→historial; DELETE: stock→bitácora→total — 3 triggers, la bitácora de borrado vive en el archivo `20`). **Todas las casillas en 1; residuos = línea base exacta** (incluye `LOG_USUARIOS`=12 y `STOCK_MINIMO`=5). Registro: contexto compras §23. *No ejercitable aquí:* la rama "LA COMPRA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA" — va con las Partes 4 y 5.

**Parte 4 — Cancelación (CERRADA ✅, 07/10/2026):**
- Suite `/tmp/opencode/test_p4_cancelacion_compras.sql` en `START TRANSACTION … ROLLBACK`: errores tempranos de `SP_CANCELAR_COMPRA` (compra/empleado inexistentes, empleado que no es el dueño), rechazo con pagos registrados (tras anular ya pasa), rechazo por stock insuficiente **antes de tocar nada** (sin SALIDA parciales), cancelación feliz (CANCELADA, TOTAL intacto, detalle como evidencia, stock 12→8, bitácora SALIDA, historial 12→8, estados ABIERTA→CANCELADA, bandera 0), doble cancelación y cancelación de RECIBIDA rechazadas, y **9 blindajes sobre la CANCELADA** (UPDATE ESTADO — la rama OLD CANCELADA que faltaba de la Parte 3 —, TOTAL, pago, nota, INSERT de PAGOS a pelo, SP/INSERT/DELETE de detalle y DELETE de compra). **Todas las casillas en 1; residuos = línea base exacta.** Registro: contexto compras §24. *Nota:* `TR_VALIDAR_BORRADO_PAGO_COMPRA` no se alcanza desde una CANCELADA (una capa antes impide nacer el pago) — se ejercitará con una DEVUELTA en la Parte 5.

**Parte 5 — Devoluciones (CERRADA ✅, 08/10/2026):**
- Suite `/tmp/opencode/test_p5_devoluciones_compras.sql` en `START TRANSACTION … ROLLBACK`, verde a la primera: 4 errores al registrar (compra ABIERTA, detalle/empleado inexistentes, cantidad 0), PENDIENTE con SUBTOTAL = cant × precio, exceso sobre lo comprado rechazado, PROCESADA parcial (TOTAL 40→30, stock 12→11, bitácora SALIDA, historial DEVOLUCION 12→11, sigue RECIBIDA sin fila nueva de estados), PROCESADA inmutable salvo MOTIVO, resto procesado → TOTAL 0 y compra **DEVUELTA** (estados RECIBIDA→DEVUELTA), 2 rechazos P12C en compra B (con motivo y sin motivo → NO ESPECIFICADO, sin mover nada) y **9 blindajes sobre la DEVUELTA** — UPDATE ESTADO/TOTAL, pago, nota, **DELETE directo del pago (dispara `TR_VALIDAR_BORRADO_PAGO_COMPRA`: cierra el pendiente de la Parte 4)**, anular pago, otra devolución, agregar línea y DELETE de compra. **Todas las casillas en 1; residuos = línea base exacta.** Registro: contexto compras §25.

**Parte 7 — Reportes (CERRADA ✅, 08/10/2026):**
- Suite `/tmp/opencode/test_p7_reportes_compras.sql` en `START TRANSACTION … ROLLBACK`, verde a la primera (solo lectura, nada que tocar): `VISTA_REPORTE_COMPRAS` (proveedor, total, estado, primera fila = la más reciente), `VISTA_COMPRAS_PENDIENTES_PAGO` con SALDO vivo (40→25 tras pago parcial→ la saldada desaparece, la CANCELADA tampoco sale), `VISTA_RESUMEN_PAGOS_COMPRA` (método EFECTIVO), `VISTA_GASTOS_PROVEEDOR` (2/80.00 → 3/120.00 con la compra de la prueba; la CANCELADA no cuenta ni suma) y `SP_CIERRE_CAJA` corriendo con actividad de compras presente sin tocarla — es de ventas por diseño (solo lee `VENTAS`/`PAGOS`), no hay nada que integrarle; con NULL devuelve su error de fecha. **Todas las casillas en 1; residuos = línea base exacta** (las vistas vuelven solas a 2/80.00). Registro: contexto compras §26. No existe `SP_REPORTE_COMPRAS`: los reportes de compras son las 4 vistas.

**Residuos #426/#464 (CERRADO ✅, 08/10/2026, con visto bueno):**
- Decisión: cancelar las dos (no dejarlas). Respaldo de datos previo (`/tmp/opencode/backup/pre_residuos_datos.sql`, mysqldump de las 8 tablas) + ensayo en `START TRANSACTION … ROLLBACK` antes del cambio real.
- `CALL SP_CANCELAR_COMPRA(426, 22); CALL SP_CANCELAR_COMPRA(464, 22);` — ambas CANCELADA con TOTAL y detalle intactos; stock prod20 8→0; bitácora, historial e historial de estados +2; `LOG_USUARIOS` 12→14 (alertas de mínimo, por diseño).
- **Nueva línea base desde el 08/10/2026:** COMPRAS 2 (CANCELADA), DETALLE 2, PAGOS 0, DEVOLUCIONES 0, HISTORIAL_ESTADOS 4, stock 0, bitácora 4, historial 4, LOG 14, bandera 0, txn 0. Registro: contexto compras §27.
