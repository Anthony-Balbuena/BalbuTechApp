-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH


/*
TABLA: USUARIOS — Descripción detallada

Propósito: almacena las credenciales y asignaciones de rol para los
usuarios del sistema. Cada usuario se asocia a un empleado y a un rol;
la separación entre `EMPLEADOS` y `USUARIOS` permite gestionar acceso
independiente del registro laboral.

Columnas clave:
- ID_USUARIO: PK autoincremental que identifica la cuenta.
- ID_EMPLEADO: FK a `EMPLEADOS(ID_EMPLEADO)`. Un empleado puede tener
    como máximo una cuenta (único en esta columna).
- ID_ROL: FK a `ROLES(ID_ROL)` que determina permisos y alcance.
- USUARIO: identificador público usado para login (único).
- CONTRASENA: hash de la contraseña; usar formatos seguros (pbkdf2, bcrypt).
- ESTADO: control lógico ('ACTIVO'/'INACTIVO') para habilitar/deshabilitar cuentas.
- FECHA_CREACION: timestamp de creación de la cuenta.

Consideraciones de seguridad:
- Las contraseñas deben almacenarse en formato hash; el cambio a
    `VARCHAR(512)` permite almacenar formatos PBKDF2 con salt e iteraciones.
- Operaciones que modifican contraseñas deben realizarse mediante
    procedimientos específicos que verifiquen hash actual y registren
    auditoría cuando aplique.

Integridad referencial y restricciones:
- FK a `EMPLEADOS` y `ROLES` garantizan referencias válidas.
- `ID_EMPLEADO` declarado `UNIQUE` obliga a 1:1 entre empleado y usuario.
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
-- Descripción:
--  Inserta un nuevo usuario en la tabla `USUARIOS` aplicando las siguientes reglas:
--   1) Valida que el empleado indicado exista en `EMPLEADOS`.
--   2) Verifica que ese empleado no tenga ya una cuenta (regla 1 cuenta por empleado).
--   3) Normaliza el valor de `P_USUARIO` (minusculas, trim, espacios->puntos) como `v_usuario_limpio`.
--   4) Comprueba que `v_usuario_limpio` no esté en uso por otro usuario.
--   5) Si todo es válido, inserta la fila en `USUARIOS` con el hash recibido en `P_HASH_CLAVE`.
--   6) Devuelve un mensaje de éxito o lanza una excepción (`SIGNAL`) en caso de error.
-- Parámetros:
--   P_ID_EMPLEADO INT, P_ID_ROL INT, P_USUARIO VARCHAR(50), P_HASH_CLAVE VARCHAR(255)
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

-- SP_TOGGLE_ESTADO_USUARIO
-- Descripción:
--  Alterna el estado (`ESTADO`) de un usuario entre 'ACTIVO' e 'INACTIVO'.
--  Pasos:
--   1) Verifica existencia de `ID_USUARIO`.
--   2) Lee el estado actual y calcula el nuevo estado.
--   3) Actualiza la fila y retorna un mensaje con el cambio.

    SELECT CONCAT('EXITO: USUARIO "', v_usuario_limpio, '" CREADO.') AS MENSAJE;
END;

DELIMITER ;

--ACTUALIZAR

-- SP_ACTUALIZAR_USUARIO
-- Descripción:
--  Actualiza los datos de un usuario existente en la tabla `USUARIOS`.
--  Pasos y reglas:
--   1) Verifica que `P_ID_USUARIO` exista en `USUARIOS`. Si no existe, lanza un error.
--   2) Si se proporciona `P_USUARIO`, lo normaliza (minúsculas, trim) y lo usa para actualizar.
--   3) Para `P_ID_ROL` y `P_ID_EMPLEADO`, si se envía NULL se mantienen los valores actuales (se usa COALESCE).
--   4) No altera la contraseña; la actualización de contraseñas debe hacerse con el procedimiento específico.
--   5) Devuelve un mensaje 'EXITO: DATOS ACTUALIZADOS.' al finalizar correctamente.
-- Parámetros:
--   P_ID_USUARIO INT: id del usuario a actualizar.
--   P_USUARIO VARCHAR(50): nuevo nombre de usuario (opcional).
--   P_ID_ROL INT: nuevo id de rol (opcional).
--   P_ID_EMPLEADO INT: nuevo id de empleado (opcional).
-- Uso:
--   CALL SP_ACTUALIZAR_USUARIO(123, 'nuevo.usuario', 2, NULL);
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
END;
DELIMITER ;
---TOGGLER PARA ESTADO
DELIMITER //

-- SP_TOGGLE_ESTADO_USUARIO
-- Descripción:
--  Alterna el valor de la columna `ESTADO` para un usuario ('ACTIVO' <-> 'INACTIVO').
--  Uso: Llamar con el `P_ID_USUARIO` objetivo desde la UI o backend para invertir su estado.
-- Parámetros: P_ID_USUARIO INT
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

END ;
DELIMITER ;


-- SP_BUSCAR_USUARIOS_FILTRADO
-- Descripción:
--  Busca y lista usuarios aplicando un filtro opcional sobre el nombre de usuario
--  o el nombre del empleado. Devuelve usuario, empleado, rol y estado.
-- Parámetro: P_BUSQUEDA VARCHAR(100) (opcional, admite NULL o cadena vacía).
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
END ;

DELIMITER ;


---CAMBIAR CONTRASENA
-- SP_CAMBIAR_CONTRASENA
-- Descripción:
--  Cambia la contraseña (hash) de un usuario verificando que la contraseña actual coincida.
--  Pasos:
--   1) Valida que el `ID_USUARIO` exista y que `P_CLAVE_ACTUAL_HASH` coincida con la almacenada.
--   2) Si la validación pasa, actualiza `CONTRASENA` con `P_CLAVE_NUEVA_HASH`.
--   3) Devuelve un mensaje de éxito o lanza `SIGNAL` en caso de error.
-- Parámetros: P_ID_USUARIO INT, P_CLAVE_ACTUAL_HASH VARCHAR(255), P_CLAVE_NUEVA_HASH VARCHAR(255)
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

END ;
DELIMITER ;



-- LOGIN ADAPTADO AL NUEVO ESQUEMA

-- SP_LOGIN_USUARIO
-- Descripción:
--  Valida credenciales contra la tabla `USUARIOS` (usuario + hash) y devuelve
--  el resultado ('EXITO'/'ERROR'), el nombre del rol y el `ID_USUARIO` si procede.
-- Uso: CALL SP_LOGIN_USUARIO(P_USUARIO, P_PASSWORD_HASH);
-- Parámetros: P_USUARIO VARCHAR(50), P_PASSWORD_HASH VARCHAR(255)
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
END ;



-- PROCEDIMIENTOS DE APOYO PARA C++ (Se mantienen iguales)
-- PARA_INSERTAR_USUARIOS
-- Descripción:
--  Devuelve listas necesarias para poblar formularios de inserción: roles y empleados.
--  Uso: CALL PARA_INSERTAR_USUARIOS();
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_INSERTAR_USUARIOS ;
CREATE PROCEDURE PARA_INSERTAR_USUARIOS()
BEGIN
    SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL ASC;
    SELECT ID_EMPLEADO, NOMBRE FROM EMPLEADOS ORDER BY ID_EMPLEADO ASC;
END ;
DELIMITER ;

-- PARA_ACTUALIZAR_USUARIOS
-- Descripción:
--  Devuelve una vista combinada de usuarios con su rol y empleado asociado,
--  útil para poblar formularios de edición/actualización. Uso: CALL PARA_ACTUALIZAR_USUARIOS();
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_ACTUALIZAR_USUARIOS ;
CREATE PROCEDURE PARA_ACTUALIZAR_USUARIOS()
BEGIN
    SELECT U.ID_USUARIO, U.USUARIO AS NOMBRE_USUARIO, R.ID_ROL, R.NOMBRE_ROL AS NOMBRE_ROL, E.ID_EMPLEADO, E.NOMBRE AS NOMBRE_EMPLEADO
    FROM USUARIOS AS U
    LEFT JOIN ROLES AS R ON U.ID_ROL = R.ID_ROL
    LEFT JOIN EMPLEADOS AS E ON U.ID_EMPLEADO = E.ID_EMPLEADO
    ORDER BY U.ID_USUARIO ASC, E.ID_EMPLEADO ASC, R.ID_ROL ASC;
END ;
DELIMITER ;


-- PARA_ACT_DESAC_USUARIOS
-- Descripción:
--  Lista usuarios y su estado para permitir activar o desactivar cuentas desde la UI.
--  Uso: CALL PARA_ACT_DESAC_USUARIOS();
DELIMITER //
DROP PROCEDURE IF EXISTS PARA_ACT_DESAC_USUARIOS ;
CREATE PROCEDURE PARA_ACT_DESAC_USUARIOS ()
BEGIN
    SELECT U.ID_USUARIO, U.USUARIO, U.ESTADO, E.NOMBRE AS EMPLEADO
    FROM USUARIOS AS U
    LEFT JOIN EMPLEADOS AS E ON U.ID_EMPLEADO = E.ID_EMPLEADO
    ORDER BY U.ID_USUARIO ASC;
END ;
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- FUNCIÓN DE PERMISOS ADAPTADA AL NUEVO ESQUEMA
-- FN_TIENE_PERMISO
-- Descripción:
--  Evalúa si un usuario (por su `USUARIO`) tiene permitido ejecutar una acción
--  concreta según el rol asociado. Retorna TRUE/FALSE.
-- Parámetros:
--  `P_USERNAME` VARCHAR(50)  - nombre de usuario a consultar
--  `P_ACCION`   VARCHAR(50)  - acción a validar (ej: 'REGISTRAR_BONO')
-- Uso: SELECT FN_TIENE_PERMISO('juan.perez', 'REGISTRAR_BONO');
DELIMITER //
DROP FUNCTION IF EXISTS FN_TIENE_PERMISO ;
CREATE FUNCTION FN_TIENE_PERMISO(P_USERNAME VARCHAR(50), P_ACCION VARCHAR(50))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE v_rol_nombre VARCHAR(50);
    
    -- Se obtiene el rol mediante el JOIN
    SELECT R.NOMBRE_ROL INTO v_rol_nombre 
    FROM USUARIOS U
    INNER JOIN ROLES R ON U.ID_ROL = R.ID_ROL
    WHERE U.USUARIO = P_USERNAME;
    
    -- Ajusta los nombres de roles según los que hayas creado (Ej: ROLE_ADMIN)
    IF P_ACCION = 'REGISTRAR_BONO' AND (v_rol_nombre = 'ROLE_ADMIN' OR v_rol_nombre = 'ROLE_GERENTE') THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END ;

DELIMITER ;




-- TR_DESACTIVAR_USUARIO_POST_LIQUIDACION
-- Descripción:
--  Trigger que se ejecuta AFTER UPDATE sobre `EMPLEADOS`. Si un empleado pasa
--  de `ACTIVO` a `INACTIVO`, desactiva automáticamente la cuenta en `USUARIOS`
--  (pone `ESTADO = 'INACTIVO'`) y registra el cambio en `LOG_USUARIOS`.
--  Nota: Asegúrate de que `LOG_USUARIOS` exista y acepte los campos usados.
-- Uso/efecto: automático al actualizar la columna `ESTADO` en `EMPLEADOS`.
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
END ;
    DELIMITER ;