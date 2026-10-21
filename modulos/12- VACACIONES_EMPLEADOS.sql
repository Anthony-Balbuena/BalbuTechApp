/*
TABLA VACACIONES_EMPLEADOS
Guarda las solicitudes de vacaciones de cada empleado: rango de fechas y
estado (PENDIENTE, APROBADO o RECHAZADO). No deja que la fecha de fin sea
menor al inicio y si se borra el empleado se borran tambien sus vacaciones.
*/
CREATE TABLE VACACIONES_EMPLEADOS (
    ID_VACACION INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    ESTADO ENUM(
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO'
    ) NOT NULL DEFAULT 'PENDIENTE',
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_VACACION),
    CONSTRAINT CK_FECHAS_VACACIONES CHECK (FECHA_FIN >= FECHA_INICIO),
    CONSTRAINT FK_VACACIONES_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
) ENGINE = InnoDB;


/*
SP_SOLICITAR_VACACIONES
Da de alta una solicitud de vacaciones en estado PENDIENTE. Valida que el
empleado exista, que las fechas no vengan en pasado ni invertidas, que no
se crucen con otra solicitud no rechazada y que no se pase de los 15 dias
al ano contando tambien las pendientes (reservan cupo).
*/

-- SOLICITUD
DELIMITER //
DROP PROCEDURE IF EXISTS SP_SOLICITAR_VACACIONES ;
    CREATE PROCEDURE SP_SOLICITAR_VACACIONES(
        IN P_ID_EMPLEADO INT,
        IN P_FECHA_INICIO DATE,
        IN P_FECHA_FIN    DATE
    )
    proc_label: BEGIN
        DECLARE v_dias_solicitados INT;
        DECLARE v_dias_acumulados INT;
        DECLARE v_nombre_empleado VARCHAR(100);

        -- 1. LIMPIEZA Y VALIDACIONES PREVIAS
        SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;

        IF v_nombre_empleado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
            LEAVE proc_label;
        END IF;

        IF P_FECHA_INICIO < CURDATE() THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO PUEDES SOLICITAR VACACIONES EN EL PASADO.';
            LEAVE proc_label;
        END IF;

        IF P_FECHA_FIN < P_FECHA_INICIO THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.';
            LEAVE proc_label;
        END IF;

        -- 2. VALIDACIÓN DE SOLAPAMIENTO (las rechazadas no bloquean)
        IF EXISTS (
            SELECT 1 FROM VACACIONES_EMPLEADOS
            WHERE ID_EMPLEADO = P_ID_EMPLEADO
            AND ESTADO <> 'RECHAZADO'
            AND (
                (P_FECHA_INICIO BETWEEN FECHA_INICIO AND FECHA_FIN) OR
                (P_FECHA_FIN BETWEEN FECHA_INICIO AND FECHA_FIN) OR
                (FECHA_INICIO BETWEEN P_FECHA_INICIO AND P_FECHA_FIN)
            )
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO YA TIENE VACACIONES PENDIENTES O APROBADAS EN ESE RANGO.';
            LEAVE proc_label;
        END IF;

        -- 3. VALIDACIÓN DE LÍMITE ANUAL (15 DÍAS): pendientes y aprobadas reservan.
        SET v_dias_solicitados = DATEDIFF(P_FECHA_FIN, P_FECHA_INICIO) + 1;

        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_acumulados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = P_ID_EMPLEADO
        AND YEAR(FECHA_INICIO) = YEAR(P_FECHA_INICIO)
        AND ESTADO <> 'RECHAZADO';

        IF (v_dias_acumulados + v_dias_solicitados) > 15 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO SUPERA EL LÍMITE DE 15 DÍAS POR AÑO.';
            LEAVE proc_label;
        END IF;

        -- 4. INSERCIÓN: toda solicitud nace PENDIENTE
        INSERT INTO VACACIONES_EMPLEADOS (ID_EMPLEADO, FECHA_INICIO, FECHA_FIN, ESTADO)
        VALUES (P_ID_EMPLEADO, P_FECHA_INICIO, P_FECHA_FIN, 'PENDIENTE');

        -- 5. MENSAJE FINAL
        SELECT CONCAT(
            'EXITO: SOLICITUD DE VACACIONES CREADA PARA "', v_nombre_empleado,
            '" (ID: ', P_ID_EMPLEADO, ') DEL ', P_FECHA_INICIO, ' AL ', P_FECHA_FIN,
            '. QUEDA PENDIENTE DE APROBACION.'
        ) AS MENSAJE;

    END //
    DELIMITER ;

/*
SP_GESTIONAR_VACACION
Aprueba o rechaza una solicitud de vacaciones. Solo se puede resolver una
vez: si el ID no existe o la solicitud ya fue aprobada o rechazada, manda
un error y no toca nada. El UPDATE vuelve a exigir PENDIENTE para que dos
gestiones simultaneas no pisen el estado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_GESTIONAR_VACACION ;
CREATE PROCEDURE SP_GESTIONAR_VACACION(
    IN P_ID_VACACION INT,
    IN P_NUEVO_ESTADO ENUM('APROBADO', 'RECHAZADO')
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. VALIDAR EXISTENCIA
    SELECT ESTADO INTO v_estado_actual
    FROM VACACIONES_EMPLEADOS
    WHERE ID_VACACION = P_ID_VACACION;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: VACACION NO ENCONTRADA.';
        LEAVE proc_label;
    END IF;

    -- 2. SOLO SE RESUELVE UNA VEZ: LA SOLICITUD DEBE ESTAR PENDIENTE
    IF v_estado_actual <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN GESTIONAR VACACIONES PENDIENTES.';
        LEAVE proc_label;
    END IF;

    -- 3. EL NUEVO ESTADO SOLO PUEDE SER APROBADO O RECHAZADO
    IF P_NUEVO_ESTADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTADO NO VALIDO. SOLO SE PUEDE APROBAR O RECHAZAR.';
        LEAVE proc_label;
    END IF;

    -- 4. ACTUALIZAR SOLO SI SIGUE PENDIENTE (ATOMICO)
    UPDATE VACACIONES_EMPLEADOS
    SET ESTADO = P_NUEVO_ESTADO
    WHERE ID_VACACION = P_ID_VACACION
      AND ESTADO = 'PENDIENTE';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN GESTIONAR VACACIONES PENDIENTES.';
        LEAVE proc_label;
    END IF;

    SELECT CONCAT('EXITO: VACACION ID ', P_ID_VACACION, ' ACTUALIZADA A ESTADO: ', P_NUEVO_ESTADO) AS MENSAJE;
END //
DELIMITER ;

/*
SP_LISTAR_VACACIONES_PENDIENTES
Lista las solicitudes que todavia no se resolvieron, con el nombre del
empleado, para la pantalla de gestion de RRHH. Va de la mas vieja a la
mas nueva: la primera que llego se atiende primero.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_VACACIONES_PENDIENTES //
CREATE PROCEDURE SP_LISTAR_VACACIONES_PENDIENTES()
BEGIN
    SELECT
        V.ID_VACACION,
        V.ID_EMPLEADO,
        E.NOMBRE,
        V.FECHA_INICIO,
        V.FECHA_FIN,
        V.FECHA_REGISTRO
    FROM VACACIONES_EMPLEADOS V
    INNER JOIN EMPLEADOS E ON E.ID_EMPLEADO = V.ID_EMPLEADO
    WHERE V.ESTADO = 'PENDIENTE'
    ORDER BY V.FECHA_REGISTRO ASC, V.ID_VACACION ASC;
END //
DELIMITER ;

/*
SP_HISTORIAL_VACACIONES_EMPLEADO
Lista todas las vacaciones de un empleado (fechas, estado y fecha de
registro) de la mas reciente a la mas antigua, para ver su historial
completo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_HISTORIAL_VACACIONES_EMPLEADO //
CREATE PROCEDURE SP_HISTORIAL_VACACIONES_EMPLEADO(IN P_ID_EMPLEADO INT)
BEGIN
    SELECT
        FECHA_INICIO,
        FECHA_FIN,
        ESTADO,
        FECHA_REGISTRO
    FROM VACACIONES_EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO
    ORDER BY FECHA_INICIO DESC, ID_VACACION DESC;
END //
DELIMITER ;

/*
SP_ACTUALIZAR_VACACIONES
Cambia las fechas de una solicitud PENDIENTE. Revisa que el registro
exista y que no haya terminado; si vienen fechas nuevas valida que no
esten invertidas; lo que llegue en NULL se queda como estaba. Una
solicitud ya aprobada o rechazada no se puede editar.
    */

    DELIMITER //
    DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_VACACIONES ;
    CREATE PROCEDURE SP_ACTUALIZAR_VACACIONES(
        IN P_ID_VACACION INT,
        IN P_NUEVA_INICIO DATE,
        IN P_NUEVA_FIN    DATE
    )
    proc_label: BEGIN
        DECLARE v_id_empleado INT;
        DECLARE v_estado VARCHAR(20);

        -- 1. VALIDAR EXISTENCIA
        SELECT ID_EMPLEADO, ESTADO INTO v_id_empleado, v_estado
        FROM VACACIONES_EMPLEADOS
        WHERE ID_VACACION = P_ID_VACACION;

        IF v_id_empleado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: REGISTRO DE VACACIONES NO ENCONTRADO.';
            LEAVE proc_label;
        END IF;

        -- 2. SOLO SE EDITAN SOLICITUDES PENDIENTES
        IF v_estado <> 'PENDIENTE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN MODIFICAR VACACIONES PENDIENTES.';
            LEAVE proc_label;
        END IF;

        -- 3. VALIDAR QUE NO SE PUEDA MODIFICAR ALGO QUE YA PASÓ
        IF EXISTS(SELECT 1 FROM VACACIONES_EMPLEADOS WHERE ID_VACACION = P_ID_VACACION AND FECHA_FIN < CURDATE()) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN MODIFICAR VACACIONES QUE YA TERMINARON.';
            LEAVE proc_label;
        END IF;

        -- 4. VALIDACIÓN DE LÓGICA con las fechas EFECTIVAS (10/10/2026):
        -- cubre los 3 casos (solo inicio, solo fin, ambas); antes solo
        -- validaba si venían ambas y el resto caía al CHECK técnico.
        IF COALESCE(P_NUEVA_FIN, (SELECT FECHA_FIN FROM VACACIONES_EMPLEADOS WHERE ID_VACACION = P_ID_VACACION))
         < COALESCE(P_NUEVA_INICIO, (SELECT FECHA_INICIO FROM VACACIONES_EMPLEADOS WHERE ID_VACACION = P_ID_VACACION)) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.';
            LEAVE proc_label;
        END IF;

        -- 5. ACTUALIZACIÓN DINÁMICA (repite PENDIENTE como guarda atómica)
        UPDATE VACACIONES_EMPLEADOS
        SET
            FECHA_INICIO = COALESCE(P_NUEVA_INICIO, FECHA_INICIO),
            FECHA_FIN    = COALESCE(P_NUEVA_FIN, FECHA_FIN)
        WHERE ID_VACACION = P_ID_VACACION
          AND ESTADO = 'PENDIENTE';

        -- 6. MENSAJE DE RETORNO ESTANDARIZADO
        SELECT CONCAT('EXITO: VACACIONES (ID: ', P_ID_VACACION, ') ACTUALIZADAS CORRECTAMENTE PARA EL EMPLEADO ID: ', v_id_empleado) AS MENSAJE;

    END //
    DELIMITER ;


    /*
    12_SP_REPORTE_DIAS_CONSUMIDOS
    Devuelve el saldo de vacaciones del empleado en el ano: nombre, dias ya
    tomados (solo las APROBADAS), dias que le quedan de los 15 y si esta
    DISPONIBLE o EXCEDE LIMITE. Si el empleado no existe manda error.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS SP_REPORTE_DIAS_CONSUMIDOS ;
    CREATE PROCEDURE SP_REPORTE_DIAS_CONSUMIDOS(
        IN P_ID_EMPLEADO INT
    )
    proc_label: BEGIN
        DECLARE v_nombre_empleado VARCHAR(100);
        DECLARE v_dias_tomados INT;

        -- 1. VALIDAR EXISTENCIA DEL EMPLEADO
        SELECT NOMBRE INTO v_nombre_empleado
        FROM EMPLEADOS
        WHERE ID_EMPLEADO = P_ID_EMPLEADO;

        IF v_nombre_empleado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO ENCONTRADO.';
            LEAVE proc_label;
        END IF;

        -- 2. CALCULAR DÍAS TOMADOS: solo las vacaciones APROBADAS del ano.
        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_tomados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = P_ID_EMPLEADO
          AND YEAR(FECHA_INICIO) = YEAR(CURDATE())
          AND ESTADO = 'APROBADO';

        -- 3. RESULTADO FINAL ESTANDARIZADO
        SELECT
            v_nombre_empleado AS NOMBRE,
            v_dias_tomados AS TOTAL_DIAS_TOMADOS,
            (15 - v_dias_tomados) AS DIAS_RESTANTES,
            IF((15 - v_dias_tomados) < 0, 'EXCEDE LÍMITE', 'DISPONIBLE') AS ESTATUS_VACACIONES
        FROM DUAL; -- DUAL es una tabla virtual para mostrar cálculos sin necesidad de FROM tablas físicas

    END //
    DELIMITER ;


    --Este SP valida que siempre se quede alguien.
    /*
    SP_VALIDAR_CUPO_VACACIONES
    Revisa si aun se pueden dar vacaciones en un cargo sin dejar menos de
    la mitad del personal disponible: devuelve TRUE o FALSE segun convenga.
    Solo cuentan las vacaciones APROBADAS. Si el cargo no existe o no tiene
    gente, manda error.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS SP_VALIDAR_CUPO_VACACIONES ;
    CREATE PROCEDURE SP_VALIDAR_CUPO_VACACIONES(
        IN P_CARGO VARCHAR(50),
        OUT P_DISPONIBLE BOOLEAN
    )
    proc_label: BEGIN
        DECLARE v_total_cargo INT;
        DECLARE v_ausentes_hoy INT;

        -- 1. VALIDAR QUE EL CARGO EXISTA Y TENGA PERSONAL
        SELECT COUNT(*) INTO v_total_cargo
        FROM EMPLEADOS
        WHERE CARGO = P_CARGO;

        IF v_total_cargo = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CARGO NO ENCONTRADO O SIN EMPLEADOS ASIGNADOS.';
            LEAVE proc_label;
        END IF;

        -- 2. CONTAR AUSENTES (solo vacaciones aprobadas)
        SELECT COUNT(*) INTO v_ausentes_hoy
        FROM VACACIONES_EMPLEADOS V
        INNER JOIN EMPLEADOS E ON V.ID_EMPLEADO = E.ID_EMPLEADO
        WHERE E.CARGO = P_CARGO
          AND V.ESTADO = 'APROBADO'
          AND CURDATE() BETWEEN V.FECHA_INICIO AND V.FECHA_FIN;

        -- 3. LÓGICA DE NEGOCIO (Permitimos si el ausente + 1 NO supera el 50%)
        -- Esto asegura que, al intentar pedir vacaciones, validemos si con su ausencia se rompe la regla
        IF (v_ausentes_hoy + 1) <= (v_total_cargo / 2) THEN
            SET P_DISPONIBLE = TRUE;
        ELSE
            SET P_DISPONIBLE = FALSE;
        END IF;
    END //
    DELIMITER ;


    --CONSULTAR QUIENES ESTAS DE VACACIONES
    /*
    12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES
    Lista los empleados con vacaciones APROBADAS hoy, con su cargo y los dias
    que les quedan hasta volver. Si nadie esta fuera no devuelve filas y eso
    no es error.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS SP_CONSULTAR_EMPLEADOS_DE_VACACIONES ;
    CREATE PROCEDURE SP_CONSULTAR_EMPLEADOS_DE_VACACIONES()
    BEGIN
        -- 1. CONSULTA CON LOGICA DE NEGOCIO CLARA
        SELECT
            E.ID_EMPLEADO,
            E.NOMBRE,
            E.CARGO,
            V.FECHA_INICIO,
            V.FECHA_FIN,
            -- Calculamos cuántos días le quedan de vacaciones a partir de hoy
            DATEDIFF(V.FECHA_FIN, CURDATE()) AS DIAS_PARA_RETORNAR
        FROM VACACIONES_EMPLEADOS V
        INNER JOIN EMPLEADOS E ON V.ID_EMPLEADO = E.ID_EMPLEADO
        WHERE V.ESTADO = 'APROBADO'
          AND CURDATE() BETWEEN V.FECHA_INICIO AND V.FECHA_FIN
        ORDER BY V.FECHA_FIN ASC;

        -- 2. NOTA: Si la consulta no devuelve filas, tu aplicación en C#
        -- simplemente recibirá un "Data Table" vacío, lo cual es correcto.
        -- No requiere SIGNAL porque no es un error que no haya nadie de vacaciones.
    END //
    DELIMITER ;


    --VALIDAR LIMITE DE VACACIONES
    /*
    TR_VALIDAR_LIMITE_VACACIONES
    Antes de guardar unas vacaciones suma los dias no rechazados que el
    empleado ya tiene este ano con los nuevos; si pasan de 15 bloquea el
    registro con un error. Trabaja en automatico, sin tener que llamarlo.
    */
    DELIMITER //

    DROP TRIGGER IF EXISTS TR_VALIDAR_LIMITE_VACACIONES //
    CREATE TRIGGER TR_VALIDAR_LIMITE_VACACIONES
    BEFORE INSERT ON VACACIONES_EMPLEADOS
    FOR EACH ROW
    BEGIN
        DECLARE v_dias_acumulados INT;
        DECLARE v_nuevos_dias INT;
        DECLARE v_anio_solicitado INT;

        SET v_anio_solicitado = YEAR(NEW.FECHA_INICIO);

        -- 1. Calcular días ya reservados en el MISMO AÑO de la solicitud
        -- (pendientes y aprobadas; las rechazadas no cuentan)
        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_acumulados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO
        AND YEAR(FECHA_INICIO) = v_anio_solicitado
        AND ESTADO <> 'RECHAZADO';

        -- 2. Calcular días de la nueva solicitud
        SET v_nuevos_dias = DATEDIFF(NEW.FECHA_FIN, NEW.FECHA_INICIO) + 1;

        -- 3. Validación estricta
        IF (v_dias_acumulados + v_nuevos_dias) > 15 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: VACACIONES DENEGADAS. EL EMPLEADO EXCEDERÍA EL LÍMITE DE 15 DÍAS ANUALES.';
        END IF;
    END //
    DELIMITER ;




    -----------------------------------------------------------------------------------------------------------------------
    ----------------------------------------------------[TRIGGER]------------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    DELIMITER //
    DROP TRIGGER IF EXISTS TR_VALIDAR_LIMITE_VACACIONES_UPDATE //
    /*
    TR_VALIDAR_LIMITE_VACACIONES_UPDATE (09/10/2026)
    Gemelo del BEFORE INSERT para el UPDATE directo y SP_ACTUALIZAR_VACACIONES:
    la misma cuenta de 15 dias sin contar la propia fila que se edita y sin
    contar las rechazadas.
    */
    CREATE TRIGGER TR_VALIDAR_LIMITE_VACACIONES_UPDATE
    BEFORE UPDATE ON VACACIONES_EMPLEADOS
    FOR EACH ROW
    BEGIN
        DECLARE v_dias_acumulados INT;
        DECLARE v_nuevos_dias INT;
        DECLARE v_anio_solicitado INT;

        SET v_anio_solicitado = YEAR(NEW.FECHA_INICIO);

        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_acumulados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO
          AND YEAR(FECHA_INICIO) = v_anio_solicitado
          AND ESTADO <> 'RECHAZADO'
          AND ID_VACACION <> NEW.ID_VACACION;

        SET v_nuevos_dias = DATEDIFF(NEW.FECHA_FIN, NEW.FECHA_INICIO) + 1;

        IF (v_dias_acumulados + v_nuevos_dias) > 15 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: VACACIONES DENEGADAS. EL EMPLEADO EXCEDERÍA EL LÍMITE DE 15 DÍAS ANUALES.';
        END IF;
    END //
    DELIMITER ;
