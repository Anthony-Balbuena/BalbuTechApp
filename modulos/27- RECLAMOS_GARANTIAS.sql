CREATE TABLE RECLAMOS_GARANTIAS (
    ID_RECLAMO_GARAN INT NOT NULL AUTO_INCREMENT,
    ID_GARANTIA INT NOT NULL,
    FECHA_RECLAMO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DESCRIPCION VARCHAR(255) NOT NULL,
    ESTADO ENUM(
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO',
        'CERRADO'
    ) NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_RECLAMO_GARAN),
    CONSTRAINT FK_RECLAMO_GARANTIA FOREIGN KEY (ID_GARANTIA) REFERENCES GARANTIAS (ID_GARANTIA) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE INDEX IX_RECLAMO_GARANTIA_FECHA ON RECLAMOS_GARANTIAS (FECHA_RECLAMO);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER //
DROP PROCEDURE IF EXISTS 27_SP_REGISTRAR_RECLAMO_GARANTIA ;
CREATE PROCEDURE 27_SP_REGISTRAR_RECLAMO_GARANTIA(
    IN P_ID_GARANTIA INT,
    IN P_DESCRIPCION VARCHAR(255)
)
proc_label: BEGIN
    DECLARE V_ESTADO_GARANTIA ENUM('ACTIVA', 'VENCIDA', 'CANCELADA');

    -- 1. Verificar si la garantía está ACTIVA
    SELECT ESTADO INTO V_ESTADO_GARANTIA FROM GARANTIAS WHERE ID_GARANTIA = P_ID_GARANTIA;

    IF V_ESTADO_GARANTIA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_GARANTIA <> 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA GARANTÍA NO ESTÁ ACTIVA Y NO SE PUEDE RECLAMAR.';
        LEAVE proc_label;
    END IF;

    -- 2. Registrar el reclamo
    INSERT INTO RECLAMOS_GARANTIAS (ID_GARANTIA, DESCRIPCION)
    VALUES (P_ID_GARANTIA, P_DESCRIPCION);

    SELECT 'EXITO: RECLAMO REGISTRADO CORRECTAMENTE.' AS MENSAJE;
END ;
DELIMITER ;

USE BALBU_TECH;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_FINALIZAR_RECLAMO_APROBADO;
CREATE TRIGGER TR_FINALIZAR_RECLAMO_APROBADO
AFTER UPDATE ON RECLAMOS_GARANTIAS
FOR EACH ROW
BEGIN
    -- Si el reclamo es aprobado, podemos marcar la garantía como cerrada/finalizada
    IF (NEW.ESTADO = 'APROBADO' AND OLD.ESTADO = 'PENDIENTE') THEN
        UPDATE GARANTIAS 
        SET ESTADO = 'CANCELADA' -- O el estado que prefieras para indicar "garantía agotada"
        WHERE ID_GARANTIA = NEW.ID_GARANTIA;
    END IF;
END;
DELIMITER ;

DELIMITER //

CREATE PROCEDURE 27_SP_FINALIZAR_RECLAMO_TOTAL(IN P_ID_RECLAMO INT)
BEGIN
    -- Declarar manejador de errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- Si algo falla, deshace todo
        RESIGNAL;
    END;

    START TRANSACTION;
        -- 1. Cerrar el reclamo
        UPDATE RECLAMOS_GARANTIAS SET ESTADO = 'CERRADO' WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;
        
        -- 2. Registrar en la auditoría (si tienes la tabla)
        INSERT INTO LOG_AUDITORIA (ACCION, DETALLES) VALUES ('CIERRE_RECLAMO', CONCAT('Reclamo #', P_ID_RECLAMO));
    COMMIT;
END;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

