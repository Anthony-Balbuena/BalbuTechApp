# Realizado

> Consolidado el 14/10/2026: todo lo terminado, movido de las notas. Lo pendiente sigue en su nota original.

## BD — base de datos

### Esquema y costos
- `P_COMPRA` en PRODUCTOS (12/10): nace en 0 = pendiente de factura. Estimados al 80% no son reales.
- Renombre `COSTO` → `P_COMPRA` (9, triggers del 22, lecturas). El parámetro del SP quedó `P_COSTO` (posicional, no afecta). Datos intactos.
- `SP_INSERTAR_PRODUCTO` de 9 parámetros, con `P_COMPRA` antes del precio (13-14/10). Valida `>= 0`. Recargado en TEST y TECH.
- `SP_ACTUALIZAR_PRODUCTOS` acepta `P_COSTO` (NULL conserva, negativo rechaza).
- `MONTO_ITBIS` + `MONTO_GANANCIA` en DETALLES_VENTA; `MONTO_ITBIS_REEMBOLSADO` (+ ganancia reembolsada) en DEVOLUCIONES.
- `SP_AGREGAR_DETALLE_VENTA`: ITBIS con tasa vigente + ganancia snapshot; fix `COSTO` → `P_COMPRA`; costo 0/NULL = ganancia desconocida (no se inventa).
- Las compras mandan `P_COMPRA` (trigger del 22 + recompute al borrar).

### Vistas y lecturas
- `VISTA_VENTA_CON_IVA` (11/10): SUBTOTAL + ITBIS de líneas − ITBIS devuelto = TOTAL final. El TOTAL no se toca.
- `VW_GANANCIAS` + mensual (38): por línea y por mes, sin IVA, neto de devoluciones. Solo reportes internos, nunca en factura.
- `39- LECTURAS` (10 SP de solo lectura) + `FN_TASA_ITBIS()` (33).
- `SP_CONSULTAR_PRODUCTOS_FILTRADO`: STOCK por LEFT JOIN + filtros por ID + PROVEEDOR. Inventario trae `P_COMPRA`.
- Reportes mudados del 37 al 24: vista + 2 SPs, SALDO a BRUTO. Import fresco: 39 archivos, 0 avisos.

### Flujos y blindaje
- Ventas cerrado 07/10 y Compras cerrado 08/10 (Partes 1, 1b, 2, 3, 4, 5 y 7). Fixes P11/P12. Stock atómico. Suites verdes, residuos 0.
- Pago a BRUTO (11/10): 6 comparadores + vista de pendientes. Suites `t_pago_bruto` verdes.
- Cierre de caja, `SP_REPORTE_VENTAS` por rango, ver pagos de una venta.
- Módulo Compras 1-4 (13/10): triggers de pago-compra a BRUTO (7 puntos + vista). Suites verdes.

### Sincronización sede trabajo (14/10)
- Columnas y vistas aplicadas a la BD viva; import 41 archivos, 0 avisos; 10/10 SPs de compras; `FN_TASA_ITBIS() = 18.00`.
- Reporte por período ventas + compras + ganancias (mismo flujo, datos reales, sin `rand()`).
- `5. Pagar compra` (espejo de ventas; en compras se paga, no se cobra): `SP_COMPRAS_PENDIENTES()` en el 19.5 + pantalla con `Monto pagado`; probado con `xxx` sin pagar.
- Abonos (14/10): `pagarCompra` manda lo tipeado (valida >0 y <= pendiente, muestra saldo restante). Probado en vivo con compra TEST #3: abono 3.00 (ABIERTA, saldo 5.00), pago anulado, compra cancelada, producto TEST a INACTIVO. La BD prohíbe borrar filas (residuo: #3 CANCELADA, excluida de reportes).
- Fix `DEFAULT` en params de SP (MariaDB no lo soporta): `1- CATEGORIAS` (5), `24- PAGOS` (1), `28- LOG` (1). La app ya manda aridad completa. `import.sh` ahora cuenta errores reales de sentencia en vez de mentir con "0 avisos".

### Sincronización sede trabajo (15/10)
- Pull de casa aplicado a la viva del trabajo: módulos `20` (kardex), `21.5` (historial), `40` (suplidores) + formato de `2`; tabla `PRODUCTO_PROVEEDOR` + trigger + 7 SP nuevos → `check-app-sps`: 0 faltantes.
- Binario recompilado; humo en vivo: `3. Movimientos` (14 movimientos reales), `13. Historial de venta` (venta 3), submenú `12. Garantias`, `6. Precios por suplidor` (vacío correcto: sin compras RECIBIDA acá todavía).
- Nota: los IDs de marcas difieren entre sedes (acá 1=ASUS; casa 1=LENOVO) — el catálogo de casa NO se copia tal cual: si se carga acá, va con mapeo por nombre, no por ID.
- Catálogo cargado con tope de 10 por tabla (pedido 15/10): +10 categorías (PLACA MADRE…HOGAR INTELIGENTE), +10 marcas (LENOVO, DELL, APPLE, AMD, NVIDIA, INTEL, GIGABYTE, ASROCK, SAMSUNG, LG), +10 proveedores placeholder (`SUPLIDOR 01`–`10`, renombrables con los reales) y +10 productos (LAP-002…LAP-007, RYZ-004, CPU-003, RTX-004, RTX-001). Mapeo por nombre, verificado con `SP_CONSULTAR_PRODUCTOS_FILTRADO`. Precios estimados de referencia; entran con stock cuando se compren por el módulo.

## C++ — app

- Base 10-11/10: submenús 9/9, `unique_ptr`, drenaje de resultados, pausa, autologin de pruebas.
- Ventas Partes 1–4 (11/10): botón 10 por rol, carrito en memoria (sin tabla CARRITO), cierre con cancelación automática, pago por BRUTO + ticket. Detalle histórico en los commits del 11/10.
- Menú ventas 12/10: devolución UI, cierre de caja, reporte por rango `AAAA-MM-DD`, ver pagos.
- Pantalla de pago 12/10: métodos por ID, `A PAGAR / RECIBIDO / DEVUELTO`.
- Costo en buscar-productos + `8. Ganancias` (mensual + líneas). Buscar alineado con CANTIDAD (`printf`).
- Update pide precio de compra; `2. Actualizar costo` en stock.
- Login envenenado (13/10): se drena antes del UPDATE de rehash; admin migra a PBKDF2.
- SELECTs a SP + `FN_TASA_ITBIS()` en la app; `9. Cobrar venta`.
- Compras 1–4 app (13/10): carrito a precio de compra, ticket BALBUTECH, pago por bruto, devolución. Botón `11. Compras` solo ADMIN (menú actual: 14 opciones).
- El alta pide precio de compra antes del de venta + muestra `El cliente pagará` con ITBIS.
- `entrar-local.ps1` local (ignorado): auto-login admin. Compila `OK`.
- Reporte por período ventas (14/10) + compras (`4.`, Volver a 5) + ganancias (`11.`, Volver a 12): `SP_REPORTE_PERIODO_COMPRA` (RECIBIDA) y `SP_REPORTE_PERIODO_GANANCIA` (fórmulas del 38, sin IVA). Probados en vivo.
- Revisión pull 14/10: quite `select *` de depuración en `2- MARCAS.sql`; cargué los 4 SP de período/pendientes en TEST y TECH (la app los llamaba y no existían); `check-app-sps` en TECH da 0 faltantes; reporte octubre en vivo cuadra (6 / 797000 / 143460 / 940460). Quitado de DEFAULTs en CATEGORIAS y PAGO: es el fix de import conocido, la app manda todos los args.
- Pendientes hechos 14/10: Kardex (`SP_KARDEX_PRODUCTO` + `3.` en stock, humo en vivo); Garantías (`12.` con registrar/reclamar/finalizar); Historial (`SP_HISTORIAL_VENTA` + `13.`); `.env` creado (gitignored). Falta tu decisión: seed admin, SRI del CDN, devcontainer y tus ganancias por mes.

## 15/10 — mapa suplidores, reintentos y etiquetas
- Mapa 6 pasos: tabla `PRODUCTO_PROVEEDOR` + trigger al RECIBIDA + 4 SP (archivo 40) + carrito elige suplidor por línea con historial + split por factura + `6. Precios por suplidor`. Verificado 2 suplidores, anular/cancelar; `check-app-sps` 0 faltantes en ambas.
- Reintentos al cerrar (compra y venta): 3 intentos estilo login, el carrito se conserva si falla.
- Rename `COSTO` → `P_COMPRA` (tabla, SPs, triggers, app); `P_COMPRA NOT NULL` con estimados al 80% (NO REALES, van facturas).
- JOIN de stock + filtros ID repuestos en SP productos; listados `ID | NOMBRE | ESTADO | P.COMPRA | STOCK`.
- `P.UNIT` en facturas de venta y compra; carrito muestra precios con ITBIS.

## 15/10 (tarde) — compra rápida y reporte de precios
- Helper `leerNumeroConIntentos` (seguridad.h/cpp, HECHO): 3 intentos por dato, rango min/max, punto o coma, `xxx` cancela, Enter = default donde aplica. Migrados 19 puntos de pagos y devoluciones (compras: pagarCompra método/monto/empleado, devolución, pagar pendiente; ventas: pagarVenta método/monto, cobrar, anular, devolución, garantía). Unificados `esNumerico` y `MAX_INTENTOS` (main.cpp incluye seguridad.h). Build OK.
- `SP_CONSULTAR_PRODUCTOS_FILTRADO` (9) devuelve `ID_PROVEEDOR`; aplicado a la viva.
- Compra rápida en 2 listas con grilla tipo Excel: inicial `ID_PROD | NOMBRE | CANTIDAD`; al elegir confirma `Producto: <id> (<nombre>)`; paso suplidor `ID_PROV | PROVEEDOR` (sin historial lista todos los activos). En prueba en vivo.
- Alta rápida de suplidor sin salir de la compra (`registroRapidoS` en compras.cpp): `0` = nuevo; ID inexistente o nombre ofrecen registrar; nombre obligatorio, tel/email opcionales. Fix `Commands out of sync` (drenar antes del retorno temprano). "Jose tech" creado en vivo desde la compra.
- Reporte `6. Precios por suplidor`: `SP_REPORTE_PRECIOS_COMPRA` (40) ahora trae `MAS_CARO` + `DONDE_CARO` (aplicado a la viva); pantalla `MAS BARATO | BARATO EN | MAS CARO | CARO EN | ULTIMA`. Verificado en vivo (DELL G15: barato Jose tech, caro PM6).

## 16/10 — barrido de notas (lo hecho a Realizado)
- `SP_CIERRE_CAJA` consumido desde C++ (`cierreCajaUI` lee resumen + por estado + por método): cierra fase pendiente 09/10.
- Venta rápida en app (`ventaRapida`, opción 1): cierra pendiente 11/10.
- Catálogo por módulo (verificado en viva): 13 compras / 14 detalles, 5/10 nuevos con stock (LENOVO 3, DELL 1, MACBOOK 1, INTEL 2, RTX4060 4); `Mouse`/`Teclado`/`2`/`FASE I` fuera. Queda: `IPHONE` como marca + renombrar `SUPLIDOR 01`–`10`.
- Formato kardex en listados C++ (marcas, empleados, roles, clientes, proveedores, métodos y resto).
- Limpieza vieja verificada: `sp_obtener_categorias_marcas` inexistente en la viva; `ROLE_INV_AUDITOR` borrado (0 usuarios/permisos), sin referencias en la app.
- Revisión 15/10: el pull ya traía todo (helper intentos, registro rápido suplidor, MAS_CARO). Faltaba en la viva: `SP_REPORTE_PRECIOS_COMPRA` con caro (recargado) + backfill del mapa (8 parejas, trigger solo llena desde que existe). `check-app-sps` en TECH: 0 faltantes. Compila `OK`.
- Barrido entradas a ciegas (15/10): `leerNumeroConIntentos` en inventario, productos, ventas y compras (pick, cantidades, cancelar, períodos, garantías, historial, devoluciones, registro). Los bucles de cerrar se quedan a mano: reintentan también errores de BD. Humo en vivo OK.
- Barrido de entradas ciegas a `leerNumeroConIntentos` (15/10): inventario, productos, ventas (pick, cantidad, cancelar, períodos, garantías, historial, devolución) y compras (registro, pick, cantidad, período). Cierres con bucle propio (reintentan errores de BD). Humo en vivo OK, compila OK.
- Venta vacía silenciosa (16/10): el SP de agregar en la viva hablaba de `COSTO` (renombre no recargado) y `Recogermensaje` se tragaba el error: nacían ventas en $0. Recargado el SP en TEST+TECH y blindados los loops de líneas (si el mensaje es `Error DB:` se cancela). Probado: factura #8 con línea. TEST guarda #8 CANCELADA como evidencia.
- Asistencia v1 en app (16/10): `7. Marcar` automático por hora BD (espejo ENTRADA/SALIDA con s/n) + `8. Ver` por rango. Humo en vivo con espejo aceptado (ENTRADA TARDE). Residuos 0.
- Caja/turnos v1 (16/10): archivo `41- TURNO_CAJA.sql` (tabla + `SP_ABRIR_TURNO/ESTADO/CERRAR` con cuadre esperado vs real) + módulo `caja.cpp` (menú 13 en ADMIN y 4 en cajero, permiso GESTIONAR_VENTAS) + aviso en venta rápida si no hay turno (no bloquea). Humo en TEST: turno #4 abrió $500, cobró $59 y cerró CUADRA en 0; frenos probados (doble apertura, turno cerrado/inexistente). `check-app-sps` 0 faltantes. Residuos demo en TEST por diseño.
- `SP_CERRAR_TURNO` unificado al patrón estándar (16/10): ahora devuelve 2 result sets — `MENSAJE` del cuadre (`EXITO: TURNO #N CERRADO. CUADRA./FALTA $x/SOBRA $x`) y después el resumen. En C++ se leen los dos a mano (`executeQuery` + `getMoreResults`) porque `Recogermensaje` drenaría el resumen. Probado: CUADRA en 0 y FALTA $10.00 con rollback.
- Descuentos por línea (16/10): columna `PORCENTAJE_DESCUENTO` (0-100) en `DETALLES_VENTA`; `SUBTOTAL` generado ahora = cantidad×precio×(1−%); ITBIS y ganancia salen sobre el bruto con descuento. SP de agregar con 5º parámetro `DEFAULT 0` (en `23`), devolución reembolsa lo cobrado (en `26`), `SP_VENTA_LINEAS` enseña el % (en `39`). App: prompt `Descuento % (Enter = 0)` solo al crear la línea (producto repetido suma cantidades y conserva su descuento), carrito y factura con columna `DESC`. Probado: 2×$50 −15% = $85 + $15.30 ITBIS = $100.30; devolución 1 ud = $42.50; 101% y negativo frenados; residuos 0. Recargado en TEST y TECH (ALTER sobre ambas, datos existentes intactos con 0%).
- Alertas de stock mínimo en ventas (17/10): solo C++, cero SQL nuevo (la BD ya tenía el estatus, el trigger y el reporte). Lista de venta con columna `ESTATUS` coloreada (rojo AGOTADO/CRÍTICO, amarillo STOCK BAJO, verde OK) + helper `avisoStockCritico` que avisa al agregar al carrito (cuánto quedaría) y al cerrar la venta (stock real ya descontado); no bloquea. Humo: vender 4 con stock 8/mínimo 5 → avisos en ambas pasadas, stock 4 CRÍTICO, residuos 0.
- Asistencia v2 en app (17/10): 3 pantallas nuevas en `empleados.cpp` — `9. Justificar` (fecha+estado+motivo → `11_SP_JUSTIFICAR_ASISTENCIA`, con doble freno: `11_SP_BLOQUEAR_EDICION_ANTIGUA` bloquea >7 días y el SP falla si no hay registro ese día), `10. Asistencia del día` (`11_SP_ASISTENCIA_HOY`, tabla coloreada + resumen presentes/tardes/ausentes/permisos) y `11. Resumen mensual` (`11_SP_RESUMEN_ASISTENCIA_MES`, días/horas/tardes/ausencias). Gate `tienePermiso("CONSULTAR_REPORTES")`: solo ADMIN justifica/consulta (RRHH y vendedores bloqueados). Los 2 SPs nuevos en `11-ASISTENCIA_EMPLEADOS.sql`, aplicados solo a TEST (la viva va aparte). Compila OK sin warnings. Probado: justificar hoy y hace 3 días OK (estado+motivo cambian), frenos (fecha >7 días, sin registro, gate de rol) OK, asistencia del día y resumen correctos, residuos 0.
- Módulo de contratos (17/10): `contrato.cpp`/`contrato.h` — al contratar, rellena `plantillas/contrato.html` (20 placeholders) y deja el HTML listo para imprimir a PDF. `armarContrato()` es backend puro (lee empleado + CONFIGURACION), `escribirContrato()` es el único punto que toca disco (al migrar a Qt se cambia por QPdfWriter). Tipo fijo/indefinido flexible; fechas desde CURDATE; horario/horas/forma de pago/dirección se piden al generar (no están en EMPLEADOS). Opción 12 en menú de empleados. Compila OK sin warnings. Humo: contrato TEmpR fijo (1 año) e indefinido, todos los placeholders llenos, RNC en guiones hasta cargarlo en CONFIGURACION. Residuos 0.
- Página web con datos reales (17/10): opción 2 del plan — la app exporta, la página lee. `web_export.cpp`/`web_export.h` nuevo: `14. Exportar datos para la web` en menú de ventas (gate CONSULTAR_REPORTES), consulta VENTAS (solo REALIZADA) + DETALLES_VENTA por mes del año y escribe `Pagina_Web/datos-web.js`. OJO verificado: `VENTAS.TOTAL` guarda el subtotal SIN ITBIS, así que el total de la página = subtotal + ITBIS de los detalles. `app.js` lee `datosWeb` si existe (etiqueta verde "Datos reales"); si no, DEMO con aviso rojo. `datos-web.js` gitignored (dato de la BD de cada sede, como contratos/). SRI sha384 agregado al SheetJS del CDN (cerraba el pendiente). Extensión Live Server (ritwickdey) instalada en VS Code. Prueba node: octubre 3 ventas $218.30, enero 0 ventas sin NaN, sin archivo → demo OK.
- Contratos en BD (17/10): `modulos/42- CONTRATOS.sql` — tabla `CONTRATOS` (FK empleado, TIPO FIJO/INDEFINIDO, FECHA_INICIO=hoy, FECHA_FIN NULL=indefinido, SALARIO snapshot de EMPLEADOS, RUTA_DOCUMENTO, ESTADO) + `SP_INSERTAR_CONTRATO` (frenos: ID inválido, tipo inválido, fijo sin meses, empleado no existe/INACTIVO, ya tiene ACTIVO; devuelve `EXITO: CONTRATO #N REGISTRADO.`), `SP_FINALIZAR_CONTRATO` (frenos: no existe, ya finalizado; corta FECHA_FIN a hoy con `COALESCE(LEAST(FECHA_FIN,CURDATE()),CURDATE())`), `SP_CONTRATOS_POR_EMPLEADO`. Aplicado solo a TEST (viva: check-app-sps muestra 5 faltantes = 3 contratos + 2 asistencia). C++: opción 12 ahora pide DURACIÓN EN MESES (12 = 1 año, `textoDerivado` → "1 año"/"6 meses"), REGISTRA antes de pedir los datos extra (freno temprano si ya hay activo) y UPDATEa la ruta tras escribir el HTML; nuevos 13. Ver contratos (tabla printf con FIN "indefinido" si NULL) y 14. Finalizar (15 = Volver). Humo TEST: alta #4 fijo 6 meses (fin 2027-04-17) + HTML "6 meses" correcto, freno duplicado, ver tabla, finalizar OK (fin cortado a hoy), doble finalizar frena, indefinido con FECHA_FIN NULL vía setNull, residuos 0. Hallazgos anotados en Pendientes: menús giran en EOF (pipe mal contado mío produjo log de 35M líneas) y `check-app-sps.sh` da falso "Faltantes: 0" si fallan todas las conexiones.
- Renombre de tipos de contrato (17/10, corrección del dueño): la UI ya no dice fijo/indefinido — ahora **TEMPORAL (con duración) / FIJO (permanente)**. Cambió el enum `TIPO ENUM('TEMPORAL','FIJO')`, la validación y lógica de fechas del `SP_INSERTAR_CONTRATO`, el menú de generar y los flags internos (`esTemporal`). TEST recreado (tabla vacía, DROP+apply); la viva ni lo tenía todavía, así que toma el enum nuevo directo. OJO: los TÍTULOS legales del HTML quedan invertidos respecto a la UI por la ley dominicana — temporal → "TERMINO FIJO", fijo → "TERMINO INDEFINIDO" (comentario de plantilla actualizado). Humo: temporal 6 meses (fin 2027-04-17, título FIJO, "por tiempo 6 meses"), fijo (fin NULL, sin prompt de duración, título INDEFINIDO), finalizar corta fin a hoy, freno por activo, residuos 0.
- Generar contrato sin ID ni BD (17/10, requerimiento del dueño: "que solo me pida los datos del nuevo empleado menos su id porque no tiene"): opción 12 pide ahora --- DATOS DE LA PERSONA --- (nombre/cédula/cargo requeridos con re-prompt, salario numérico con 2 decimales, teléfono/email Enter = "-", fecha de ingreso con validación AAAA-MM-DD manual + Enter = hoy) y --- CONTRATO --- (tipo + condiciones), genera el HTML y NO escribe en la BD (elimuidos el INSERT temprano, el UPDATE de ruta y el SELECT de nombre; `armarContrato` recibe struct `DatosPersonaContrato`, solo lee CONFIGURACION). Humo: "32/13/99" frena y re-pide, HTML con los datos tipeados y 0 placeholders sin llenar, CONTRATOS = 0 filas, residuos 0. El footer de la plantilla ya marcaba "Borrador sujeto a revisión legal antes de su firma". Próximo pendiente: registro AL FIRMAR.
- Subir contrato = alta automática de empleado (18/10, requerimiento del dueño: "UN TR QUE META AL EMPLEADO AUTOMATICO... PARA QUE LA INTRODUCCION DE UN EMPLEADO SEA DIRECTO" + "con borrador arranca"): TR_ALTA_EMPLEADO (BEFORE INSERT en CONTRATOS) crea al empleado nuevo con ESTADO ACTIVO y le asigna el ID al contrato, o vincula el existente por cédula sin duplicar, o frena si hay más de uno con la misma cédula. SP_SUBIR_CONTRATO recibe los datos de la persona (sin ID) con frenos: activo por cédula, inactivo, teléfono/email únicos (o "-"), temporal sin meses, tipo inválido. CONTRATOS con snapshot NOMBRE/CEDULA/CARGO/TELEFONO/EMAIL/FECHA_INGRESO (+ ALTER IF NOT EXISTS idempotente). App: 12 genera el .borrador (clave=valor) junto al HTML; 13 Subir lista pendientes, pide teléfono/email reales solo si el empleado nuevo viene con "-", registra y marca .subido; menú 12-16. Test rojo→verde db/test-contratos-subir.sh (10 casos, frenos, residuos 0, aborta si base sucia); check-app-sps 0 faltantes real; humo punta a punta OK (contrato #5 → empleado recién creado ID 23, FECHA_FIN +8 meses). Lección: BD tests SIEMPRE en serie (una corrida paralela dejó 8 filas basura commiteadas).

## 18/10 — Auditoría BD general (08/10) cerrada → movida acá

> Reverificado contra la viva el 18/10/2026. Lo que seguía **abierto** quedó en `../Auditoria/Auditoría BD general - 08-10-2026.md`.

### Los 8 errores reales (corregidos 08–10/10, verificados objeto por objeto el 09/10)
- `SP_TOGGLE_ESTADO_MARCA` (`2`): alternaba `ACTIVO/INACTIVO` contra un ENUM `ACTIVA/INACTIVA` → ERROR 1265. Ahora `ACTIVA/INACTIVA`, con validación de existencia.
- `SP_TOGGLE_ESTADO_METODO_PAGO` (`4`): hacía `UPDATE` de una columna `ESTADO` que no existía. Columna agregada en el `CREATE` + migración `ADD COLUMN IF NOT EXISTS`, con backfill `ACTIVO`.
- `SP_ASIGNAR_TECNICO_RECLAMO` (`34`): ponía `EN_PROCESO` en un ENUM que no lo tenía. Se eliminó ese `UPDATE`: el reclamo queda `PENDIENTE` y el avance vive en `ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION`.
- `SP_ASIGNAR_PERMISO_A_ROL` / `FN_TIENE_PERMISO` (`36`): leían `USUARIOS_SISTEMA`, que no existe. Ahora `USUARIOS → ROLES`.
- `SP_REGISTRAR_ASISTENCIA` (`11`): insertaba en `ASISTENCIA`, que no existe. Ahora `ASISTENCIA_EMPLEADOS` (`ENTRADA` crea la fila, `SALIDA` pone `HORA_SALIDA`).
- `27_SP_FINALIZAR_RECLAMO_TOTAL` (`27`): insertaba en `LOG_AUDITORIA`, inexistente → ROLLBACK siempre. Ahora `AUDITORIA_SISTEMA`; además quedó blindado (patrón fase I + guard `RECLAMO NO ENCONTRADO`).
- `SP_REPORTAR_ACCESOS` (`28`): usaba `U.NOMBRE_USUARIO`; la columna real es `USUARIOS.USUARIO`.
- `sp_obtener_categorias_marcas` (`Mejoras_extras.sql`): leía tablas en minúscula con columnas inexistentes. Archivo borrado (`git rm`) y SP dado de baja en la viva (inexistencia reverificada el 16/10).
- Barrido del 09/10: cero referencias rotas a tablas/vistas en los `.sql`, ENUMs consistentes, tablas archivos↔BD 40/40.

### Mejoras 1–4 (09/10, archivo + BD, con pruebas)
- #1 `SP_ASIGNAR_TECNICO_RECLAMO`: valida que el empleado exista e impide doble asignación en curso del mismo reclamo.
- #2 Asistencia: rechaza doble `ENTRADA` y `SALIDA` sin `ENTRADA` (mensaje amable en vez del 1062 crudo).
- #3 `sp_obtener_categorias_marcas`: `DROP` en la viva.
- #4a Contraseñas: `USUARIOS.CONTRASENA` → 512 y los params de `SP_INSERTAR_USUARIO` y `SP_CAMBIAR_CONTRASENA` → 512. (Quedó una rutina sin tocar: ver pendientes.)
- #4b Roles alineados al C++ (que manda): `ROLE_ADMIN`→`ADMIN`, `ROLE_GERENTE`→`RRHH`, `ROLE_VENDEDOR`→`EMPLEADO`; `ROL_PERMISO.ROL_NOMBRE` → `VARCHAR(50)` + FK `FK_ROL_PERMISO_ROL`. `FN_TIENE_PERMISO('abalbuena','GESTIONAR_ROLES')` pasó de 0 a **1** y `abalbuena` cae en la rama ADMIN del menú. `ROLE_INV_AUDITOR` borrado de la viva (0 usuarios, 0 permisos).

### Planes 1, 2 y 3 (09/10)
- Plan 1 cerrado salvo 1.2; Plan 2 (blindaje mediano) y Plan 3 (auditoría completa) cerrados. Todo probado en `ROLLBACK` con residuos 0.
- Lección: un `replaceAll` global tocó 2 líneas sanas de un SP y hubo que revertir verificando línea por línea.

### Contrato C++ ↔ SQL (09/10)
- C1 `SP_INSERTAR_CATEGORIA` 1 vs 3 args y C2 `SP_ACTUALIZAR_CATEGORIA` 2 vs 4 → `DEFAULT NULL` en los params.
- C3 `SP_ACTUALIZAR_EMPLEADO` permutado (corrompía datos) → firma al orden del C++, cada dato verificado en su columna.
- C4 `usuarios.cpp:242` `NOMBRE_USUARIO` → `USUARIO`. C5 `database.cpp:51,61` `CATEGORIA`/`MARCA` singular → plural.
- V1 `SP_CANCELAR_VENTA` sin transacción ni `FOR UPDATE` → fase I + `FOR UPDATE`. V2 `SP_ASIGNAR_FACTURA_VENTA` sin traducir el 1062 → handler espejo de compras. V3 `24_SP_REGISTRAR_PAGO` exigía 5 args → `DEFAULT NULL`. V4 ~8 errores técnicos de ventas → guards amables.
- Falso positivo descartado: las vistas con `GROUP BY` corren bien (la PK las cubre); el `SUM`/`VUELTO` en `NULL` es cosmético.

### Login (09–10/10)
- 09/10: la clave del admin estaba en texto plano. Se pasó a `SHA2(clave,256)` (64 chars) y la app la rehasha a PBKDF2 en el primer login.
- 10/10 causa raíz: **era el conector, no la clave**. `libmysqlcppconn 7.1.1.9` corrompe al leer strings de más de 64 bytes por protocolo binario (`REPEAT('A',100)` volvía roto). Fix: Connector/C++ 8.4.0 en `~/conectores`, `build.sh` con `-std=c++17` y fallback al sistema, `output/app` recompilado. Eso cerró también el bloqueo de toolchain que la nota daba por pendiente.
- Verificado punta a punta: login → menú ADMIN → Roles → listar los 3 → volver → cerrar sesión.

### Bugs sistémicos de C++ (10/10)
- **Out-of-sync**: cada `CALL` deja un result-set de cola; sin drenarlo falla la query siguiente (por eso algunos listados sí andaban). Helper `drenarResultados()` (2 overloads) + `Recogermensaje` (cubre todas las escrituras) + 50+ sitios de lectura. Corrida completa de 9 submenús con **0 errores**.
- **`unique_ptr`**: ~90 declaraciones migradas, `delete` manuales fuera, `#include <memory>`; diff 591+/274-. Verificado con build + auditoría anti-doble-free en 0 + tour de 9 submenús + alta real.
- **Fuga de `pstmt`**: el refactor masivo (`delete` en el catch, por script) rompió fin de línea, paréntesis y scopes; se detectó con build + diff y se revirtió. La fuga (~100 bytes por operación fallida) queda como **deuda técnica aceptada**, a mano y función por función.
- **Métodos de pago** (huérfano rescatado): permiso `GESTIONAR_METODOS_PAGO` asignado al ADMIN + opción 9 en su menú + `ejecutarSubmenuMetodosPago()` + include faltante.

### TEST montado (11/10)
- `BALBU_TECH_TEST` cargado con `import.sh` (40 tablas / 124 rutinas / 72 triggers / 19 vistas) + seed admin.
- Fix durable: neutralizados los 3 `USE BALBU_TECH;` hardcodeados (`1-`, `10-`, `27-`) que fugaban objetos a TECH.
- Regla de la casa: **probar en TEST, no en TECH**. Smoke test con `ROLLBACK`, aserciones contra seeds (no contra 0).

### Gemelos de la BD (cerrado y reverificado 18/10)
- IDÉNTICOS: `13_SP_HISTORIAL_PERMISOS_EMPLEADO` y `35_SP_FINALIZAR_RECLAMO_TOTAL` ya no existen en la viva y tienen 0 referencias en el repo.
- DIFERENTES: `1_SP_BUSCAR_CATEGORIAS`, `1_SP_TOGGLE_ESTADO_CATEGORIA` y `5_SP_TOGGLE_ESTADO_PROVEEDOR` ya no existen; quedaron las versiones sin número, que **sí** tienen llamadas (`categorias.cpp:138`, `proveedores.cpp`, `ventas.cpp`).
- `VERANTESDEINSERT`: no existe en la viva.

### Otras mejoras del 08/10 ya resueltas (reverificadas 18/10)
- FK `PRODUCTOS.ID_PROVEEDOR` → `FK_PRODUCTO_PROVEEDOR` (ya no hay huérfanos posibles).
- FK `ROL_PERMISO.ROL_NOMBRE` → `FK_ROL_PERMISO_ROL` (el CHECK pasó a FK real).
- `DETALLE_REPARACIONES.ESTADO_AVANCE` → ENUM.
- Orden de triggers explícito con `FOLLOWS` en los grupos frágiles (`23-`, `26-`, `32-`, `15-`): ya no depende del orden de creación.
- Tablas que estaban sin `BEFORE`: `DEVOLUCIONES` (`INSERT`/`UPDATE`/`DELETE`), `BONOS_EMPLEADOS` (`INSERT`/`UPDATE`), `LIQUIDACIONES` (`INSERT`/`UPDATE`/`DELETE`) y `RECLAMOS_GARANTIAS` (`UPDATE`/`DELETE`).
- `USUARIOS_SISTEMA`: 0 referencias vivas (solo un comentario histórico en `36-`).
- `leerDatoSeguro` «se comía la línea vacía»: era el `peek`/`ignore`, eliminado el 10/10 (`seguridad.cpp:23-25`). Hoy es `cin.clear()` + `getline`.

### ITBIS (11/10)
- Opción A, por línea: `MONTO_ITBIS` en `DETALLE_COMPRA`/`DETALLES_VENTA` + snapshots en devoluciones, tasa leída de `CONFIGURACION`, `TOTAL` bruto intacto, 2 vistas con IVA. Suites `t_iva*.sql` verdes en TEST y TECH, residuos 0.

### Lecciones de esta auditoría
- `git pull` antes de editar y commit propio después: otro commit (`b421d91`) reescribió `12-` y `15-` sin los fixes y hubo que re-aplicarlos.
- Los tests de BD van **en serie**: una corrida en paralelo dejó 8 filas basura.
- `-e` sin `ROLLBACK` no se usa. Aserciones contra seeds/demo, no contra 0.
- El diff manda: verificar línea por línea después de cualquier reemplazo global.

## 19/10 — El contrato no crea empleados (eliminado `TR_ALTA_EMPLEADO`)

**Decisión (pedido del dueño):** subir un contrato **no** debe dar de alta a nadie en `EMPLEADOS`. El empleado se registra antes, a mano, en el módulo de empleados; el contrato solo **vincula** por cédula. Revierte el pedido original de «alta directa al firmar» (18/10).

**Por qué:** un contrato es un documento, no el origen de un registro maestro. El trigger creaba empleados sin usuario, sin revisión de RRHH y colgando del `AUTO_INCREMENT`; un error en la carga dejaba altas sin control.

**Qué se cambió**
- `modulos/42- CONTRATOS.sql`:
  - `SP_SUBIR_CONTRATO`: busca `ID_EMPLEADO` por cédula. Si no existe → `ERROR: NO EXISTE UN EMPLEADO CON ESA CEDULA. REGISTRELO PRIMERO EN EL MODULO DE EMPLEADOS.` Si hay 2 o más → error de ambigüedad. Inserta con ese `v_id` (antes iba `NULL` y lo resolvía el trigger). Mensaje fijo `… EMPLEADO VINCULADO.`
  - Se borró `TR_ALTA_EMPLEADO` (líneas 235-274) y quedó un `DROP TRIGGER IF EXISTS` para limpiar las bases donde exista.
  - Typo `FINALIZELLO` → mensaje reescrito: «CIERRE ESE CONTRATO ANTES DE REGISTRAR OTRO».
  - Fuera las validaciones de teléfono/email únicos: solo aplicaban al alta automática.
- `contrato.cpp`: opción 13 avisa antes de llamar al SP si la cédula no existe («Esa cedula no esta registrada en Empleados…») y no pide más datos. Se eliminaron los dos bucles de teléfono/email del alta.
- `contrato.h`: comentario actualizado (ya no menciona el trigger).
- `modulos/42- CONTRATOS.md`: intro, tabla, validaciones, sección Triggers («Ninguno») y reglas de negocio.
- Tests: `db/test-contratos-subir.sh` reescrito (T1 ahora prueba que una cédula inexistente **no crea nada**; 7 casos, 1 alta exitosa). `db/test-contrato-borrador.sh` caso 5 pasa a probar el aviso de cédula no registrada.

**Evidencia**
- `bash build.sh` → `OK: ./output/app`.
- `DB_PASSWORD=… bash db/test-contratos-subir.sh` → `TODOS LOS TESTS DE CONTRATOS-SUBIR OK` (contra `BALBU_TECH_TEST`, con `ROLLBACK`).
- `bash db/test-contrato-borrador.sh` → 5/5 OK (contra `BALBU_TECH_TEST`, usuario fixture `admin`).
- En la viva: trigger eliminado (0 triggers en `CONTRATOS`), `SP_SUBIR_CONTRATO` sin `INSERT INTO EMPLEADOS`, prueba con cédula inexistente frena y con cédula real vincula; `ROLLBACK` deja 0 contratos y 9 empleados.

**Consecuencia operativa:** si cambia el cargo o el salario, se corrige en el módulo de empleados. El contrato guarda el snapshot de lo firmado y no toca al empleado.

### 19/10 (segunda parte) — Opción 12 pide cédula y separa salario ofrecido / pactado

**Pedido del dueño:** el borrador tiene que pedir los datos del empleado y arrancar por la cédula (es la clave real: art. 24.1 de la Ley 16-92 y dato obligatorio del registro del MT). El salario ofrecido puede no ser el pactado: el empleado puede pedir más y la empresa dárselo, o la empresa dar menos.

**Cómo quedó la opción 12 (`generarContratoUI`, antes `ejecutarSubmenuContratos`)**
1. Pide la **cédula** y busca en `EMPLEADOS`:
   - no existe → avisa y no genera nada;
   - 2 o más con la misma cédula → frena (misma regla que el SP);
   - existe → precarga nombre y cargo actuales como default (Enter los acepta).
2. `Cargo que se le ofrece` (default: el actual).
3. `Salario ofrecido` (default: el que gana hoy).
4. `Salario pactado` (default: el ofrecido). Se puede subir o bajar.
5. Teléfono/email (Enter = `-`), fecha de ingreso (Enter = hoy), tipo (fijo/temporal + meses), dirección, horario, horas semanales y forma de pago.

**Qué se guarda dónde**
- El contrato (HTML y `CONTRATOS.SALARIO`) lleva el **pactado**.
- El borrador guarda además `salario_ofrecido=` como referencia; la opción 13 lo ignora.
- No se agregó columna a la base: el ofrecido es un dato de negociación, no del contrato firmado.

**Evidencia**
- `bash build.sh` → `OK`.
- `db/test-contrato-borrador.sh` → **6/6 OK** (nuevo caso 6: cédula inexistente en la opción 12 avisa y no genera archivos).
- Prueba manual con la viva: cédula 00000000000 → nombre y cargo precargados, cargo cambiado a «Cajero», ofrecido 20 000, pactado 18 000; el borrador guardó ambos y el HTML mostró 18 000.
- El directorio temporal se borró después de la prueba.

### 19/10 (tercera parte) — La opción 12 ya no consulta la base, firmas y tabla EMPRESA

**Pedido del dueño:** "si un empleado acaba de firmar todavía no está en la DB, eso no cuadra".

**Por qué:** la opción 12 es la **oferta**. La genera reclutamiento antes de que la persona exista como empleado. Exigir la cédula en `EMPLEADOS` invertía el orden real: primero el papel firmado, después el alta.

**Qué se cambió**
- `contrato.cpp` — `generarContratoUI()`:
  - Fuera la consulta a `EMPLEADOS` y los dos frenos (cédula repetida, cédula no registrada). Ahora pide cédula, nombre y cargo directo.
  - La cédula se valida a **11 dígitos** (sin guiones ni espacios).
  - `Salario ofrecido` pasa a ser obligatorio (antes tenía como default el sueldo actual del empleado, que ya no se consulta).
  - `pedirMonto()`: con la entrada agotada corta antes de volver a pedir. Sin eso, un monto obligatorio sin default giraba sin fin.
- `plantillas/contrato.html` — bloque de firmas nuevo: línea + nombre + cédula del empleado; línea + representante + cédula + empresa. El pie pasa de "generado por BALBU_TECH" a "generado por {empresa}, RNC {rnc}, {ciudad}, República Dominicana, el {fecha}".
- `modulos/33- CONFIGURACION.sql` — se agregaron las cinco claves de empresa (`RNC`, `CIUDAD`, `DIRECCION_EMPRESA`, `REPRESENTANTE`, `CEDULA_REPRESENTANTE`) con valor **vacío**. `CONFIGURACION` es la configuración de la empresa (ya tenía `NOMBRE_TIENDA = BALBU_TECH`); ahí va todo lo suyo.
- `armarContrato()` — lee la empresa de `CONFIGURACION`. Lo que esté vacío se imprime como `____________`.

**Hallazgo:** `CONFIGURACION` solo tenía `NOMBRE_TIENDA`, `ITBIS` y `DIAS_GARANTIA`. `armarContrato` pedía `RNC`, `CIUDAD`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`, no los encontraba y los dejaba en `____________`. **Todos los contratos generados hasta hoy salieron con el RNC, la ciudad, la dirección y el representante en blanco.** No era un problema del pie: era del documento entero.

**Decisión:** primero se creó una tabla `EMPRESA` aparte; el dueño la rechazó. Todo lo de la empresa va en `CONFIGURACION`, con las claves nuevas vacías hasta que cargue los datos con un `UPDATE`. La tabla `EMPRESA` se borró de `BALBU_TECH` y `BALBU_TECH_TEST` y su módulo `43- EMPRESA.sql` se eliminó.

**Evidencia**
- `bash build.sh` → `OK: ./output/app`.
- `db/test-contrato-borrador.sh` → **7/7 OK** contra `BALBU_TECH_TEST` (caso 6 reescrito: cédula válida inexistente no frena; caso 7 nuevo: cédula de 3 dígitos rechazada).
- Prueba manual con cédula 00000000000, ofrecido 20 000, pactado 18 000, FIJO: HTML con `CÉDULA: 00000000000` bajo la firma, pie con `BALBU_TECH, RNC ____________, ____________` y borrador con `salario_ofrecido=20000.00` / `salario=18000.00`. Cero escrituras en la base.
- En la viva y en TEST: `EMPRESA` eliminada; `CONFIGURACION` con las cinco claves nuevas vacías (TEST conservó `CIUDAD = Santo Domingo` que ya tenía).
- Segunda prueba manual contra TEST: el pie salió con `BALBU_TECH, RNC ____________, Santo Domingo` — el nombre y la ciudad salieron de `CONFIGURACION`, el RNC vacío del placeholder.

**Pendiente:** cargar RNC, dirección, representante y su cédula con `UPDATE` sobre `CONFIGURACION`. Y decidir si la 13 vuelve a crear el empleado o se mantiene el alta manual (pregunta abierta).

### 19/10 (cuarta parte) — Opción 13: cotejo, registro y alta vinculada

**Pedido del dueño:** ejecutar el plan aprobado de la opción 13 ("dale con todo").

**El modelo que quedó**

```
12  reclutamiento arma el borrador            → HTML + .borrador
13  contrataciones coteja y registra          → CONTRATOS con CEDULA e ID_EMPLEADO = NULL
1   el encargado de altas elige el contrato   → datos precargados
    INSERT en EMPLEADOS → TR_VINCULAR_CONTRATO completa ID_EMPLEADO
```

`CONTRATOS` es el registro del papel. La cédula es la llave y existe desde la
oferta; `ID_EMPLEADO` puede ser `NULL` hasta el alta.

**Qué se cambió**

- `modulos/42- CONTRATOS.sql`
  - `ID_EMPLEADO INT NULL` en el `CREATE TABLE` y un `ALTER ... MODIFY`
    idempotente para las bases que ya existían.
  - Índice `IX_CONTRATOS_CEDULA` (se crea solo si falta).
  - `TR_VINCULAR_CONTRATO` (AFTER INSERT en `EMPLEADOS`): completa el ID de los
    contratos huérfanos de esa cédula. No crea ni modifica nada más.
  - `SP_SUBIR_CONTRATO` reescrito: ya no exige empleado; freno de contrato
    ACTIVO por cédula; `FECHA_INICIO`/`FECHA_FIN` desde `P_FECHA_INGRESO`;
    mensaje `EMPLEADO PENDIENTE DE ALTA` o `EMPLEADO VINCULADO`.
  - `SP_CONTRATOS_POR_CEDULA` reemplaza a `SP_CONTRATOS_POR_EMPLEADO` y devuelve
    nombre, cargo y `VINCULO` (`PENDIENTE`/`VINCULADO`).
  - **Desvío consciente:** el freno de empleado INACTIVO se mantiene **solo si
    la cédula ya existe**; el caso nuevo (persona sin alta) no lo toca.
- `modulos/8- EMPLEADOS.sql` — `SP_INSERTAR_EMPLEADO` recibe `P_FECHA_INGRESO`
  (7º parámetro); sin fecha usa `CURDATE()`, como antes.
- `contrato.cpp`
  - **13** coteja el borrador contra el papel: muestra cada valor como default,
    valida cédula/salario/fecha, resume las diferencias y pide confirmación.
  - Escaneo opcional (PDF/JPG/PNG, ≤ 20 MB) copiado a `contratos/firmados/`;
    Enter = sin escaneo. Nunca se guarda en la base.
  - **14** pide cédula, lista el historial y ofrece adjuntar el escaneo si falta.
  - **15** pide cédula, busca el contrato ACTIVO y lo finaliza.
- `empleados.cpp` — la opción 1 lista los contratos firmados sin empleado y
  precarga todos los datos (incluida la fecha de ingreso).
- `db/check-app-sps.sh` — nombre del SP actualizado.

**Evidencia**
- `bash build.sh` → `OK: ./output/app`.
- `DB_PASSWORD=… bash db/test-contratos-subir.sh` → **OK**, 9 aserciones contra
  `BALBU_TECH_TEST` con `ROLLBACK` (cero residuos).
- `DB_NAME=BALBU_TECH_TEST … bash db/test-contrato-borrador.sh` → **14/14 OK**.
- `DB_HOST=127.0.0.1 bash db/check-app-sps.sh` → `Faltantes: 0 (verificados 82)`.
- Viva: el contrato #4 de Empleado de prueba quedó intacto (1 fila, `ACTIVO`,
  `ID_EMPLEADO = 1`). Las pruebas de UI solo tocan `BALBU_TECH_TEST` y limpian
  sus cédulas marcador.

**Pendiente**
- Cargar `RNC`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE` en
  `CONFIGURACION` (siguen vacíos y el contrato los imprime en blanco).
- Campos legales que el contrato todavía no pide: nacionalidad, edad, sexo,
  estado civil, RNL, lugar de prestación, provincia y municipio.

### 20/10 — Opción 12 ya no pide el salario pactado

**Pedido del dueño (verbatim):** "en generar contrato no puede ponerme sueldo pactado, eso va en subir el contrato. Tienes que quitar eso de ahí, solo se deja en subir el contrato."

**Qué se cambió**
- `contrato.cpp` — `generarContratoUI()`: la opción 12 pide solo `Salario ofrecido`; se eliminó el prompt `Salario pactado`.
- El HTML y el `.borrador` se generan con ese monto. El `.borrador` conserva `salario_ofrecido=` (mismo valor); la opción 13 lo usa como default del cotejo.
- La opción 13 sigue pidiendo `Salario pactado` y es la que registra el valor en `CONTRATOS.SALARIO`.
- `contrato.h` — comentarios del struct `DatosPersonaContrato` actualizados.

**Evidencia**
- `bash build.sh` → `OK: ./output/app`.
- Humo contra la viva: opción 12 con 18500 mostró solo `Salario ofrecido`; HTML con `RD$18500.00`; borrador con `salario=18500.00` / `salario_ofrecido=18500.00`.
- Humo opción 13: mostró `Salario pactado [18500.00]` y cortó con EOF sin escribir en la base.
- La suite completa contra `BALBU_TECH_TEST` no se pudo correr con el usuario de la app (`balbu_app` no tiene acceso a esa base).

### 20/10 - Costo fantasma: el precio de una compra cancelada ya no se queda pegado

**Qué se cambió**
- `modulos/22- DETALLE_COMPRA.sql`
  - Nueva función `FN_COSTO_COMPRA_VIGENTE(P_ID_PRODUCTO)`: devuelve el precio de
    la última línea de compra **cuya compra NO está CANCELADA** (0 si no hay
    ninguna). Es la única definición de la regla del costo de compra.
  - `TR_ACTUALIZAR_COSTO_COMPRA` (AFTER INSERT) ahora usa la función: antes
    ponía el precio de la línea que entraba sin preguntar si su compra estaba
    cancelada.
  - `TR_RECALCULAR_COSTO_BORRADO_COMPRA` (AFTER DELETE) ahora usa la función:
    antes tomaba la última línea que quedara, aunque su compra estuviera
    cancelada.
  - **Nuevo** `TR_RECALCULAR_COSTO_COMPRA_CANCELADA` (AFTER UPDATE ON `COMPRAS`):
    cuando una compra pasa a CANCELADA, el costo de sus productos vuelve al de
    la última compra válida. Este es el trigger que cierra el bug.
  - `FOLLOWS` en toda la cadena de `DETALLE_COMPRA` y de `COMPRAS`: el orden de
    ejecución ya no depende del orden accidentado de creación.
- `modulos/32- HISTORIAL_MOVIMIENTOS_PRODUCTO.sql`: `TR_HISTORIAL_COMPRA`
  declara su lugar en la cadena (total → stock → auditoría → costo → historial).
- `modulos/40- PRODUCTO_PROVEEDOR.sql`: `TR_MAPA_COMPRA_RECIBIDA` declara su
  lugar en la cadena de `COMPRAS`.

**Por qué pasaba**
`SP_CANCELAR_COMPRA` marca la compra CANCELADA pero conserva el detalle ("el
detalle queda como evidencia"), así que el trigger que recalcula el costo
(solo corre en AFTER DELETE) nunca se disparaba y el precio de la compra
cancelada quedaba pegado en `PRODUCTOS.P_COMPRA`. Como
`23- DETALLE_VENTA.sql` usa ese valor como costo, la venta mostraba una
ganancia o una pérdida que no existía.

**Evidencia**
- Test en la viva (transacción con `ROLLBACK`, 0 residuos): producto con costo
  manual 999 → compra de 1 unidad a 100 → costo 100 → **cancelar la compra →
  costo 0** (antes quedaba 100) → segunda compra a 200 → costo 200 → borrar la
  línea → costo 0.
- Orden real de los triggers medido en la viva: coincide con el declarado.
- `bash build.sh` → `OK: ./output/app`.
- `db/check-app-sps.sh` → `Faltantes: 0 (verificados 85)`.
- Producto de prueba 8 (TEST ABONO, el único costo fantasma vivo) borrado con
  sus tablas referenciadoras: **0 residuos**. La compra 3 (CANCELADA) quedó con
  TOTAL 0.
- Rollback: `backups/costo-fantasma-antes-20-10.sql`.

**Pendiente**
- La regla acordada es "última compra válida": el costo manual que se carga en
  la ficha de un producto se respeta hasta la primera compra real; después
  manda la compra (y si esa compra se cancela, el costo queda en 0 = "nunca se
  compró"). Si el costo manual debe ser intocable, hace falta una columna
  aparte.
- `SP_ACTUALIZAR_PRODUCTO` (módulo 9) deja sobrescribir `P_COMPRA` a mano: es
  una segunda entrada al costo, fuera de la regla automática.
- `DETALLES_VENTA.MONTO_GANANCIA` es un snapshot: las ganancias ya registradas
  no se recalculan con este fix (solo las ventas futuras).

## 22/10 — Migración de roles aplicada a la viva

La viva `BALBU_TECH` seguía con el set viejo (6 roles, 18 permisos paraguas)
mientras el código ya esperaba los permisos finos: el menú de ADMIN escondía
**Usuarios** y **Clientes** sin dar ningún error. `BALBU_TECH_TEST` sí estaba
migrada.

- Backup previo: `backups/pre_roles_20261022_200029.sql` (594 KB, 43 tablas, 167 SPs).
- Orden aplicado: `44- MIGRACION_ROLES.sql` → `36- PERMISOS_ROLES.sql` → `44` otra vez
  (idempotente). El `3- ROLES.sql` **no** sirve sobre una base existente: su
  `CREATE TABLE ROLES` no tiene `IF NOT EXISTS` y corta con `ERROR 1050`.
- Resultado: 7 roles (ADMIN 30, GERENTE 24, SUBGERENTE 16, RRHH 10, VENDEDOR 10,
  ALMACEN 8, CONTABILIDAD 3), 30 permisos, EMPLEADO y CAJERO retirados.
- Matriz idéntica a TEST (diff vacío). `FN_TIENE_PERMISO` responde 1 para los
  permisos nuevos y 0 para uno inexistente.
- Contrato #4 (Jose Alcantara, cédula 40229519463, empleado 1) y los 9 empleados
  intactos. `check-app-sps` → `Faltantes: 0 (verificados 93)`.
- `bash build.sh` → `OK: ./output/app` (el binario estaba viejo: `productos.cpp`
  y `ventas.cpp` eran más nuevos que el ejecutable).

**Pendiente**
- Terminar la migración de permisos finos de los módulos que faltan (P0 de
  `PENDIENTES.md`).
- `VENDEDOR` ve "Empleados" (necesita `REGISTRAR_ASISTENCIA` para fichar) y
  dentro ve "Ver asistencia", "Asistencia del día" e "Historial" porque tiene
  `CONSULTAR_REPORTES`: puede ver la asistencia de todos. Decidir si se separa.

## 23/10 — Asistencia como ítem propio (los 7 roles fichan)

La asistencia vivía dentro de **Empleados**: VENDEDOR no tenía el ítem y
CONTABILIDAD tampoco, así que no podían fichar; y VENDEDOR veía la asistencia
de todos por `CONSULTAR_REPORTES`.

- Ítem nuevo **Asistencia**, primero del menú principal, visible con
  `REGISTRAR_ASISTENCIA`. Adentro: `Marcar entrada/salida` y `Mi asistencia`
  (usa `USUARIOS.ID_EMPLEADO`; nadie marca por otro).
- `CONSULTAR_ASISTENCIA` (nuevo): `Ver asistencia`, `Asistencia del día` e
  `Historial`. Lo tienen ADMIN, GERENTE, SUBGERENTE y RRHH. **VENDEDOR no**:
  conserva `CONSULTAR_REPORTES` y todos los reportes de venta.
- `REGISTRAR_ASISTENCIA` se sumó a RRHH, ALMACEN y CONTABILIDAD. Nadie perdió
  permisos.
- SUBGERENTE conserva Empleados con `EMPLEADOS_VER` (Buscar, Listar, Volver) y
  recibió `JUSTIFICAR_ASISTENCIA`.
- `modulos/45- PERMISO_CONSULTAR_ASISTENCIA.sql` (idempotente) + `36` y su `.md`.
- Matriz final: ADMIN 31, GERENTE 25, SUBGERENTE 19, RRHH 12, VENDEDOR 10,
  ALMACEN 9, CONTABILIDAD 4; 31 permisos / 110 pares.
- Tests: `test-menus-por-rol.sh` OK (menú por rol, VENDEDOR sin reportes,
  SUBGERENTE en Empleados), `test-asistencia-propia.sh` OK (fichaje sin pedir
  ID), `test-contrato-borrador.sh` 15/15 (índices actualizados),
  `check-app-sps` 93/0.
- Viva: backup `backups/pre_asistencia_20261022_221606.sql` (596 KB, 43 tablas),
  `45` aplicado dos veces. 9 empleados, 1 contrato y 0 asistencias intactos.

**Pendiente**
- Commitear el cambio (el usuario hace commit/push).
- RDD: el assess da `high_risk`; la review nativa queda pendiente para cuando el
  cambio esté commiteado (el worktree mezcla el vault sin commitear).

## 23/10 — Permisos finos de Proveedores (Tanda B, módulo 1)

Proveedores era el último módulo de la Tanda B que seguía con un permiso
paraguas: `GESTIONAR_PROVEEDORES` abría el ítem y las 6 opciones a la vez.

- `proveedores.cpp` pasó al patrón de `clientes.cpp`: enum de acciones, vector
  `{etiqueta, permiso, accion}`, lista visible filtrada con `tienePermiso()`,
  numeración sobre lo visible y despacho por `accion`. `Volver` siempre visible.
- `roles.cpp`: el ítem Proveedores se muestra con cualquiera de los cuatro
  permisos finos, no con el paraguas.
- Permisos: `PROVEEDORES_VER` (Buscar/Listar), `PROVEEDORES_CREAR`,
  `PROVEEDORES_EDITAR` y `PROVEEDORES_ESTADO`. Los tienen ADMIN, GERENTE,
  SUBGERENTE y ALMACEN; VENDEDOR, RRHH y CONTABILIDAD no ven el ítem.
- `modulos/36- PERMISOS_ROLES.sql` y su `.md`: 34 permisos / 122 pares.
  `modulos/46- PERMISOS_PROVEEDORES.sql` (idempotente) migra bases existentes,
  preserva roles personalizados que tenían el paraguas y lo borra. Orden:
  binario nuevo antes del SQL.
- `modulos/5- PROVEEDORES.md` documenta el mapa del submenú; `00- INDICE.md`
  queda en 48 módulos (suma los módulos 45 y 46, que faltaban).
- Tests: `build.sh` OK; `test-menus-por-rol.sh` OK (nuevo `PRUEBA_PROV_VER` con
  solo `PROVEEDORES_VER` → 3 opciones, y `ALMACEN/Proveedores` → 6 opciones);
  `test-migracion-roles.sh` OK; `test-asistencia-propia.sh` OK;
  `test-contrato-borrador.sh` 15/15; `check-app-sps` 93/0.
- Viva: backup `backups/pre_proveedores_20261022_233409.sql` (596 KB),
  `46` aplicado dos veces. 34 permisos / 122 pares; los 4 roles con los 4;
  proveedores, empleados y contratos intactos.
- Review RDD: no disponible. Las lentes `risk` y `reliability` devolvieron
  salida vacía (`provider_result_empty`); se declararon no alcanzables y la
  review terminó en `unachievable_lens_slot`, sin aprobación. Reintentar con
  otro modelo si se quiere el sello.

**Pendiente**
- Commit y push (los hace el usuario). El commit de este módulo queda en la rama
  `feat/permisos-finos-proveedores`.
- Seguir con Categorías, Marcas, Productos, Métodos de pago, Compras,
  Inventario, Ventas y Caja.
