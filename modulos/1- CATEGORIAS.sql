-- Active: 1788274174973@@127.0.0.1@3306
/*
 MÓDULO: CATEGORÍAS
 ------------------
 Administra el catálogo de categorías de productos y expone procedimientos
 almacenados para crear, editar, activar/desactivar, consultar y validar
 categorías.

 Reglas principales:
 - NOMBRE es obligatorio, único y se almacena sin espacios redundantes.
 - ESTADO se controla mediante un cambio entre ACTIVO e INACTIVO.
 - Las búsquedas admiten coincidencias en NOMBRE y DESCRIPCION.
*/

-- ================================================================
-- ESTRUCTURA DEL CATÁLOGO
-- ================================================================
CREATE TABLE CATEGORIAS (
    ID_CATEGORIA INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(50) NOT NULL UNIQUE,
    DESCRIPCION VARCHAR(100),
    ICONO_URL VARCHAR(255),
    ESTADO ENUM('ACTIVO', 'INACTIVO') DEFAULT 'ACTIVO',
    FECHA_REGISTRO DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_CATEGORIA)
) ENGINE = InnoDB;
CREATE INDEX IX_NOMBRE_CATEGORIA ON CATEGORIAS (NOMBRE);


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------

-- ================================================================
-- 1. INSERTAR CATEGORÍA
-- Limpia los textos, valida el nombre y evita duplicados.
-- ================================================================
SELECT * FROM `USUARIOS`;
-- TODO: indicar aquí el esquema activo si la conexión no lo establece.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_CATEGORIA ;
CREATE PROCEDURE SP_INSERTAR_CATEGORIA(
    IN P_NOMBRE VARCHAR(50),
    IN P_DESCRIPCION VARCHAR(100),
    IN P_ICONO VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);
    DECLARE v_desc_limpia   VARCHAR(100);

    -- 0. LIMPIEZA
    SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    SET v_desc_limpia   = REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' ');

    -- 1. VALIDACIÓN NOMBRE
    IF v_nombre_limpio = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE ES OBLIGATORIO.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN DUPLICADOS
    IF EXISTS (SELECT 1 FROM CATEGORIAS WHERE NOMBRE = v_nombre_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA CATEGORÍA YA EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. INSERCIÓN
    INSERT INTO CATEGORIAS (NOMBRE, DESCRIPCION, ICONO_URL) 
    VALUES (v_nombre_limpio, v_desc_limpia, P_ICONO);

    SELECT CONCAT('EXITO: CATEGORÍA "', v_nombre_limpio, '" INSERTADA. ID: ', LAST_INSERT_ID()) AS MENSAJE;
END ;
DELIMITER ;
-- Ejemplos de inserción:
CALL `1_SP_INSERTAR_CATEGORIA`('COMPUTADORAS PORTATILES O LAPTOPS', 'EQUIPOS DE COMPUTO MOVILES', 'ICON-LAPTOP');

CALL `1_SP_INSERTAR_CATEGORIA`('TARJETA DE VIDEO', 'COMPONENTE DE PROCESAMIENDO GRAFICO', 'ICON-GPU');
 CALL `1_SP_INSERTAR_CATEGORIA` ('RAM', 'MEMORIA DE ACCESO ALEATORIO', 'ICON-RAM');
CALL `1_SP_INSERTAR_CATEGORIA`('CPU', 'UNIDAD DE PROCESAMIENTO', 'ICON CPU');






-- ================================================================
-- 2. ACTUALIZAR CATEGORÍA
-- Permite actualizar parcialmente nombre, descripción e icono.
-- ================================================================
DELIMITER //

DROP PROCEDURE if EXISTS SP_ACTUALIZAR_CATEGORIA ;

CREATE PROCEDURE SP_ACTUALIZAR_CATEGORIA(
    IN P_ID_CATEGORIA INT,
    IN P_NOMBRE       VARCHAR(50),
    IN P_DESCRIPCION  VARCHAR(100),
    IN P_ICONO        VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);
    DECLARE v_desc_limpia   VARCHAR(100);

    IF NOT EXISTS (SELECT 1 FROM CATEGORIAS WHERE ID_CATEGORIA = P_ID_CATEGORIA) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CATEGORÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_NOMBRE IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
        IF v_nombre_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM CATEGORIAS WHERE NOMBRE = v_nombre_limpio AND ID_CATEGORIA <> P_ID_CATEGORIA) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE NOMBRE YA ESTÁ EN USO.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_DESCRIPCION IS NOT NULL THEN
        SET v_desc_limpia = REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' ');
    END IF;

    UPDATE CATEGORIAS 
    SET NOMBRE = COALESCE(v_nombre_limpio, NOMBRE),
        DESCRIPCION = COALESCE(v_desc_limpia, DESCRIPCION),
        ICONO_URL = COALESCE(P_ICONO, ICONO_URL)
    WHERE ID_CATEGORIA = P_ID_CATEGORIA;

    SELECT CONCAT('EXITO: CATEGORÍA ID ', P_ID_CATEGORIA, ' ACTUALIZADA.') AS MENSAJE;
END ;
DELIMITER ;



-- ================================================================
-- 3. ACTIVAR / DESACTIVAR CATEGORÍA
-- Alterna ESTADO sin eliminar físicamente el registro.
-- ================================================================
DELIMITER //
DROP PROCEDURE IF EXISTS `SP_TOGGLE_ESTADO_CATEGORIA` ;
CREATE PROCEDURE SP_TOGGLE_ESTADO_CATEGORIA(
    IN P_ID_CATEGORIA INT
)
proc_label: BEGIN
    -- 1. Validamos existencia
    IF NOT EXISTS (SELECT 1 FROM CATEGORIAS WHERE ID_CATEGORIA = P_ID_CATEGORIA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CATEGORÍA NO ENCONTRADA.';
        LEAVE proc_label;
    END IF;

    -- 2. Realizamos el cambio de estado (Toggle)
    UPDATE CATEGORIAS
    SET ESTADO = IF(ESTADO = 'ACTIVO', 'INACTIVO', 'ACTIVO')
    WHERE ID_CATEGORIA = P_ID_CATEGORIA;

    -- 3. Retornamos el mensaje con los datos actualizados
    SELECT CONCAT(
        'EXITO: CATEGORÍA "', NOMBRE, '" (ID: ', ID_CATEGORIA, 
        ') HA SIDO ', ESTADO, '.'
    ) AS MENSAJE
    FROM CATEGORIAS
    WHERE ID_CATEGORIA = P_ID_CATEGORIA;

END ;
DELIMITER ;

-- ================================================================
-- 4. BUSCAR CATEGORÍAS
-- Sin término devuelve todas; con término busca en nombre o descripción.
-- ================================================================
drop PROCEDURE if EXISTS SP_BUSCAR_CATEGORIAS ;
CREATE PROCEDURE SP_BUSCAR_CATEGORIAS(
    IN P_BUSQUEDA VARCHAR(50)
)
BEGIN
    -- Si P_BUSQUEDA es NULL o una cadena vacía, retorna todos los registros
    -- Si tiene valor, busca por NOMBRE o DESCRIPCION
    SELECT * FROM CATEGORIAS 
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '') 
       OR (NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%') 
       OR DESCRIPCION LIKE CONCAT('%', P_BUSQUEDA, '%'));
END ;
DELIMITER ;


-- ================================================================
-- 5. CONSULTAR CATEGORÍAS POR FECHA DE REGISTRO
-- Devuelve las categorías cuyo registro está dentro del intervalo indicado.
-- ================================================================
DELIMITER //
CREATE PROCEDURE 1_SP_CATEGORIAS_POR_FECHA(
    IN P_FECHA_INICIO DATETIME,
    IN P_FECHA_FIN DATETIME
)
BEGIN
    SELECT * FROM CATEGORIAS 
    WHERE FECHA_REGISTRO BETWEEN P_FECHA_INICIO AND P_FECHA_FIN;
END ;
DELIMITER ;

-- ================================================================
-- 6. VERIFICAR EXISTENCIA DE CATEGORÍA
-- Retorna 1 si el nombre ya existe; P_ID_EXCLUIR permite editar un registro.
-- ================================================================
DELIMITER //
CREATE PROCEDURE 1_SP_VERIFICAR_CATEGORIA_EXISTE(
    IN P_NOMBRE VARCHAR(50),
    IN P_ID_EXCLUIR INT -- Útil para edición: ignora el ID actual
)
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM CATEGORIAS 
        WHERE NOMBRE = TRIM(P_NOMBRE) 
        AND ID_CATEGORIA <> P_ID_EXCLUIR
    ) AS EXISTE;
END ;
DELIMITER ;

USE BALBU_TECH;
SELECT * FROM `EMPLEADOS;


