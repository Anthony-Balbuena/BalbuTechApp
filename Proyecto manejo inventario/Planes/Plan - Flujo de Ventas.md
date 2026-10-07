# Plan — Flujo de ventas (BalbuTechApp)

> **Estado:** ✅ **A1 ejecutado y verificado** (06/10/2026) — pendientes A2-A4
> **Fecha:** 06/10/2026
> **Siguiente acción:** decidir A2-A4 o pasar a la **Parte 2 (cobro y cierre automático)**.

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
2. No hay SP de consulta/listado de ventas ni cierre de caja (solo vistas); `VW_REPORTE_VENTAS` solo existe como ejemplo en `.vscode/prompts/descipcion_modulos.prompt.md`.
3. `Pagina_Web/app.js` genera ventas con `Math.random()` (líneas 167-176): reporte simulado, no lee la BD.
4. Inconsistencias: prefijos numéricos (`21_SP_...`, `24_SP_...`) vs. sin ellos; en `23- DETALLE_VENTA.sql` viven índices de otras tablas (`IX_CLIENTE_NOMBRE`, `IX_VENTAS_FECHA`).
5. **Carrera de stock:** la validación no candadea la fila (ver Parte 1).

---

## 2. Divisiones en partes (prioridad / complejidad)

| # | Parte | Alcance | Prioridad | Complejidad |
|---|---|---|---|---|
| **1** | Núcleo: abrir venta y agregar productos | `21_SP_INICIAR_VENTA` + `SP_AGREGAR_DETALLE_VENTA` + `TR_ACTUALIZAR_TOTAL_VENTA` + `TR_AUDITORIA_MOVIMIENTO_VENTA` | Alta | Baja |
| **1b** | **Stock atómico ("un solo golpe")** | Ver sección 4 | **Alta (en curso)** | Baja (A1) / Media-alta (A3) |
| **2** | Cobro y cierre automático | `24_SP_REGISTRAR_PAGO`, `TR_VALIDAR_MONTO_PAGO`, `TR_AUTO_FINALIZAR_VENTA`, bono 1% | Alta | Media |
| **3** | Blindajes (candados y banderas) | `TR_VALIDAR_ACTUALIZACION_VENTA`, `@VENTAS_INTERNO`, orden de triggers, historial de estados | Alta | Media-alta |
| **4** | Cancelación y reversión de stock | `SP_CANCELAR_VENTA`, `SP_ANULAR_PAGO` | Media | Media |
| **5** | Devoluciones y garantías | `25- DEVOLUCIONES.sql`, `26- GARANTIAS.sql` | Media | Alta |
| **6** | Módulo C++ `ventas.cpp` (no existe) | 6a menú + permiso; 6b alta; 6c cobro; 6d cancelación/listados | Alta | Alta |
| **7** | Reportes y cierre de caja | SP de listado, `VW_REPORTE_VENTAS` real, conectar `Pagina_Web` | Baja | Media |

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

### Pendientes de la Parte 1b (no aprobados aún)
- **A2:** documentar en `23- DETALLE_VENTA.sql` que el SP y `TR_VALIDAR_STOCK_DETALLE_VENTA` pasan a ser red de mensajes amigables.
- **A3:** pruebas de carrera con 2 sesiones + suites existentes (`test_blindaje`, `smoke_fase1`, `test_fase_h`, `test_paquetito_j/k`).
- **A4:** registrar la fase en `Contextos.opencodetxt/contexto tabla ventas.txt`.

---

## 5. Cómo seguir

1. ~~Ejecutar **A1**~~ ✅ hecho (06/10/2026) con verificación y respaldo.
2. Decidir **A2** (documentar en el archivo 23), **A3** (pruebas de carrera con 2 sesiones) y **A4** (nota en el contexto).
3. Revisar con `git diff "modulos/20- MOVIMIENTOS_INVENTARIO.sql"` (lo viejo queda comentado arriba de lo nuevo).
4. Pasar a la **Parte 2 — Cobro y cierre automático**.
