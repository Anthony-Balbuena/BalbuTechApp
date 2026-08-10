CREATE TABLE GARANTIAS (
    ID_GARANTIA INT NOT NULL AUTO_INCREMENT,
    ID_DETALLE_VENTA INT NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    ESTADO ENUM(
        'ACTIVA',
        'VENCIDA',
        'CANCELADA'
    ) NOT NULL DEFAULT 'ACTIVA',
    PRIMARY KEY (ID_GARANTIA),
    CONSTRAINT UQ_GARANTIA_DETALLE UNIQUE (ID_DETALLE_VENTA),
    CONSTRAINT CK_GARANTIA_FECHAS CHECK (FECHA_FIN > FECHA_INICIO),
    CONSTRAINT FK_GARANTIA_DETALLE FOREIGN KEY (ID_DETALLE_VENTA) REFERENCES DETALLES_VENTA (ID_DETALLE_VENTA) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE INDEX IX_GARANTIA_INICIO ON GARANTIAS (FECHA_INICIO);

CREATE INDEX IX_GARANTIA_FIN ON GARANTIAS (FECHA_FIN);


CREATE INDEX IX_GARANTIA_ESTADO ON GARANTIAS (ESTADO);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_GARANTIA;
CREATE PROCEDURE SP_REGISTRAR_GARANTIA(
    IN P_ID_DETALLE_VENTA INT,
    IN P_DIAS_VALIDEZ INT
)
proc_label: BEGIN
    DECLARE V_EXISTE INT;
    DECLARE V_NUEVO_ID INT;

    -- 1. Verificar si ya existe una garantía
    SELECT COUNT(*) INTO V_EXISTE FROM GARANTIAS WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA;
    
    IF V_EXISTE > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.';
        LEAVE proc_label;
    END IF;

    -- 2. Insertar el registro
    INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN)
    VALUES (
        P_ID_DETALLE_VENTA, 
        CURRENT_DATE, 
        DATE_ADD(CURRENT_DATE, INTERVAL P_DIAS_VALIDEZ DAY)
        
    );

    -- 3. Capturar el ID recién generado
    SET V_NUEVO_ID = LAST_INSERT_ID();

    -- 4. Devolver mensaje y el ID para tu interfaz C#
    SELECT 
        'EXITO' AS ESTATUS,
        'GARANTÍA REGISTRADA CON ÉXITO.' AS MENSAJE,
        V_NUEVO_ID AS ID_GENERADO;
END ;
DELIMITER ;




DELIMITER //

DROP PROCEDURE IF EXISTS 26_SP_RECHAZAR_DEVOLUCION;

CREATE PROCEDURE 26_SP_RECHAZAR_DEVOLUCION(
    IN P_ID_DEVOLUCION INT,
    IN P_MOTIVO_RECHAZO VARCHAR(200)
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);

    -- 1. Validar que la devolución exista
    SELECT ESTADO INTO V_ESTADO_ACTUAL FROM DEVOLUCIONES WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;
    
    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCIÓN NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que la devolución no esté ya procesada (solo se pueden rechazar las pendientes)
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN RECHAZAR DEVOLUCIONES EN ESTADO PENDIENTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Aplicar el rechazo
    UPDATE DEVOLUCIONES 
    SET ESTADO = 'RECHAZADA',
        MOTIVO = CONCAT(MOTIVO, ' | RECHAZO: ', P_MOTIVO_RECHAZO)
    WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;
    
    -- 4. Confirmación
    SELECT 'EXITO: DEVOLUCIÓN RECHAZADA CORRECTAMENTE.' AS MENSAJE;
END;

DELIMITER ;
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_FECHAS_GARANTIA ;
CREATE TRIGGER TR_VALIDAR_FECHAS_GARANTIA
BEFORE INSERT ON GARANTIAS
FOR EACH ROW
BEGIN
    IF NEW.FECHA_INICIO < CURRENT_DATE THEN
        SET NEW.FECHA_INICIO = CURRENT_DATE;
    END IF;
END ;
DELIMITER ;





-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

CREATE OR REPLACE VIEW VISTA_DEVOLUCIONES_PENDIENTES AS
SELECT 
    D.ID_DEVOLUCION,
    D.FECHA,
    V.ID_VENTA,
    P.NOMBRE AS PRODUCTO,
    D.CANTIDAD,
    D.MOTIVO
FROM DEVOLUCIONES D
JOIN DETALLES_VENTA DV ON D.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
JOIN VENTAS V ON DV.ID_VENTA = V.ID_VENTA
JOIN PRODUCTOS P ON DV.ID_PRODUCTO = P.ID_PRODUCTO
WHERE D.ESTADO = 'PENDIENTE';


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------