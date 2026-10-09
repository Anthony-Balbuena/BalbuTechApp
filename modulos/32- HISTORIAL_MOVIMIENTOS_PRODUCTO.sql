/*
TABLA HISTORIAL_MOVIMIENTOS_PRODUCTO
Guarda cada movimiento de stock con el tipo, la cantidad y el stock antes
y despues del cambio. Sirve para reconstruir en que momento cambio el
stock de cualquier producto.
*/
CREATE TABLE HISTORIAL_MOVIMIENTOS_PRODUCTO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'VENTA', 'DEVOLUCION') NOT NULL,
    CANTIDAD INT NOT NULL,
    STOCK_ANTERIOR INT NOT NULL,
    STOCK_NUEVO INT NOT NULL,
    FECHA_MOVIMIENTO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_HISTORIAL_PROD FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO) ON DELETE CASCADE
) ENGINE = InnoDB; 

/*
INDICE IX_HIST_MOVIMIENTO_FECHA
Trae el historial de movimientos por fecha: hasta ahora solo estaba la PK
y el FK del producto, y todo lo que pide "que paso en tal dia" tenia que
recorrer la tabla entera.
*/
CREATE INDEX IX_HIST_MOVIMIENTO_FECHA ON HISTORIAL_MOVIMIENTOS_PRODUCTO (FECHA_MOVIMIENTO);


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
---VENTA
DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_VENTA ;

/*
TR_HISTORIAL_VENTA
Cuando se vende un producto, anota en el historial el stock antes y
despues de la venta con tipo VENTA. Solo registra: el que descuenta el
stock es TR_AUDITORIA_MOVIMIENTO_VENTA (20), que corre antes.
*/
CREATE TRIGGER TR_HISTORIAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
-- (09/10/2026) Orden fijo: despues del total (lee el stock ya descontado y sumado).
FOLLOWS TR_ACTUALIZAR_TOTAL_VENTA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Leemos el stock ya descontado (el trigger de la venta, archivo 20,
    -- se crea primero y por eso corre antes)
    SELECT STOCK_ACTUAL INTO v_stock_nuevo FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. El stock anterior era el actual mas lo vendido
    SET v_stock_anterior = v_stock_nuevo + NEW.CANTIDAD;

    -- 3. Insertamos en el historial de movimientos
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'VENTA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Venta registrada automáticamente'
    );
END //

DELIMITER ;

-----COMPRA

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_COMPRA ;

/*
TR_HISTORIAL_COMPRA
Al comprar, anota en el historial la ENTRADA con el stock antes y
despues. Solo registra: el que suma el stock es
TR_ACTUALIZAR_STOCK_COMPRA (19), que corre antes.
*/
CREATE TRIGGER TR_HISTORIAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Leemos el stock ya actualizado (el trigger de la compra, archivo 19,
    -- se crea primero y por eso corre antes)
    SELECT STOCK_ACTUAL INTO v_stock_nuevo FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. El stock anterior era el actual menos lo comprado
    SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;

    -- 3. Registramos el movimiento en el historial
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'ENTRADA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Compra registrada automáticamente'
    );
END//

DELIMITER ;
/*
TR_HISTORIAL_BORRADO_COMPRA - NO SE CREA AQUI
El historial de cuando se quita una linea de una compra lo escribe
TR_ACTUALIZAR_STOCK_BORRADO_COMPRA (19- COMPRAS) dentro del mismo
trigger que baja el stock: los triggers de DELETE no se pueden ordenar
y asi el antes/despues sale siempre bien. Aqui solo queda la nota.
*/
----DEVOLUCIONES (version vieja, comentada)

DELIMITER //

-- Limpieza por si existiera en alguna base vieja
DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION //

/*
TR_HISTORIAL_DEVOLUCION sobre DETALLES_DEVOLUCION
COMENTADO: la tabla DETALLES_DEVOLUCION no existe en la base (las
devoluciones se guardan completas en DEVOLUCIONES). El trigger de mas
abajo, sobre DEVOLUCIONES, es el que ahora lleva el historial.
*/
-- CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
-- AFTER INSERT ON DETALLES_DEVOLUCION
-- FOR EACH ROW
-- BEGIN
--     DECLARE v_stock_anterior INT;
--     DECLARE v_stock_nuevo INT;
--
--     SELECT STOCK_ACTUAL INTO v_stock_anterior FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
--     SET v_stock_nuevo = v_stock_anterior + NEW.CANTIDAD;
--
--     INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
--         ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
--     ) VALUES (
--         NEW.ID_PRODUCTO, 'AJUSTE', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Devolución de producto'
--     );
-- END //

DELIMITER ;

----DEVOLUCIONES

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION;

/*
TR_HISTORIAL_DEVOLUCION (sobre DEVOLUCIONES)
Cuando una devolucion pasa de PENDIENTE a APROBADA o REEMBOLSADA, anota
en el historial el stock antes y despues con tipo DEVOLUCION. Solo registra:
el que devuelve el stock es TR_REINTEGRAR_STOCK_DEVOLUCION (25), que se
crea primero y por eso corre antes (los triggers van en orden de creacion).
*/
CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
AFTER UPDATE ON DEVOLUCIONES
FOR EACH ROW
-- (09/10/2026) Orden fijo: despues de marcar la venta (usa el stock ya reintegrado).
FOLLOWS TR_MARCAR_VENTA_DEVUELTA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;
    DECLARE v_id_producto INT;

    -- Solo cuando la devolucion es aprobada o reembolsada desde PENDIENTE
    IF NEW.ESTADO IN ('APROBADA', 'REEMBOLSADA') AND OLD.ESTADO = 'PENDIENTE' THEN

        -- 1. Producto de la venta relacionada
        SELECT ID_PRODUCTO INTO v_id_producto
        FROM DETALLES_VENTA
        WHERE ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA;

        -- 2. Stock actual: el reintegro (25) ya corrio y sumo la cantidad
        SELECT STOCK_ACTUAL INTO v_stock_nuevo
        FROM INVENTARIO
        WHERE ID_PRODUCTO = v_id_producto;

        SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;

        -- 3. Registramos en el historial
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
            ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
        ) VALUES (
            v_id_producto, 'DEVOLUCION', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo,
            CONCAT('Devolución aprobada: ', IFNULL(NEW.MOTIVO, ''))
        );
    END IF;
END//

DELIMITER ;

DROP TRIGGER IF EXISTS TR_HISTORIAL_AJUSTE ;
/*
TR_HISTORIAL_AJUSTE (ELIMINADO)
Era el segundo trigger generico sobre UPDATE de INVENTARIO: anotaba TODA
subida o bajada de stock como si fuera un 'Ajuste manual de inventario',
lo cual era falso para compras, ventas y devoluciones, y sumaba una fila
a la que ya escribia el trigger de negocio (o la de
17_TR_REGISTRAR_HISTORIAL_INVENTARIO, tambien eliminado): cada movimiento
dejaba 3 filas en el historial.
Desde esta fase el historial lo escribe UNA sola vez quien hace el
movimiento (lista completa en 17- INVENTARIO.sql).
*/


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------



