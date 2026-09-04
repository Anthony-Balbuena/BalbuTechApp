CREATE TABLE MOVIMIENTOS_INVENTARIO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM(
        'ENTRADA',
        'SALIDA',
        'AJUSTE',
        'DEVOLUCION'
    ) NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_MOVIMIENTO_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_MOVIMIENTO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- Tu índice para rastrear qué pasó con cada producto
CREATE INDEX IX_MOVIMIENTO_PRODUCTO ON MOVIMIENTOS_INVENTARIO (ID_PRODUCTO);

CREATE INDEX IX_CANTIDAD_MOVIINVENTORIO ON MOVIMIENTOS_INVENTARIO (CANTIDAD);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER //

DROP PROCEDURE IF EXISTS 20_SP_REGISTRAR_AJUSTE_INVENTARIO ;
CREATE PROCEDURE 20_SP_REGISTRAR_AJUSTE_INVENTARIO(
    IN P_ID_PRODUCTO INT,
    IN P_ID_EMPLEADO INT,
    IN P_TIPO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION'),
    IN P_CANTIDAD INT,
    IN P_OBSERVACION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Validación de existencia
    IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Registro del movimiento
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION);

    -- 3. Actualización de Stock (Lógica de Ajuste)
    IF P_TIPO IN ('ENTRADA', 'DEVOLUCION') THEN
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    ELSE
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL - P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    END IF;

    SELECT 'EXITO: MOVIMIENTO REGISTRADO Y STOCK ACTUALIZADO.' AS MENSAJE;
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
--COMPRA
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_COMPRA ;
CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    -- Obtenemos el empleado de la cabecera de la compra para el registro
    DECLARE V_ID_EMPLEADO INT;
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'ENTRADA', NEW.CANTIDAD, CONCAT('Compra registrada ID: ', NEW.ID_COMPRA));
END ;

--VENTAS
DELIMITER //

DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_VENTA ;

CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_VENTA
AFTER INSERT ON DETALLES_VENTA -- <--- AQUÍ ESTABA EL ERROR
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;

    -- Obtenemos el empleado de la cabecera de la venta
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- Restamos del Inventario
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- Registramos el movimiento
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD, CONCAT('Venta realizada ID: ', NEW.ID_VENTA));
END ;

DELIMITER ;









V-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------