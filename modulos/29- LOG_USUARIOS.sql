-- Active: 1775068811273@@127.0.0.1@3306@BALBU_TECH
/*
TABLA LOG_USUARIOS
Bitacora de los cambios que se hacen a los usuarios: cambio de rol, de
estado o de usuario, con el valor anterior, el nuevo, quien lo hizo y cuando.
*/
CREATE TABLE LOG_USUARIOS (
    ID_LOG INT PRIMARY KEY AUTO_INCREMENT,
    ID_USUARIO INT,
    ACCION VARCHAR(50),      -- 'CAMBIO_ROL', 'CAMBIO_ESTADO', 'CAMBIO_USUARIO'
    VALOR_ANTERIOR VARCHAR(255),
    VALOR_NUEVO VARCHAR(255),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ID_USUARIO_ADMIN INT,     -- Quién realizó el cambio
    CONSTRAINT FK_LOG_USUARIOS_USUARIO FOREIGN KEY (ID_USUARIO) REFERENCES USUARIOS (ID_USUARIO),
    CONSTRAINT FK_LOG_USUARIOS_ADMIN FOREIGN KEY (ID_USUARIO_ADMIN) REFERENCES USUARIOS (ID_USUARIO)
);
DESCRIBE USUARIOS;
----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS SP_OBTENER_LOG_USUARIOS;
/*
SP_OBTENER_LOG_USUARIOS
Trae los ultimos 100 cambios de usuarios desde la vista de historial,
del cambio mas reciente al mas viejo.
*/
CREATE PROCEDURE SP_OBTENER_LOG_USUARIOS()
BEGIN
    SELECT * FROM VIEW_HISTORIAL_CAMBIOS_USUARIOS LIMIT 100;
END//
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TRG_AUDITORIA_USUARIOS ;
/*
TRG_AUDITORIA_USUARIOS
Cada vez que se modifica un usuario, revisa si cambio el rol, el estado o
el nombre. Si cambio alguno, guarda el valor anterior, el nuevo y quien lo
hizo en LOG_USUARIOS. El admin sale de @ID_USUARIO_ACTUAL, que la app deja
en la conexion al iniciar sesion; si no esta, queda NULL.
*/
CREATE TRIGGER TRG_AUDITORIA_USUARIOS
AFTER UPDATE ON USUARIOS
FOR EACH ROW
BEGIN
    DECLARE v_admin INT DEFAULT NULL;

    -- (25/10/2026) Si el id no existe, NULL: el log no tumba el cambio.
    SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL);

    -- Auditoría de Cambio de Rol
    IF NOT (OLD.ID_ROL <=> NEW.ID_ROL) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ROL', CAST(OLD.ID_ROL AS CHAR), CAST(NEW.ID_ROL AS CHAR), v_admin);
    END IF;

    -- Auditoría de Cambio de Estado
    IF NOT (OLD.ESTADO <=> NEW.ESTADO) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ESTADO', OLD.ESTADO, NEW.ESTADO, v_admin);
    END IF;

    -- Auditoría de Cambio de Nombre de Usuario
    IF NOT (OLD.USUARIO <=> NEW.USUARIO) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_USUARIO', OLD.USUARIO, NEW.USUARIO, v_admin);
    END IF;
END//
DELIMITER ;





-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
/*
VIEW_HISTORIAL_CAMBIOS_USUARIOS
Muestra los cambios de usuarios con el nombre del afectado y el del admin
que los hizo. LEFT JOIN: si una cuenta se borra, el registro no desaparece.
*/
CREATE OR REPLACE VIEW VIEW_HISTORIAL_CAMBIOS_USUARIOS AS
SELECT 
    L.ID_LOG,
    U.USUARIO AS USUARIO_AFECTADO,
    L.ACCION,
    L.VALOR_ANTERIOR,
    L.VALOR_NUEVO,
    L.FECHA_CAMBIO,
    L.ID_USUARIO_ADMIN,
    A.USUARIO AS USUARIO_ADMIN
FROM LOG_USUARIOS L
LEFT JOIN USUARIOS U ON L.ID_USUARIO = U.ID_USUARIO
LEFT JOIN USUARIOS A ON L.ID_USUARIO_ADMIN = A.ID_USUARIO
ORDER BY L.FECHA_CAMBIO DESC;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
