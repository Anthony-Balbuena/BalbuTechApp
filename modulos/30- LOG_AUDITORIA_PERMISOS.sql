/*
TABLA LOG_AUDITORIA_PERMISOS
Guarda cada cambio de estado de un permiso: el anterior, el nuevo y cuando
paso. Sirve como bitacora de auditoria sobre los permisos de empleados.
*/
CREATE TABLE LOG_AUDITORIA_PERMISOS (
    ID_LOG INT AUTO_INCREMENT PRIMARY KEY,
    ID_PERMISO INT,
    ESTADO_ANTERIOR VARCHAR(20),
    ESTADO_NUEVO VARCHAR(20),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_LOG_PERMISO FOREIGN KEY (ID_PERMISO) 
        REFERENCES PERMISOS_EMPLEADOS(ID_PERMISO) ON DELETE CASCADE
) ENGINE = InnoDB;

-- Trigger que registra cada vez que se gestiona un permiso
/*
TR_LOG_GESTION_PERMISO
Cada vez que cambia el estado de un permiso, lo anota en la bitacora.
Si el estado no cambio, no registra nada.
*/
DELIMITER //
DROP TRIGGER IF EXISTS TR_LOG_GESTION_PERMISO ;
CREATE TRIGGER TR_LOG_GESTION_PERMISO
AFTER UPDATE ON PERMISOS_EMPLEADOS
FOR EACH ROW
BEGIN
    IF OLD.ESTADO <> NEW.ESTADO THEN
        INSERT INTO LOG_AUDITORIA_PERMISOS (ID_PERMISO, ESTADO_ANTERIOR, ESTADO_NUEVO)
        VALUES (NEW.ID_PERMISO, OLD.ESTADO, NEW.ESTADO);
    END IF;
END //
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