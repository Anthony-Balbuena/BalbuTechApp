/*
ARCHIVO 19.6 - DEVOLUCION_COMPRA
Devoluciones de mercancia al proveedor: que se devuelve, cuando, porque y
en que condicion. Solo se devuelve de una compra RECIBIDA; al procesar la
devolucion baja el stock, anota la SALIDA, escribe el historial y baja el
TOTAL de la compra. Si se devuelve todo, la compra queda DEVUELTA.
Carga despues del 19.5 y antes del 20.
*/
-- TABLA DEVOLUCION_COMPRA (+indices) reubicada en 22-DETALLE_COMPRA.sql: necesita DETALLE_COMPRA ya creada.


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_DEVOLUCION_COMPRA ;
/*
SP_REGISTRAR_DEVOLUCION_COMPRA
Deja anotada la intencion de devolver mercancia (queda PENDIENTE, sin
tocar stock ni totales). Valida empleado, que el detalle exista, que la
compra este RECIBIDA y que la cantidad no pase de lo comprado (contando
las devoluciones pendientes o ya procesadas). Devuelve el ID para
procesarla despues con SP_PROCESAR_DEVOLUCION_COMPRA.
*/
CREATE PROCEDURE SP_REGISTRAR_DEVOLUCION_COMPRA(
    IN P_ID_DETALLE_COMPRA INT,
    IN P_ID_EMPLEADO INT,
    IN P_CANTIDAD INT,
    IN P_MOTIVO VARCHAR(200),
    IN P_CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO'),
    OUT P_ID_DEVOLUCION_GENERADO INT
)
proc_label: BEGIN
    DECLARE V_ID_COMPRA INT;
    DECLARE V_ESTADO_COMPRA VARCHAR(20);
    DECLARE V_CANTIDAD_COMPRADA INT;
    DECLARE V_PRECIO_UNITARIO DECIMAL(10, 2);
    DECLARE V_YA_DEVUELTA INT;
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 1. Cantidad valida
    IF IFNULL(P_CANTIDAD, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 2. El empleado debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. El detalle debe existir (trae compra, cantidad, precio y estado)
    SELECT DC.ID_COMPRA, DC.CANTIDAD, DC.PRECIO_UNITARIO, C.ESTADO
      INTO V_ID_COMPRA, V_CANTIDAD_COMPRADA, V_PRECIO_UNITARIO, V_ESTADO_COMPRA
      FROM DETALLE_COMPRA DC
      JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
     -- BLINDAJE (07/10/2026): FOR UPDATE congela el detalle y la compra
     -- para que dos devoluciones a la vez no pasen juntas la validacion
     -- del paso 5 (evita devolver de mas por carrera).
     -- WHERE DC.ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA;
     WHERE DC.ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA
       FOR UPDATE;

    IF V_ID_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DETALLE DE LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 4. Solo se devuelve de una compra RECIBIDA (de una ABIERTA se cancela,
    --    de una CANCELADA o DEVUELTA ya no hay nada que devolver)
    IF V_ESTADO_COMPRA <> 'RECIBIDA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA RECIBIDA; SOLO SE DEVUELVE MERCANCIA DE UNA COMPRA RECIBIDA.';
        LEAVE proc_label;
    END IF;

    -- 5. No devolver de mas: lo pendiente ya cuenta contra lo comprado
    SELECT IFNULL(SUM(CANTIDAD), 0) INTO V_YA_DEVUELTA
      FROM DEVOLUCION_COMPRA
     WHERE ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA
       AND ESTADO IN ('PENDIENTE', 'PROCESADA');

    IF P_CANTIDAD > (V_CANTIDAD_COMPRADA - V_YA_DEVUELTA) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES REGISTRADAS DE ESTE PRODUCTO).';
        LEAVE proc_label;
    END IF;

    -- 6. Guarda la devolucion pendiente con su subtotal al dia de hoy
    INSERT INTO DEVOLUCION_COMPRA
        (ID_DETALLE_COMPRA, ID_EMPLEADO, CANTIDAD, MOTIVO, CONDICION_PRODUCTO, SUBTOTAL_DEVUELTO)
    VALUES
        (P_ID_DETALLE_COMPRA, P_ID_EMPLEADO, P_CANTIDAD, P_MOTIVO, P_CONDICION_PRODUCTO,
         P_CANTIDAD * V_PRECIO_UNITARIO);

    SET P_ID_DEVOLUCION_GENERADO = LAST_INSERT_ID();

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_GENERADO,
                  ' REGISTRADA (PENDIENTE).') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PROCESAR_DEVOLUCION_COMPRA ;
/*
SP_PROCESAR_DEVOLUCION_COMPRA
Cierra una devolucion pendiente: PROCESADA devuelve la mercancia al
proveedor (baja stock, anota SALIDA + historial, baja el TOTAL y deja la
compra DEVUELTA si se devolvio todo); RECHAZADA no toca efectos (stock, total ni bitacora) pero si
anota el motivo del rechazo en MOTIVO encima del motivo original
(P12C). Valida que
exista y que siga PENDIENTE; los efectos los hace
TR_PROCESAR_DEVOLUCION_COMPRA, que tambien valen en un UPDATE directo.
*/
-- P12C (07/10/2026): el rechazo no dejaba rastro del por que; ahora el
-- SP acepta el motivo del rechazo y lo anota en MOTIVO encima del motivo
-- original. Los llamados pasan NULL explicito si no hay motivo
-- (MariaDB no admite DEFAULT en parametros de procedures).
-- CREATE PROCEDURE SP_PROCESAR_DEVOLUCION_COMPRA(
--     IN P_ID_DEVOLUCION_COMPRA INT,
--     IN P_NUEVO_ESTADO ENUM('PROCESADA', 'RECHAZADA')
-- )
CREATE PROCEDURE SP_PROCESAR_DEVOLUCION_COMPRA(
    IN P_ID_DEVOLUCION_COMPRA INT,
    IN P_NUEVO_ESTADO ENUM('PROCESADA', 'RECHAZADA'),
    IN P_MOTIVO_RECHAZO VARCHAR(200)
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 1. La devolucion debe existir
    -- BLINDAJE (07/10/2026): FOR UPDATE congela la fila; dos procesos
    -- a la vez se serializan y el segundo ve el estado ya cambiado.
    -- SELECT ESTADO INTO V_ESTADO_ACTUAL
    --   FROM DEVOLUCION_COMPRA
    --  WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;
    SELECT ESTADO INTO V_ESTADO_ACTUAL
      FROM DEVOLUCION_COMPRA
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA
       FOR UPDATE;

    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCION NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo se procesa una vez
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA DEVOLUCION YA FUE PROCESADA.';
        LEAVE proc_label;
    END IF;

    -- 3. Cambiar el estado dispara TR_PROCESAR_DEVOLUCION_COMPRA.
    -- P12C (07/10/2026): al rechazar se anota el motivo encima del
    -- original (LEFT: MOTIVO es VARCHAR(200) y la concatenacion no
    -- puede pasarse de largo); a PROCESADA no se le toca el motivo.
    -- UPDATE DEVOLUCION_COMPRA
    --    SET ESTADO = P_NUEVO_ESTADO
    --  WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;
    UPDATE DEVOLUCION_COMPRA
       SET ESTADO = P_NUEVO_ESTADO,
           MOTIVO = CASE
                        WHEN P_NUEVO_ESTADO = 'RECHAZADA' THEN
                            LEFT(CONCAT(IFNULL(CONCAT(MOTIVO, ' | '), ''),
                                        'RECHAZO: ',
                                        IFNULL(P_MOTIVO_RECHAZO, 'NO ESPECIFICADO')),
                                 200)
                        ELSE MOTIVO
                    END
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_COMPRA, ' ', P_NUEVO_ESTADO, '.') AS MENSAJE;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger TR_PROCESAR_DEVOLUCION_COMPRA movido a 22 (tabla DEVOLUCION_COMPRA vive ahi).

-- Trigger TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA movido a 22 (idem).

-- Trigger TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA movido a 22 (idem).
