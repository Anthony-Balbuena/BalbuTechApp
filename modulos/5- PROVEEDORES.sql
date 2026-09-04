-- Active: 1788274174973@@127.0.0.1@3306@BALBU_TECH
CREATE TABLE PROVEEDORES (
    ID_PROVEEDOR INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(100) NOT NULL,
    TELEFONO VARCHAR(15) UNIQUE ,
    EMAIL VARCHAR(100) UNIQUE ,
    DIRECCION VARCHAR(120),
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    PRIMARY KEY (ID_PROVEEDOR),
    CONSTRAINT UQ_PROVEEDOR_TELEFONO UNIQUE (TELEFONO),
    CONSTRAINT UQ_PROVEEDOR_EMAIL UNIQUE (EMAIL)
) ENGINE = InnoDB;

-- Para buscar proveedores por nombre (muy común)
CREATE INDEX IX_PROVEEDOR_NOMBRE ON PROVEEDORES (NOMBRE);

-- Para filtrar proveedores activos rápidamente
CREATE INDEX IX_PROVEEDOR_ESTADO ON PROVEEDORES (ESTADO);
----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------
--1. INSERTAR 
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_PROVEEDOR;
CREATE PROCEDURE SP_INSERTAR_PROVEEDOR(
    IN P_NOMBRE    VARCHAR(100),
    IN P_TELEFONO  VARCHAR(15),
    IN P_EMAIL     VARCHAR(100),
    IN P_DIRECCION VARCHAR(120)
)
proc_label: BEGIN 
    DECLARE v_nombre_limpio   VARCHAR(100);
    DECLARE v_telefono_limpio VARCHAR(15);
    DECLARE v_email_limpio    VARCHAR(100);
    DECLARE v_dir_limpia      VARCHAR(120);

    -- 0. LIMPIEZA
    SET v_nombre_limpio   = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    SET v_telefono_limpio = REGEXP_REPLACE(P_TELEFONO, '[[:space:]()\-]', '');
    SET v_email_limpio    = LOWER(REPLACE(P_EMAIL, ' ', ''));
    SET v_dir_limpia      = REGEXP_REPLACE(TRIM(P_DIRECCION), '[[:space:]]+', ' ');

    -- 1. VALIDACIÓN: NOMBRE (Obligatorio)
    IF P_NOMBRE IS NULL OR v_nombre_limpio = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE DEL PROVEEDOR NO PUEDE ESTAR VACÍO.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN: TELÉFONO
    IF P_TELEFONO IS NOT NULL THEN
        IF TRIM(P_TELEFONO) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM PROVEEDORES WHERE TELEFONO = v_telefono_limpio) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO YA ESTÁ REGISTRADO.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- 3. VALIDACIÓN: EMAIL
    IF P_EMAIL IS NOT NULL THEN
        IF TRIM(P_EMAIL) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM PROVEEDORES WHERE EMAIL = v_email_limpio) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL YA ESTÁ REGISTRADO.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- 4. INSERCIÓN FINAL
    INSERT INTO PROVEEDORES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
    VALUES (v_nombre_limpio, v_telefono_limpio, v_email_limpio, v_dir_limpia);

    SELECT CONCAT('EXITO: PROVEEDOR "', v_nombre_limpio, '" INSERTADO. ID: ', LAST_INSERT_ID()) AS MENSAJE;

END ;
DELIMITER ;


--2. ACTUALIZAR

DELIMITER //
drop PROCEDURE if EXISTS SP_ACTUALIZAR_PROVEEDOR;
CREATE PROCEDURE SP_ACTUALIZAR_PROVEEDOR(
    IN P_ID_PROVEEDOR INT,
    IN P_NOMBRE       VARCHAR(100),
    IN P_TELEFONO     VARCHAR(15),
    IN P_EMAIL        VARCHAR(100),
    IN P_DIRECCION    VARCHAR(120)
)
proc_label: BEGIN
    -- Declaración de variables para el proceso
    DECLARE v_nombre_limpio   VARCHAR(100);
    DECLARE v_telefono_limpio VARCHAR(15);
    DECLARE v_email_limpio    VARCHAR(100);
    DECLARE v_dir_limpia      VARCHAR(120);

    -- 1. VALIDAR EXISTENCIA
    IF NOT EXISTS (SELECT 1 FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. LIMPIEZA DE DATOS (Solo si se enviaron valores)
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
        ELSEIF EXISTS (SELECT 1 FROM PROVEEDORES WHERE TELEFONO = v_telefono_limpio AND ID_PROVEEDOR <> P_ID_PROVEEDOR) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO YA PERTENECE A OTRO PROVEEDOR.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_EMAIL IS NOT NULL THEN
        SET v_email_limpio = LOWER(REPLACE(P_EMAIL, ' ', ''));
        IF v_email_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM PROVEEDORES WHERE EMAIL = v_email_limpio AND ID_PROVEEDOR <> P_ID_PROVEEDOR) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL YA PERTENECE A OTRO PROVEEDOR.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_DIRECCION IS NOT NULL THEN
        SET v_dir_limpia = REGEXP_REPLACE(TRIM(P_DIRECCION), '[[:space:]]+', ' ');
    END IF;

    -- 3. ACTUALIZACIÓN DINÁMICA
    UPDATE PROVEEDORES 
    SET 
        NOMBRE    = COALESCE(v_nombre_limpio, NOMBRE),
        TELEFONO  = COALESCE(v_telefono_limpio, TELEFONO),
        EMAIL     = COALESCE(v_email_limpio, EMAIL),
        DIRECCION = COALESCE(v_dir_limpia, DIRECCION)
    WHERE ID_PROVEEDOR = P_ID_PROVEEDOR;

    SELECT CONCAT('EXITO: DATOS ACTUALIZADOS PARA EL PROVEEDOR ID: ', P_ID_PROVEEDOR) AS MENSAJE;

END ;
DELIMITER ;


--3. togler cambiar estado 

DELIMITER //
drop PROCEDURE if EXISTS `SP_TOGGLE_ESTADO_PROVEEDOR`;
CREATE PROCEDURE SP_TOGGLE_ESTADO_PROVEEDOR(
    IN P_ID_PROVEEDOR INT
)
proc_label: BEGIN
    -- 1. Verificamos existencia
    IF NOT EXISTS (SELECT 1 FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PROVEEDOR NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Realizamos el cambio de estado
    UPDATE PROVEEDORES
    SET ESTADO = IF(ESTADO = 'ACTIVO', 'INACTIVO', 'ACTIVO')
    WHERE ID_PROVEEDOR = P_ID_PROVEEDOR;

    -- 3. Retornamos el mensaje usando los datos que ya están en la tabla
    SELECT CONCAT(
        'EXITO: PROVEEDOR "', NOMBRE, '" (ID: ', ID_PROVEEDOR, 
        ') HA SIDO ', ESTADO, '.'
    ) AS MENSAJE
    FROM PROVEEDORES
    WHERE ID_PROVEEDOR = P_ID_PROVEEDOR;

END ;
DELIMITER ;

--4. LISTAR 

DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_PROVEEDORES;
CREATE PROCEDURE SP_LISTAR_PROVEEDORES(
    IN P_FILTRO VARCHAR(100)
)
BEGIN
    SELECT 
        ID_PROVEEDOR, 
        NOMBRE, 
        TELEFONO, 
        EMAIL, 
        DIRECCION, 
        ESTADO
    FROM PROVEEDORES
    WHERE (P_FILTRO IS NULL OR P_FILTRO = '' 
           OR NOMBRE LIKE CONCAT('%', P_FILTRO, '%') 
           OR TELEFONO LIKE CONCAT('%', P_FILTRO, '%'))
    ORDER BY ID_PROVEEDOR ASC; -- <-- CAMBIADO AQUÍ (Ordena 1, 2, 3...)
END ;
DELIMITER ;