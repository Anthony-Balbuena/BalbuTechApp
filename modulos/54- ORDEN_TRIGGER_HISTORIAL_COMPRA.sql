/*
MODULO 54 - ORDEN DEL TRIGGER DE HISTORIAL DE COMPRAS

Problema
--------
En bases creadas antes del 20/10/2026, TR_HISTORIAL_COMPRA quedo creado sin
FOLLOWS y corria antes que TR_ACTUALIZAR_STOCK_COMPRA. Cuando la compra
incluia un producto que todavia no tenia fila en INVENTARIO (producto nuevo),
el historial leia NULL y fallaba con:

    Column 'STOCK_ANTERIOR' cannot be null

La linea no se podia cargar y la compra se cancelaba.

Solucion
--------
Recrear TR_HISTORIAL_COMPRA con FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA, que es el
ultimo trigger AFTER INSERT de DETALLE_COMPRA. Asi el historial lee el stock
ya sumado por TR_ACTUALIZAR_STOCK_COMPRA (modulo 22), que ademas crea la fila
de INVENTARIO si el producto no la tenia.

Es idempotente: se puede correr las veces que haga falta. No toca datos ni
tablas; solo reemplaza el trigger.
*/

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_COMPRA ;

CREATE TRIGGER TR_HISTORIAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Leemos el stock ya actualizado por TR_ACTUALIZAR_STOCK_COMPRA (22)
    SELECT STOCK_ACTUAL INTO v_stock_nuevo
      FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. El stock anterior era el actual menos lo comprado
    SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;

    -- 3. Registramos el movimiento en el historial
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'ENTRADA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Compra registrada automáticamente'
    );
END //

DELIMITER ;
