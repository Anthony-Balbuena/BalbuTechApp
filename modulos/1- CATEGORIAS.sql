-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
TABLA CATEGORIAS
Lista las categorias de productos de la tienda: nombre, descripcion e icono.
Solo puede haber una categoria con cada nombre y todas arrancan ACTIVAS.
Se usa para agrupar los productos en el catalogo.
*/


CREATE TABLE CATEGORIAS (
    ID_CATEGORIA INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(50) NOT NULL UNIQUE,
    DESCRIPCION VARCHAR(100),
    ICONO_URL VARCHAR(255),
    ESTADO ENUM('ACTIVO', 'INACTIVO') DEFAULT 'ACTIVO',
    FECHA_REGISTRO DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_CATEGORIA)
) ENGINE = InnoDB;
/*
INDICE IX_NOMBRE_CATEGORIA
Busca categorias por su nombre, asi la busqueda por texto sale rapida
sin recorrer toda la tabla.
*/
CREATE INDEX IX_NOMBRE_CATEGORIA ON CATEGORIAS (NOMBRE);


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------


-- 1. INSERTAR
/*
SP_INSERTAR_CATEGORIA
Da de alta una categoria nueva.
Limpia los espacios del nombre, valida que no este vacio ni repetido, y si
todo esta bien la guarda y devuelve su ID.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_CATEGORIA ;
CREATE PROCEDURE SP_INSERTAR_CATEGORIA(
    IN P_NOMBRE VARCHAR(50),
    -- (09/10/2026) C1. DEFAULTs: la app manda solo el nombre (1 arg).
    IN P_DESCRIPCION VARCHAR(100) DEFAULT NULL,
    IN P_ICONO VARCHAR(255) DEFAULT NULL
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
END //
DELIMITER ;


-- 2. ACTUALIZAR
/*
SP_ACTUALIZAR_CATEGORIA
Cambia nombre, descripcion o icono de una categoria existente.
Revisa que la categoria exista y que el nuevo nombre no este repetido;
lo que no venga se queda como estaba.
*/
DELIMITER //
DROP PROCEDURE if EXISTS SP_ACTUALIZAR_CATEGORIA ;
CREATE PROCEDURE SP_ACTUALIZAR_CATEGORIA(
    IN P_ID_CATEGORIA INT,
    -- (09/10/2026) C2. DEFAULTs: la app manda solo id + nombre (2 args).
    IN P_NOMBRE       VARCHAR(50) DEFAULT NULL,
    IN P_DESCRIPCION  VARCHAR(100) DEFAULT NULL,
    IN P_ICONO        VARCHAR(255) DEFAULT NULL
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
END //
DELIMITER ;



-- 3. DESACTIVAR  o activar CATEGORIA  
/*
SP_TOGGLE_ESTADO_CATEGORIA
Activa o desactiva una categoria.
Verifica que exista, le da la vuelta al estado y confirma con un mensaje
que trae el nombre y el nuevo estado.
*/
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

END //
DELIMITER ;

--4. BUSCAR CATEGORIAS 
/*
SP_BUSCAR_CATEGORIAS
Busca categorias por nombre o descripcion.
Si la busqueda viene vacia o nula, devuelve todas las categorias sin filtrar.
*/
DELIMITER //
drop PROCEDURE if EXISTS SP_BUSCAR_CATEGORIA ;
CREATE PROCEDURE SP_BUSCAR_CATEGORIA(
    IN P_BUSQUEDA VARCHAR(50)
)
BEGIN
    -- Si P_BUSQUEDA es NULL o una cadena vacía, retorna todos los registros
    -- Si tiene valor, busca por NOMBRE o DESCRIPCION
    SELECT * FROM CATEGORIAS 
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '') 
       OR (NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%') 
       OR DESCRIPCION LIKE CONCAT('%', P_BUSQUEDA, '%'));
END //
DELIMITER ;


--5. BUSQUEDA DE FECHAS 
/*
1_SP_CATEGORIAS_POR_FECHA
Trae las categorias registradas entre dos fechas.
Sirve para filtrar por periodo en reportes.
*/
DELIMITER //
CREATE PROCEDURE 1_SP_CATEGORIAS_POR_FECHA(
    IN P_FECHA_INICIO DATETIME,
    IN P_FECHA_FIN DATETIME
)
BEGIN
    SELECT * FROM CATEGORIAS 
    WHERE FECHA_REGISTRO BETWEEN P_FECHA_INICIO AND P_FECHA_FIN;
END //
DELIMITER ;

--6. VERIFICAR SI LA CATEGORIA EXISTE
/*
1_SP_VERIFICAR_CATEGORIA_EXISTE
Revisa si ya existe una categoria con ese nombre.
El ID que se excluye permite validar el nombre al editar sin marcarse
como duplicado a si misma.
*/
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
END //
DELIMITER ;

USE BALBU_TECH;

-----------------------------------------------------------------------------------------------------------------------
--- SP requerido por la app C++ (categorias.cpp:listarCategorias).
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_CATEGORIAS ;
CREATE PROCEDURE SP_LISTAR_CATEGORIAS()
BEGIN
    SELECT ID_CATEGORIA, NOMBRE, ESTADO FROM CATEGORIAS ORDER BY ID_CATEGORIA;
END //
DELIMITER ;


