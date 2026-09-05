-- Active: 1788274174973@@127.0.0.1@3306@BALBU_TECH
/*
MODULO: PROVEEDORES — Descripción general y propósito

Este archivo contiene la definición de la tabla `PROVEEDORES` y los
procedimientos almacenados relacionados. El módulo gestiona el CRUD de
proveedores, índices para búsquedas frecuentes y utilidades para cambiar
el estado de un proveedor. Los procedimientos normalizan entradas,
validan unicidades y retornan mensajes amigables para la capa C++.

Secciones principales:
- Definición de la tabla `PROVEEDORES` (estructura de columnas y
    restricciones).
- Índices para búsquedas rápidas.
- Procedimientos almacenados: insertar, actualizar, toggle de estado
    y listar.
*/
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
/*
ÍNDICE: IX_PROVEEDOR_NOMBRE

Propósito: acelerar búsquedas por el campo `NOMBRE`, usado en ayudas
de UI y búsquedas parciales. No es único; soporta consultas `LIKE`.
*/
CREATE INDEX IX_PROVEEDOR_NOMBRE ON PROVEEDORES (NOMBRE);

-- Para filtrar proveedores activos rápidamente
/*
ÍNDICE: IX_PROVEEDOR_ESTADO

Propósito: optimizar filtros por `ESTADO` ('ACTIVO'/'INACTIVO') en
listados administrativos y reportes.
*/
CREATE INDEX IX_PROVEEDOR_ESTADO ON PROVEEDORES (ESTADO);
----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------
/*
SECCIÓN: PROCEDIMIENTOS ALMACENADOS

Comentarios generales: los procedimientos usan limpieza de datos
(REGEXP_REPLACE, TRIM), validaciones y `SIGNAL SQLSTATE '45000'` para
reportar errores controlados. Las respuestas de éxito se retornan como
SELECT con mensajes amigables para integrarse con el cliente C++.

A continuación: `SP_INSERTAR_PROVEEDOR`, `SP_ACTUALIZAR_PROVEEDOR`,
`SP_TOGGLE_ESTADO_PROVEEDOR` y `SP_LISTAR_PROVEEDORES`.
*/

--1. INSERTAR 
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_PROVEEDOR;
/*
SP: SP_INSERTAR_PROVEEDOR

Propósito: insertar un nuevo proveedor.

Parámetros:
- P_NOMBRE (VARCHAR(100)): obligatorio; se normaliza espacios.
- P_TELEFONO (VARCHAR(15)): opcional; se limpia de caracteres no numéricos
    y se valida unicidad si se proporciona.
- P_EMAIL (VARCHAR(100)): opcional; normalizado a minúsculas y sin espacios;
    se valida unicidad si se proporciona.
- P_DIRECCION (VARCHAR(120)): opcional; se normaliza espacios internos.

Comportamiento:
- Valida obligatoriedad de `P_NOMBRE`.
- Si `P_TELEFONO` o `P_EMAIL` se pasan, valida que no existan duplicados.
- Inserta el registro y devuelve un mensaje con `LAST_INSERT_ID()`.
*/
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
/*
SP: SP_ACTUALIZAR_PROVEEDOR

Propósito: actualizar campos de un proveedor existente de forma parcial.

Parámetros:
- P_ID_PROVEEDOR (INT): id del proveedor a actualizar (obligatorio).
- P_NOMBRE, P_TELEFONO, P_EMAIL, P_DIRECCION: valores opcionales; si son
    NULL no se modifican.

Comportamiento:
- Verifica existencia del proveedor.
- Normaliza y valida unicidad de teléfono/email cuando se proporcionan.
- Actualiza solo los campos enviados usando `COALESCE`.
- Retorna mensaje de éxito estandarizado.
*/

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
/*
SP: SP_TOGGLE_ESTADO_PROVEEDOR

Propósito: alternar el campo `ESTADO` entre 'ACTIVO' e 'INACTIVO'.

Parámetros:
- P_ID_PROVEEDOR (INT): id del proveedor cuyo estado se alternará.

Comportamiento:
- Valida que el proveedor exista.
- Actualiza `ESTADO` con la lógica IF(ESTADO='ACTIVO','INACTIVO','ACTIVO').
- Retorna un mensaje con el nombre y el nuevo estado.
*/

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
/*
SP: SP_LISTAR_PROVEEDORES

Propósito: listar proveedores aplicando un filtro opcional por nombre o
teléfono.

Parámetros:
- P_FILTRO (VARCHAR(100)): texto opcional; si es NULL o vacío devuelve
    todos los proveedores. Cuando se proporciona, se usa para buscar en
    `NOMBRE` y `TELEFONO` con `LIKE`.

Comportamiento:
- Devuelve columnas clave: ID_PROVEEDOR, NOMBRE, TELEFONO, EMAIL,
    DIRECCION, ESTADO.
- Ordena los resultados por `ID_PROVEEDOR`.
*/

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