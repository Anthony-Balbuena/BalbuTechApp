-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH


/*
TABLA USUARIOS
Cuentas de acceso del sistema: usuario, contrasena en hash y el rol que
le da sus permisos. Cada empleado puede tener una sola cuenta y el nombre
de usuario es unico. La contrasena se guarda en formato hash y la cuenta
arranca ACTIVA.
*/

CREATE TABLE USUARIOS (
  ID_USUARIO INT PRIMARY KEY AUTO_INCREMENT,
  ID_EMPLEADO INT NOT NULL UNIQUE,
  ID_ROL INT NOT NULL,
  USUARIO VARCHAR(50) NOT NULL UNIQUE,
  CONTRASENA VARCHAR(255) NOT NULL,
  ESTADO ENUM('ACTIVO','INACTIVO') DEFAULT 'ACTIVO',
  FECHA_CREACION TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_USUARIO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS(ID_EMPLEADO),
  CONSTRAINT FK_USUARIO_ROL FOREIGN KEY (ID_ROL) REFERENCES ROLES(ID_ROL)
) ENGINE = InnoDB;

/*
INDICE IX_USER
Acelera el login y las busquedas por nombre de usuario, que es el dato
que mas se consulta en esta tabla.
*/
CREATE INDEX IX_USER ON USUARIOS (USUARIO);



-- Migration: Aumentar tamaño de la columna CONTRASENA para almacenar hashes PBKDF2.
-- IMPORTANTE: HAZ BACKUP ANTES DE EJECUTAR.
USE BALBU_TECH;

-- Ver estado actual (opcional):
-- SELECT COLUMN_NAME, COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS
--  WHERE TABLE_SCHEMA='BALBU_TECH' AND TABLE_NAME='USUARIOS' AND COLUMN_NAME='CONTRASENA';

ALTER TABLE `USUARIOS`
  MODIFY COLUMN `CONTRASENA` VARCHAR(512) NOT NULL;  

-- Después de ejecutar esta migración, las nuevas contraseñas se almacenarán
-- en formato `pbkdf2$<iter>$<salt_b64>$<hash_b64>` generado por la aplicación.

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------    


DELIMITER //
/*
SP_GET_USUARIO_LOGIN
Busca la cuenta por su nombre de usuario (solo si esta ACTIVA) y devuelve
el hash de la contrasena junto con el rol, para que la aplicacion compare
la clave y deje entrar.
*/
DROP PROCEDURE IF EXISTS SP_GET_USUARIO_LOGIN //
CREATE PROCEDURE SP_GET_USUARIO_LOGIN(
    IN P_USUARIO VARCHAR(50)
)
BEGIN
    SELECT U.ID_USUARIO, U.CONTRASENA, R.NOMBRE_ROL 
    FROM USUARIOS U
    INNER JOIN ROLES R ON U.ID_ROL = R.ID_ROL
    WHERE U.USUARIO = P_USUARIO 
      AND U.ESTADO = 'ACTIVO';
END //
DELIMITER ;


--Sp para mostrar antes de hacer ciertas acciones. Van en el modulo de  usuarios

-- uso de agregar un usuario
/*
SP_INSERTAR_USUARIO
Crea la cuenta de un usuario nuevo.
Valida que el empleado exista y que aun no tenga cuenta, limpia el nombre
de usuario (minusculas y espacios a puntos) para que no se repita y guarda
el hash de la contrasena recibido.
*/
DELIMITER //

DROP PROCEDURE IF EXISTS SP_INSERTAR_USUARIO ;
CREATE PROCEDURE SP_INSERTAR_USUARIO(
    IN P_ID_EMPLEADO INT,
    IN P_ID_ROL      INT,
    IN P_USUARIO     VARCHAR(50),
    IN P_HASH_CLAVE  VARCHAR(255) 
)
proc_label: BEGIN
    DECLARE v_usuario_limpio VARCHAR(50);
    DECLARE v_nombre_empleado VARCHAR(100);

    -- 1. Validar que el empleado exista
    SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    IF v_nombre_empleado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que el empleado no tenga ya una cuenta (Regla traída de tu 2do módulo)
    IF EXISTS (SELECT 1 FROM USUARIOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE EMPLEADO YA TIENE UN USUARIO ASIGNADO.';
        LEAVE proc_label;
    END IF;

    SET v_usuario_limpio = LOWER(REPLACE(TRIM(P_USUARIO), ' ', '.'));

    -- 3. Validar que el username no esté en uso
    IF EXISTS (SELECT 1 FROM USUARIOS WHERE USUARIO = v_usuario_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: USUARIO YA EN USO.';
        LEAVE proc_label;
    END IF;

    INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA)
    VALUES (P_ID_EMPLEADO, P_ID_ROL, v_usuario_limpio, P_HASH_CLAVE);

    SELECT CONCAT('EXITO: USUARIO "', v_usuario_limpio, '" CREADO.') AS MENSAJE;
END//


DELIMITER ;
--ACTUALIZAR

/*
SP_ACTUALIZAR_USUARIO
Cambia el nombre de usuario, el rol o el empleado de una cuenta existente.
Si alguno llega en NULL se queda como estaba. No toca la contrasena: ese
cambio se hace con su procedimiento aparte.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_USUARIO ;
CREATE OR REPLACE PROCEDURE SP_ACTUALIZAR_USUARIO(
    IN P_ID_USUARIO   INT,
    IN P_USUARIO      VARCHAR(50),
    IN P_ID_ROL       INT,
    IN P_ID_EMPLEADO  INT
)
proc_label: BEGIN
    DECLARE v_usuario_limpio VARCHAR(50);

    IF NOT EXISTS (SELECT 1 FROM `USUARIOS` WHERE `ID_USUARIO` = P_ID_USUARIO) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: USUARIO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- Lógica de limpieza solo si el usuario cambió
    IF P_USUARIO IS NOT NULL THEN
        SET v_usuario_limpio = LOWER(TRIM(P_USUARIO));
    END IF;

    UPDATE `USUARIOS` 
    SET 
        `USUARIO`     = COALESCE(v_usuario_limpio, `USUARIO`),
        -- El COALESCE aquí permite que, si enviamos NULL desde C++, se conserve el hash anterior
        `ID_EMPLEADO` = COALESCE(P_ID_EMPLEADO, `ID_EMPLEADO`),
        `ID_ROL`      = COALESCE(P_ID_ROL, `ID_ROL`)
    WHERE `ID_USUARIO` = P_ID_USUARIO;

    SELECT 'EXITO: DATOS ACTUALIZADOS.' AS MENSAJE;
END//
DELIMITER ;

-- Semilla del administrador: solo se crea si existe el empleado 1 y aun no
-- tiene cuenta, asi la recarga del archivo no se queja ni duplica la fila.
SET @puede_crearse := (SELECT COUNT(*) FROM EMPLEADOS E
                        WHERE E.ID_EMPLEADO = 1
                          AND NOT EXISTS (SELECT 1 FROM USUARIOS U WHERE U.ID_EMPLEADO = 1));
SET @sql_semilla := IF(@puede_crearse = 1,
    'CALL SP_INSERTAR_USUARIO (1, 1, ''abalbuena'', ''Pedro0110'')',
    'SELECT ''SEMILLA DE USUARIO OMITIDA (falta empleado 1 o ya tiene cuenta)'' AS AVISO');
PREPARE semilla_usuario FROM @sql_semilla;
EXECUTE semilla_usuario;
DEALLOCATE PREPARE semilla_usuario;
---TOGGLER PARA ESTADO
DELIMITER //

/*
SP_TOGGLE_ESTADO_USUARIO
Le da la vuelta al estado de la cuenta: de ACTIVO a INACTIVO y viceversa.
Si el ID no existe manda un error; si existe responde con un mensaje que
dice de que estado paso al nuevo.
*/
DROP PROCEDURE IF EXISTS SP_TOGGLE_ESTADO_USUARIO;
CREATE PROCEDURE SP_TOGGLE_ESTADO_USUARIO(
    IN P_ID_USUARIO INT
)
proc_label: BEGIN
    -- VARIABLES PARA CAPTURAR LA INFO ACTUAL
    DECLARE v_USUARIO_NOMBRE VARCHAR(50);
    DECLARE v_ESTADO_ACTUAL  VARCHAR(20);
    DECLARE v_NUEVO_ESTADO   VARCHAR(20);

    -- 1. VALIDAR QUE EL USUARIO EXISTA
    IF NOT EXISTS (SELECT 1 FROM `USUARIOS` WHERE `ID_USUARIO` = P_ID_USUARIO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL USUARIO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. OBTENER ESTADO Y NOMBRE ACTUAL
    SELECT `USUARIO`, `ESTADO` INTO v_USUARIO_NOMBRE, v_ESTADO_ACTUAL 
    FROM `USUARIOS` 
    WHERE `ID_USUARIO` = P_ID_USUARIO;

    -- 3. LÓGICA DEL "INTERRUPTOR" (TOGGLE)
    IF v_ESTADO_ACTUAL = 'ACTIVO' THEN
        SET v_NUEVO_ESTADO = 'INACTIVO';
    ELSE 
        SET v_NUEVO_ESTADO = 'ACTIVO';
    END IF;

    -- 4. APLICAR EL CAMBIO
    UPDATE `USUARIOS` 
    SET `ESTADO` = v_NUEVO_ESTADO 
    WHERE `ID_USUARIO` = P_ID_USUARIO;

    -- 5. MENSAJE FINAL
    SELECT CONCAT(
        'USUARIO: "', v_USUARIO_NOMBRE, 
        '" - CAMBIO DE: ', v_ESTADO_ACTUAL, 
        ' A: ', v_NUEVO_ESTADO
    ) AS MENSAJE;

END //
DELIMITER ;


/*
SP_BUSCAR_USUARIOS_FILTRADO
Lista los usuarios con su empleado, rol y estado, buscando por el nombre
de usuario o por el nombre del empleado. Si la busqueda viene vacia o NULL
trae todos, ordenados por usuario.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_BUSCAR_USUARIOS_FILTRADO ;
CREATE PROCEDURE SP_BUSCAR_USUARIOS_FILTRADO(
    IN P_BUSQUEDA VARCHAR(100)
)
BEGIN
    SELECT
        U.ID_USUARIO,
        U.USUARIO,
        E.NOMBRE AS EMPLEADO,
        R.NOMBRE_ROL AS ROL,
        U.ESTADO
    FROM `USUARIOS` U
    INNER JOIN `ROLES` R ON U.ID_ROL = R.ID_ROL
    INNER JOIN `EMPLEADOS` E ON E.ID_EMPLEADO = U.ID_EMPLEADO
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = ''
           OR U.USUARIO LIKE CONCAT('%', P_BUSQUEDA, '%')
           OR E.NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%'))
    ORDER BY U.USUARIO ASC;
END //

DELIMITER ;


---CAMBIAR CONTRASENA
/*
SP_CAMBIAR_CONTRASENA
Cambia la contrasena de un usuario pero solo si la clave actual que manda
coincide con la guardada. Si el ID no existe o la clave actual esta mal,
manda un error y no cambia nada.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_CAMBIAR_CONTRASENA ;
CREATE PROCEDURE SP_CAMBIAR_CONTRASENA(
    IN P_ID_USUARIO INT,
    IN P_CLAVE_ACTUAL_HASH VARCHAR(255),
    IN P_CLAVE_NUEVA_HASH  VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_usuario_nombre VARCHAR(50);

    -- 1. Validar existencia y que la clave actual sea correcta
    SELECT `USUARIO` INTO v_usuario_nombre 
    FROM `USUARIOS` 
    WHERE `ID_USUARIO` = P_ID_USUARIO 
      AND `CONTRASENA` = P_CLAVE_ACTUAL_HASH;

    IF v_usuario_nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: USUARIO NO ENCONTRADO O CLAVE ACTUAL INCORRECTA.';
        LEAVE proc_label;
    END IF;

    -- 2. Actualizar a la nueva clave
    UPDATE `USUARIOS` 
    SET `CONTRASENA` = P_CLAVE_NUEVA_HASH
    WHERE `ID_USUARIO` = P_ID_USUARIO;

    -- 3. Mensaje de éxito incluyendo el ID y el nombre del usuario
    SELECT CONCAT(
        'EXITO: CONTRASEÑA ACTUALIZADA PARA EL USUARIO: "', 
        v_usuario_nombre, 
        '" (ID: ', P_ID_USUARIO, ')'
    ) AS MENSAJE;

END //
DELIMITER ;



-- LOGIN ADAPTADO AL NUEVO ESQUEMA

/*
SP_LOGIN_USUARIO
Valida el login cruzando usuario, contrasena hash y estado ACTIVO, y
devuelve EXITO con el rol y el ID de la cuenta, o ERROR si las
credenciales no coinciden.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LOGIN_USUARIO ;
CREATE PROCEDURE SP_LOGIN_USUARIO(
    IN P_USUARIO VARCHAR(50),
    IN P_PASSWORD_HASH VARCHAR(255)
)
BEGIN
    DECLARE v_id INT;
    DECLARE v_rol VARCHAR(50);

    -- Buscamos cruzando con la tabla ROLES
    SELECT U.ID_USUARIO, R.NOMBRE_ROL INTO v_id, v_rol 
    FROM USUARIOS U
    INNER JOIN ROLES R ON U.ID_ROL = R.ID_ROL
    WHERE U.USUARIO = P_USUARIO 
      AND U.CONTRASENA = P_PASSWORD_HASH 
      AND U.ESTADO = 'ACTIVO';

    IF v_id IS NOT NULL THEN
        SELECT 'EXITO' AS ESTADO, v_rol AS ROL, v_id AS ID_USUARIO;
    ELSE
        SELECT 'ERROR' AS ESTADO, NULL AS ROL, NULL AS ID_USUARIO;
    END IF;
END //
DELIMITER ;



-- PROCEDIMIENTOS DE APOYO PARA C++ (Se mantienen iguales)
/*
PARA_INSERTAR_USUARIOS
Prepara los datos del formulario de alta de usuario: devuelve en dos
result sets los roles y los empleados disponibles para llenar los selects.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_INSERTAR_USUARIOS ;
CREATE PROCEDURE PARA_INSERTAR_USUARIOS()
BEGIN
    SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL ASC;
    SELECT ID_EMPLEADO, NOMBRE FROM EMPLEADOS ORDER BY ID_EMPLEADO ASC;
END //
DELIMITER ;

/*
PARA_ACTUALIZAR_USUARIOS
Prepara los datos del formulario de edicion de usuario: devuelve cada
cuenta con su rol y su empleado asociados para popular los controles.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_ACTUALIZAR_USUARIOS ;
CREATE PROCEDURE PARA_ACTUALIZAR_USUARIOS()
BEGIN
    SELECT U.ID_USUARIO, U.USUARIO AS NOMBRE_USUARIO, R.ID_ROL, R.NOMBRE_ROL AS NOMBRE_ROL, E.ID_EMPLEADO, E.NOMBRE AS NOMBRE_EMPLEADO
    FROM USUARIOS AS U
    LEFT JOIN ROLES AS R ON U.ID_ROL = R.ID_ROL
    LEFT JOIN EMPLEADOS AS E ON U.ID_EMPLEADO = E.ID_EMPLEADO
    ORDER BY U.ID_USUARIO ASC, E.ID_EMPLEADO ASC, R.ID_ROL ASC;
END //
DELIMITER ;


/*
PARA_ACT_DESAC_USUARIOS
Lista los usuarios con su estado y el nombre del empleado, que es lo que
la pantalla usa para activar o desactivar cuentas.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_ACT_DESAC_USUARIOS ;
CREATE PROCEDURE PARA_ACT_DESAC_USUARIOS ()
BEGIN
    SELECT U.ID_USUARIO, U.USUARIO, U.ESTADO, E.NOMBRE AS EMPLEADO
    FROM USUARIOS AS U
    LEFT JOIN EMPLEADOS AS E ON U.ID_EMPLEADO = E.ID_EMPLEADO
    ORDER BY U.ID_USUARIO ASC;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- FN_TIENE_PERMISO vivia aqui en version angosta (solo REGISTRAR_BONO);
-- la version general y canonica esta en 36- PERMISOS_ROLES.sql (ese archivo la crea al final).




/*
TR_DESACTIVAR_USUARIO_POST_LIQUIDACION
Cuando un empleado pasa de ACTIVO a INACTIVO, este trigger desactiva solo
su cuenta de usuario y deja el cambio anotado en LOG_USUARIOS. Trabaja en
automatico al actualizar EMPLEADOS.
*/
DELIMITER //
DROP TRIGGER IF EXISTS TR_DESACTIVAR_USUARIO_POST_LIQUIDACION ;
CREATE TRIGGER TR_DESACTIVAR_USUARIO_POST_LIQUIDACION
AFTER UPDATE ON EMPLEADOS
FOR EACH ROW
BEGIN
    -- Si el empleado pasa a inactivo
    IF NEW.ESTADO = 'INACTIVO' AND OLD.ESTADO = 'ACTIVO' THEN
        
        -- 1. Desactivar cuenta en la tabla unificada
        UPDATE USUARIOS 
        SET ESTADO = 'INACTIVO'
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO;
        
        -- 2. Registrar en log (Asegúrate de que la tabla LOG_USUARIOS exista)
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO)
        SELECT ID_USUARIO, 'BLOQUEO_AUTO_POR_LIQUIDACION', 'ACTIVO', 'INACTIVO'
        FROM USUARIOS 
        WHERE ID_EMPLEADO = NEW.ID_EMPLEADO;
        
    END IF;
END //
    DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
--- SPs requeridos por la app C++ (usuarios.cpp:buscarUsuario/cambiarClaveUsuario).
--- La tabla usa columna USUARIO; se expone como NOMBRE_USUARIO para la app.
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP PROCEDURE IF EXISTS SP_BUSCAR_USUARIOS ;
CREATE PROCEDURE SP_BUSCAR_USUARIOS(
    IN P_FILTRO VARCHAR(50)
)
BEGIN
    SELECT ID_USUARIO, USUARIO AS NOMBRE_USUARIO, ESTADO FROM USUARIOS
    WHERE (P_FILTRO IS NULL OR P_FILTRO = '')
       OR (USUARIO LIKE CONCAT('%', P_FILTRO, '%'));
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CAMBIAR_CLAVE_USUARIO ;
CREATE PROCEDURE SP_CAMBIAR_CLAVE_USUARIO(
    IN P_ID_USUARIO INT,
    IN P_HASH VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM USUARIOS WHERE ID_USUARIO = P_ID_USUARIO) THEN
        SELECT 'ERROR: EL USUARIO NO EXISTE.' AS MENSAJE;
    ELSE
        UPDATE USUARIOS SET CONTRASENA = P_HASH WHERE ID_USUARIO = P_ID_USUARIO;
        SELECT CONCAT('EXITO: CLAVE DEL USUARIO ID ', P_ID_USUARIO, ' ACTUALIZADA.') AS MENSAJE;
    END IF;
END //
DELIMITER ;