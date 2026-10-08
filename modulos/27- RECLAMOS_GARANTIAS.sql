/*
TABLA RECLAMOS_GARANTIAS
Guarda los reclamos que se hacen sobre una garantia: que paso, cuando y
en que estado esta el reclamo (pendiente, aprobado, rechazado o cerrado).
*/
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

/*
INDICE IX_RECLAMO_GARANTIA_FECHA
Ordena los reclamos por fecha, asi los mas recientes salen primero
sin recorrer toda la tabla.
*/
CREATE INDEX IX_RECLAMO_GARANTIA_FECHA ON RECLAMOS_GARANTIAS (FECHA_RECLAMO);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER //
DROP PROCEDURE IF EXISTS 27_SP_REGISTRAR_RECLAMO_GARANTIA ;
/*
27_SP_REGISTRAR_RECLAMO_GARANTIA
Registra un reclamo sobre una garantia.
Revisa que la garantia exista y que este ACTIVA; si no, corta con error,
y si esta bien, guarda el reclamo en estado PENDIENTE.
*/
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
END //
DELIMITER ;

USE BALBU_TECH;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_FINALIZAR_RECLAMO_APROBADO;
/*
TR_FINALIZAR_RECLAMO_APROBADO
Cuando un reclamo pasa de PENDIENTE a APROBADO, cancela la garantia.
Sirve para marcar que la garantia ya se uso con ese reclamo.
*/
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
END//
DELIMITER ;

DELIMITER //

/*
27_SP_FINALIZAR_RECLAMO_TOTAL
Cierra un reclamo y deja constancia en la auditoria, todo en una transaccion.
Si algo falla en el camino, deshace todo para no dejar datos a medias.
*/
CREATE PROCEDURE 27_SP_FINALIZAR_RECLAMO_TOTAL(IN P_ID_RECLAMO INT)
BEGIN
    -- Declarar manejador de errores
    DECLARE V_ESTADO_ANT VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- Si algo falla, deshace todo
        RESIGNAL;
    END;

    START TRANSACTION;
        -- 1. Cerrar el reclamo (se guarda el estado previo para auditarlo)
        SELECT ESTADO INTO V_ESTADO_ANT FROM RECLAMOS_GARANTIAS WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;
        UPDATE RECLAMOS_GARANTIAS SET ESTADO = 'CERRADO' WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;
        
        -- 2. Registrar en la auditoria (era LOG_AUDITORIA, inexistente; se usa AUDITORIA_SISTEMA).
        INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
        VALUES ('RECLAMOS_GARANTIAS', P_ID_RECLAMO, 'UPDATE', USER(), V_ESTADO_ANT, 'CERRADO');
    COMMIT;
END//

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

