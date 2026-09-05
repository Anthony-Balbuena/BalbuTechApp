-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
DESCRIPCION DEL MODULO ROLES

Este módulo contiene la definición de la tabla `ROLES` y procedimientos
relacionados para gestionar los roles del sistema (crear, actualizar,
buscar y listar).

TABLA ROLES
- ID_ROL: identificador único autoincremental.
- NOMBRE_ROL: nombre del rol (único), usado para permisos y asignaciones.

Restricciones:
- La tabla utiliza InnoDB para permitir transacciones y claves foráneas.
*/
CREATE TABLE ROLES (
    ID_ROL INT PRIMARY KEY AUTO_INCREMENT,
    NOMBRE_ROL VARCHAR(50) NOT NULL UNIQUE
) ENGINE = InnoDB; 
/*
DESCRIPCION DEL INDICE IX_ROLES_NOMBRE

Índice no único sobre `NOMBRE_ROL` que acelera búsquedas y listados.
*/
CREATE INDEX IX_ROLES_NOMBRE ON ROLES(NOMBRE_ROL);


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------


--INSERTAR
/*
DESCRIPCION DE SP_INSERTAR_ROL

Inserta un nuevo rol en la tabla `ROLES`.

- Parámetros:
  - P_NOMBRE_ROL: nombre del rol a insertar.

Comportamiento:
- Normaliza espacios y comprueba que el nombre no sea vacío.
- Verifica duplicados; si existe, lanza un error.
- Inserta la nueva fila y devuelve un mensaje con el ID.
*/
DELIMITER//

drop PROCEDURE IF EXISTS SP_INSERTAR_ROL;

CREATE PROCEDURE SP_INSERTAR_ROL(
    IN P_NOMBRE_ROL VARCHAR(50)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);

    SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE_ROL), '[[:space:]]+', ' ');

    IF v_nombre_limpio = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE DEL ROL ES OBLIGATORIO.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM ROLES WHERE NOMBRE_ROL = v_nombre_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE ROL YA EXISTE.';
        LEAVE proc_label;
    END IF;

    INSERT INTO ROLES (NOMBRE_ROL) VALUES (v_nombre_limpio);

    SELECT CONCAT('EXITO: ROL "', v_nombre_limpio, '" INSERTADO. ID: ', LAST_INSERT_ID()) AS MENSAJE;
END ;
DELIMITER ;




--ACTUALIZAR 
/*
DESCRIPCION DE SP_ACTUALIZAR_ROL

Actualiza el nombre de un rol existente.

- Parámetros:
    - P_ID_ROL: id del rol a actualizar.
    - P_NOMBRE_ROL: nuevo nombre del rol.

Comportamiento:
- Verifica existencia y evita duplicados. Retorna mensaje de éxito.
*/
DELIMITER //
 DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_ROL ;
CREATE PROCEDURE SP_ACTUALIZAR_ROL(
    IN P_ID_ROL INT,
    IN P_NOMBRE_ROL VARCHAR(50)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(50);

    IF NOT EXISTS (SELECT 1 FROM ROLES WHERE ID_ROL = P_ID_ROL) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL ROL NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_NOMBRE_ROL IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE_ROL), '[[:space:]]+', ' ');
        IF v_nombre_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE DEL ROL NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM ROLES WHERE NOMBRE_ROL = v_nombre_limpio AND ID_ROL <> P_ID_ROL) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE ROL YA EXISTE.';
            LEAVE proc_label;
        END IF;
    END IF;

    UPDATE ROLES SET NOMBRE_ROL = COALESCE(v_nombre_limpio, NOMBRE_ROL) WHERE ID_ROL = P_ID_ROL;

    SELECT CONCAT('EXITO: ROL ID ', P_ID_ROL, ' ACTUALIZADO.') AS MENSAJE;
END ;
DELIMITER ;




--BUSCAR 
/*
DESCRIPCION DE SP_BUSCAR_ROLES

Busca roles por nombre parcial. Si `P_BUSQUEDA` es NULL o vacío, devuelve todos.

- Parámetros:
  - P_BUSQUEDA: texto para buscar en `NOMBRE_ROL`.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_BUSCAR_ROLES ; 
CREATE PROCEDURE SP_BUSCAR_ROLES(
    IN P_BUSQUEDA VARCHAR(50)
)
BEGIN
    SELECT * FROM ROLES 
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '') 
       OR (NOMBRE_ROL LIKE CONCAT('%', P_BUSQUEDA, '%'));
END ;
DELIMITER ; 

--LISTAR ROLES
/*
DESCRIPCION DE SP_LISTAR_ROLES

Retorna la lista de roles con su id y nombre, ordenada alfabéticamente.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS  SP_LISTAR_ROLES ;
CREATE PROCEDURE SP_LISTAR_ROLES()
BEGIN
    SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY NOMBRE_ROL ASC;
END ;
DELIMITER ;