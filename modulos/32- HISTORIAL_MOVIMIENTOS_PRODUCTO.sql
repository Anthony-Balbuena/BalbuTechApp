CREATE TABLE HISTORIAL_MOVIMIENTOS_PRODUCTO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'VENTA') NOT NULL,
    CANTIDAD INT NOT NULL,
    STOCK_ANTERIOR INT NOT NULL,
    STOCK_NUEVO INT NOT NULL,
    FECHA_MOVIMIENTO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_HISTORIAL_PROD FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO) ON DELETE CASCADE
) ENGINE = InnoDB; 


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
---VENTA
DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_VENTA ;

CREATE TRIGGER TR_HISTORIAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Obtenemos el stock actual del producto antes de la venta
    SELECT STOCK INTO v_stock_anterior FROM PRODUCTOS WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
    
    -- 2. Calculamos el nuevo stock restando la cantidad vendida
    SET v_stock_nuevo = v_stock_anterior - NEW.CANTIDAD;

    -- 3. Insertamos en el historial de movimientos
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'VENTA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Venta registrada automáticamente'
    );
END ;

DELIMITER ;

-----COMPRA

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_COMPRA ;

CREATE TRIGGER TR_HISTORIAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA -- Ajusta aquí si tu tabla tiene otro nombre
FOR EACH ROW
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Obtenemos el stock actual del producto antes de la compra
    SELECT STOCK INTO v_stock_anterior FROM PRODUCTOS WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
    
    -- 2. Calculamos el nuevo stock (Sumamos la cantidad comprada)
    SET v_stock_nuevo = v_stock_anterior + NEW.CANTIDAD;

    -- 3. Actualizamos el stock en la tabla de productos (Paso CRÍTICO)
    UPDATE PRODUCTOS 
    SET STOCK = v_stock_nuevo 
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 4. Registramos el movimiento en el historial
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'ENTRADA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Compra registrada automáticamente'
    );
END;

DELIMITER ;

----DEVOLUCIONES 

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION //

CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
AFTER INSERT ON DETALLES_DEVOLUCION
FOR EACH ROW
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Obtenemos el stock actual antes de la devolución
    SELECT STOCK INTO v_stock_anterior FROM PRODUCTOS WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
    
    -- 2. Calculamos el nuevo stock (Sumamos la cantidad devuelta)
    SET v_stock_nuevo = v_stock_anterior + NEW.CANTIDAD;

    -- 3. Actualizamos el stock en la tabla de productos
    UPDATE PRODUCTOS 
    SET STOCK = v_stock_nuevo 
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 4. Registramos en el historial
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'AJUSTE', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Devolución de producto'
    );
END //

DELIMITER ;


----DEVOLUCIONES 

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION;

CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
AFTER INSERT ON DEVOLUCIONES
FOR EACH ROW
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;
    DECLARE v_id_producto INT;

    -- 1. Obtenemos el ID del producto desde el detalle de la venta relacionada
    SELECT ID_PRODUCTO INTO v_id_producto 
    FROM DETALLES_VENTA 
    WHERE ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA;

    -- 2. Solo actualizamos stock si el producto está en BUEN estado
    IF NEW.CONDICION_PRODUCTO = 'BUENO' THEN
        
        SELECT STOCK INTO v_stock_anterior FROM PRODUCTOS WHERE ID_PRODUCTO = v_id_producto;
        SET v_stock_nuevo = v_stock_anterior + NEW.CANTIDAD;

        -- Actualizamos stock
        UPDATE PRODUCTOS SET STOCK = v_stock_nuevo WHERE ID_PRODUCTO = v_id_producto;

        -- Registramos el movimiento
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
            ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
        ) VALUES (
            v_id_producto, 'AJUSTE', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 
            CONCAT('Devolución: ', NEW.MOTIVO)
        );
    END IF;
END;

DELIMITER ;

-----AJUSTE MANUAL

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_AJUSTE;

CREATE TRIGGER TR_HISTORIAL_AJUSTE
AFTER UPDATE ON INVENTARIO
FOR EACH ROW
BEGIN
    -- Solo registramos si el stock cambió
    IF OLD.STOCK_ACTUAL <> NEW.STOCK_ACTUAL THEN
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
            ID_PRODUCTO, 
            TIPO_MOVIMIENTO, 
            CANTIDAD, 
            STOCK_ANTERIOR, 
            STOCK_NUEVO, 
            OBSERVACION
        ) VALUES (
            NEW.ID_PRODUCTO, 
            'AJUSTE', 
            ABS(NEW.STOCK_ACTUAL - OLD.STOCK_ACTUAL), 
            OLD.STOCK_ACTUAL, 
            NEW.STOCK_ACTUAL, 
            'Ajuste manual de inventario'
        );
    END IF;
END ;

DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------



