CREATE TABLE CLIENTES (
    ID_CLIENTE INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(100) NOT NULL,
    TELEFONO VARCHAR(20) NOT NULL UNIQUE,
    EMAIL VARCHAR(100) NOT NULL UNIQUE,
    DIRECCION VARCHAR(150),
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_CLIENTE),
    CONSTRAINT CK_CLIENTE_EMAIL CHECK (EMAIL LIKE '%@%.%'),
    CONSTRAINT CK_CLIENTE_NOMBRE CHECK (CHAR_LENGTH(TRIM(NOMBRE)) > 0)
) ENGINE = InnoDB;

----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------
--1. INSERTAR
DELIMITER //     
 DROP PROCEDURE IF EXISTS SP_INSERTAR_CLIENTES ; 
CREATE PROCEDURE SP_INSERTAR_CLIENTES(
    IN P_NOMBRE    VARCHAR(100),
    IN P_TELEFONO  VARCHAR(20),
    IN P_EMAIL     VARCHAR(100),
    IN P_DIRECCION VARCHAR(150)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio    VARCHAR(100);
    DECLARE v_telefono_limpio  VARCHAR(20);
    DECLARE v_email_limpio     VARCHAR(100);
    DECLARE v_direccion_limpia VARCHAR(150);

    -- 0. LIMPIEZA PROFUNDA
    SET v_nombre_limpio    = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    SET v_telefono_limpio  = TRIM(P_TELEFONO);
    SET v_email_limpio     = LOWER(TRIM(P_EMAIL));
    SET v_direccion_limpia = REGEXP_REPLACE(TRIM(P_DIRECCION), '[[:space:]]+', ' ');

    -- 1. VALIDACIONES DE OBLIGATORIEDAD
    IF v_nombre_limpio = '' OR v_telefono_limpio = '' OR v_email_limpio = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NOMBRE, TELÉFONO Y EMAIL SON OBLIGATORIOS.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN: DUPLICADOS (Teléfono y Email)
    IF EXISTS (SELECT 1 FROM CLIENTES WHERE TELEFONO = v_telefono_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM CLIENTES WHERE EMAIL = v_email_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE EMAIL YA ESTÁ REGISTRADO.';
        LEAVE proc_label;
    END IF;

    -- 3. INSERCIÓN FINAL
    INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL, DIRECCION) 
    VALUES (v_nombre_limpio, v_telefono_limpio, v_email_limpio, v_direccion_limpia);

    -- 4. MENSAJE ESTANDARIZADO PARA C++
    SELECT CONCAT('EXITO: CLIENTE "', v_nombre_limpio, '" INSERTADO. ID: ', LAST_INSERT_ID()) AS MENSAJE;
END;
DELIMITER ;
 
--2.ACTUALIZAR

DELIMITER //

DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_CLIENTES ;
CREATE PROCEDURE SP_ACTUALIZAR_CLIENTES( 
    IN P_ID_CLIENTE INT,
    IN P_NOMBRE     VARCHAR(100),
    IN P_TELEFONO   VARCHAR(20),
    IN P_EMAIL      VARCHAR(100),
    IN P_DIRECCION  VARCHAR(150)
)
proc_label: BEGIN
    -- Declaración de variables para el proceso de limpieza
    DECLARE v_nombre_limpio    VARCHAR(100);
    DECLARE v_telefono_limpio  VARCHAR(20);
    DECLARE v_email_limpio     VARCHAR(100);
    DECLARE v_dir_limpia       VARCHAR(150);

    -- 1. VALIDAR EXISTENCIA DEL CLIENTE
    IF NOT EXISTS (SELECT 1 FROM CLIENTES WHERE ID_CLIENTE = P_ID_CLIENTE) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL CLIENTE NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. LIMPIEZA DE DATOS Y VALIDACIONES (Solo si se envían valores)
    IF P_NOMBRE IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
        IF v_nombre_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_TELEFONO IS NOT NULL THEN
        SET v_telefono_limpio = REGEXP_REPLACE(P_TELEFONO, '[[:space:]()\-]', '');
        IF v_telefono_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM CLIENTES WHERE TELEFONO = v_telefono_limpio AND ID_CLIENTE <> P_ID_CLIENTE) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO YA PERTENECE A OTRO CLIENTE.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_EMAIL IS NOT NULL THEN
        SET v_email_limpio = LOWER(REPLACE(P_EMAIL, ' ', ''));
        IF v_email_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM CLIENTES WHERE EMAIL = v_email_limpio AND ID_CLIENTE <> P_ID_CLIENTE) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL YA PERTENECE A OTRO CLIENTE.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_DIRECCION IS NOT NULL THEN
        SET v_dir_limpia = REGEXP_REPLACE(TRIM(P_DIRECCION), '[[:space:]]+', ' ');
    END IF;

  -- 3. ACTUALIZACIÓN DINÁMICA
    UPDATE CLIENTES 
    SET 
        NOMBRE    = COALESCE(v_nombre_limpio, NOMBRE),
        TELEFONO  = COALESCE(v_telefono_limpio, TELEFONO),
        EMAIL     = COALESCE(v_email_limpio, EMAIL),
        DIRECCION = COALESCE(v_dir_limpia, DIRECCION)
    WHERE ID_CLIENTE = P_ID_CLIENTE;

    -- 4. FORMA SEGURA DE RETORNAR EL MENSAJE
    -- Primero guardamos en una variable para evitar conflictos de contexto
    SET @mensaje_final = (SELECT CONCAT('EXITO: EL CLIENTE "', 
                                        COALESCE(v_nombre_limpio, NOMBRE), 
                                        '" FUE ACTUALIZADO. (EMAIL: ', 
                                        COALESCE(v_email_limpio, EMAIL), 
                                        ')') 
                          FROM CLIENTES WHERE ID_CLIENTE = P_ID_CLIENTE);

    SELECT @mensaje_final AS MENSAJE;

END ;

DELIMITER ;

--BUSCAR

DELIMITER //

DROP PROCEDURE IF EXISTS SP_LISTAR_CLIENTES ;
CREATE PROCEDURE SP_LISTAR_CLIENTES(
    IN P_FILTRO VARCHAR(100)
)
proc_label: BEGIN
    -- 1. LIMPIEZA DEL FILTRO
    -- Si el filtro es NULL o está vacío, lo tratamos como vacío para la búsqueda
    DECLARE v_filtro_limpio VARCHAR(100);
    SET v_filtro_limpio = IFNULL(TRIM(P_FILTRO), '');

    -- 2. BÚSQUEDA DINÁMICA
    -- Usamos LIKE CONCAT para encontrar coincidencias en nombre, teléfono o email
    SELECT 
        ID_CLIENTE, 
        NOMBRE, 
        TELEFONO, 
        EMAIL, 
        DIRECCION, 
        ESTADO, 
        FECHA_REGISTRO
    FROM CLIENTES
    WHERE (v_filtro_limpio = '' 
           OR NOMBRE LIKE CONCAT('%', v_filtro_limpio, '%') 
           OR TELEFONO LIKE CONCAT('%', v_filtro_limpio, '%')
           OR EMAIL LIKE CONCAT('%', v_filtro_limpio, '%'))
    ORDER BY NOMBRE ASC;

END ;

DELIMITER ;

--TOGLER CAMBIAR ESTADO 

DROP PROCEDURE IF EXISTS SP_TOGGLE_ESTADO_CLIENTES;
DELIMITER //
CREATE PROCEDURE SP_TOGGLE_ESTADO_CLIENTES(IN P_ID_CLIENTE INT)
BEGIN
    -- 1. Validamos si el cliente existe
    IF NOT EXISTS (SELECT 1 FROM CLIENTES WHERE ID_CLIENTE = P_ID_CLIENTE) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: EL ID DEL CLIENTE NO EXISTE.';
    ELSE
        -- 2. Hacemos el Toggler
        UPDATE CLIENTES 
        SET ESTADO = IF(ESTADO = 'ACTIVO', 'INACTIVO', 'ACTIVO')
        WHERE ID_CLIENTE = P_ID_CLIENTE;
        
        -- 3. Enviamos el mensaje de éxito
        SELECT CONCAT('SISTEMA: CLIENTE ', IF(ESTADO='ACTIVO', 'ACTIVADO', 'DESACTIVADO'), ' EXITOSAMENTE.') AS MENSAJE 
        FROM CLIENTES 
        WHERE ID_CLIENTE = P_ID_CLIENTE;
    END IF;
END ;
DELIMITER ;


----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

DELIMITER //

-- 1. Trigger para registrar nuevos clientes
DROP TRIGGER IF EXISTS TR_AUDIT_CLIENTES_INSERT ;
CREATE TRIGGER TR_AUDIT_CLIENTES_INSERT
AFTER INSERT ON CLIENTES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_NUEVO)
    VALUES ('CLIENTES', NEW.ID_CLIENTE, 'INSERT', CURRENT_USER(), 
            CONCAT('Nombre: ', NEW.NOMBRE, ', Email: ', NEW.EMAIL));
END ;

-- 2. Trigger para registrar cambios en clientes existentes
DROP TRIGGER IF EXISTS TR_AUDIT_CLIENTES_UPDATE ;
CREATE TRIGGER TR_AUDIT_CLIENTES_UPDATE
AFTER UPDATE ON CLIENTES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES ('CLIENTES', OLD.ID_CLIENTE, 'UPDATE', CURRENT_USER(), 
            CONCAT('Nombre: ', OLD.NOMBRE, ', Email: ', OLD.EMAIL),
            CONCAT('Nombre: ', NEW.NOMBRE, ', Email: ', NEW.EMAIL));
END ;

DELIMITER ;


CALL `SP_INSERTAR_CLIENTES` ('Jose Perez', '8097282431','perez01@gmail.com','Villa carmen')