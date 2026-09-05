-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
DESCRIPCION DEL MODULO DE CATEGORIAS

Este modulo administra las categorias de productos de la base de datos
BALBU_TECH.

TABLA CATEGORIAS
- ID_CATEGORIA: identificador unico, clave primaria y autoincremental.
- NOMBRE: nombre obligatorio y unico de la categoria.
- DESCRIPCION: detalle informativo de la categoria.
- ICONO_URL: referencia o nombre del icono asociado.
- ESTADO: indica si la categoria esta ACTIVO o INACTIVO. Por defecto es ACTIVO.
- FECHA_REGISTRO: fecha y hora de registro, generada automaticamente.

RESTRICCIONES
- La clave primaria identifica cada categoria.
- NOMBRE UNIQUE impide registrar categorias con el mismo nombre.

La tabla utiliza el motor InnoDB.
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
CREATE INDEX IX_NOMBRE_CATEGORIA ON CATEGORIAS (NOMBRE);


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------


-- 1. INSERTAR
/*
DESCRIPCION DE SP_INSERTAR_CATEGORIA

Inserta una nueva categoria.
- P_NOMBRE: nombre de la categoria.
- P_DESCRIPCION: descripcion de la categoria.
- P_ICONO: icono asociado.

Limpia los espacios de los textos, valida que el nombre sea obligatorio y
comprueba que no exista otra categoria con el mismo nombre. Si las validaciones
son correctas, inserta el registro y devuelve su identificador.
*/
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


-- 2. ACTUALIZAR
/*
DESCRIPCION DE SP_ACTUALIZAR_CATEGORIA

Actualiza los datos de una categoria existente.
- P_ID_CATEGORIA: identificador de la categoria.
- P_NOMBRE: nuevo nombre.
- P_DESCRIPCION: nueva descripcion.
- P_ICONO: nuevo icono.

Verifica que la categoria exista, valida el nombre cuando se recibe y evita
duplicados. Luego actualiza los valores proporcionados y devuelve un mensaje
de confirmacion.
*/
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



-- 3. DESACTIVAR  o activar CATEGORIA  
/*
DESCRIPCION DE SP_TOGGLE_ESTADO_CATEGORIA

Cambia el estado de una categoria entre ACTIVO e INACTIVO.
- P_ID_CATEGORIA: identificador de la categoria.

Verifica que la categoria exista, invierte su estado y devuelve un mensaje con
el nombre, identificador y nuevo estado de la categoria.
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

END ;
DELIMITER ;

--4. BUSCAR CATEGORIAS 
/*
DESCRIPCION DE SP_BUSCAR_CATEGORIAS

Busca categorias por nombre o descripcion.
- P_BUSQUEDA: texto utilizado para realizar la busqueda.

Si el parametro es NULL o esta vacio, devuelve todas las categorias. Si tiene
un valor, busca coincidencias parciales en NOMBRE y DESCRIPCION.
*/
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


--5. BUSQUEDA DE FECHAS 
/*
DESCRIPCION DE 1_SP_CATEGORIAS_POR_FECHA

Consulta las categorias registradas dentro de un periodo.
- P_FECHA_INICIO: fecha y hora inicial.
- P_FECHA_FIN: fecha y hora final.

Devuelve las categorias cuya FECHA_REGISTRO se encuentra entre las dos fechas
recibidas.
*/
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

--6. VERIFICAR SI LA CATEGORIA EXISTE
/*
DESCRIPCION DE 1_SP_VERIFICAR_CATEGORIA_EXISTE

Verifica si ya existe una categoria con un nombre determinado.
- P_NOMBRE: nombre que se desea comprobar.
- P_ID_EXCLUIR: identificador que se excluye de la busqueda, util al editar.

Devuelve el resultado en la columna EXISTE. El identificador excluido permite
validar un nombre sin marcar como duplicado la misma categoria que se edita.
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
END ;
DELIMITER ;

USE BALBU_TECH;
SELECT * FROM `EMPLEADOS;


