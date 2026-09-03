/*
ESTRUCTURA DE LA TABLA ASISTENCIA_EMPLEADOS

Esta tabla almacena la asistencia diaria de los empleados.

- ID_ASISTENCIA: identificador único y autoincremental de cada registro.
- ID_EMPLEADO: empleado al que pertenece la asistencia.
- FECHA: día en que se registra la asistencia.
- HORA_ENTRADA: hora de entrada del empleado.
- HORA_SALIDA: hora de salida; puede quedar NULL mientras no se registre.
- HORAS_TRABAJADAS: columna calculada automáticamente con la diferencia entre
    la hora de entrada y la hora de salida, expresada en horas decimales.
- ESTADO: estado de la asistencia: PRESENTE, AUSENTE, TARDE o PERMISO.
- OBSERVACION: comentario o justificación de hasta 200 caracteres.

Restricciones:
- La clave primaria identifica cada asistencia.
- Un empleado solo puede tener un registro por fecha.
- ID_EMPLEADO debe existir previamente en la tabla EMPLEADOS.

La tabla utiliza InnoDB para permitir claves foráneas y transacciones.
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
DESCRIPCION DE SP_REGISTRAR_ASISTENCIA

Registra la entrada o salida de un empleado mediante los siguientes parametros:
- P_ID_EMPLEADO: identificador del empleado.
- P_TIPO_MOVIMIENTO: tipo de movimiento, ENTRADA o SALIDA.

Antes de registrar la asistencia, valida que el empleado no tenga un permiso
aprobado ni se encuentre en vacaciones durante el dia actual. Si supera ambas
validaciones, guarda la fecha y hora actuales y muestra un mensaje de exito.
Si alguna validacion falla, detiene la operacion y muestra un mensaje de error.
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

    -- 3. SI PASA TODO, REGISTRAMOS ASISTENCIA NORMAL
    INSERT INTO ASISTENCIA (ID_EMPLEADO, FECHA, HORA, TIPO)
    VALUES (P_ID_EMPLEADO, CURDATE(), CURTIME(), P_TIPO_MOVIMIENTO);

    SELECT 'EXITO: ASISTENCIA REGISTRADA.' AS MENSAJE;
END ;
DELIMITER ;



---Salida

/*
DESCRIPCION DE SP_REGISTRAR_SALIDA

Registra la hora de salida del empleado indicado.
- P_ID_EMPLEADO: identificador del empleado.

El procedimiento actualiza HORA_SALIDA con la hora actual del servidor y solo
modifica el registro de asistencia correspondiente al empleado y a la fecha
actual.
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
END ;
DELIMITER ;


---TARDANZA JUSTIFICADA 

/*
DESCRIPCION DE SP_JUSTIFICAR_ASISTENCIA

Permite justificar o modificar el estado de la asistencia de un empleado.
- P_ID_EMPLEADO: identificador del empleado.
- P_FECHA: fecha del registro que se desea justificar.
- P_NUEVO_ESTADO: nuevo estado de la asistencia.
- P_JUSTIFICACION: motivo de la justificacion, con un maximo de 200 caracteres.

Primero verifica que exista un registro para el empleado y la fecha indicada.
Si existe, actualiza el estado y guarda la justificacion en OBSERVACION.
Finalmente devuelve un mensaje confirmando la operacion.
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
END ;
DELIMITER ;

---REPORTE DE AISTENCIA POR EMPLEADO 

/*
DESCRIPCION DE SP_REPORTE_ASISTENCIA_INDIVIDUAL

Genera el reporte de asistencia de un empleado durante un periodo determinado.
- P_ID_EMPLEADO: identificador del empleado.
- P_FECHA_INICIO: fecha inicial del periodo que se desea consultar.
- P_FECHA_FIN: fecha final del periodo que se desea consultar.

Devuelve la fecha, las horas de entrada y salida, las horas trabajadas y el
estado de cada asistencia encontrada. Los resultados se muestran desde la
fecha mas reciente hasta la mas antigua.
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
END ;
DELIMITER ;


---BLOQUEAR

/*
DESCRIPCION DE SP_BLOQUEAR_EDICION_ANTIGUA

Controla si se permite editar la asistencia de un empleado en una fecha
determinada.
- P_ID_EMPLEADO: identificador del empleado.
- P_FECHA: fecha del registro que se desea editar.

Si la fecha tiene mas de siete dias de antiguedad, bloquea la operacion y
devuelve un mensaje de error mediante SIGNAL. Si la fecha esta dentro del
periodo permitido, devuelve el mensaje ACCESO PERMITIDO.
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
END ;

DELIMITER ;


----------------------------------------------------------------------------------------------------

/*
DESCRIPCION DE TR_BLOQUEAR_ASISTENCIA_INAPROPIADA

Trigger que se ejecuta automaticamente antes de insertar un registro en
ASISTENCIA_EMPLEADOS.

Verifica si el empleado esta de vacaciones o tiene un permiso aprobado vigente
para la fecha actual. Si alguna condicion se cumple, bloquea la insercion con
SIGNAL y muestra un mensaje de error. Si no se cumple ninguna condicion, permite
que el registro se inserte normalmente.
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