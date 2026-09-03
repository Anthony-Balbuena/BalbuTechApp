-- 1. Estructura de la Tabla
CREATE TABLE HISTORIAL_ESTADOS_PRODUCTO (
    ID_HISTORIAL INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL,
    ESTADO_ANTERIOR ENUM('ACTIVO', 'INACTIVO'),
    MOTIVO_CAMBIO VARCHAR(255),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_HISTORIAL),
    CONSTRAINT FK_HISTORIAL_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_HISTORIAL_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- 2. Índices para optimizar consultas de auditoría
CREATE INDEX HISTORIAL_ESTADOS_PRODUCTO_FECHACAMBIO ON HISTORIAL_ESTADOS_PRODUCTO (FECHA_CAMBIO);
CREATE INDEX IX_HISTORIAL_ESTADO_ACTUAL ON HISTORIAL_ESTADOS_PRODUCTO (ESTADO);
CREATE INDEX IX_HISTORIAL_ESTADO_ANTERIOR ON HISTORIAL_ESTADOS_PRODUCTO (ESTADO_ANTERIOR);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS 18_SP_CAMBIAR_ESTADO_PRODUCTO //
CREATE PROCEDURE 18_SP_CAMBIAR_ESTADO_PRODUCTO(
    IN P_ID_PRODUCTO INT,
    IN P_ID_EMPLEADO INT,
    IN P_NUEVO_ESTADO ENUM('ACTIVO', 'INACTIVO'),
    IN P_MOTIVO VARCHAR(255)
)
BEGIN
    -- 1. Definir las variables que el Trigger usará
    SET @ID_EMPLEADO_ACTUAL = P_ID_EMPLEADO;
    SET @MOTIVO_CAMBIO = P_MOTIVO;

    -- 2. Realizar la actualización. 
    -- El Trigger 'TR_LOG_CAMBIO_ESTADO_PRODUCTO' se disparará automáticamente aquí
    UPDATE PRODUCTOS 
    SET ESTADO = P_NUEVO_ESTADO 
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    
    -- 3. Limpiar variables de sesión para evitar conflictos
    SET @ID_EMPLEADO_ACTUAL = NULL;
    SET @MOTIVO_CAMBIO = NULL;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_LOG_CAMBIO_ESTADO_PRODUCTO //
CREATE TRIGGER TR_LOG_CAMBIO_ESTADO_PRODUCTO
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
BEGIN
    -- Solo registramos si hubo un cambio real en el estado
    IF OLD.ESTADO <> NEW.ESTADO THEN
        INSERT INTO HISTORIAL_ESTADOS_PRODUCTO (
            ID_PRODUCTO, 
            ID_EMPLEADO, 
            ESTADO, 
            ESTADO_ANTERIOR,
            MOTIVO_CAMBIO
        )
        VALUES (
            NEW.ID_PRODUCTO,
            -- Asegúrate de que esta variable esté definida en tu sesión antes de la actualización
            IFNULL(@ID_EMPLEADO_ACTUAL, 1), 
            NEW.ESTADO,
            OLD.ESTADO,
            -- Registramos el motivo enviado desde la app a través de una variable de sesión
            IFNULL(@MOTIVO_CAMBIO, 'Cambio de estado automático')
        );
    END IF;
END //
DELIMITER ;





----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


CREATE OR REPLACE VIEW VISTA_ULTIMOS_MOVIMIENTOS AS
SELECT 
    H.FECHA_CAMBIO,
    P.NOMBRE AS PRODUCTO,
    H.MOTIVO_CAMBIO
FROM HISTORIAL_ESTADOS_PRODUCTO H
JOIN PRODUCTOS P ON H.ID_PRODUCTO = P.ID_PRODUCTO
ORDER BY H.FECHA_CAMBIO DESC
LIMIT 10;





-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------