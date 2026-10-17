# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje, unique_ptr, pausa y autologin pruebas: hechos ✅ (10-11/10). Push: lo hace el usuario.


## C++ críticos (barrido 10/10, verificados)



## BD medios (barrido 10/10, con línea)
- [x] Contratos de empleados (16/10) → HECHO 17/10: tabla `CONTRATOS` + 3 SPs en `modulos/42- CONTRATOS.sql` (aplicado a TEST; la viva con sus 3 SPs pendientes de orden). `SP_INSERTAR_CONTRATO` (meses → FECHA_FIN, salario snapshot de EMPLEADOS, frenos: empleado INACTIVO, ya tiene ACTIVO, fijo sin meses), `SP_FINALIZAR_CONTRATO` (corta FECHA_FIN a hoy si vence después), `SP_CONTRATOS_POR_EMPLEADO`. Opción B aceptada: RUTA_DOCUMENTO guarda el HTML en `contratos/` gitignored. Opción C (BLOB) descartada.

## Web / Docker (barrido 10/10)


- [x] `Pagina_Web` mock + CDN sin SRI → HECHO 17/10: la app exporta datos reales (`web_export.cpp`, `14. Exportar datos para la web` en ventas; escribe `Pagina_Web/datos-web.js`, gitignored porque es dato de la BD de cada sede). La página lee `datosWeb` si existe, si no queda en DEMO con aviso. SRI (sha384) agregado al SheetJS del CDN. Extensión Live Server instalada en VS Code para verla.
- [x] `.env` creado 14/10 (gitignored); seed `admin/admin123` se deja como está (decisión del dueño 14/10).
- [x] `.devcontainer`/tasks revisados 15/10: labels al día (Windows, Nativo, Docker).

## Menú ventas (revisión 12/10, solo con SPs/vistas existentes)

> Hechos movidos a `Realizado.md` (14/10/2026).
- [x] Garantías/reclamos UI (HECHO 14/10: `12. Garantias` en ventas con registrar/reclamar/finalizar).
- [x] Historial de estados (HECHO 14/10: `13. Historial de venta` con `SP_HISTORIAL_VENTA`).
- [x] Ayudante único para todo ID/monto a ciegas (HECHO 15/10: `leerNumeroConIntentos` en seguridad.h/cpp + 19 puntos de pagos y devoluciones migrados; detalle en `Realizado.md`).
- [x] Barrido de entradas a ciegas (HECHO 15/10): helper en inventario, productos, ventas y compras; cierres con bucle propio (reintentan errores de BD). Humo en vivo OK.

## Menú empleados (16/10, detalle en `Plan - Asistencia - 16-10-2026.md`)
- [x] Contratos UI en menú Empleados (17/10): 13. Ver contratos + 14. Finalizar contrato (15 = Volver). `ejecutarSubmenuContratos` ahora además REGISTRA en `CONTRATOS` (primero pide datos y registra con ruta NULL — frena antes de gastar los campos si ya hay activo — y al generar el HTML se UPDATEa la ruta). Duración fijo ahora se pide en MESES (12 = 1 año) y se deriva el texto del HTML (`textoDuracion`).
- [x] Generar contrato sin ID ni BD (HECHO 17/10): la opción 12 ahora pide SOLO los datos de la persona (nombre, cédula, cargo, salario, teléfono/email con Enter = "-", fecha de ingreso con validación AAAA-MM-DD y Enter = hoy) + tipo + condiciones, y genera el HTML SIN registrar nada (antes pedía ID y hacía INSERT+UPDATE de ruta). `armarContrato` ya no consulta EMPLEADOS: recibe un struct `DatosPersonaContrato` (solo lee CONFIGURACION de la empresa). Detalle: el HTML footer ya trae "Borrador sujeto a revisión legal antes de su firma".
- [ ] Registro de contratos AL FIRMAR (dueño 17/10: "quiero que los contratos estén en la BD... subirlos cuando lo firma el empleado"): el generador ya no registra; falta planificar el flujo de registro manual (antes planificado como "13. Registrar a mano sin HTML") y qué pasa con las opciones 13 Ver / 14 Finalizar que hoy leen una tabla vacía. Pendiente de planificar y aprobar.
- [ ] Menús en EOF giran sin fin: si se agota la entrada (pipe corto o Ctrl+D), `cin` queda en failbit y el loop imprime "Opcion no valida" millones de veces (log de 35M líneas en el humo 17/10). Falta detectar EOF en la lectura de opción y salir.
- [ ] `db/check-app-sps.sh` miente con "Faltantes: 0" si TODAS las conexiones fallan (el contador solo suma cuando `c = "0"`; si la query falla `c` queda vacío). Falta fallar en rojo cuando no hay conexión.
- [ ] API para la web (la última, pospuesta igual que la web).
- [ ] NCF / comprobante fiscal DGII (17/10, pendiente de autorización): secuencia por tipo en BD (`NCF_SECUENCIAS`: tipo, serie, último número, rango desde/hasta autorizado, estado), columnas `NCF`/`TIPO_NCF` en `VENTAS` (default NULL = venta sin NCF como hoy), SP `SP_EMITIR_NCF` con candado `FOR UPDATE` (dos cajeros no se pegan el mismo número; frena sin secuencia activa, rango agotado o venta ya facturada), al cobrar preguntar tipo (1=B01 crédito fiscal con RNC del cliente, 2=B02 consumo, Enter = sin NCF), imprimir NCF + vigencia en el ticket. Tipos (fuente oficial: https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscales/Paginas/tiposComprobantes.aspx): B01 crédito fiscal (empresa/RNC), B02 consumo (cliente final), B03 nota de débito (mora/fletes, poco usado), B04 nota de crédito (devoluciones/anulaciones = fase 2 con el módulo de devoluciones). Estructura NCF: B + 2 dígitos tipo + 8 secuencia = 11 caracteres. TRÁMITE PREVIO en oficina virtual: autorización (autorizacionNCF.aspx) y asignación de secuencia (secuenciaNCF.aspx); la app solo lleva la secuencia que la DGII asigne, no inventa números. NO incluye: reportes 606/607, e-CF con firma digital, validación en línea.
