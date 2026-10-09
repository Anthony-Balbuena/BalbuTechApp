# Flujos — Base de Datos (BalbuTechApp)

> Mapa vivo de los flujos de la BD `BALBU_TECH`. Creado 09/10/2026. (Detalle por flujo: se agrega cuando se pida.)

## Flujos principales (mercadería)

| Flujo | Estados | Objetos clave | Verificación | Datos hoy |
|---|---|---|---|---|
| **Compras** | ABIERTA → RECIBIDA → DEVUELTA · → CANCELADA | `19_SP_INICIAR_COMPRA`, `22_SP_AGREGAR_DETALLE_COMPRA`, pagos, anular, nota de crédito, cancelar, 2 SPs de devolución + ~15 triggers | ✅ Blindado y probado punta a punta (Partes 1–5, 7) | 2 CANCELADA |
| **Ventas** | EN_PROCESO → REALIZADA → DEVUELTA · → CANCELADA | `21_SP_INICIAR_VENTA`, detalle, `24_SP_REGISTRAR_PAGO`, anular, cancelar + triggers con `FOLLOWS` | ✅ Cerrado | 0 filas |
| **Devoluciones de ventas** | PENDIENTE → APROBADA → REEMBOLSADA / RECHAZADA | `SP_REGISTRAR_DEVOLUCION`, procesar, rechazar + 3 triggers con orden fijo | 🟡 Parcial (cuota probada; flujo completo no corrido) | 0 filas |
| **Devoluciones de compras** | PENDIENTE → PROCESADA / RECHAZADA | 2 SPs + `TR_PROCESAR_DEVOLUCION_COMPRA` + bloqueos | ✅ Probado (Parte 5) | 0 filas |

## Cadena de garantías y reclamos

Garantía (ACTIVA → VENCIDA/CANCELADA) → Reclamo (PENDIENTE → APROBADO/RECHAZADO → CERRADO) → Asignación a técnico (PENDIENTE → EN_PROCESO → COMPLETADO) → Reparación (avance PENDIENTE → EN_PROCESO → COMPLETADO/CANCELADO).

🟡 Piezas probadas por separado (asignar, finalizar, avance, cerrar); la cadena entera de una sola vez no se corrió.

## Flujos de personal

| Flujo | Estados | Verificación | Datos hoy |
|---|---|---|---|
| **Asistencia** (ENTRADA/SALIDA + cruce con vacaciones/permisos) | PRESENTE/AUSENTE/TARDE/PERMISO | ✅ Probado | 0 filas |
| **Vacaciones** (tope 15 días) | solicitud + control INSERT/UPDATE | 🟡 Triggers probados; SPs no | 0 filas |
| **Permisos** | PENDIENTE → APROBADO/RECHAZADO | 🟡 SPs existen; sin prueba punta a punta | 0 filas |
| **Bonos** (alimenta el 1% del cierre) | PENDIENTE → PAGADO/ANULADO | 🟡 Pagar/anular revisados; candado nuevo probado | 0 filas |
| **Liquidaciones** (registro terminal, empleado → INACTIVO) | MOTIVO fijo | ✅ Registrar probado | 0 filas |

## Sin flujo (datos maestros)

Usuarios, empleados, clientes, proveedores, marcas, categorías, productos, roles, métodos de pago: altas/bajas y `ACTIVO/INACTIVO`.
