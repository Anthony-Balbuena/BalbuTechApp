-- ================================================================
-- BALBU_TECH - CAMBIO DE CLAVE EN EL FORMATO DEL SERVIDOR
-- ================================================================
-- (05/11/2026) El modulo 65 movio la verificacion de la clave al servidor:
-- desde entonces el verificador es USUARIOS.CLAVE_SERVIDOR =
-- SHA2(pepper || derivado) y CONTRASENA queda en NULL para todo usuario que
-- ya entro una vez.
--
-- SP_CAMBIAR_CLAVE_USUARIO se quedo atras: escribia CONTRASENA con un hash
-- SHA256 del cliente. Con un usuario migrado eso tenia dos consecuencias:
--
--   1. El login compara CLAVE_SERVIDOR primero, asi que la clave nueva no
--      entraba: la vieja seguia funcionando.
--   2. CONTRASENA volvia a tener material de clave, que es justo lo que el
--      modulo 65 habia sacado.
--
-- Este modulo lo reescribe para que reciba el derivado en el formato
-- serializado que ya produce la app (pbkdf2$iter$sal$hash), lo guarde con el
-- pepper y cierre las sesiones abiertas del usuario.
--
-- Quien puede: solo USUARIOS_CLAVE (ADMIN). Es un reset administrativo: no
-- pide la clave actual porque la app no puede verificarla sin exponer el
-- material de clave.
--
-- Requiere el modulo 66 (SP_EXIGIR_PERMISO, SESIONES y SECRETO_SISTEMA).
-- La guarda va incluida en el cuerpo para que el modulo sea autosuficiente:
-- si se aplica suelto, igual queda protegido.
-- Idempotente.
-- ================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SP_CAMBIAR_CLAVE_USUARIO;
CREATE PROCEDURE SP_CAMBIAR_CLAVE_USUARIO(
    IN P_ID_USUARIO INT,
    IN P_HASH       VARCHAR(512)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_iter   INT DEFAULT NULL;
    DECLARE v_salt   VARCHAR(64) DEFAULT NULL;
    DECLARE v_dk     VARCHAR(128) DEFAULT NULL;
    DECLARE v_pepper VARCHAR(255) DEFAULT NULL;

    CALL SP_EXIGIR_PERMISO('SP_CAMBIAR_CLAVE_USUARIO');

    SELECT COUNT(*) INTO v_existe FROM USUARIOS WHERE ID_USUARIO = P_ID_USUARIO;

    IF v_existe = 0 THEN
        SELECT 'ERROR: EL USUARIO NO EXISTE.' AS MENSAJE;
    ELSEIF P_HASH IS NULL
        OR P_HASH NOT REGEXP '^pbkdf2\\$[1-9][0-9]*\\$[A-Za-z0-9+/]+={0,2}\\$[A-Za-z0-9+/]+={0,2}$' THEN
        -- Nunca aceptar texto plano ni el SHA256 viejo: los dos dejarian la
        -- clave en un formato que el login ya no usa. El patron tambien exige
        -- iteraciones numericas: sin el, un 'pbkdf2$abc$...' moria en un
        -- 1292 crudo al castear.
        SELECT 'ERROR: FORMATO DE CLAVE INVALIDO.' AS MENSAJE;
    ELSE
        SET v_iter = CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(P_HASH, '$', 2), '$', -1) AS UNSIGNED);
        SET v_salt = SUBSTRING_INDEX(SUBSTRING_INDEX(P_HASH, '$', 3), '$', -1);
        SET v_dk   = SUBSTRING_INDEX(P_HASH, '$', -1);

        SELECT VALOR INTO v_pepper
          FROM SECRETO_SISTEMA WHERE CLAVE = 'PEPPER_LOGIN';

        UPDATE USUARIOS
           SET SALT_LOGIN     = v_salt,
               ITER_LOGIN     = IFNULL(v_iter, 100000),
               CLAVE_SERVIDOR = SHA2(CONCAT(IFNULL(v_pepper, ''), v_dk), 256),
               CONTRASENA     = NULL
         WHERE ID_USUARIO = P_ID_USUARIO;

        -- Un reset de clave cierra las sesiones abiertas: si no, el token
        -- emitido con la clave vieja seguiria valido hasta 12 horas.
        DELETE FROM SESIONES WHERE ID_USUARIO = P_ID_USUARIO;

        SELECT CONCAT('EXITO: CLAVE DEL USUARIO ID ', P_ID_USUARIO,
                      ' ACTUALIZADA.') AS MENSAJE;
    END IF;
END//

DELIMITER ;

SELECT 'MODULO 67 APLICADO: CAMBIO DE CLAVE EN EL FORMATO DEL SERVIDOR.' AS RESULTADO;
