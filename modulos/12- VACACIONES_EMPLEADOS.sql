/*
MODULO: VACACIONES_EMPLEADOS
END //
DELIMITER ;

--CONSULTAR QUIENES ESTAS DE VACACIONES 
/*
DESCRIPCION DE 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES

Propósito: listar empleados que actualmente están de vacaciones (o en un
rango), con nombre, cargo y días restantes hasta su retorno.

Parametros:
 - (opc) P_FECHA_REFERENCIA DATE o ninguno para usar CURDATE().

Retorno:
 - Filas con ID_EMPLEADO, NOMBRE, CARGO, FECHA_INICIO, FECHA_FIN, DIAS_PARA_RETORNAR.
*/
DELIMITER //

DROP PROCEDURE IF EXISTS 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES //
CREATE PROCEDURE 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES()

Notas de despliegue:
- Hacer backup antes de cambios: mysqldump de la tabla y de los SPs.
- Probar en staging con casos límite (cruce de años, concurrencia).
*/
-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
CREATE TABLE VACACIONES_EMPLEADOS (
    ID_VACACION INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_VACACION),
    CONSTRAINT CK_FECHAS_VACACIONES CHECK (FECHA_FIN >= FECHA_INICIO),
    CONSTRAINT FK_VACACIONES_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
) ENGINE = InnoDB;

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure]-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

/*
DESCRIPCION DE SP_INSERTAR_VACACIONES

Propósito: insertar una nueva solicitud de vacaciones validando existencia
del empleado, fechas (no en pasado, fin >= inicio), solapamientos y cupo
anual (15 días por defecto). Emite SIGNAL en caso de violación.

Parametros:
 - P_ID_EMPLEADO INT
 - P_FECHA_INICIO DATE
 - P_FECHA_FIN DATE

Retorno:
 - SELECT con mensaje de éxito y detalles (ID/empleado) o SIGNAL en error.
*/

-- INSERT
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_VACACIONES ;
CREATE PROCEDURE SP_INSERTAR_VACACIONES(
    IN P_ID_EMPLEADO INT,
    /*
    MODULO: VACACIONES_EMPLEADOS

    Propósito: Gestiona las solicitudes de vacaciones de empleados. Centraliza
    las reglas de negocio (validación de fechas, cupos anuales, solapamientos,
    autorizaciones) mediante procedimientos almacenados y triggers. Está
    diseñado para integrarse con la tabla `EMPLEADOS` y los módulos de usuario
    y auditoría.

    Artefactos incluidos en este archivo:
    - Tabla: VACACIONES_EMPLEADOS
    - Stored Procedures: SP_INSERTAR_VACACIONES, 12_SP_ACTUALIZAR_VACACIONES,
      12_SP_REPORTE_DIAS_CONSUMIDOS, 12_SP_VALIDAR_CUPO_VACACIONES,
      12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES
    - Triggers: TR_VALIDAR_LIMITE_VACACIONES

    Reglas clave:
    - Límite anual por defecto: 15 días (validado en SP y trigger).
    - No se permiten solapamientos de periodos para un mismo empleado.
    - FECHA_FIN debe ser >= FECHA_INICIO.
    - Los errores se reportan vía SIGNAL SQLSTATE '45000' con mensajes claros
      para que el backend los capture y muestre al usuario.

    Notas de despliegue:
    - Hacer backup antes de cambios: mysqldump de la tabla y de los SPs.
    - Probar en staging con casos límite (cruce de años, concurrencia).
    */
    -- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
    CREATE TABLE VACACIONES_EMPLEADOS (
        ID_VACACION INT NOT NULL AUTO_INCREMENT,
        ID_EMPLEADO INT NOT NULL,
        FECHA_INICIO DATE NOT NULL,
        FECHA_FIN DATE NOT NULL,
        FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (ID_VACACION),
        CONSTRAINT CK_FECHAS_VACACIONES CHECK (FECHA_FIN >= FECHA_INICIO),
        CONSTRAINT FK_VACACIONES_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
    ) ENGINE = InnoDB;

    -----------------------------------------------------------------------------------------------------------------------------
    -----------------------------------------[Store procedure]-------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------------

    /*
    DESCRIPCION DE SP_INSERTAR_VACACIONES

    Propósito: insertar una nueva solicitud de vacaciones validando existencia
    del empleado, fechas (no en pasado, fin >= inicio), solapamientos y cupo
    anual (15 días por defecto). Emite SIGNAL en caso de violación.

    Parametros:
     - P_ID_EMPLEADO INT
     - P_FECHA_INICIO DATE
     - P_FECHA_FIN DATE

    Retorno:
     - SELECT con mensaje de éxito y detalles (ID/empleado) o SIGNAL en error.
    */

    -- INSERT
    DELIMITER //
    DROP PROCEDURE IF EXISTS SP_INSERTAR_VACACIONES ;
    CREATE PROCEDURE SP_INSERTAR_VACACIONES(
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
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO PUEDES REGISTRAR VACACIONES EN EL PASADO.';
            LEAVE proc_label;
        END IF;

        IF P_FECHA_FIN < P_FECHA_INICIO THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.';
            LEAVE proc_label;
        END IF;

        -- 2. VALIDACIÓN DE SOLAPAMIENTO
        IF EXISTS (
            SELECT 1 FROM VACACIONES_EMPLEADOS 
            WHERE ID_EMPLEADO = P_ID_EMPLEADO 
            AND (
                (P_FECHA_INICIO BETWEEN FECHA_INICIO AND FECHA_FIN) OR 
                (P_FECHA_FIN BETWEEN FECHA_INICIO AND FECHA_FIN) OR
                (FECHA_INICIO BETWEEN P_FECHA_INICIO AND P_FECHA_FIN)
            ) 
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO YA TIENE VACACIONES EN ESE RANGO.';
            LEAVE proc_label;
        END IF;

        -- 3. VALIDACIÓN DE LÍMITE ANUAL (15 DÍAS)
        SET v_dias_solicitados = DATEDIFF(P_FECHA_FIN, P_FECHA_INICIO) + 1;
    
        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_acumulados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = P_ID_EMPLEADO 
        AND YEAR(FECHA_INICIO) = YEAR(P_FECHA_INICIO);

        IF (v_dias_acumulados + v_dias_solicitados) > 15 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO SUPERA EL LÍMITE DE 15 DÍAS POR AÑO.';
            LEAVE proc_label;
        END IF;

        -- 4. INSERCIÓN
        INSERT INTO VACACIONES_EMPLEADOS (ID_EMPLEADO, FECHA_INICIO, FECHA_FIN)
        VALUES (P_ID_EMPLEADO, P_FECHA_INICIO, P_FECHA_FIN);

        -- 5. MENSAJE FINAL
        SELECT CONCAT(
            'EXITO: VACACIONES REGISTRADAS PARA "', v_nombre_empleado, 
            '" (ID: ', P_ID_EMPLEADO, ') DEL ', P_FECHA_INICIO, ' AL ', P_FECHA_FIN, '.'
        ) AS MENSAJE;

    END ;
    DELIMITER ;

    /*
    DESCRIPCION DE 12_SP_ACTUALIZAR_VACACIONES

    Propósito: actualizar una solicitud de vacaciones (fechas o estado). Valida
    que el registro exista, que no se modifiquen periodos ya finalizados y que
    las nuevas fechas no incumplan reglas (fin >= inicio, sin solapamientos,
    y dentro del cupo anual si aplica).

    Parametros:
     - P_ID_VACACION INT
     - P_NUEVA_INICIO DATE (nullable)
     - P_NUEVA_FIN DATE (nullable)

    Retorno:
     - Mensaje de éxito o SIGNAL en caso de violación.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS 12_SP_ACTUALIZAR_VACACIONES ;
    CREATE PROCEDURE 12_SP_ACTUALIZAR_VACACIONES(
        IN P_ID_VACACION INT,
        IN P_NUEVA_INICIO DATE,
        IN P_NUEVA_FIN    DATE
    )
    proc_label: BEGIN
        DECLARE v_id_empleado INT;

        -- 1. VALIDAR EXISTENCIA
        SELECT ID_EMPLEADO INTO v_id_empleado 
        FROM VACACIONES_EMPLEADOS 
        WHERE ID_VACACION = P_ID_VACACION;

        IF v_id_empleado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: REGISTRO DE VACACIONES NO ENCONTRADO.';
            LEAVE proc_label;
        END IF;

        -- 2. VALIDAR QUE NO SE PUEDA MODIFICAR ALGO QUE YA PASÓ
        IF EXISTS(SELECT 1 FROM VACACIONES_EMPLEADOS WHERE ID_VACACION = P_ID_VACACION AND FECHA_FIN < CURDATE()) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN MODIFICAR VACACIONES QUE YA TERMINARON.';
            LEAVE proc_label;
        END IF;

        -- 3. VALIDACIÓN DE LÓGICA (Si vienen nuevas fechas, validarlas)
        IF P_NUEVA_INICIO IS NOT NULL AND P_NUEVA_FIN IS NOT NULL THEN
            IF P_NUEVA_FIN < P_NUEVA_INICIO THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FECHA DE FIN NO PUEDE SER MENOR A LA DE INICIO.';
                LEAVE proc_label;
            END IF;
        END IF;

        -- 4. ACTUALIZACIÓN DINÁMICA
        UPDATE VACACIONES_EMPLEADOS 
        SET 
            FECHA_INICIO = COALESCE(P_NUEVA_INICIO, FECHA_INICIO),
            FECHA_FIN    = COALESCE(P_NUEVA_FIN, FECHA_FIN)
        WHERE ID_VACACION = P_ID_VACACION;

        -- 5. MENSAJE DE RETORNO ESTANDARIZADO
        SELECT CONCAT('EXITO: VACACIONES (ID: ', P_ID_VACACION, ') ACTUALIZADAS CORRECTAMENTE PARA EL EMPLEADO ID: ', v_id_empleado) AS MENSAJE;

    END ;
    DELIMITER ;


    /*
    DESCRIPCION DE 12_SP_REPORTE_DIAS_CONSUMIDOS

    Propósito: devolver el total de días consumidos por un empleado en el año
    actual, mostrando nombre, total de días tomados y días restantes según el
    cupo por defecto (15 días). Se usa para mostrar saldo al usuario.

    Parametros:
     - P_ID_EMPLEADO INT

    Retorno:
     - Registro con NOMBRE, TOTAL_DIAS_TOMADOS, DIAS_RESTANTES, ESTATUS_VACACIONES.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS 12_SP_REPORTE_DIAS_CONSUMIDOS //
    CREATE PROCEDURE 12_SP_REPORTE_DIAS_CONSUMIDOS(
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

        -- 2. CALCULAR DÍAS TOMADOS (Usamos SUM con IFNULL directo)
        -- Si no hay registros en VACACIONES_EMPLEADOS, esto devolverá 0 de forma limpia
        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_tomados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = P_ID_EMPLEADO 
          AND YEAR(FECHA_INICIO) = YEAR(CURDATE());

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
    DESCRIPCION DE 12_SP_VALIDAR_CUPO_VACACIONES

    Propósito: comprobar si, para un cargo dado, es posible otorgar nuevas
    vacaciones sin que se exceda la proporción mínima de personal disponible.
    Devuelve por OUT un booleano `P_DISPONIBLE`.

    Parametros:
     - P_CARGO VARCHAR(50)
     - OUT P_DISPONIBLE BOOLEAN

    Retorno:
     - P_DISPONIBLE = TRUE/FALSE. En caso de error (cargo no encontrado), se
       lanza SIGNAL.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS 12_SP_VALIDAR_CUPO_VACACIONES //
    CREATE PROCEDURE 12_SP_VALIDAR_CUPO_VACACIONES(
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

        -- 2. CONTAR AUSENTES
        SELECT COUNT(*) INTO v_ausentes_hoy 
        FROM VACACIONES_EMPLEADOS V
        INNER JOIN EMPLEADOS E ON V.ID_EMPLEADO = E.ID_EMPLEADO
        WHERE E.CARGO = P_CARGO 
          AND CURDATE() BETWEEN V.FECHA_INICIO AND V.FECHA_FIN;

        -- 3. LÓGICA DE NEGOCIO (Permitimos si el ausente + 1 NO supera el 50%)
        -- Esto asegura que, al intentar pedir vacaciones, validemos si con su ausencia se rompe la regla
        IF (v_ausentes_hoy + 1) <= (v_total_cargo / 2) THEN
            SET P_DISPONIBLE = TRUE;
        ELSE
            SET P_DISPONIBLE = FALSE;
        END IF;
    END 
    DELIMITER ;


    --CONSULTAR QUIENES ESTAS DE VACACIONES 
    /*
    DESCRIPCION DE 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES

    Propósito: listar empleados que actualmente están de vacaciones (o en un
    rango), con nombre, cargo y días restantes hasta su retorno.

    Parametros:
     - (opc) P_FECHA_REFERENCIA DATE o ninguno para usar CURDATE().

    Retorno:
     - Filas con ID_EMPLEADO, NOMBRE, CARGO, FECHA_INICIO, FECHA_FIN, DIAS_PARA_RETORNAR.
    */
    DELIMITER //
    DROP PROCEDURE IF EXISTS 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES //
    CREATE PROCEDURE 12_SP_CONSULTAR_EMPLEADOS_DE_VACACIONES()
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
        WHERE CURDATE() BETWEEN V.FECHA_INICIO AND V.FECHA_FIN
        ORDER BY V.FECHA_FIN ASC;

        -- 2. NOTA: Si la consulta no devuelve filas, tu aplicación en C# 
        -- simplemente recibirá un "Data Table" vacío, lo cual es correcto.
        -- No requiere SIGNAL porque no es un error que no haya nadie de vacaciones.
    END //
    DELIMITER ;


    ----------------------------------------------------------------------------------------------------
    -----------------------------------------[TRIGERR}--------------------------------------------------
    ----------------------------------------------------------------------------------------------------


    --VALIDAR LIMITE DE VACACIONES
    /*
    DESCRIPCION DE TR_VALIDAR_LIMITE_VACACIONES

    Propósito: trigger BEFORE INSERT que valida que la suma de días ya
    tomados en el año más los días solicitados no exceda el cupo anual
    permitido (15 días). Si excede, lanza SIGNAL para bloquear la inserción.

    Notas:
     - Mantener el trigger ligero; la lógica de negocio más compleja debe
       preferiblemente residir en procedures para facilitar pruebas.
     - Revisar comportamiento si se crean registros históricos o migraciones
       masivas (puede necesitar desactivación temporal).
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

        -- 1. Calcular días ya tomados en el MISMO AÑO de la solicitud
        SELECT IFNULL(SUM(DATEDIFF(FECHA_FIN, FECHA_INICIO) + 1), 0)
        INTO v_dias_acumulados
        FROM VACACIONES_EMPLEADOS
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO 
        AND YEAR(FECHA_INICIO) = v_anio_solicitado;

        -- 2. Calcular días de la nueva solicitud
        SET v_nuevos_dias = DATEDIFF(NEW.FECHA_FIN, NEW.FECHA_INICIO) + 1;

        -- 3. Validación estricta
        IF (v_dias_acumulados + v_nuevos_dias) > 15 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: VACACIONES DENEGADAS. EL EMPLEADO EXCEDERÍA EL LÍMITE DE 15 DÍAS ANUALES.';
        END IF;
    END //
    DELIMITER ;





