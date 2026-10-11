-- 1. Tabla con integridad referencial
/*
TABLA LOG_ACCESOS
Guarda cada intento de acceso al sistema con su fecha y si salio bien o no.
Si el usuario se borra, el registro se queda sin usuario pero no se pierde.
*/
CREATE TABLE LOG_ACCESOS (
    ID_LOG INT PRIMARY KEY AUTO_INCREMENT,
    ID_USUARIO INT,
    FECHA_ACCESO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ESTADO_INTENTO VARCHAR(50),
    CONSTRAINT FK_LOG_USUARIO FOREIGN KEY (ID_USUARIO) 
        REFERENCES USUARIOS (ID_USUARIO) ON DELETE SET NULL
) ENGINE = InnoDB;

-- 2. SP Corregido y limpio
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_ACCESO ;
/*
SP_REGISTRAR_ACCESO
Anota un intento de acceso: quien intento entrar y si fue exitoso o no.
Solo inserta el registro en el log, sin validar nada mas.
*/
CREATE PROCEDURE SP_REGISTRAR_ACCESO(
    IN P_ID_USUARIO INT,
    IN P_ESTADO VARCHAR(50)
)
BEGIN
    INSERT INTO LOG_ACCESOS (ID_USUARIO, ESTADO_INTENTO) 
    VALUES (P_ID_USUARIO, P_ESTADO);
END //
DELIMITER ;
----reporte
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTAR_ACCESOS;
/*
SP_REPORTAR_ACCESOS
Muestra los ultimos 50 intentos de acceso, del mas reciente al mas viejo.
Trae la fecha, el usuario y el resultado, sin saturar el sistema.
*/
CREATE PROCEDURE SP_REPORTAR_ACCESOS()
BEGIN
    SELECT 
        L.FECHA_ACCESO, 
        U.USUARIO, 
        L.ESTADO_INTENTO
    FROM LOG_ACCESOS L
    LEFT JOIN USUARIOS U ON L.ID_USUARIO = U.ID_USUARIO
    ORDER BY L.FECHA_ACCESO DESC
    LIMIT 50; -- Solo los últimos 50 para no sobrecargar el sistema
END //
DELIMITER ;

----limpieza (en uso): borra intentos de más de 120 días
/*
SP_LIMPIAR_LOGS_ANTIGUOS
Limpieza de mantenimiento: conserva los últimos 120 días contando desde
el día que se ejecuta y borra del día 121 para allá. Sin parámetro usa
120. Responde cuántos borró.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LIMPIAR_LOGS_ANTIGUOS //
CREATE PROCEDURE SP_LIMPIAR_LOGS_ANTIGUOS(IN P_DIAS INT DEFAULT 120)
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