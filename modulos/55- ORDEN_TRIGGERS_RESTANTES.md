# 55 - Orden de los triggers restantes

## Qué arregla

Completa el módulo 54. Recrea con orden explícito tres triggers que en la
base viva habían quedado creados antes de que sus módulos declararan el
orden:

| Tabla | Trigger | Corre después de |
|---|---|---|
| `DETALLES_VENTA` | `TR_VALIDAR_STOCK_DETALLE_VENTA` | `TR_BLOQUEAR_VENTA_FINALIZADA` |
| `EMPLEADOS` | `TR_AUDITORIA_PERFIL_EMPLEADO` | `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` |
| `PRODUCTOS` | `TR_LOG_CAMBIO_ESTADO_PRODUCTO` | `TR_AUDITORIA_PRODUCTOS_UPDATE` |

## Por qué importa

- **Ventas**: con el orden viejo, `TR_VALIDAR_STOCK_DETALLE_VENTA` corre
  primero. Si la venta ya está finalizada y además el producto no tiene stock,
  el usuario recibe `STOCK INSUFICIENTE` en vez de
  `NO SE PUEDEN AGREGAR PRODUCTOS A UNA VENTA QUE YA NO ESTA ABIERTA`. La
  operación se rechaza igual, pero con el mensaje equivocado.
- **Empleados**: la auditoría del perfil corre antes de desactivar el usuario.
  No rompe nada, pero el orden declarado es el inverso.
- **Productos**: la auditoría de precio y el log de cambio de estado corren
  invertidos respecto de una importación limpia.

Ninguno de los tres cambia datos ni resultados de negocio: son orden de
validación y de auditoría.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/55- ORDEN_TRIGGERS_RESTANTES.sql"
```

Es idempotente. No requiere reiniciar la app.

## Cómo verificar

```sql
SELECT EVENT_OBJECT_TABLE, ACTION_ORDER, TRIGGER_NAME
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'BALBU_TECH'
   AND EVENT_OBJECT_TABLE IN ('DETALLES_VENTA', 'EMPLEADOS', 'PRODUCTOS')
   AND ACTION_TIMING IN ('BEFORE', 'AFTER')
 ORDER BY EVENT_OBJECT_TABLE, EVENT_MANIPULATION, ACTION_TIMING, ACTION_ORDER;
```

El orden tiene que coincidir con `BALBU_TECH_TEST`. Prueba de humo: intentar
agregar una línea a una venta `REALIZADA` debe devolver el mensaje de venta
cerrada, no el de stock.

## Cambio en el módulo 18

`TR_LOG_CAMBIO_ESTADO_PRODUCTO` ahora declara
`FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE` en su módulo de origen, para que una
importación desde cero no dependa solo del número de archivo.
