CREATE TABLE PAGOS (
    ID_PAGO INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_METODO_PAGO INT NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO),
    CONSTRAINT FK_PAGO_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_PAGO_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO)
) ENGINE = InnoDB;

CREATE INDEX IX_PAGOS_FECHA ON PAGOS (FECHA);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS 24_SP_REGISTRAR_PAGO;
CREATE PROCEDURE 24_SP_REGISTRAR_PAGO(
    IN P_ID_VENTA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_ID_EMPLEADO INT -- Recibimos el ID del empleado que procesa el pago
)
proc_label: BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_NOMBRE_EMPLEADO VARCHAR(100);

    -- 1. Validar venta
    SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
    IF V_TOTAL_VENTA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Obtener nombre del empleado para el mensaje
    SELECT NOMBRE INTO V_NOMBRE_EMPLEADO FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    
    -- Si el empleado no existe, ponemos uno genérico o lanzamos error
    IF V_NOMBRE_EMPLEADO IS NULL THEN
        SET V_NOMBRE_EMPLEADO = 'DESCONOCIDO';
    END IF;

    -- 3. Insertar el pago
    INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, MONTO)
    VALUES (P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO);

    -- 4. Mensaje personalizado
    SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO POR EL EMPLEADO: ', V_NOMBRE_EMPLEADO) AS MENSAJE;
END;
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_MONTO_PAGO ;
CREATE TRIGGER TR_VALIDAR_MONTO_PAGO
BEFORE INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(10, 2);

    SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    IF (V_TOTAL_PAGADO + NEW.MONTO) > V_TOTAL_VENTA THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.';
    END IF;
END;
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_FINALIZAR_VENTA;
CREATE TRIGGER TR_AUTO_FINALIZAR_VENTA
AFTER INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(10, 2);

    SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    SELECT SUM(MONTO) INTO V_TOTAL_PAGADO FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    -- Si ya se cubrió el total, cambiamos el estado
    IF V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = NEW.ID_VENTA;
    END IF;
END;
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS AS
SELECT 
    P.ID_PAGO,
    P.ID_VENTA,
    MP.NOMBRE_METODO, -- Asumiendo que así se llama la columna en METODOS_PAGO
    P.MONTO,
    P.FECHA
FROM PAGOS P
JOIN METODOS_PAGO MP ON P.ID_METODO_PAGO = MP.ID_METODO_PAGO;










-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------