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
- [ ] Asistencia v1 en app (BD ya existe y aplicada, sin SQL nuevo): 7. Marcar entrada, 8. Marcar salida (`SP_REGISTRAR_ASISTENCIA`, errores amables del SP), 9. Ver asistencia (ID + rango AAAA-MM-DD, `11_SP_REPORTE_ASISTENCIA_INDIVIDUAL`). Probar: entrada→salida, doble entrada, salida sin entrada.
- [ ] Asistencia v2 (mejoras): justificar (fecha + estado + motivo, regla 7 días vía `11_SP_BLOQUEAR_EDICION_ANTIGUA`) + reporte del día (presentes/ausentes/tarde, SP nuevo) + resumen mensual (días/horas/tardes por empleado, SP nuevo) + permiso por rol (cajero marca, admin justifica).
- [ ] Contratos UI en menú Empleados (depende del item BD): registrar, ver, finalizar.
