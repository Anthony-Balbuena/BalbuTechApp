CREATE TABLE DETALLES_VENTA (
    ID_DETALLE_VENTA INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_PRODUCTO INT NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    PRECIO_UNITARIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO_UNITARIO > 0),
    SUBTOTAL DECIMAL(10, 2) GENERATED ALWAYS AS (CANTIDAD * PRECIO_UNITARIO) STORED,
    PRIMARY KEY (ID_DETALLE_VENTA),
    CONSTRAINT UQ_VENTA_PRODUCTO UNIQUE (ID_VENTA, ID_PRODUCTO),
    CONSTRAINT FK_DETALLE_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_DETALLE_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO)
) ENGINE = InnoDB;

CREATE INDEX IX_CLIENTE_NOMBRE ON CLIENTES (NOMBRE);

CREATE INDEX IX_VENTAS_FECHA ON VENTAS (FECHA);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //

DROP PROCEDURE IF EXISTS 23_SP_AGREGAR_DETALLE_VENTA ;
CREATE PROCEDURE 23_SP_AGREGAR_DETALLE_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT,
    IN P_ID_EMPLEADO INT -- Nuevo parámetro
)
proc_label: BEGIN
    DECLARE V_PRECIO DECIMAL(10, 2);
    DECLARE V_STOCK_DISPONIBLE INT;
    DECLARE V_ID_VENTA_EMPLEADO INT;

    -- 1. Validar que la venta exista y verificar empleado
    SELECT ID_EMPLEADO INTO V_ID_VENTA_EMPLEADO FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
    
    IF V_ID_VENTA_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- Opcional: Validar que el empleado sea el mismo que inició la venta
    IF V_ID_VENTA_EMPLEADO <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar stock
    SELECT STOCK_ACTUAL INTO V_STOCK_DISPONIBLE FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    IF V_STOCK_DISPONIBLE < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Obtener precio
    SELECT PRECIO INTO V_PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. Insertar
    INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO);

    SELECT 'EXITO: PRODUCTO AGREGADO CORRECTAMENTE.' AS MENSAJE;
END ;
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


DELIMITER //
DROP PROCEDURE IF EXISTS SP_AGREGAR_DETALLE_VENTA ;
CREATE PROCEDURE SP_AGREGAR_DETALLE_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT
)
proc_label: BEGIN
    DECLARE V_PRECIO DECIMAL(10, 2);
    DECLARE V_STOCK_DISPONIBLE INT;

    -- 1. Validaciones
    SELECT STOCK_ACTUAL INTO V_STOCK_DISPONIBLE FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    
    IF V_STOCK_DISPONIBLE < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE PARA ESTE PRODUCTO.';
        LEAVE proc_label;
    END IF;

    -- 2. Obtener precio actual de venta
    SELECT PRECIO INTO V_PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 3. Insertar detalle (El subtotal se calcula solo gracias a tu columna generada)
    INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO);

    SELECT 'EXITO: PRODUCTO AGREGADO A LA VENTA.' AS MENSAJE;
END ;
DELIMITER ;



DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_TOTAL_VENTA ;
CREATE TRIGGER TR_ACTUALIZAR_TOTAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    UPDATE VENTAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_VENTA = NEW.ID_VENTA;
END ;
DELIMITER ;




DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_VENTA_FINALIZADA ;
CREATE TRIGGER TR_BLOQUEAR_VENTA_FINALIZADA
BEFORE INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);
    SELECT ESTADO INTO V_ESTADO FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    
    IF V_ESTADO = 'REALIZADA' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN AGREGAR PRODUCTOS A UNA VENTA YA FINALIZADA.';
    END IF;
END ;
DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------