# Plan — Flujo de ventas (BalbuTechApp)

> **Estado:** ✅ **FLUJO COMPLETO CERRADO (07/10/2026)** — Partes 1, 1b, 2, 3, 4, 5 y 7 hechas · Parte 6 **⛔ fuera de alcance**
> **Fecha:** 07/10/2026
> **Alcance:** **solo SQL** (BD `BALBU_TECH` y sus módulos `.sql`); no se trabaja en C++ ni en `Pagina_Web`.
> **Siguiente acción:** sin pasos del flujo; fixes **P11** (`EXIT HANDLER` apaga `@VENTAS_INTERNO`) y **P12** (`CONCAT` preserva rechazo con motivo `NULL`) **hechos el 07/10/2026**.

### A1 — resultado
- Archivo `modulos/20- MOVIMIENTOS_INVENTARIO.sql` modificado (único archivo del repo): versión vieja conservada comentada arriba de la nueva.
- BD `BALBU_TECH`: trigger recargado con versión condicional y **orden de triggers restaurado** (stock → total → historial, igual que una carga completa; recrearlo había movido el de stock al final y habría dejado mal `STOCK_ANTERIOR/STOCK_NUEVO`).
- Pruebas: ruta feliz OK (stock 8→6, 1 fila `SALIDA` de 2 unidades, historial correcto, TOTAL 200.00), `ROLLBACK` sin residuos, y `ERROR: STOCK INSUFICIENTE.` sin residuos.
- Respaldo previo: `/tmp/opencode/backup/pre_a1_20-MOVIMIENTOS.sql`.

---

## 1. Revisión del flujo de ventas (dónde vive)

El flujo está casi entero en la capa SQL (`modulos/`), cargada en orden numérico:

| Archivo | Aporta al flujo |
|---|---|
| `21- VENTAS.sql` | Tabla `VENTAS`, `21_SP_INICIAR_VENTA`, `SP_CANCELAR_VENTA`, `SP_ASIGNAR_FACTURA_VENTA`, candado `TR_VALIDAR_ACTUALIZACION_VENTA`, bloqueo de borrado, `VISTA_DETALLE_VENTA` |
| `21.5- HISTORIAL_ESTADOS_VENTA.sql` | Rastro de cada cambio de estado (2 triggers) |
| `23- DETALLE_VENTA.sql` | Tabla `DETALLES_VENTA`, `SP_AGREGAR_DETALLE_VENTA`, `TR_ACTUALIZAR_TOTAL_VENTA`, bloqueos de línea, `TR_VALIDAR_STOCK_DETALLE_VENTA` |
| `20- MOVIMIENTOS_INVENTARIO.sql` | `TR_AUDITORIA_MOVIMIENTO_VENTA` (descuenta stock + bitácora `SALIDA`) |
| `24- PAGOS.sql` | `24_SP_REGISTRAR_PAGO`, `SP_ANULAR_PAGO`, auto-cierre a `REALIZADA` + bono 1%, 6 triggers, 2 vistas |
| `25- DEVOLUCIONES.sql` | `SP_REGISTRAR_DEVOLUCION`, `25_SP_PROCESAR_DEVOLUCION`, reintegro de stock |
| `26- GARANTIAS.sql` / `27- RECLAMOS` | Cuelgan de `ID_DETALLE_VENTA` |

**Ruta feliz:** `21_SP_INICIAR_VENTA` → `SP_AGREGAR_DETALLE_VENTA` (descuenta stock por trigger) → `24_SP_REGISTRAR_PAGO` (al cubrir el total, trigger → `REALIZADA` + bono 1%) → opcional `SP_ASIGNAR_FACTURA_VENTA`.

### Huecos detectados
1. **No existe módulo C++**: no hay `ventas.cpp`/`ventas.h`, ningún `CALL` a los SP de venta, y `roles.cpp` no muestra menú "Ventas" (el permiso `GESTIONAR_VENTAS` está declarado y nadie lo usa).
2. ~~No hay SP de consulta/listado de ventas ni cierre de caja~~ ✅ **Resuelto (Parte 7)**: `37- REPORTES_VENTAS.sql` trae `VW_REPORTE_VENTAS` real + `SP_REPORTE_VENTAS` (rango de fechas) + `SP_CIERRE_CAJA` (resumen/estados/método).
3. `Pagina_Web/app.js` genera ventas con `Math.random()` (líneas 167-176): reporte simulado, no lee la BD. ⛔ **Fuera de alcance (solo SQL)**.
4. Inconsistencias: prefijos numéricos (`21_SP_...`, `24_SP_...`) vs. sin ellos; en `23- DETALLE_VENTA.sql` viven índices de otras tablas (`IX_CLIENTE_NOMBRE`, `IX_VENTAS_FECHA`).
5. **Carrera de stock:** la validación no candadea la fila (ver Parte 1).

---

## 2. Divisiones en partes (prioridad / complejidad)

| # | Parte | Alcance | Prioridad | Complejidad |
|---|---|---|---|---|
| **1** | Núcleo: abrir venta y agregar productos | `21_SP_INICIAR_VENTA` + `SP_AGREGAR_DETALLE_VENTA` + `TR_ACTUALIZAR_TOTAL_VENTA` + `TR_AUDITORIA_MOVIMIENTO_VENTA` | ✅ **Cerrada (explicada; ver sección 3)** | Baja |
| **1b** | **Stock atómico ("un solo golpe")** | Ver sección 4 | ✅ **Cerrada (07/10/2026)** | Baja (A1) / Media-alta (A3) |
| **2** | Cobro y cierre automático | `24_SP_REGISTRAR_PAGO`, `TR_VALIDAR_MONTO_PAGO`, `TR_AUTO_FINALIZAR_VENTA`, bono 1% | ✅ **Cerrada (07/10/2026)** | Media |
| **3** | Blindajes (candados y banderas) | `TR_VALIDAR_ACTUALIZACION_VENTA`, `@VENTAS_INTERNO`, orden de triggers, historial de estados | ✅ **Cerrada (07/10/2026)** | Media-alta |
| **4** | Cancelación y reversión de stock | `SP_CANCELAR_VENTA`, `SP_ANULAR_PAGO` | ✅ **Cerrada (07/10/2026)** | Media |
| **5** | Devoluciones y garantías | `25- DEVOLUCIONES.sql`, `26- GARANTIAS.sql` | ✅ **Cerrada (07/10/2026)** | Alta |
| **6** | Módulo C++ `ventas.cpp` (no existe) | 6a menú + permiso; 6b alta; 6c cobro; 6d cancelación/listados | ⛔ **Fuera de alcance (solo SQL)** | Alta |
| **7** | Reportes y cierre de caja | SP de listado, `VW_REPORTE_VENTAS` real, conectar `Pagina_Web` | ✅ **Cerrada SQL (07/10/2026)** · web ⛔ fuera de alcance | Media |

**Orden:** 1 → 2 → 3 → 4 → 5 → 6 → 7. Cada parte se explica con el formato del skill `Explicar_codigo.md` (Para qué sirve / Paso a paso / Ejemplo / Un detalle a vigilar / Tu turno) antes de tocar nada.

---

## 3. Parte 1 — Núcleo (ya explicada)

- `21_SP_INICIAR_VENTA`: valida empleado/cliente, crea la venta en `0.00` y `EN_PROCESO`, devuelve el ID.
- `SP_AGREGAR_DETALLE_VENTA`: valida dueño de la venta, stock y precio; inserta la línea.
- `TR_BLOQUEAR_VENTA_FINALIZADA` + `TR_VALIDAR_STOCK_DETALLE_VENTA` (BEFORE INSERT): candados de entrada.
- `TR_ACTUALIZAR_TOTAL_VENTA` + `TR_AUDITORIA_MOVIMIENTO_VENTA` (AFTER INSERT): suman total y descuentan stock.

**Hallazgo — carrera de stock:** dos cajeros leen el mismo stock con un `SELECT` sin candado y ambos pasan la validación. Quien frena el negativo es el `CHECK (STOCK_ACTUAL >= 0)` de `17- INVENTARIO.sql:12`, pero con un error técnico (salta dentro del trigger AFTER) y no el mensaje amigable.

---

## 4. Parte 1b — Stock atómico (decisión tomada)

**Decisión:** alternativa **A — "un solo golpe"** (`UPDATE ... WHERE STOCK_ACTUAL >= ?`), **implementada en el trigger, no en el SP**: así venta y stock se mueven juntos en una sola sentencia, sin transacciones explícitas ni `@@in_transaction`.

**Descartado (por ahora):** `FOR UPDATE` (tocaba solo el SP, pero exige `START TRANSACTION ... COMMIT` y retiene candados toda la llamada). Queda como referencia de un refactor futuro.

### A1 — EL CAMBIO (EJECUTADO el 06/10/2026)

**Archivo:** `modulos/20- MOVIMIENTOS_INVENTARIO.sql` → trigger `TR_AUDITORIA_MOVIMIENTO_VENTA` (línea 187).

**Formato pedido:** lo viejo **queda comentado arriba** para revisión (`-- VERSIÓN ANTERIOR`), lo nuevo en su propio bloque debajo. El `DROP TRIGGER IF EXISTS` de arriba sigue igual (evita duplicados: mismo nombre, solo uno activo).

**Versión vieja (se conserva comentada):**
```sql
    UPDATE INVENTARIO
    SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
```

**Versión nueva (la que se ejecuta):**
```sql
    -- Un solo golpe: comprobacion y resta en la misma sentencia.
    UPDATE INVENTARIO
       SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
     WHERE ID_PRODUCTO = NEW.ID_PRODUCTO
       AND STOCK_ACTUAL >= NEW.CANTIDAD;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
    END IF;
```
Se mantiene igual el `INSERT INTO MOVIMIENTOS_INVENTARIO ... 'SALIDA'` (bitácora) y la lectura del empleado.

**Detalles verificados:**
- "Producto sin fila en INVENTARIO" ya lo atrapa antes `TR_VALIDAR_STOCK_DETALLE_VENTA` (BEFORE INSERT) → `ROW_COUNT()=0` aquí siempre significa stock insuficiente.
- El trigger de stock (archivo 20) corre **antes** que `TR_ACTUALIZAR_TOTAL_VENTA` (23): si falla, ni siquiera se suma el total.
- Si la `SIGNAL` salta, MySQL/MariaDB revierte la sentencia → **no queda línea de venta sin descuento**.

**Verificación de A1:**
1. Respaldo previo en `/tmp/opencode/backup/`.
2. Recargar solo el archivo 20 con el loader (`/tmp/opencode/loader.py` o `load_modules.py`).
3. Confirmar en `information_schema.TRIGGERS` la definición nueva y sin duplicados.
4. Ruta feliz: stock baja **una** vez, aparece **una** fila `SALIDA`.
5. Grep de pruebas existentes por si asertan el mensaje de error viejo.

### Resultados de la Parte 1b — TODOS EJECUTADOS ✅

- **A2 ✅ (06/10):** notas en `23- DETALLE_VENTA.sql` — el SP y `TR_VALIDAR_STOCK_DETALLE_VENTA` pasan a ser red de mensajes amigables. Solo comentarios, cero SQL.
- **A3 ✅ (06/10):** carrera real con 2 sesiones (4 variantes): integridad protegida 100%, cero residuos; detectó el `ERROR 1020` en carrera encadenada. *Sub-pendiente abierto: recrear los suites viejos (`test_blindaje`, `smoke_fase1`, `test_fase_h`, `test_paquetito_j/k`).*
- **A4 ✅ (06/10):** secciones 14 y 15 en `Contextos.opencodetxt/contexto tabla ventas.txt`.
- **P8 ✅ (06/10):** `PAGOS.ID_EMPLEADO` + `FK_PAGO_EMPLEADO`; el SP valida al empleado (antes ponía `DESCONOCIDO`); `VISTA_RESUMEN_PAGOS` con `NOMBRE_EMPLEADO`.
- **P10 ✅ (06/10):** el `ERROR 1020` **sí es alcanzable en producción** (triggers de un `INSERT` comparten transacción); `EXIT HANDLER FOR 1020` en `SP_AGREGAR_DETALLE_VENTA` → `'ERROR: STOCK INSUFICIENTE, INTENTE DE NUEVO.'`.
- **P9 ✅ (07/10):** `MONTO_RECIBIDO` + `CHECK (MONTO_RECIBIDO >= MONTO)` + `VUELTO` en la vista (Opción A); SP con param `DEFAULT NULL`; `MONTO` no cambió → saldos/cancelaciones/devoluciones intactos.

---

## 5. Cómo seguir

1. ~~Parte 1b — A1, A2, A3, A4, P8, P10, P9~~ ✅ **cerrada** (07/10/2026), con respaldos y cero residuos.
2. **Parte 2 — Cobro y cierre automático:** explicación **preparada en la sección 6** → explicarla en el chat con el formato del skill `Explicar_codigo.md` y, si procede, documentar en `24- PAGOS.sql`.
3. Después, en orden: **Partes 3-7** de la tabla de la sección 2.
4. *Pendiente suelto de A3:* recrear los suites de pruebas viejos cuando se toque la Parte 3.

---

## 6. Parte 2 — Cobro y cierre automático ✅ EJECUTADA (07/10/2026)

> Documentación aplicada: +15 comentarios (0 SQL) en `24- PAGOS.sql` · contexto sección 16 · Pendientes marcado. Sin cambios de BD.

> Formato del skill `Explicar_codigo.md`. Archivo: `modulos/24- PAGOS.sql`.
> **Es documentación/explicación**: el código ya existe y ya está probado (P8 y P9 lo tocaron). No se prevén cambios de BD.
> Avance previo dentro de esta parte: **P8** (quién cobró) y **P9** (vuelto) ya hechos ✅.

### Para qué sirve
Cuando el cajero cobra, **tres piezas en cadena** trabajan dentro del mismo `INSERT` en `PAGOS`:
1. **`24_SP_REGISTRAR_PAGO`** — la puerta de entrada: valida venta, empleado (P8), monto recibido (P9) e inserta.
2. **`TR_VALIDAR_MONTO_PAGO`** (BEFORE INSERT) — **el freno**: solo pagos a ventas abiertas y nunca más del total.
3. **`TR_AUTO_FINALIZAR_VENTA`** (AFTER INSERT) — **el cierre**: si el acumulado cubre el total, la venta pasa sola a `REALIZADA` y nace el **bono del 1%** al empleado.

### Paso a paso (el viaje de un pago)
1. El cajero llama: `CALL 24_SP_REGISTRAR_PAGO(venta, método, monto, empleado[, recibido])`.
2. El SP valida: venta existe → empleado existe → `MONTO_RECIBIDO >= MONTO` → `INSERT INTO PAGOS`.
3. **`TR_VALIDAR_MONTO_PAGO`** lee `TOTAL`/`ESTADO` de la venta y `SUM(MONTO)` ya pagado:
   - estado ≠ `EN_PROCESO` → `SIGNAL 'ERROR: LA VENTA NO ESTA ABIERTA PARA RECIBIR PAGOS.'`
   - `pagado + nuevo > TOTAL` → `SIGNAL 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.'`
4. Si pasa ambas → la fila se guarda.
5. **`TR_AUTO_FINALIZAR_VENTA`** recalcula: si `V_ESTADO = 'EN_PROCESO'` **y** `pagado >= TOTAL`:
   - `UPDATE VENTAS SET ESTADO = 'REALIZADA'`
   - `INSERT INTO BONOS_EMPLEADOS` con `ROUND(TOTAL * 0.01, 2)`, descripción `'Comisión por venta #N'`, estado `PENDIENTE`.
6. La condición `V_ESTADO = 'EN_PROCESO'` hace de **guardia anti-doble-bono**: solo dispara la primera vez (un UPDATE de pago o un pago extra ya no vuelve a crear bono).
7. El cambio de estado lo rastrea `21.5- HISTORIAL_ESTADOS_VENTA.sql` (Parte 3).

### Ejemplo
Venta **#426**, `TOTAL = 100`, método EFECTIVO, empleado 7:
```text
CALL 24_SP_REGISTRAR_PAGO(426, 1, 60.00, 7);   → guardado; 60 < 100 → sigue EN_PROCESO (sin bono)
CALL 24_SP_REGISTRAR_PAGO(426, 1, 40.00, 7);   → guardado; 100 >= 100 → REALIZADA + bono 1.00 PENDIENTE
CALL 24_SP_REGISTRAR_PAGO(426, 1, 10.00, 7);   → BEFORE corta: 'ERROR: LA VENTA NO ESTA ABIERTA...'
```

### Un detalle a vigilar
- **El bono se calcula sobre `V_TOTAL_VENTA`, no sobre lo pagado** — correcto hoy porque `MONTO` nunca excede el total (eso garantiza el freno) y con P9 el vuelto vive en otra columna.
- Son **6 triggers** en `PAGOS` (INSERT/UPDATE/DELETE); al recrear cualquiera, revisar `information_schema.TRIGGERS.ACTION_ORDER` (lección de A1).
- Los pagos de una venta `CANCELADA/DEVUELTA` también están blindados por `TR_VALIDAR_BORRADO_PAGO` / `TR_VALIDAR_UPDATE_PAGO` (limite con Parte 4).

### Tu turno (1 pregunta)
Si la venta #427 vale **200** y ya tiene pagos de **100 + 50**, ¿qué pasa cuando el cajero intenta registrar **60** más? Di qué valores compara `TR_VALIDAR_MONTO_PAGO` y qué mensaje exacto sale.

### Al ejecutar esta parte
1. Explicar en el chat con el formato del skill (esto es lo preparado aquí).
2. Solo si se decide documentar: notas en `24- PAGOS.sql` (patrón A2: solo comentarios).
3. Marcar **Parte 2 ✅** en `Pendientes - Flujo de ventas.md` y anotar en `contexto tabla ventas.txt`.
