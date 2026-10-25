# 54 - Orden del trigger de historial de compras

## Qué arregla

Recrea `TR_HISTORIAL_COMPRA` para que corra **después** de
`TR_ACTUALIZAR_STOCK_COMPRA`. Sin eso, una compra que incluye un producto
nuevo (sin fila en `INVENTARIO`) falla con:

```text
Error DB: Column 'STOCK_ANTERIOR' cannot be null
```

y la app cancela la compra.

## Por qué pasa

`TR_HISTORIAL_COMPRA` (módulo 32) hace:

```sql
SELECT STOCK_ACTUAL INTO v_stock_nuevo
  FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;
```

Si el producto no tiene fila en `INVENTARIO`, el `SELECT` deja
`v_stock_nuevo` en `NULL`, el cálculo da `NULL` y la columna
`STOCK_ANTERIOR` es `NOT NULL`.

El trigger que crea esa fila y suma la cantidad es
`TR_ACTUALIZAR_STOCK_COMPRA` (módulo 22). El orden de la cadena está
declarado con `FOLLOWS`:

```text
TR_CALCULAR_TOTAL_COMPRA
  -> TR_ACTUALIZAR_STOCK_COMPRA
    -> TR_AUDITORIA_MOVIMIENTO_COMPRA
      -> TR_ACTUALIZAR_COSTO_COMPRA
        -> TR_HISTORIAL_COMPRA
```

En las bases donde el trigger se creó **antes** de que el módulo 32
declarara ese orden, quedó sin `FOLLOWS` y corre primero. MariaDB sí
respeta `FOLLOWS`/`PRECEDES`; el problema es la versión vieja del trigger.

## Qué hace este módulo

Hace `DROP TRIGGER IF EXISTS TR_HISTORIAL_COMPRA` y lo vuelve a crear con
`FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA`. No toca tablas ni datos.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/54- ORDEN_TRIGGER_HISTORIAL_COMPRA.sql"
```

Es idempotente: se puede correr dos veces.

No hace falta reiniciar la app: el trigger se lee de la base en cada
sentencia.

## Cómo verificar

El orden real de los triggers `AFTER INSERT` sobre `DETALLE_COMPRA`:

```sql
SELECT ACTION_ORDER, TRIGGER_NAME
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'BALBU_TECH'
   AND EVENT_OBJECT_TABLE = 'DETALLE_COMPRA'
   AND EVENT_MANIPULATION = 'INSERT'
   AND ACTION_TIMING = 'AFTER'
 ORDER BY ACTION_ORDER;
```

`TR_HISTORIAL_COMPRA` tiene que quedar último. Prueba funcional: cargar una
compra con un producto sin fila en `INVENTARIO`; debe registrarse y dejar en
`HISTORIAL_MOVIMIENTOS_PRODUCTO` una fila con `STOCK_ANTERIOR = 0` y
`STOCK_NUEVO = CANTIDAD`.

## Qué queda pendiente

Otras tres tablas tienen el mismo desfase de orden entre la viva y una base
importada de cero:

| Tabla | Triggers |
|---|---|
| `DETALLES_VENTA` | `TR_VALIDAR_STOCK_DETALLE_VENTA` / `TR_BLOQUEAR_VENTA_FINALIZADA` |
| `EMPLEADOS` | `TR_AUDITORIA_PERFIL_EMPLEADO` / `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` |
| `PRODUCTOS` | `TR_LOG_CAMBIO_ESTADO_PRODUCTO` / `TR_AUDITORIA_PRODUCTOS_UPDATE` |

No rompen el flujo: solo cambia qué validación gana o el orden de una
auditoría. Se dejan documentados, sin tocar.
