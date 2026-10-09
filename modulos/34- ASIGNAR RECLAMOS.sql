-- Active: 1775068811273@@127.0.0.1@3306@BALBU_TECH
/*
TABLA ASIGNACIONES_RECLAMOS
Guarda a que tecnico se le asigno cada reclamo de garantia, con su
prioridad, estado de la asignacion y fechas. Un reclamo puede tener
varias asignaciones a lo largo del tiempo.
*/
CREATE TABLE ASIGNACIONES_RECLAMOS (
    ID_ASIGNACION INT NOT NULL AUTO_INCREMENT,
    ID_RECLAMO_GARAN INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA_ASIGNACION TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FECHA_FINALIZACION DATETIME NULL,
    PRIORIDAD ENUM('BAJA', 'MEDIA', 'ALTA', 'URGENTE') DEFAULT 'MEDIA',
    ESTADO_ASIGNACION ENUM('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'CANCELADO') DEFAULT 'PENDIENTE',
    OBSERVACIONES VARCHAR(255),
    PRIMARY KEY (ID_ASIGNACION),
    -- Índices para búsqueda rápida
    INDEX IDX_EMPLEADO_FECHA (ID_EMPLEADO, FECHA_ASIGNACION),
    -- Relaciones
    CONSTRAINT FK_ASIGNACION_RECLAMO FOREIGN KEY (ID_RECLAMO_GARAN) REFERENCES RECLAMOS_GARANTIAS (ID_RECLAMO_GARAN) ON DELETE CASCADE,
    CONSTRAINT FK_ASIGNACION_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

ALTER TABLE ASIGNACIONES_RECLAMOS 
ADD CONSTRAINT IF NOT EXISTS CHK_FECHAS_VALIDAS
CHECK (FECHA_FINALIZACION >= FECHA_ASIGNACION);



/*
INDICE IDX_ASIGNACIONES_EMPLEADO_FECHA
Busca las asignaciones de un empleado por fecha, util para ver la carga
de trabajo de cada tecnico.
*/
CREATE INDEX IDX_ASIGNACIONES_EMPLEADO_FECHA 
ON ASIGNACIONES_RECLAMOS (ID_EMPLEADO, FECHA_ASIGNACION);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

---COMIENZA AISGNACION
DELIMITER //

DROP PROCEDURE IF EXISTS SP_ASIGNAR_TECNICO_RECLAMO; 

/*
SP_ASIGNAR_TECNICO_RECLAMO
Asigna un tecnico a un reclamo que este PENDIENTE.
Revisa que el reclamo exista y no este ya tomado, crea la asignacion en
EN_PROCESO y deja el reclamo en PENDIENTE (su enum no admite EN_PROCESO;
el avance vive en ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION).
*/
CREATE PROCEDURE SP_ASIGNAR_TECNICO_RECLAMO(
    IN P_ID_RECLAMO INT,
    IN P_ID_EMPLEADO INT,
    IN P_PRIORIDAD ENUM('BAJA', 'MEDIA', 'ALTA', 'URGENTE'),
    IN P_OBSERVACIONES VARCHAR(255)
)
proc_label: BEGIN
    DECLARE V_ESTADO_RECLAMO VARCHAR(20);

    -- 1. Validar que el reclamo exista y esté pendiente
    SELECT ESTADO INTO V_ESTADO_RECLAMO 
    FROM RECLAMOS_GARANTIAS 
    WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;

    IF V_ESTADO_RECLAMO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: RECLAMO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_RECLAMO <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN ASIGNAR TÉCNICOS A RECLAMOS PENDIENTES.';
        LEAVE proc_label;
    END IF;

    -- 1b (09/10/2026). El tecnico debe existir (mensaje amable en vez del FK 1452).
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 1c (09/10/2026). Sin doble asignacion en curso para el mismo reclamo.
    IF EXISTS (SELECT 1 FROM ASIGNACIONES_RECLAMOS
                WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO
                  AND ESTADO_ASIGNACION IN ('PENDIENTE', 'EN_PROCESO')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL RECLAMO YA TIENE UNA ASIGNACION EN CURSO.';
        LEAVE proc_label;
    END IF;

    -- 2. Insertar la asignación con la nueva estructura
    INSERT INTO ASIGNACIONES_RECLAMOS (
        ID_RECLAMO_GARAN, 
        ID_EMPLEADO, 
        PRIORIDAD, 
        ESTADO_ASIGNACION, 
        OBSERVACIONES
    )
    VALUES (
        P_ID_RECLAMO, 
        P_ID_EMPLEADO, 
        P_PRIORIDAD, 
        'EN_PROCESO', 
        P_OBSERVACIONES
    );
    
    -- 3. El reclamo sigue PENDIENTE (su ENUM no admite EN_PROCESO; antes este
    -- UPDATE ponia 'EN_PROCESO' y fallaba con ERROR 1265. El avance del trabajo
    -- vive en ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION = 'EN_PROCESO').
    
    SELECT 'EXITO: TÉCNICO ASIGNADO CORRECTAMENTE.' AS MENSAJE;
END//

DELIMITER ;

---FINALIZAR 

DELIMITER //

DROP PROCEDURE IF EXISTS SP_FINALIZAR_RECLAMO;

/*
SP_FINALIZAR_RECLAMO
Cierra la asignacion y el reclamo al mismo tiempo.
Marca la asignacion como COMPLETADO con su fecha final, agrega la nota
final y deja el reclamo en CERRADO.
*/
CREATE PROCEDURE SP_FINALIZAR_RECLAMO(
    IN P_ID_ASIGNACION INT,
    IN P_OBSERVACIONES_FINALES VARCHAR(255)
)
proc_label: BEGIN
    -- BLINDAJE (09/10/2026, patron fase I): 2 UPDATEs atados a la misma suerte.
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ESTADO_ASIG VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 0. La asignacion debe existir y seguir en curso (antes un id malo
    -- dejaba 0 filas tocadas y mentia EXITO).
    SELECT ESTADO_ASIGNACION INTO V_ESTADO_ASIG
      FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    IF V_ESTADO_ASIG IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ASIGNACION NO ENCONTRADA.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_ASIG = 'COMPLETADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA ASIGNACION YA FUE FINALIZADA.';
        LEAVE proc_label;
    END IF;

    -- 1. Actualizamos la asignación
    UPDATE ASIGNACIONES_RECLAMOS 
    SET ESTADO_ASIGNACION = 'COMPLETADO',
        FECHA_FINALIZACION = NOW(),
        OBSERVACIONES = CONCAT(OBSERVACIONES, ' | Nota final: ', P_OBSERVACIONES_FINALES)
    WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    -- 2. Actualizamos el reclamo general a 'CERRADO'
    UPDATE RECLAMOS_GARANTIAS
    SET ESTADO = 'CERRADO'
    WHERE ID_RECLAMO_GARAN = (SELECT ID_RECLAMO_GARAN FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION);

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT 'EXITO: RECLAMO FINALIZADO Y CERRADO.' AS MENSAJE;
END//

DELIMITER ;