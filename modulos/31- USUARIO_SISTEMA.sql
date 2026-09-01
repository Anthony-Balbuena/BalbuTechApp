-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
CREATE TABLE USUARIOS_SISTEMA (
    ID_USUARIO INT PRIMARY KEY AUTO_INCREMENT,
    USERNAME VARCHAR(50) UNIQUE NOT NULL,
    PASSWORD_HASH VARCHAR(255) NOT NULL, -- Siempre guarda hashes, nunca texto plano
    ROL ENUM('ADMIN', 'RRHH', 'EMPLEADO') NOT NULL,
    ESTADO_CUENTA ENUM('ACTIVO', 'INACTIVO') DEFAULT 'ACTIVO',
    ID_EMPLEADO INT,
    CONSTRAINT FK_USER_EMP FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS(ID_EMPLEADO)
);

use BALBU_TECH;
-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
select * from USUARIOS_SISTEMA;
--CREAR
-- Crea un usuario del sistema para un empleado, validando que no tenga ya una cuenta.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_CREAR_USUARIO;
CREATE PROCEDURE SP_CREAR_USUARIO(
    IN P_USERNAME VARCHAR(50),
    IN P_PASSWORD_HASH VARCHAR(255),
    IN P_ROL VARCHAR(20),
    IN P_ID_EMPLEADO INT
)
BEGIN
    -- Validamos si el empleado ya tiene usuario asignado
    IF EXISTS (SELECT 1 FROM USUARIOS_SISTEMA WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SELECT 'ERROR: ESTE EMPLEADO YA TIENE UN USUARIO ASIGNADO.' AS MENSAJE;
    ELSE
        INSERT INTO USUARIOS_SISTEMA (USERNAME, PASSWORD_HASH, ROL, ID_EMPLEADO)
        VALUES (P_USERNAME, P_PASSWORD_HASH, P_ROL, P_ID_EMPLEADO);
        SELECT 'EXITO: USUARIO REGISTRADO CORRECTAMENTE.' AS MENSAJE;
    END IF;
END ;
DELIMITER ;


-- Valida las credenciales del usuario y devuelve si el acceso es correcto, activo y autorizado.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LOGIN_USUARIO ;
CREATE PROCEDURE SP_LOGIN_USUARIO(
    IN P_USERNAME VARCHAR(50),
    IN P_PASSWORD_HASH VARCHAR(255)
)
BEGIN
    DECLARE v_id INT;
    DECLARE v_rol VARCHAR(20);

    -- Buscamos el usuario con el hash proporcionado
    SELECT ID_USUARIO, ROL INTO v_id, v_rol 
    FROM USUARIOS_SISTEMA 
    WHERE USERNAME = P_USERNAME AND PASSWORD_HASH = P_PASSWORD_HASH 
    AND ESTADO_CUENTA = 'ACTIVO';

    IF v_id IS NOT NULL THEN
        SELECT 'EXITO' AS ESTADO, v_rol AS ROL, v_id AS ID_USUARIO;
    ELSE
        SELECT 'ERROR' AS ESTADO, NULL AS ROL, NULL AS ID_USUARIO;
    END IF;
END ;
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
-- Bloquea automáticamente la cuenta del sistema cuando un empleado queda inactivo por liquidación.
DELIMITER //

DROP TRIGGER IF EXISTS TR_DESACTIVAR_USUARIO_POST_LIQUIDACION ;

CREATE TRIGGER TR_DESACTIVAR_USUARIO_POST_LIQUIDACION
AFTER UPDATE ON EMPLEADOS
FOR EACH ROW
BEGIN
    IF NEW.ESTADO = 'INACTIVO' AND OLD.ESTADO = 'ACTIVO' THEN
        
        -- 1. Desactivar cuenta
        UPDATE USUARIOS_SISTEMA 
        SET ESTADO_CUENTA = 'INACTIVO'
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO;
        
        -- 2. Registrar en log (usando ID_USUARIO en lugar de USERNAME)
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO)
        SELECT ID_USUARIO, 'BLOQUEO_AUTO_POR_LIQUIDACION', 'ACTIVO', 'INACTIVO'
        FROM USUARIOS_SISTEMA 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO;
        
    END IF;
END;

DELIMITER ;






-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Evalúa si un usuario específico tiene acceso a una acción del sistema según su rol.
DELIMITER //

DROP FUNCTION IF EXISTS FN_TIENE_PERMISO ;

CREATE FUNCTION FN_TIENE_PERMISO(P_USERNAME VARCHAR(50), P_ACCION VARCHAR(20))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE v_rol VARCHAR(20);
    SELECT ROL INTO v_rol FROM USUARIOS_SISTEMA WHERE USERNAME = P_USERNAME;
    
    IF P_ACCION = 'REGISTRAR_BONO' AND (v_rol = 'ADMIN' OR v_rol = 'RRHH') THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END ;

DELIMITER ;