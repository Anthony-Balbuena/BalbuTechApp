-- 1. Tabla con integridad referencial
/*
TABLA LOG_ACCESOS
Guarda cada intento de acceso al sistema con su fecha y el resultado.
USUARIO_INTENTADO conserva el nombre tecleado aunque la cuenta no exista.
Si el usuario se borra, el registro se queda sin ID pero no se pierde.
*/
CREATE TABLE LOG_ACCESOS (
    ID_LOG INT PRIMARY KEY AUTO_INCREMENT,
    ID_USUARIO INT,
    USUARIO_INTENTADO VARCHAR(50) NOT NULL,
    FECHA_ACCESO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ESTADO_INTENTO ENUM('EXITOSO', 'FALLIDO', 'INACTIVO') NOT NULL,
    CONSTRAINT FK_LOG_USUARIO FOREIGN KEY (ID_USUARIO)
        REFERENCES USUARIOS (ID_USUARIO) ON DELETE SET NULL
) ENGINE = InnoDB;

-- 2. SP que usa login.cpp en cada intento
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_ACCESO ;
/*
SP_REGISTRAR_ACCESO
Anota un intento de acceso: quien lo intento y como termino. El usuario es
obligatorio y el estado solo admite EXITOSO, FALLIDO o INACTIVO.
*/
CREATE PROCEDURE SP_REGISTRAR_ACCESO(
    IN P_ID_USUARIO INT,
    IN P_USUARIO_INTENTADO VARCHAR(50),
    IN P_ESTADO VARCHAR(20)
)
BEGIN
    IF P_USUARIO_INTENTADO IS NULL OR TRIM(P_USUARIO_INTENTADO) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL USUARIO ES OBLIGATORIO.';
    END IF;
    IF P_ESTADO NOT IN ('EXITOSO', 'FALLIDO', 'INACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTADO DE INTENTO INVALIDO.';
    END IF;
    INSERT INTO LOG_ACCESOS (ID_USUARIO, USUARIO_INTENTADO, ESTADO_INTENTO)
    VALUES (P_ID_USUARIO, TRIM(P_USUARIO_INTENTADO), P_ESTADO);
END //
DELIMITER ;
----reporte
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTAR_ACCESOS;
/*
SP_REPORTAR_ACCESOS
Muestra los ultimos 50 intentos de acceso, del mas reciente al mas viejo.
Trae la fecha, el usuario intentado y el resultado. Sin JOIN: el nombre vive
en el propio log y sobrevive al borrado de la cuenta.
*/
CREATE PROCEDURE SP_REPORTAR_ACCESOS()
BEGIN
    SELECT
        FECHA_ACCESO,
        USUARIO_INTENTADO,
        ESTADO_INTENTO
    FROM LOG_ACCESOS
    ORDER BY FECHA_ACCESO DESC, ID_LOG DESC
    LIMIT 50; -- Solo los últimos 50 para no sobrecargar el sistema
END //
DELIMITER ;

----limpieza (en uso): borra intentos de mas de P_DIAS dias
/*
SP_LIMPIAR_LOGS_ANTIGUOS
Limpieza de mantenimiento: conserva los ultimos P_DIAS dias contando desde
el dia que se ejecuta y borra del dia siguiente para alla. P_DIAS es
obligatorio y debe ser mayor a cero. Responde cuantos borro.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LIMPIAR_LOGS_ANTIGUOS //
CREATE PROCEDURE SP_LIMPIAR_LOGS_ANTIGUOS(IN P_DIAS INT)
BEGIN
    DECLARE V_BORRADOS INT;
    -- (10/10/2026) Días positivos: con 0 o negativo el corte es hoy/futuro
    -- y borraría todo.
    IF IFNULL(P_DIAS, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LOS DIAS DEBEN SER MAYORES A CERO.';
    END IF;
    DELETE FROM LOG_ACCESOS
    WHERE FECHA_ACCESO < CURDATE() - INTERVAL P_DIAS DAY;
    SET V_BORRADOS = ROW_COUNT();
    SELECT CONCAT('LIMPIEZA COMPLETADA: ', V_BORRADOS, ' REGISTROS DE MAS DE ', P_DIAS, ' DIAS ELIMINADOS.') AS MENSAJE;
END//
DELIMITER ;




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------







-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------