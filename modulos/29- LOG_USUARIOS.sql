-- Active: 1775068811273@@127.0.0.1@3306@BALBU_TECH
CREATE TABLE LOG_USUARIOS (
    ID_LOG INT PRIMARY KEY AUTO_INCREMENT,
    ID_USUARIO INT,
    ACCION VARCHAR(50),      -- 'CAMBIO_ROL', 'CAMBIO_ESTADO', 'CAMBIO_USUARIO'
    VALOR_ANTERIOR VARCHAR(255),
    VALOR_NUEVO VARCHAR(255),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ID_USUARIO_ADMIN INT     -- Quién realizó el cambio
);
DESCRIBE USUARIOS;
----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS SP_OBTENER_LOG_USUARIOS;
CREATE PROCEDURE SP_OBTENER_LOG_USUARIOS()
BEGIN
    SELECT * FROM VIEW_HISTORIAL_CAMBIOS_USUARIOS LIMIT 100;
END;
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TRG_AUDITORIA_USUARIOS ;
CREATE TRIGGER TRG_AUDITORIA_USUARIOS
AFTER UPDATE ON USUARIOS
FOR EACH ROW
BEGIN
    -- Auditoría de Cambio de Rol
    IF OLD.ID_ROL <> NEW.ID_ROL THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ROL', CAST(OLD.ID_ROL AS CHAR), CAST(NEW.ID_ROL AS CHAR));
    END IF;

    -- Auditoría de Cambio de Estado
    IF OLD.ESTADO <> NEW.ESTADO THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ESTADO', OLD.ESTADO, NEW.ESTADO);
    END IF;
END;
DELIMITER ;





-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
CREATE OR REPLACE VIEW VIEW_HISTORIAL_CAMBIOS_USUARIOS AS
SELECT 
    L.ID_LOG,
    U.USUARIO AS USUARIO_AFECTADO, -- Aquí estaba el error
    L.ACCION,
    L.VALOR_ANTERIOR,
    L.VALOR_NUEVO,
    L.FECHA_CAMBIO
FROM LOG_USUARIOS L
INNER JOIN USUARIOS U ON L.ID_USUARIO = U.ID_USUARIO
ORDER BY L.FECHA_CAMBIO DESC;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
