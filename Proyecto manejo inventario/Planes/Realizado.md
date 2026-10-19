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
- Ventas Partes 1–4 (11/10): botón 10 por rol, carrito en memoria (sin tabla CARRITO), cierre con cancelación automática, pago por BRUTO + ticket. Detalle histórico en `Modulo Ventas Caja - 11-10-2026.md`.
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
