
/*
TABLA MARCAS
Almacena las marcas de productos disponibles en el sistema.
Solo puede haber una marca con cada nombre y todas arrancan ACTIVAS.
La tabla usa InnoDB para permitir claves foraneas y transacciones.
*/
CREATE TABLE MARCAS (
    ID_MARCA INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(100) NOT NULL UNIQUE,
    ESTADO ENUM('ACTIVA', 'INACTIVA') NOT NULL DEFAULT 'ACTIVA',
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_MARCA)
) ENGINE = InnoDB;


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------

-- 1.INSERT
/*
SP_INSERTAR_MARCA
Registra una marca nueva.
Limpia el nombre, valida que no este vacio ni repetido y si todo esta bien
la guarda y devuelve un mensaje con el ID creado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_MARCA;
CREATE PROCEDURE SP_INSERTAR_MARCA (
    IN P_NOMBRE VARCHAR(50)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);

    SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');

    IF v_nombre_limpio = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE DE LA MARCA ES OBLIGATORIO.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM MARCAS WHERE NOMBRE = v_nombre_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA MARCA YA EXISTE.';
        LEAVE proc_label;
    END IF;

    INSERT INTO MARCAS (NOMBRE) VALUES (v_nombre_limpio);

    SELECT CONCAT('EXITO: MARCA "', v_nombre_limpio, '" INSERTADA. ID: ', LAST_INSERT_ID()) AS MENSAJE;
END //
DELIMITER ;


--2. ACTUALIZAR
/*
SP_ACTUALIZAR_MARCA
Cambia el nombre de una marca existente.
Verifica que la marca exista y que el nuevo nombre no este repetido; si no
se manda nombre, se queda el que tenia.
*/
DELIMITER //
DROP PROCEDURE if EXISTS SP_ACTUALIZAR_MARCA ;
CREATE PROCEDURE SP_ACTUALIZAR_MARCA(
    IN P_ID_MARCA INT,
    IN P_NOMBRE   VARCHAR(50)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);

    IF NOT EXISTS (SELECT 1 FROM MARCAS WHERE ID_MARCA = P_ID_MARCA) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA MARCA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_NOMBRE IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
        IF v_nombre_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM MARCAS WHERE NOMBRE = v_nombre_limpio AND ID_MARCA <> P_ID_MARCA) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA MARCA YA EXISTE.';
            LEAVE proc_label;
        END IF;
    END IF;

    UPDATE MARCAS SET NOMBRE = COALESCE(v_nombre_limpio, NOMBRE) WHERE ID_MARCA = P_ID_MARCA;

    SELECT CONCAT('EXITO: MARCA ID ', P_ID_MARCA, ' ACTUALIZADA.') AS MENSAJE;
END //
DELIMITER ;

--3. BUSCAR 
/*
SP_BUSCAR_MARCAS
Busca marcas por nombre parcial.
Si la busqueda viene vacia o nula, devuelve todas las marcas.
*/
DELIMITER //
drop PROCEDURE if EXISTS SP_BUSCAR_MARCA; 
CREATE PROCEDURE SP_BUSCAR_MARCA(
    IN P_BUSQUEDA VARCHAR(100)
)
BEGIN
    -- Busca por coincidencia parcial en el NOMBRE
    -- Retorna todo si P_BUSQUEDA está vacío
    SELECT * FROM MARCAS 
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '') 
       OR (NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%'));
END //
DELIMITER ;

--4. TOGLER ACTUALIZAR ESTADO 

/*
SP_TOGGLE_ESTADO_MARCA
Activa o desactiva una marca.
Verifica que exista, le da la vuelta al estado y confirma con un mensaje
que trae el nombre y el nuevo estado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_TOGGLE_ESTADO_MARCA;
CREATE PROCEDURE SP_TOGGLE_ESTADO_MARCA(
    IN P_ID_MARCA INT
)
proc_label: BEGIN
    -- 1. Validamos existencia
    IF NOT EXISTS (SELECT 1 FROM MARCAS WHERE ID_MARCA = P_ID_MARCA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: MARCA NO ENCONTRADA.';
        LEAVE proc_label;
    END IF;

    -- 2. Realizamos el cambio de estado (Toggle). Ojo: MARCAS.ESTADO es
    -- ENUM('ACTIVA','INACTIVA') en femenino; con 'ACTIVO' daba ERROR 1265.
    UPDATE MARCAS
    SET ESTADO = IF(ESTADO = 'ACTIVA', 'INACTIVA', 'ACTIVA')
    WHERE ID_MARCA = P_ID_MARCA;

    -- 3. Retornamos el mensaje con los datos actualizados
    SELECT CONCAT(
        'EXITO: MARCA "', NOMBRE, '" (ID: ', ID_MARCA, 
        ') HA SIDO ', ESTADO, '.'
    ) AS MENSAJE
    FROM MARCAS
    WHERE ID_MARCA = P_ID_MARCA;

END //
DELIMITER ;

--5. BUSCAR TODAS LAS MARCAS 
/*
2_SP_OBTENER_MARCA
Devuelve la marca con el ID que se le pida.
Sirve para cargar una marca en concreto para verla o editarla.
*/
DELIMITER //
CREATE PROCEDURE 2_SP_OBTENER_MARCA(IN P_ID INT)
BEGIN
    SELECT * FROM MARCAS WHERE ID_MARCA = P_ID;
END //
DELIMITER ;

--6. BUSCAR MARCAS ACTIVAS
/*
2_SP_LISTAR_MARCAS
Lista las marcas, con la opcion de traer solo las activas.
Si el parametro viene en 1 muestra solo ACTIVAS, si no muestra todas.
*/
DELIMITER //
CREATE PROCEDURE 2_SP_LISTAR_MARCAS(IN P_SOLO_ACTIVAS BIT)
BEGIN
    IF P_SOLO_ACTIVAS = 1 THEN
        SELECT * FROM MARCAS WHERE ESTADO = 'ACTIVA';
    ELSE
        SELECT * FROM MARCAS;
    END IF;
END //
DELIMITER ;

CALL `SP_INSERTAR_MARCA` ('ASUS');
CALL `SP_INSERTAR_MARCA` ('MSI');
CALL `SP_INSERTAR_MARCA` ('LOGITECH');
CALL `SP_INSERTAR_MARCA` ('RAZER');
CALL `SP_INSERTAR_MARCA` ('HP');
CALL `SP_INSERTAR_MARCA` ('WESTERN DIGITAL');
CALL `SP_INSERTAR_MARCA` ('IPHONE');
CALL `SP_INSERTAR_MARCA` ('XIAOMI');
CALL `SP_INSERTAR_MARCA` ('JBL');
CALL `SP_INSERTAR_MARCA` ('RED MAGIC');

-----------------------------------------------------------------------------------------------------------------------
--- SP requerido por la app C++ (marcas.cpp:listarMarcas).
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_MARCAS ;
CREATE PROCEDURE SP_LISTAR_MARCAS()
BEGIN
    SELECT ID_MARCA, NOMBRE, ESTADO FROM MARCAS ORDER BY ID_MARCA;
END //
DELIMITER ;
