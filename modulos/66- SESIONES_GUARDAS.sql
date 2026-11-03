-- ================================================================
-- BALBU_TECH - SESIONES DE SERVIDOR Y GUARDAS DE PERMISO
-- ================================================================
-- (03/11/2026) Cierra el ultimo tramo del hallazgo A6: que el permiso valga
-- tambien cuando el SP se llama desde un cliente SQL y no desde la app.
--
-- Como funciona:
--   1. SP_LOGIN_AUTENTICAR emite un TOKEN aleatorio en SESIONES.
--   2. La app lo deja en la conexion con SET @TOKEN_SESION = '<token>'.
--   3. FN_USUARIO_SESION() lo resuelve a un ID_USUARIO, o NULL si no vale.
--   4. Cada SP sensible arranca con CALL SP_EXIGIR_PERMISO('NOMBRE_SP').
--
-- El cliente puede setear la variable, pero no puede inventar un token: solo
-- existen los que emitio el servidor. Un token robado sirve para ese usuario,
-- con sus permisos y hasta que venza.
--
-- SP_EXIGIR_PERMISO es data-driven: el permiso sale de PERMISO_POR_RUTINA.
-- Si EXIGIR = 0, NO bloquea pero deja evidencia en LOG_PERMISO_SP. Eso permite
-- encender la exigencia area por area mirando primero que se habria rechazado.
--
-- Ojo: este modulo REDEFINE SP_LOGIN_AUTENTICAR (la version del modulo 65 no
-- emitia token). Importar 65 y despues 66, en ese orden.
-- Idempotente. Aplicar primero en BALBU_TECH_TEST.
-- ================================================================

-- ================================================================
-- 1) TABLAS
-- ================================================================
CREATE TABLE IF NOT EXISTS SESIONES (
    TOKEN CHAR(64) PRIMARY KEY,
    ID_USUARIO INT NOT NULL,
    CREADA TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    EXPIRA TIMESTAMP NOT NULL,
    CONSTRAINT FK_SESION_USUARIO FOREIGN KEY (ID_USUARIO)
        REFERENCES USUARIOS (ID_USUARIO) ON DELETE CASCADE,
    INDEX IX_SESIONES_EXPIRA (EXPIRA)
) ENGINE = InnoDB;

/*
TABLA PERMISO_POR_RUTINA
Dice que permiso exige cada procedimiento. EXIGIR = 0 es modo auditoria:
se registra la decision pero no se corta la operacion. Una rutina sin fila
queda como "sin exigencia" y se ve en el reporte de cobertura.
*/
CREATE TABLE IF NOT EXISTS PERMISO_POR_RUTINA (
    RUTINA VARCHAR(80) PRIMARY KEY,
    PERMISO VARCHAR(80) NULL,
    EXIGIR TINYINT NOT NULL DEFAULT 0,
    CONSTRAINT FK_PERMISO_RUTINA_PERMISO FOREIGN KEY (PERMISO)
        REFERENCES PERMISOS (NOMBRE_PERMISO) ON UPDATE CASCADE
) ENGINE = InnoDB;

/*
TABLA LOG_PERMISO_SP
Evidencia de que permiso se evaluo en cada llamada. Con EXIGIR = 0 muestra
que se habria rechazado; con EXIGIR = 1 registra tambien los rechazos reales.
*/
CREATE TABLE IF NOT EXISTS LOG_PERMISO_SP (
    ID_LOG INT PRIMARY KEY AUTO_INCREMENT,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    RUTINA VARCHAR(80),
    PERMISO VARCHAR(80),
    USUARIO VARCHAR(50),
    RESULTADO ENUM('OK', 'SIN_SESION', 'SIN_PERMISO', 'SIN_MAPEO') NOT NULL
) ENGINE = InnoDB;

-- ================================================================
-- 2) RESOLUCION DE SESION
-- ================================================================
DELIMITER //
DROP FUNCTION IF EXISTS FN_USUARIO_SESION;
/*
FN_USUARIO_SESION
Devuelve el ID_USUARIO del token que la conexion dejo en @TOKEN_SESION,
o NULL si no hay token, no existe o vencio.
*/
CREATE FUNCTION FN_USUARIO_SESION()
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_token VARCHAR(64) DEFAULT NULL;
    DECLARE v_id INT DEFAULT NULL;

    SET v_token = @TOKEN_SESION;
    IF v_token IS NULL OR v_token = '' THEN
        RETURN NULL;
    END IF;

    SELECT ID_USUARIO INTO v_id
      FROM SESIONES
     WHERE TOKEN = v_token AND EXPIRA > NOW()
     LIMIT 1;

    RETURN v_id;
END//
DELIMITER ;

-- ================================================================
-- 3) GUARDA
-- ================================================================
DELIMITER //
DROP PROCEDURE IF EXISTS SP_EXIGIR_PERMISO;
/*
SP_EXIGIR_PERMISO
Punto unico de control. Lo llama cada SP sensible al empezar.
Con EXIGIR = 0 solo registra; con EXIGIR = 1 corta con SIGNAL.
Una rutina sin fila en PERMISO_POR_RUTINA se registra como SIN_MAPEO y, si
alguna vez se pone el modo estricto global, tambien se corta.
*/
CREATE PROCEDURE SP_EXIGIR_PERMISO(IN P_RUTINA VARCHAR(80))
BEGIN
    DECLARE v_exigir TINYINT DEFAULT 0;
    DECLARE v_permiso VARCHAR(80) DEFAULT NULL;
    DECLARE v_id INT DEFAULT NULL;
    DECLARE v_usuario VARCHAR(50) DEFAULT NULL;
    DECLARE v_ok TINYINT DEFAULT 0;
    DECLARE v_estricto TINYINT DEFAULT 0;
    DECLARE v_admin TINYINT DEFAULT 0;

    SELECT EXIGIR, PERMISO INTO v_exigir, v_permiso
      FROM PERMISO_POR_RUTINA WHERE RUTINA = P_RUTINA;

    -- Interruptor global: permite volver a modo auditoria sin redeploy.
    SELECT IFNULL(CAST(VALOR AS UNSIGNED), 0) INTO v_estricto
      FROM SECRETO_SISTEMA WHERE CLAVE = 'EXIGIR_PERMISO_SP';

    -- (03/11/2026) Una conexion administrativa (root o balbu_admin) queda
    -- fuera del control: ya tiene ALL PRIVILEGES sobre el esquema, asi que
    -- bloquearla solo rompe mantenimiento y tests. USER() devuelve el cliente
    -- real aunque el SP sea DEFINER.
    IF SUBSTRING_INDEX(USER(), '@', 1) IN ('root', 'balbu_admin') THEN
        SET v_admin = 1;
    END IF;

    IF v_admin = 0 THEN
        SET v_id = FN_USUARIO_SESION();
    END IF;

    IF v_admin = 1 THEN
        -- Nada que controlar ni que registrar.
        SET v_exigir = 0;
        SET v_estricto = 0;
    ELSEIF v_id IS NULL THEN
        -- Se registra siempre: sin sesion no hay forma de saber si era legitimo.
        INSERT INTO LOG_PERMISO_SP (RUTINA, PERMISO, USUARIO, RESULTADO)
        VALUES (P_RUTINA, v_permiso, NULL, 'SIN_SESION');
        IF v_exigir = 1 OR v_estricto = 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SESION INVALIDA O VENCIDA.';
        END IF;
    ELSE
        SELECT USUARIO INTO v_usuario FROM USUARIOS WHERE ID_USUARIO = v_id;
        SET v_ok = IFNULL(FN_TIENE_PERMISO(v_usuario, v_permiso), 0);

        IF v_ok = 0 THEN
            INSERT INTO LOG_PERMISO_SP (RUTINA, PERMISO, USUARIO, RESULTADO)
            VALUES (P_RUTINA, v_permiso, v_usuario,
                    IF(v_permiso IS NULL, 'SIN_MAPEO', 'SIN_PERMISO'));
            IF v_exigir = 1 OR v_estricto = 1 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: SIN PERMISO PARA ESTA OPERACION.';
            END IF;
        ELSEIF v_exigir = 1 OR v_estricto = 1 THEN
            -- Con la exigencia prendida se deja rastro de las permitidas
            -- tambien; en modo auditoria solo se registran los problemas,
            -- si no el log se llena con cada lectura normal.
            INSERT INTO LOG_PERMISO_SP (RUTINA, PERMISO, USUARIO, RESULTADO)
            VALUES (P_RUTINA, v_permiso, v_usuario, 'OK');
        END IF;
    END IF;
END//
DELIMITER ;

-- ================================================================
-- 4) CIERRE DE SESION
-- ================================================================
DELIMITER //
DROP PROCEDURE IF EXISTS SP_CERRAR_SESION_SERVIDOR;
/*
SP_CERRAR_SESION_SERVIDOR
Borra el token de la conexion. Si no hay token, no hace nada.
*/
CREATE PROCEDURE SP_CERRAR_SESION_SERVIDOR()
BEGIN
    IF @TOKEN_SESION IS NOT NULL AND @TOKEN_SESION <> '' THEN
        DELETE FROM SESIONES WHERE TOKEN = @TOKEN_SESION;
        SET @TOKEN_SESION = NULL;
    END IF;
END//
DELIMITER ;

-- ================================================================
-- 5) INTERRUPTORES
-- ================================================================
INSERT INTO SECRETO_SISTEMA (CLAVE, VALOR) VALUES ('EXIGIR_PERMISO_SP', '0')
ON DUPLICATE KEY UPDATE CLAVE = CLAVE;

-- ================================================================
-- 6) LOGIN QUE EMITE TOKEN
-- ================================================================
-- Reemplaza la version del modulo 65 (misma verificacion, mas el token).
-- Devuelve una columna TOKEN extra; los demas casos la devuelven NULL.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LOGIN_AUTENTICAR;
CREATE PROCEDURE SP_LOGIN_AUTENTICAR(
    IN P_USUARIO VARCHAR(50),
    IN P_CREDENCIAL VARCHAR(255)
)
BEGIN
    DECLARE v_ventana INT DEFAULT 15;
    DECLARE v_max_fallos INT DEFAULT 5;
    DECLARE v_fallos INT DEFAULT 0;
    DECLARE v_minutos INT DEFAULT 0;
    DECLARE v_desde TIMESTAMP DEFAULT TIMESTAMP '1970-01-01 00:00:01';

    DECLARE v_id INT DEFAULT NULL;
    DECLARE v_id_emp INT DEFAULT NULL;
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;
    DECLARE v_rol INT DEFAULT NULL;
    DECLARE v_rol_nombre VARCHAR(50) DEFAULT NULL;
    DECLARE v_serv VARCHAR(128) DEFAULT NULL;
    DECLARE v_clave VARCHAR(512) DEFAULT NULL;
    DECLARE v_salt VARCHAR(64) DEFAULT NULL;
    DECLARE v_iter INT DEFAULT NULL;
    DECLARE v_esperado VARCHAR(128) DEFAULT NULL;
    DECLARE v_ok TINYINT DEFAULT 0;
    DECLARE v_pepper VARCHAR(255) DEFAULT NULL;
    DECLARE v_token CHAR(64) DEFAULT NULL;

    -- 1) Bloqueo: cuenta los fallos posteriores al ultimo EXITOSO.
    SELECT IFNULL(MAX(FECHA_ACCESO), v_desde) INTO v_desde
      FROM LOG_ACCESOS
     WHERE USUARIO_INTENTADO = P_USUARIO AND ESTADO_INTENTO = 'EXITOSO';

    SELECT COUNT(*) INTO v_fallos
      FROM LOG_ACCESOS
     WHERE USUARIO_INTENTADO = P_USUARIO
       AND ESTADO_INTENTO = 'FALLIDO'
       AND FECHA_ACCESO >= NOW() - INTERVAL v_ventana MINUTE
       AND FECHA_ACCESO > v_desde;

    IF v_fallos >= v_max_fallos THEN
        SELECT IFNULL(CEIL(TIMESTAMPDIFF(SECOND, NOW(),
                      MIN(FECHA_ACCESO) + INTERVAL v_ventana MINUTE) / 60), 1) INTO v_minutos
          FROM LOG_ACCESOS
         WHERE USUARIO_INTENTADO = P_USUARIO
           AND ESTADO_INTENTO = 'FALLIDO'
           AND FECHA_ACCESO >= NOW() - INTERVAL v_ventana MINUTE
           AND FECHA_ACCESO > v_desde;
        IF v_minutos < 1 THEN SET v_minutos = 1; END IF;
        SELECT 'BLOQUEADO' AS RESULTADO, v_minutos AS MINUTOS,
               NULL AS ID_USUARIO, NULL AS ID_EMPLEADO, NULL AS USUARIO_BD,
               NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL,
               NULL AS TOKEN;
    ELSE
        SELECT ID_USUARIO, ID_EMPLEADO, ESTADO, ID_ROL, CLAVE_SERVIDOR,
               CONTRASENA, SALT_LOGIN, ITER_LOGIN
          INTO v_id, v_id_emp, v_estado, v_rol, v_serv, v_clave, v_salt, v_iter
          FROM USUARIOS
         WHERE USUARIO = P_USUARIO
         LIMIT 1;

        IF v_id IS NULL THEN
            CALL SP_REGISTRAR_ACCESO(NULL, P_USUARIO, 'FALLIDO');
            SELECT 'CLAVE' AS RESULTADO, 0 AS MINUTOS,
                   NULL AS ID_USUARIO, NULL AS ID_EMPLEADO, NULL AS USUARIO_BD,
                   NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL,
                   NULL AS TOKEN;
        ELSE
            -- 2) Comparacion segun el formato guardado.
            IF v_serv IS NOT NULL THEN
                SELECT VALOR INTO v_pepper
                  FROM SECRETO_SISTEMA WHERE CLAVE = 'PEPPER_LOGIN';
                SET v_esperado = SHA2(CONCAT(IFNULL(v_pepper, ''), P_CREDENCIAL), 256);
                SET v_ok = (v_esperado = v_serv);
            ELSEIF v_clave IS NOT NULL AND v_clave LIKE 'pbkdf2$%' THEN
                SET v_esperado = SUBSTRING_INDEX(v_clave, '$', -1);
                SET v_ok = (v_esperado = P_CREDENCIAL);
            ELSE
                SET v_ok = (v_clave IS NOT NULL AND v_clave = P_CREDENCIAL);
            END IF;

            IF v_ok = 1 THEN
                IF IFNULL(v_estado, '') <> 'ACTIVO' THEN
                    CALL SP_REGISTRAR_ACCESO(v_id, P_USUARIO, 'INACTIVO');
                    SELECT 'INACTIVO' AS RESULTADO, 0 AS MINUTOS,
                           NULL AS ID_USUARIO, NULL AS ID_EMPLEADO, NULL AS USUARIO_BD,
                           NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL,
                           NULL AS TOKEN;
                ELSE
                    -- 3) Migracion al formato del servidor en el primer login.
                    IF v_serv IS NULL THEN
                        IF v_salt IS NULL AND v_clave LIKE 'pbkdf2$%' THEN
                            SET v_salt = SUBSTRING_INDEX(SUBSTRING_INDEX(v_clave, '$', 3), '$', -1);
                            SET v_iter = CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(v_clave, '$', 2), '$', -1) AS UNSIGNED);
                        END IF;
                        IF v_salt IS NOT NULL THEN
                            SELECT VALOR INTO v_pepper
                              FROM SECRETO_SISTEMA WHERE CLAVE = 'PEPPER_LOGIN';
                            UPDATE USUARIOS
                               SET SALT_LOGIN = v_salt,
                                   ITER_LOGIN = IFNULL(v_iter, 100000),
                                   CLAVE_SERVIDOR = SHA2(CONCAT(IFNULL(v_pepper, ''), P_CREDENCIAL), 256),
                                   CONTRASENA = NULL
                             WHERE ID_USUARIO = v_id;
                        END IF;
                    END IF;

                    CALL SP_REGISTRAR_ACCESO(v_id, P_USUARIO, 'EXITOSO');

                    -- 4) Token de sesion. Se limpian los vencidos de paso.
                    DELETE FROM SESIONES WHERE EXPIRA < NOW();
                    SET v_token = LOWER(SHA2(CONCAT(UUID(), UUID(), RAND(), NOW(6), v_id), 256));
                    INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA)
                    VALUES (v_token, v_id, NOW() + INTERVAL 12 HOUR);

                    SELECT R.NOMBRE_ROL INTO v_rol_nombre
                      FROM ROLES R WHERE R.ID_ROL = v_rol;

                    SELECT 'OK' AS RESULTADO, 0 AS MINUTOS,
                           v_id AS ID_USUARIO, v_id_emp AS ID_EMPLEADO,
                           P_USUARIO AS USUARIO_BD, v_estado AS ESTADO_BD,
                           v_rol AS ID_ROL, v_rol_nombre AS NOMBRE_ROL,
                           v_token AS TOKEN;
                END IF;
            ELSE
                CALL SP_REGISTRAR_ACCESO(v_id, P_USUARIO, 'FALLIDO');
                SELECT 'CLAVE' AS RESULTADO, 0 AS MINUTOS,
                       NULL AS ID_USUARIO, NULL AS ID_EMPLEADO, NULL AS USUARIO_BD,
                       NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL,
                       NULL AS TOKEN;
            END IF;
        END IF;
    END IF;
END//
DELIMITER ;

SELECT 'MODULO 66 APLICADO: SESIONES Y GUARDAS LISTAS (MODO AUDITORIA).' AS RESULTADO;
