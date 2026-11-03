-- ================================================================
-- BALBU_TECH - VERIFICACION DE CLAVE DEL LADO DEL SERVIDOR
-- ================================================================
-- (03/11/2026) Hasta aca el cliente leia USUARIOS.CONTRASENA y verificaba
-- PBKDF2 en C++. Eso obligaba a darle a balbu_app SELECT sobre el hash: con
-- la clave del .env cualquiera bajaba los hashes y los atacaba offline.
--
-- Ahora el flujo es:
--   1. SP_LOGIN_PARAMETROS(usuario) -> SAL, ITER, FORMATO (la sal no es secreta).
--   2. El cliente deriva PBKDF2 con esa sal e iteraciones.
--   3. SP_LOGIN_AUTENTICAR(usuario, derivado) compara del lado del servidor,
--      aplica el bloqueo por intentos y escribe LOG_ACCESOS.
--
-- El valor guardado se vuelve SHA2(pepper || derivado). El pepper vive en
-- SECRETO_SISTEMA, que la app no puede leer: sin el, un volcado de USUARIOS
-- no sirve para atacar offline. Los usuarios se migran solos en su primer
-- login exitoso (CONTRASENA queda en NULL).
--
-- El bloqueo pasa a ser del servidor: llamar al SP desde un cliente SQL no
-- lo saltea, porque el conteo y el registro viven aca.
--
-- Idempotente. Aplicar primero en BALBU_TECH_TEST.
-- ================================================================

-- ================================================================
-- 1) SECRETO DEL SERVIDOR
-- ================================================================
CREATE TABLE IF NOT EXISTS SECRETO_SISTEMA (
    CLAVE VARCHAR(50) PRIMARY KEY,
    VALOR VARCHAR(255) NOT NULL
) ENGINE = InnoDB;

-- El valor se genera una sola vez; si ya existe, se respeta.
INSERT INTO SECRETO_SISTEMA (CLAVE, VALOR)
VALUES ('PEPPER_LOGIN', LOWER(SHA2(CONCAT(UUID(), UUID(), NOW(6), RAND()), 256)))
ON DUPLICATE KEY UPDATE CLAVE = CLAVE;

-- ================================================================
-- 2) COLUMNAS DEL FORMATO NUEVO
-- ================================================================
ALTER TABLE USUARIOS
    ADD COLUMN IF NOT EXISTS SALT_LOGIN VARCHAR(64) NULL,
    ADD COLUMN IF NOT EXISTS ITER_LOGIN INT NULL,
    ADD COLUMN IF NOT EXISTS CLAVE_SERVIDOR VARCHAR(128) NULL;

-- CONTRASENA deja de ser NOT NULL: en el formato nuevo queda vacia y el
-- verificador es CLAVE_SERVIDOR.
ALTER TABLE USUARIOS MODIFY CONTRASENA VARCHAR(512) NULL;

-- ================================================================
-- 3) PARAMETROS PUBLICOS DEL LOGIN
-- ================================================================
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LOGIN_PARAMETROS;
/*
SP_LOGIN_PARAMETROS
Devuelve lo que el cliente necesita para derivar la clave: sal, iteraciones
y formato. Nada de esto es secreto: sin CLAVE_SERVIDOR y sin el pepper, la
sal no sirve para atacar el hash.
Si el usuario no existe devuelve una sal fija para que el cliente derive
igual y la respuesta no delate por tiempo si la cuenta existe.
*/
CREATE PROCEDURE SP_LOGIN_PARAMETROS(IN P_USUARIO VARCHAR(50))
BEGIN
    DECLARE v_salt VARCHAR(64) DEFAULT NULL;
    DECLARE v_iter INT DEFAULT NULL;
    DECLARE v_serv VARCHAR(128) DEFAULT NULL;
    DECLARE v_clave VARCHAR(512) DEFAULT NULL;

    SELECT SALT_LOGIN, ITER_LOGIN, CLAVE_SERVIDOR, CONTRASENA
      INTO v_salt, v_iter, v_serv, v_clave
      FROM USUARIOS
     WHERE USUARIO = P_USUARIO
     LIMIT 1;

    IF v_serv IS NOT NULL AND v_salt IS NOT NULL THEN
        SELECT v_salt AS SAL, IFNULL(v_iter, 100000) AS ITER, 'SERVIDOR' AS FORMATO;
    ELSEIF v_clave IS NOT NULL AND v_clave LIKE 'pbkdf2$%' THEN
        SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(v_clave, '$', 3), '$', -1) AS SAL,
               CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(v_clave, '$', 2), '$', -1) AS UNSIGNED) AS ITER,
               'PBKDF2' AS FORMATO;
    ELSEIF v_clave IS NOT NULL AND v_clave <> '' THEN
        SELECT NULL AS SAL, 0 AS ITER, 'SHA256' AS FORMATO;
    ELSE
        SELECT 'AAAAAAAAAAAAAAAAAAAAAA==' AS SAL, 100000 AS ITER, 'NOEXISTE' AS FORMATO;
    END IF;
END//
DELIMITER ;

-- ================================================================
-- 4) AUTENTICACION, BLOQUEO Y REGISTRO
-- ================================================================
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LOGIN_AUTENTICAR;
/*
SP_LOGIN_AUTENTICAR
Verifica la credencial derivada por el cliente, aplica el bloqueo por fuerza
bruta y deja el intento en LOG_ACCESOS. Devuelve siempre una fila con:
RESULTADO (OK | CLAVE | BLOQUEADO | INACTIVO), MINUTOS, y los datos de
sesion cuando corresponde.

Un intento con la cuenta ya bloqueada NO escribe en LOG_ACCESOS: si
escribiera, cada reintento correria la ventana y el bloqueo no venceria.
*/
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
               NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL;
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
                   NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL;
        ELSE
            -- 2) Comparacion segun el formato guardado. Cada formato se
            -- compara contra algo distinto: en el del servidor lo guardado es
            -- SHA2(pepper||derivado), no el derivado en claro.
            IF v_serv IS NOT NULL THEN
                SELECT VALOR INTO v_pepper
                  FROM SECRETO_SISTEMA WHERE CLAVE = 'PEPPER_LOGIN';
                SET v_esperado = SHA2(CONCAT(IFNULL(v_pepper, ''), P_CREDENCIAL), 256);
                SET v_ok = (v_esperado = v_serv);
            ELSEIF v_clave IS NOT NULL AND v_clave LIKE 'pbkdf2$%' THEN
                -- El cliente manda el derivado; el hash es el ultimo campo.
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
                           NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL;
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

                    SELECT R.NOMBRE_ROL INTO v_rol_nombre
                      FROM ROLES R WHERE R.ID_ROL = v_rol;

                    SELECT 'OK' AS RESULTADO, 0 AS MINUTOS,
                           v_id AS ID_USUARIO, v_id_emp AS ID_EMPLEADO,
                           P_USUARIO AS USUARIO_BD, v_estado AS ESTADO_BD,
                           v_rol AS ID_ROL, v_rol_nombre AS NOMBRE_ROL;
                END IF;
            ELSE
                CALL SP_REGISTRAR_ACCESO(v_id, P_USUARIO, 'FALLIDO');
                SELECT 'CLAVE' AS RESULTADO, 0 AS MINUTOS,
                       NULL AS ID_USUARIO, NULL AS ID_EMPLEADO, NULL AS USUARIO_BD,
                       NULL AS ESTADO_BD, NULL AS ID_ROL, NULL AS NOMBRE_ROL;
            END IF;
        END IF;
    END IF;
END//
DELIMITER ;

-- ================================================================
-- 5) SIN LECTURA DEL HASH POR PARTE DE LA APP
-- ================================================================
-- La app ya no necesita CONTRASENA: db/grant-minimos.sql quita esa columna
-- del grant y se aplica aparte con db/aplicar-grants.sh (requiere root).
-- No se hace aca para que el modulo siga siendo importable con balbu_admin,
-- que no tiene GRANT OPTION.

SELECT 'MODULO 65 APLICADO: LOGIN VERIFICADO EN EL SERVIDOR.' AS RESULTADO;
