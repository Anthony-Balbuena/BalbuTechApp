/*
MODULO 56 - AUDITORIA DE CAMBIOS DE USUARIOS

Problema
--------
TRG_AUDITORIA_USUARIOS anotaba el cambio de rol y de estado, pero:
  - dejaba ID_USUARIO_ADMIN siempre NULL (no se sabia quien lo hizo),
  - no registraba el cambio de nombre de usuario (CAMBIO_USUARIO),
  - la vista del historial no mostraba al admin.

Solucion
--------
La app deja el id del usuario logueado en la variable de conexion
@ID_USUARIO_ACTUAL al iniciar sesion. El trigger la usa como admin del
cambio; si la variable no esta o el usuario ya no existe, guarda NULL y el
UPDATE sigue su curso.

Es idempotente. No toca datos: solo reemplaza el trigger y la vista.
*/

DELIMITER //

DROP TRIGGER IF EXISTS TRG_AUDITORIA_USUARIOS //

CREATE TRIGGER TRG_AUDITORIA_USUARIOS
AFTER UPDATE ON USUARIOS
FOR EACH ROW
BEGIN
    DECLARE v_admin INT DEFAULT NULL;

    -- (25/10/2026) Quien hizo el cambio. Si el id no existe, queda NULL:
    -- un problema del log nunca debe tumbar el cambio de usuario.
    SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL);

    IF NOT (OLD.ID_ROL <=> NEW.ID_ROL) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ROL', CAST(OLD.ID_ROL AS CHAR), CAST(NEW.ID_ROL AS CHAR), v_admin);
    END IF;

    IF NOT (OLD.ESTADO <=> NEW.ESTADO) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_ESTADO', OLD.ESTADO, NEW.ESTADO, v_admin);
    END IF;

    IF NOT (OLD.USUARIO <=> NEW.USUARIO) THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN)
        VALUES (OLD.ID_USUARIO, 'CAMBIO_USUARIO', OLD.USUARIO, NEW.USUARIO, v_admin);
    END IF;
END //

DELIMITER ;

/*
VIEW_HISTORIAL_CAMBIOS_USUARIOS
Muestra los cambios de usuarios con el nombre del afectado y el del admin
que los hizo. LEFT JOIN: si una cuenta se borra, el registro no desaparece.
*/
CREATE OR REPLACE VIEW VIEW_HISTORIAL_CAMBIOS_USUARIOS AS
SELECT
    L.ID_LOG,
    U.USUARIO AS USUARIO_AFECTADO,
    L.ACCION,
    L.VALOR_ANTERIOR,
    L.VALOR_NUEVO,
    L.FECHA_CAMBIO,
    L.ID_USUARIO_ADMIN,
    A.USUARIO AS USUARIO_ADMIN
FROM LOG_USUARIOS L
LEFT JOIN USUARIOS U ON L.ID_USUARIO = U.ID_USUARIO
LEFT JOIN USUARIOS A ON L.ID_USUARIO_ADMIN = A.ID_USUARIO
ORDER BY L.FECHA_CAMBIO DESC;
