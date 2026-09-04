
/*
ESTRUCTURA DE LA TABLA MARCAS

Esta tabla almacena las marcas de productos disponibles en el sistema.

- ID_MARCA: identificador único autoincremental de la marca.
- NOMBRE: nombre de la marca (único), usado para búsquedas y visualización.
- ESTADO: indica si la marca está 'ACTIVA' o 'INACTIVA'.
- FECHA_REGISTRO: timestamp de creación.

Restricciones:
- La clave primaria es ID_MARCA.
- NOMBRE es único para evitar duplicados.
La tabla utiliza InnoDB para permitir claves foráneas y transacciones.
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
DESCRIPCION DE SP_INSERTAR_MARCA

Registra una nueva marca validando y limpiando el nombre recibido.

- Parámetros:
    - P_NOMBRE: nombre de la marca a insertar.

Comportamiento:
- Normaliza espacios y trim del nombre.
- Verifica que el nombre no esté vacío y que no exista otra marca con el mismo nombre.
- Inserta la marca y retorna un mensaje con el ID creado.
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
END ;
DELIMITER ;


--2. ACTUALIZAR
/*
DESCRIPCION DE SP_ACTUALIZAR_MARCA

Actualiza el nombre de una marca existente.

- Parámetros:
    - P_ID_MARCA: id de la marca a actualizar.
    - P_NOMBRE: nuevo nombre (opcional).

Comportamiento:
- Verifica que la marca exista.
- Si se proporciona nombre, lo normaliza, valida que no esté vacío y que no exista otra marca con ese nombre.
- Actualiza la marca y devuelve mensaje de éxito.
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
END ;
DELIMITER ;

--3. BUSCAR 
/*
DESCRIPCION DE SP_BUSCAR_MARCAS

Busca marcas por nombre parcial. Si `P_BUSQUEDA` está vacío o NULL, retorna todas las marcas.

- Parámetros:
    - P_BUSQUEDA: cadena parcial a buscar en el nombre.
*/
DELIMITER //
drop PROCEDURE if EXISTS SP_BUSCAR_MARCAS; 
CREATE PROCEDURE SP_BUSCAR_MARCAS(
    IN P_BUSQUEDA VARCHAR(100)
)
BEGIN
    -- Busca por coincidencia parcial en el NOMBRE
    -- Retorna todo si P_BUSQUEDA está vacío
    SELECT * FROM MARCAS 
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '') 
       OR (NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%'));
END ;
DELIMITER ;

--4. TOGLER ACTUALIZAR ESTADO 

/*
DESCRIPCION DE SP_TOGGLE_ESTADO_MARCA

Activa o desactiva una marca (toggle) verificando su existencia.

- Parámetros:
    - P_ID_MARCA: id de la marca a cambiar de estado.

Comportamiento:
- Valida existencia y cambia el campo ESTADO entre 'ACTIVA' y 'INACTIVA'.
- Retorna un mensaje con el estado actualizado.
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

    -- 2. Realizamos el cambio de estado (Toggle)
    UPDATE MARCAS
    SET ESTADO = IF(ESTADO = 'ACTIVO', 'INACTIVO', 'ACTIVO')
    WHERE ID_MARCA = P_ID_MARCA;

    -- 3. Retornamos el mensaje con los datos actualizados
    SELECT CONCAT(
        'EXITO: MARCA "', NOMBRE, '" (ID: ', ID_MARCA, 
        ') HA SIDO ', ESTADO, '.'
    ) AS MENSAJE
    FROM MARCAS
    WHERE ID_MARCA = P_ID_MARCA;

END ;
DELIMITER ;

--5. BUSCAR TODAS LAS MARCAS 
/*
DESCRIPCION DE 2_SP_OBTENER_MARCA

Retorna la marca cuyo ID se indique.

- Parámetros:
    - P_ID: id de la marca a consultar.
*/
DELIMITER //
CREATE PROCEDURE 2_SP_OBTENER_MARCA(IN P_ID INT)
BEGIN
    SELECT * FROM MARCAS WHERE ID_MARCA = P_ID;
END ;
DELIMITER ;

--6. BUSCAR MARCAS ACTIVAS
/*
DESCRIPCION DE 2_SP_LISTAR_MARCAS

Lista las marcas; opcionalmente solo las activas.

- Parámetros:
  - P_SOLO_ACTIVAS: si es 1 retorna solo las marcas con ESTADO = 'ACTIVA', si no retorna todas.
*/
DELIMITER //
CREATE PROCEDURE 2_SP_LISTAR_MARCAS(IN P_SOLO_ACTIVAS BIT)
BEGIN
    IF P_SOLO_ACTIVAS = 1 THEN
        SELECT * FROM MARCAS WHERE ESTADO = 'ACTIVA';
    ELSE
        SELECT * FROM MARCAS;
    END IF;
END ;
DELIMITER ;

CALL `2_SP_INSERTAR_MARCA` ('ASUS');
CALL `2_SP_INSERTAR_MARCA` ('MSI');
CALL `2_SP_INSERTAR_MARCA` ('LOGITECH');
CALL `2_SP_INSERTAR_MARCA` ('RAZER');
CALL `2_SP_INSERTAR_MARCA` ('HP');
CALL `2_SP_INSERTAR_MARCA` ('WESTERN DIGITAL');
CALL `2_SP_INSERTAR_MARCA` ('IPHONE');
CALL `2_SP_INSERTAR_MARCA` ('XIAOMI');
CALL `2_SP_INSERTAR_MARCA` ('JBL');
CALL `2_SP_INSERTAR_MARCA` ('RED MAGIC');
