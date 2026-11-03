-- ================================================================
-- BALBU_TECH - T2 SEGURIDAD: BLOQUEO POR FUERZA BRUTA
-- ================================================================
-- (03/11/2026) Migracion idempotente para bases ya importadas.
-- No crea tablas ni columnas: el bloqueo se calcula sobre LOG_ACCESOS.
--
--   1) Indice en LOG_ACCESOS para contar fallos de un usuario sin scan completo.
--   2) FN_TIENE_PERMISO ignora cuentas con ESTADO = 'INACTIVO'.
--
-- Los modulos 28 y 36 ya traen estos cambios para una base nueva; este modulo
-- los aplica sobre una base viva sin reimportar la matriz de permisos.
-- Aplicar primero en BALBU_TECH_TEST.
-- ================================================================

-- ================================================================
-- 1) INDICE DEL BLOQUEO
-- ================================================================
-- El login consulta: USUARIO_INTENTADO = ? AND ESTADO_INTENTO = 'FALLIDO'
-- AND FECHA_ACCESO >= NOW() - INTERVAL 15 MINUTE. La clave compuesta deja ese
-- filtro en un rango sobre el indice en vez de un recorrido de tabla.
ALTER TABLE LOG_ACCESOS
    ADD INDEX IF NOT EXISTS IX_LOG_ACCESOS_USUARIO_FECHA (USUARIO_INTENTADO, FECHA_ACCESO);

-- ================================================================
-- 2) FN_TIENE_PERMISO: SOLO CUENTAS ACTIVAS
-- ================================================================
-- Se recrea completa porque la version anterior resolvia el rol sin mirar
-- ESTADO, asi que un usuario desactivado seguia pasando el control de permisos.
DELIMITER //
DROP FUNCTION IF EXISTS FN_TIENE_PERMISO;
CREATE FUNCTION FN_TIENE_PERMISO(P_USERNAME VARCHAR(50), P_ACCION VARCHAR(80))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE v_rol VARCHAR(50) DEFAULT NULL;
    DECLARE v_existe INT DEFAULT 0;

    SELECT R.NOMBRE_ROL INTO v_rol
    FROM USUARIOS U
    INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    WHERE U.USUARIO = P_USERNAME
      AND U.ESTADO = 'ACTIVO'
    LIMIT 1;

    IF v_rol IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO v_existe
    FROM USUARIOS U
    INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    INNER JOIN ROL_PERMISO RP ON RP.ROL_NOMBRE = R.NOMBRE_ROL
    INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
    WHERE U.USUARIO = P_USERNAME
      AND U.ESTADO = 'ACTIVO'
      AND P.NOMBRE_PERMISO = P_ACCION;

    RETURN v_existe > 0;
END//
DELIMITER ;

SELECT 'T2 SEGURIDAD APLICADO: INDICE DE LOG_ACCESOS Y FN_TIENE_PERMISO ACTIVO.' AS RESULTADO;

-- ================================================================
-- 3) SP DEL BLOQUEO
-- ================================================================
-- (03/11/2026) El login necesita contar fallos por usuario, pero darle a
-- balbu_app SELECT sobre LOG_ACCESOS le abriria todo el historial de accesos.
-- Este SP corre como DEFINER: la app recibe solo FALLOS y MINUTOS, y el log
-- queda privado.
-- P_VENTANA_MIN llega desde login.cpp (VENTANA_BLOQUEO_MIN) para que el
-- umbral viva en un solo lugar.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ESTADO_BLOQUEO_LOGIN;
CREATE PROCEDURE SP_ESTADO_BLOQUEO_LOGIN(
    IN P_USUARIO VARCHAR(50),
    IN P_VENTANA_MIN INT
)
BEGIN
    DECLARE v_desde TIMESTAMP DEFAULT TIMESTAMP '1970-01-01 00:00:01';
    DECLARE v_ventana INT DEFAULT 15;

    IF P_VENTANA_MIN IS NOT NULL AND P_VENTANA_MIN > 0 THEN
        SET v_ventana = P_VENTANA_MIN;
    END IF;

    -- Un acceso exitoso reinicia la cuenta sin borrar evidencia: solo cuentan
    -- los fallos posteriores al ultimo EXITOSO.
    SELECT IFNULL(MAX(FECHA_ACCESO), v_desde) INTO v_desde
    FROM LOG_ACCESOS
    WHERE USUARIO_INTENTADO = P_USUARIO
      AND ESTADO_INTENTO = 'EXITOSO';

    SELECT COUNT(*) AS FALLOS,
           IFNULL(CEIL(TIMESTAMPDIFF(SECOND, NOW(),
                  MIN(FECHA_ACCESO) + INTERVAL v_ventana MINUTE) / 60), 0) AS MINUTOS
    FROM LOG_ACCESOS
    WHERE USUARIO_INTENTADO = P_USUARIO
      AND ESTADO_INTENTO = 'FALLIDO'
      AND FECHA_ACCESO >= NOW() - INTERVAL v_ventana MINUTE
      AND FECHA_ACCESO > v_desde;
END//
DELIMITER ;

SELECT 'T2 SEGURIDAD: SP_ESTADO_BLOQUEO_LOGIN LISTO.' AS RESULTADO;
