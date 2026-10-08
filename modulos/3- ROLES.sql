-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
TABLA ROLES
Lista los roles del sistema (ADMIN, GERENTE, VENDEDOR, etc) que despues
se asignan a los usuarios. El nombre del rol tiene que ser unico.
La tabla usa InnoDB para permitir transacciones y claves foraneas.
*/
CREATE TABLE ROLES (
    ID_ROL INT PRIMARY KEY AUTO_INCREMENT,
    NOMBRE_ROL VARCHAR(50) NOT NULL UNIQUE
) ENGINE = InnoDB; 
/*
INDICE IX_ROLES_NOMBRE
Indice no unico sobre NOMBRE_ROL que acelera las busquedas y listados
de roles por su nombre.
*/
CREATE INDEX IX_ROLES_NOMBRE ON ROLES(NOMBRE_ROL);


----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------
SELECT * FROM ROLES; 

--INSERTAR
/*
SP_INSERTAR_ROL
Crea un rol nuevo en el sistema.
Limpia el nombre, valida que no este vacio ni repetido y si todo esta bien
lo guarda y devuelve un mensaje con el ID.
*/
DELIMITER //

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
END //
DELIMITER ;




--ACTUALIZAR 
/*
SP_ACTUALIZAR_ROL
Cambia el nombre de un rol existente.
Verifica que el rol exista y que el nuevo nombre no este repetido, y si
todo esta bien lo actualiza y confirma con un mensaje.
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
END //
DELIMITER ;




--BUSCAR 
/*
SP_BUSCAR_ROLES
Busca roles por nombre parcial.
Si la busqueda viene vacia o nula, devuelve todos los roles.
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
END //
DELIMITER ;

--LISTAR ROLES
/*
SP_LISTAR_ROLES
Devuelve todos los roles con su ID y nombre, ordenados alfabeticamente.
Sirve para llenar los menu y selects del sistema.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS  SP_LISTAR_ROLES ;
CREATE PROCEDURE SP_LISTAR_ROLES()
BEGIN
    SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY NOMBRE_ROL ASC;
END //
DELIMITER ;