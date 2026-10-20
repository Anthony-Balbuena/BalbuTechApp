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
    -- (10/10/2026) Hora tope de llegada 08:30 (cambiar aquí si cambia el horario).
    DECLARE V_HORA_SALIDA TIME;
    -- 1. VALIDAR SI TIENE PERMISO APROBADO HOY
    -- (OJO: aqui CURDATE() esta bien: este SP siempre registra con FECHA = hoy.)
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
    -- 3b (09/10/2026). Sin doble ENTRADA el mismo dia (mensaje amable en vez del 1062 del UNIQUE).
    IF P_TIPO_MOVIMIENTO = 'ENTRADA'
       AND EXISTS (SELECT 1 FROM ASISTENCIA_EMPLEADOS
                    WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = CURDATE()) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA TIENE REGISTRO DE ENTRADA HOY.';
        LEAVE proc_label;
    END IF;
    IF P_TIPO_MOVIMIENTO = 'ENTRADA' THEN
        -- (10/10/2026) Después de las 08:30 queda TARDE, no PRESENTE.
        INSERT INTO ASISTENCIA_EMPLEADOS (ID_EMPLEADO, FECHA, HORA_ENTRADA, ESTADO)
        VALUES (P_ID_EMPLEADO, CURDATE(), CURTIME(), IF(CURTIME() > '08:30:00', 'TARDE', 'PRESENTE'));
    ELSE
        SELECT HORA_SALIDA INTO V_HORA_SALIDA FROM ASISTENCIA_EMPLEADOS
         WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = CURDATE();
        -- 3c (09/10/2026). SALIDA sin ENTRADA no dice EXITO falso.
        IF V_HORA_SALIDA IS NULL
           AND NOT EXISTS (SELECT 1 FROM ASISTENCIA_EMPLEADOS
                            WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = CURDATE()) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO TIENE REGISTRO DE ENTRADA HOY.';
            LEAVE proc_label;
        END IF;
        -- (10/10/2026) Segunda SALIDA no pisa la primera.
        IF V_HORA_SALIDA IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA TIENE SALIDA REGISTRADA HOY.';
            LEAVE proc_label;
        END IF;
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
    DECLARE V_HORA_SALIDA TIME;
    SELECT HORA_SALIDA INTO V_HORA_SALIDA FROM ASISTENCIA_EMPLEADOS
     WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = CURRENT_DATE;
    -- (09/10/2026). SALIDA sin ENTRADA: avisar en vez de callar.
    IF V_HORA_SALIDA IS NULL
       AND NOT EXISTS (SELECT 1 FROM ASISTENCIA_EMPLEADOS
                        WHERE ID_EMPLEADO = P_ID_EMPLEADO AND FECHA = CURRENT_DATE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO TIENE REGISTRO DE ENTRADA HOY.';
    END IF;
    -- (10/10/2026). Segunda SALIDA no pisa la primera.
    IF V_HORA_SALIDA IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA TIENE SALIDA REGISTRADA HOY.';
    END IF;
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
    -- (09/10/2026) NEW.FECHA en vez de CURDATE(): con otra fecha el chequeo se saltaba.
    IF EXISTS (
        SELECT 1 FROM VACACIONES_EMPLEADOS 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO 
        AND NEW.FECHA BETWEEN FECHA_INICIO AND FECHA_FIN
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: REGISTRO DENEGADO. EL EMPLEADO SE ENCUENTRA DE VACACIONES.';
    END IF;

    -- 2. Verificar si tiene Permiso Aprobado
    IF EXISTS (
        SELECT 1 FROM PERMISOS_EMPLEADOS 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO 
        AND NEW.FECHA BETWEEN FECHA_INICIO AND FECHA_FIN
        AND ESTADO = 'APROBADO'
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: REGISTRO DENEGADO. EL EMPLEADO TIENE UN PERMISO APROBADO.';
    END IF;
END //
DELIMITER ;

/*
SP: 11_SP_RESUMEN_ASISTENCIA_MES  (17/10/2026 - asistencia v2)
Resumen de un empleado en un mes (AAAA-MM): dias marcados, horas,
tardanzas. Util para cerrar nomina.
Devuelve 1 fila (0 si el empleado no marcó ese mes).
*/

DELIMITER //

DROP PROCEDURE IF EXISTS 11_SP_RESUMEN_ASISTENCIA_MES //
CREATE PROCEDURE 11_SP_RESUMEN_ASISTENCIA_MES(
    IN P_ID_EMPLEADO INT,
    IN P_MES VARCHAR(7)        -- 'AAAA-MM'
)
BEGIN
    -- Dias marcados en el mes (cualquier estado)
    SELECT
        COUNT(*)                                        AS DIAS_MARCADOS,
        IFNULL(SUM(HORAS_TRABAJADAS), 0)               AS HORAS_TOTALES,
        IFNULL(SUM(ESTADO = 'TARDE'), 0)               AS TARDANZAS,
        IFNULL(SUM(ESTADO = 'AUSENTE'), 0)             AS AUSENCIAS,
        IFNULL(SUM(ESTADO = 'PERMISO'), 0)             AS PERMISOS,
        IFNULL(SUM(ESTADO = 'PRESENTE'), 0)            AS PRESENCIAS
    FROM ASISTENCIA_EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO
      AND DATE_FORMAT(FECHA, '%Y-%m') = P_MES;
END //

DELIMITER ;


/*
SP: 11_SP_ASISTENCIA_HOY  (17/10/2026 - asistencia v2)
Lista a todos los empleados activos con su estado del dia dado
(por defecto HOY): PRESENTE / TARDE / PERMISO / AUSENTE.
Si no hay fila en ASISTENCIA ese dia se marca AUSENTE.
Devuelve 1 fila por empleado activo.
*/

DELIMITER //

DROP PROCEDURE IF EXISTS 11_SP_ASISTENCIA_HOY //
CREATE PROCEDURE 11_SP_ASISTENCIA_HOY(
    IN P_FECHA DATE              -- NULL = hoy
)
BEGIN
    DECLARE V_FECHA DATE;
    SET V_FECHA = IFNULL(P_FECHA, CURDATE());

    SELECT
        E.ID_EMPLEADO,
        E.NOMBRE,
        E.CARGO,
        IFNULL(A.ESTADO, 'AUSENTE')        AS ESTADO,
        A.HORA_ENTRADA,
        A.HORA_SALIDA,
        IFNULL(A.HORAS_TRABAJADAS, 0)      AS HORAS
    FROM EMPLEADOS E
    LEFT JOIN ASISTENCIA_EMPLEADOS A
           ON A.ID_EMPLEADO = E.ID_EMPLEADO
          AND A.FECHA = V_FECHA
    WHERE E.ESTADO = 'ACTIVO'
    ORDER BY E.ID_EMPLEADO;
END //

DELIMITER ;
