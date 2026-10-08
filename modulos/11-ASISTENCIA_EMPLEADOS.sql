/*
TABLA ASISTENCIA_EMPLEADOS
Guarda la asistencia diaria de cada empleado: fecha, hora de entrada, hora
de salida y las horas trabajadas (que se calculan solas al cerrar el dia).
Un empleado solo puede tener un registro por dia y el estado sale como
PRESENTE, AUSENTE, TARDE o PERMISO.
*/
CREATE TABLE ASISTENCIA_EMPLEADOS (
    ID_ASISTENCIA INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL,
    HORA_ENTRADA TIME NOT NULL,
    HORA_SALIDA TIME,
    -- Calculamos la diferencia en minutos y dividimos por 60 para tener horas decimales
    HORAS_TRABAJADAS DECIMAL(5, 2) AS (
        CASE
            WHEN HORA_SALIDA IS NULL THEN NULL
            ELSE TIMESTAMPDIFF(
                MINUTE,
                HORA_ENTRADA,
                HORA_SALIDA
            ) / 60.0
        END
    ) STORED, 
    ESTADO ENUM(
        'PRESENTE',
        'AUSENTE',
        'TARDE',
        'PERMISO'
    ) NOT NULL DEFAULT 'PRESENTE',
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_ASISTENCIA),
    CONSTRAINT UQ_ASISTENCIA_DIA UNIQUE (ID_EMPLEADO, FECHA),
    CONSTRAINT FK_ASISTENCIA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

/*
ÍNDICE IX_ASISTENCIA_FECHA
Facilita las búsquedas de asistencia por fecha, por ejemplo, para consultar
la asistencia del día actual o de un mes específico.
*/
CREATE INDEX IX_ASISTENCIA_FECHA ON ASISTENCIA_EMPLEADOS (FECHA);

/*
ÍNDICE IX_ASISTENCIA_EMPLEADO
Facilita la consulta del historial de asistencia y puntualidad de un empleado
a partir de su ID_EMPLEADO.
*/
CREATE INDEX IX_ASISTENCIA_EMPLEADO ON ASISTENCIA_EMPLEADOS (ID_EMPLEADO);

/*
ÍNDICE IX_ASISTENCIA_ESTADO
Facilita la búsqueda y generación de reportes agrupados por estado de
asistencia, como PRESENTE, AUSENTE, TARDE o PERMISO.
*/
CREATE INDEX IX_ASISTENCIA_ESTADO ON ASISTENCIA_EMPLEADOS (ESTADO);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------                


---ENTRADE DE EMPLEADO 

/*
SP_REGISTRAR_ASISTENCIA
Registra la entrada o la salida del empleado con la fecha y hora actuales.
Antes revisa que el empleado no tenga vacaciones ni un permiso aprobado
para hoy; si tiene alguno de los dos no deja registrar y manda error.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_ASISTENCIA ;
CREATE PROCEDURE SP_REGISTRAR_ASISTENCIA(
    IN P_ID_EMPLEADO INT,
    IN P_TIPO_MOVIMIENTO ENUM('ENTRADA', 'SALIDA')
)
proc_label: BEGIN
    -- 1. VALIDAR SI TIENE PERMISO APROBADO HOY
    IF EXISTS (
        SELECT 1 FROM PERMISOS_EMPLEADOS 
        WHERE ID_EMPLEADO = P_ID_EMPLEADO 
        AND CURDATE() BETWEEN FECHA_INICIO AND FECHA_FIN
        AND ESTADO = 'APROBADO'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO CON PERMISO APROBADO. NO REQUIERE REGISTRO DE ASISTENCIA.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDAR SI TIENE VACACIONES
    IF EXISTS (
        SELECT 1 FROM VACACIONES_EMPLEADOS 
        WHERE ID_EMPLEADO = P_ID_EMPLEADO 
        AND CURDATE() BETWEEN FECHA_INICIO AND FECHA_FIN
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO DE VACACIONES. NO REQUIERE REGISTRO DE ASISTENCIA.';
        LEAVE proc_label;
    END IF;

    -- 3. SI PASA TODO, REGISTRAMOS EN ASISTENCIA_EMPLEADOS (era tabla ASISTENCIA, no existe).
    -- ENTRADA crea la fila del dia; SALIDA le pone la hora de salida (igual que 11_SP_REGISTRAR_SALIDA).
    IF P_TIPO_MOVIMIENTO = 'ENTRADA' THEN
        INSERT INTO ASISTENCIA_EMPLEADOS (ID_EMPLEADO, FECHA, HORA_ENTRADA, ESTADO)
        VALUES (P_ID_EMPLEADO, CURDATE(), CURTIME(), 'PRESENTE');
    ELSE
        UPDATE ASISTENCIA_EMPLEADOS
        SET HORA_SALIDA = CURTIME()
        WHERE ID_EMPLEADO = P_ID_EMPLEADO
          AND FECHA = CURDATE();
    END IF;

    SELECT 'EXITO: ASISTENCIA REGISTRADA.' AS MENSAJE;
END //
DELIMITER ;



---Salida

/*
11_SP_REGISTRAR_SALIDA
Cierra la jornada del empleado: le pone la hora de salida actual al
registro de asistencia de hoy. Si el empleado hoy no tiene registro, no
se modifica nada.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS 11_SP_REGISTRAR_SALIDA;
CREATE PROCEDURE 11_SP_REGISTRAR_SALIDA(
    IN P_ID_EMPLEADO INT
)
BEGIN
    UPDATE ASISTENCIA_EMPLEADOS
    SET HORA_SALIDA = CURRENT_TIME
    WHERE ID_EMPLEADO = P_ID_EMPLEADO 
      AND FECHA = CURRENT_DATE;
END //
DELIMITER ;


---TARDANZA JUSTIFICADA 

/*
11_SP_JUSTIFICAR_ASISTENCIA
Justifica o corrige la asistencia de un empleado en una fecha: cambia el
estado (PRESENTE, AUSENTE, TARDE o PERMISO) y guarda el motivo en la
observacion. Si para ese dia no hay registro, manda error.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS 11_SP_JUSTIFICAR_ASISTENCIA ;
CREATE PROCEDURE 11_SP_JUSTIFICAR_ASISTENCIA(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA DATE,
    IN P_NUEVO_ESTADO ENUM('PRESENTE', 'AUSENTE', 'TARDE', 'PERMISO'),
    IN P_JUSTIFICACION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Validar que el registro exista
    IF NOT EXISTS (SELECT 1 FROM ASISTENCIA_EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = P_FECHA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO EXISTE REGISTRO PARA ESTE EMPLEADO EN LA FECHA.';
        LEAVE proc_label;
    END IF;

    -- 2. Actualizar estado y guardar la razón detallada
    -- Usamos CONCAT para que quede claro qué se justificó
    UPDATE ASISTENCIA_EMPLEADOS
    SET ESTADO = P_NUEVO_ESTADO,
        OBSERVACION = CONCAT('JUSTIFICACIÓN: ', P_JUSTIFICACION)
    WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = P_FECHA;

    -- 3. Mensaje de éxito
    SELECT CONCAT('EXITO: ASISTENCIA DE ID ', P_ID_EMPLEADO, ' JUSTIFICADA COMO ', P_NUEVO_ESTADO) AS MENSAJE;
END //
DELIMITER ;

---REPORTE DE AISTENCIA POR EMPLEADO 

/*
11_SP_REPORTE_ASISTENCIA_INDIVIDUAL
Reporte de asistencia de un empleado en un periodo: fecha, entradas,
salidas, horas trabajadas y estado de cada dia, del dia mas reciente al
mas antiguo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS 11_SP_REPORTE_ASISTENCIA_INDIVIDUAL ;
CREATE PROCEDURE 11_SP_REPORTE_ASISTENCIA_INDIVIDUAL(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA_INICIO DATE,
    IN P_FECHA_FIN DATE
)
BEGIN
    SELECT 
        FECHA,
        HORA_ENTRADA,
        HORA_SALIDA,
        HORAS_TRABAJADAS,
        ESTADO
    FROM ASISTENCIA_EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO
      AND FECHA BETWEEN P_FECHA_INICIO AND P_FECHA_FIN
    ORDER BY FECHA DESC;
END //
DELIMITER ;


---BLOQUEAR

/*
11_SP_BLOQUEAR_EDICION_ANTIGUA
Control de seguridad para editar asistencia: si la fecha tiene mas de siete
dias de antiguedad bloquea la operacion con un error; si esta dentro del
periodo permitido responde ACCESO PERMITIDO.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS 11_SP_BLOQUEAR_EDICION_ANTIGUA //
CREATE PROCEDURE 11_SP_BLOQUEAR_EDICION_ANTIGUA(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA DATE
)
proc_label: BEGIN
    -- Si la fecha es mayor a 7 días atrás, bloqueamos la edición
    IF P_FECHA < (CURRENT_DATE - INTERVAL 7 DAY) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: SEGURIDAD BLOQUEA LA EDICIÓN DE FECHAS SUPERIORES A 7 DÍAS.';
        LEAVE proc_label;
    END IF;
    
    SELECT 'ACCESO PERMITIDO' AS ESTADO;
END //

DELIMITER ;


----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

/*
TR_BLOQUEAR_ASISTENCIA_INAPROPIADA
Antes de insertar una asistencia revisa que el empleado no este de
vacaciones ni con permiso aprobado para hoy; si esta en una de esas dos
situaciones bloquea el registro con un error. Trabaja en automatico.
*/


DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_ASISTENCIA_INAPROPIADA //
CREATE TRIGGER TR_BLOQUEAR_ASISTENCIA_INAPROPIADA
BEFORE INSERT ON ASISTENCIA_EMPLEADOS
FOR EACH ROW
BEGIN
    -- 1. Verificar si tiene Vacaciones
    IF EXISTS (
        SELECT 1 FROM VACACIONES_EMPLEADOS 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO 
        AND CURDATE() BETWEEN FECHA_INICIO AND FECHA_FIN
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: REGISTRO DENEGADO. EL EMPLEADO SE ENCUENTRA DE VACACIONES.';
    END IF;

    -- 2. Verificar si tiene Permiso Aprobado
    IF EXISTS (
        SELECT 1 FROM PERMISOS_EMPLEADOS 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO 
        AND CURDATE() BETWEEN FECHA_INICIO AND FECHA_FIN
        AND ESTADO = 'APROBADO'
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: REGISTRO DENEGADO. EL EMPLEADO TIENE UN PERMISO APROBADO.';
    END IF;
END //
DELIMITER ;