# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje, unique_ptr, pausa y autologin pruebas: hechos ✅ (10-11/10). Push: lo hace el usuario.


## C++ críticos (barrido 10/10, verificados)



## BD medios (barrido 10/10, con línea)
- [ ] Contratos de empleados (16/10, pendiente de sentarse a entender): tabla CONTRATOS (empleado FK, tipo, inicio, fin NULL=indefinido, salario, RUTA_DOCUMENTO NULL, estado ACTIVO/FINALIZADO) + SPs INSERTAR/FINALIZAR/POR_EMPLEADO (un solo ACTIVO por empleado, validado en SP). Opciones: A) solo datos, B) datos + escaneo en carpeta `contratos/` gitignored (recomendado; mismo patrón que PRODUCTOS.IMAGEN; los archivos no viajan con la BD entre sedes), C) BLOB en BD (no recomendado). Al despedir se finaliza a mano por ahora.

## Web / Docker (barrido 10/10)


- [ ] `Pagina_Web` es mock (`Math.random()`); CDN sin SRI
- [x] `.env` creado 14/10 (gitignored); seed `admin/admin123` se deja como está (decisión del dueño 14/10).
- [x] `.devcontainer`/tasks revisados 15/10: labels al día (Windows, Nativo, Docker).

## Menú ventas (revisión 12/10, solo con SPs/vistas existentes)

> Hechos movidos a `Realizado.md` (14/10/2026).
- [x] Garantías/reclamos UI (HECHO 14/10: `12. Garantias` en ventas con registrar/reclamar/finalizar).
- [x] Historial de estados (HECHO 14/10: `13. Historial de venta` con `SP_HISTORIAL_VENTA`).
- [x] Ayudante único para todo ID/monto a ciegas (HECHO 15/10: `leerNumeroConIntentos` en seguridad.h/cpp + 19 puntos de pagos y devoluciones migrados; detalle en `Realizado.md`).
- [x] Barrido de entradas a ciegas (HECHO 15/10): helper en inventario, productos, ventas y compras; cierres con bucle propio (reintentan errores de BD). Humo en vivo OK.

## Menú empleados (16/10, detalle en `Plan - Asistencia - 16-10-2026.md`)
- [ ] Contratos UI en menú Empleados (depende del item BD): registrar, ver, finalizar.
- [ ] API para la web (la última, pospuesta igual que la web).
- [ ] NCF / comprobante fiscal DGII (17/10, pendiente de autorización): secuencia por tipo en BD (`NCF_SECUENCIAS`: tipo, serie, último número, rango desde/hasta autorizado, estado), columnas `NCF`/`TIPO_NCF` en `VENTAS` (default NULL = venta sin NCF como hoy), SP `SP_EMITIR_NCF` con candado `FOR UPDATE` (dos cajeros no se pegan el mismo número; frena sin secuencia activa, rango agotado o venta ya facturada), al cobrar preguntar tipo (1=B01 crédito fiscal con RNC del cliente, 2=B02 consumo, Enter = sin NCF), imprimir NCF + vigencia en el ticket. Tipos (fuente oficial: https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscales/Paginas/tiposComprobantes.aspx): B01 crédito fiscal (empresa/RNC), B02 consumo (cliente final), B03 nota de débito (mora/fletes, poco usado), B04 nota de crédito (devoluciones/anulaciones = fase 2 con el módulo de devoluciones). Estructura NCF: B + 2 dígitos tipo + 8 secuencia = 11 caracteres. TRÁMITE PREVIO en oficina virtual: autorización (autorizacionNCF.aspx) y asignación de secuencia (secuenciaNCF.aspx); la app solo lleva la secuencia que la DGII asigne, no inventa números. NO incluye: reportes 606/607, e-CF con firma digital, validación en línea.
