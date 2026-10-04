/*
ARCHIVO 19.6 - DEVOLUCION_COMPRA
Devoluciones de mercancia al proveedor: que se devuelve, cuando, porque y
en que condicion. Solo se devuelve de una compra RECIBIDA; al procesar la
devolucion baja el stock, anota la SALIDA, escribe el historial y baja el
TOTAL de la compra. Si se devuelve todo, la compra queda DEVUELTA.
Carga despues del 19.5 y antes del 20.
*/
/*
TABLA DEVOLUCION_COMPRA
Guarda cada devolucion al proveedor con su cantidad, motivo y condicion.
Nace PENDIENTE; al procesarla devuelve la mercancia y al rechazarla no
toca nada. El subtotal se guarda al registrar para no depender de
precios que puedan cambiar despues.
*/
CREATE TABLE DEVOLUCION_COMPRA (
    ID_DEVOLUCION_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_DETALLE_COMPRA INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL DEFAULT (CURRENT_DATE),
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    MOTIVO VARCHAR(200),
    CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO') NOT NULL DEFAULT 'BUENO',
    SUBTOTAL_DEVUELTO DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    ESTADO ENUM('PENDIENTE', 'PROCESADA', 'RECHAZADA') NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_DEVOLUCION_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_DETALLE FOREIGN KEY (ID_DETALLE_COMPRA) REFERENCES DETALLE_COMPRA (ID_DETALLE_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

/*
INDICE IX_DEVOLUCION_COMPRA_FECHA
Busca las devoluciones por fecha, igual que las demas tablas de compra,
para los reportes del periodo.
*/
CREATE INDEX IX_DEVOLUCION_COMPRA_FECHA ON DEVOLUCION_COMPRA (FECHA);


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
     WHERE DC.ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA;

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

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_GENERADO,
                  ' REGISTRADA (PENDIENTE).') AS MENSAJE;
END ;
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PROCESAR_DEVOLUCION_COMPRA ;
/*
SP_PROCESAR_DEVOLUCION_COMPRA
Cierra una devolucion pendiente: PROCESADA devuelve la mercancia al
proveedor (baja stock, anota SALIDA + historial, baja el TOTAL y deja la
compra DEVUELTA si se devolvio todo); RECHAZADA no toca nada. Valida que
exista y que siga PENDIENTE; los efectos los hace
TR_PROCESAR_DEVOLUCION_COMPRA, que tambien valen en un UPDATE directo.
*/
CREATE PROCEDURE SP_PROCESAR_DEVOLUCION_COMPRA(
    IN P_ID_DEVOLUCION_COMPRA INT,
    IN P_NUEVO_ESTADO ENUM('PROCESADA', 'RECHAZADA')
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);

    -- 1. La devolucion debe existir
    SELECT ESTADO INTO V_ESTADO_ACTUAL
      FROM DEVOLUCION_COMPRA
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;

    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCION NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo se procesa una vez
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA DEVOLUCION YA FUE PROCESADA.';
        LEAVE proc_label;
    END IF;

    -- 3. Cambiar el estado dispara TR_PROCESAR_DEVOLUCION_COMPRA
    UPDATE DEVOLUCION_COMPRA
       SET ESTADO = P_NUEVO_ESTADO
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_COMPRA, ' ', P_NUEVO_ESTADO, '.') AS MENSAJE;
END ;
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_PROCESAR_DEVOLUCION_COMPRA ;
/*
TR_PROCESAR_DEVOLUCION_COMPRA
Cuando una devolucion pasa de PENDIENTE a PROCESADA: valida que la compra
sigue RECIBIDA y que el stock alcanza (si no, todo falla sin cambios),
baja el stock, anota la SALIDA en movimientos, escribe UNA fila de
historial con el stock antes y despues, y baja el TOTAL de la compra; si
el TOTAL llega a 0 la compra queda DEVUELTA. RECHAZADA no toca nada.
Tambien se aplica si alguien cambia el estado con un UPDATE directo.
*/
CREATE TRIGGER TR_PROCESAR_DEVOLUCION_COMPRA
AFTER UPDATE ON DEVOLUCION_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ID_COMPRA INT;
    DECLARE V_ID_PRODUCTO INT;
    DECLARE V_ESTADO_COMPRA VARCHAR(20);
    DECLARE V_STOCK_ANTES INT;
    DECLARE V_TOTAL_ACTUAL DECIMAL(10, 2);

    IF NEW.ESTADO = 'PROCESADA' AND OLD.ESTADO = 'PENDIENTE' THEN

        -- Datos del detalle que se devuelve
        SELECT DC.ID_COMPRA, DC.ID_PRODUCTO
          INTO V_ID_COMPRA, V_ID_PRODUCTO
          FROM DETALLE_COMPRA DC
         WHERE DC.ID_DETALLE_COMPRA = NEW.ID_DETALLE_COMPRA;

        -- La compra debe seguir RECIBIDA
        SELECT ESTADO INTO V_ESTADO_COMPRA
          FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

        IF V_ESTADO_COMPRA <> 'RECIBIDA' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA RECIBIDA; NO SE PUEDE PROCESAR LA DEVOLUCION.';
        END IF;

        -- El stock tiene que alcanzar (si alguien ya se lo vendio, no hay)
        SET V_STOCK_ANTES = IFNULL((
            SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = V_ID_PRODUCTO
        ), 0);

        IF V_STOCK_ANTES < NEW.CANTIDAD THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL STOCK ACTUAL NO ALCANZA PARA DEVOLVER (YA HUBO VENTAS DE ESA MERCANCIA).';
        END IF;

        -- El subtotal nunca puede pasarse del total (candado ante UPDATE directo)
        SELECT TOTAL INTO V_TOTAL_ACTUAL
          FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

        IF NEW.SUBTOTAL_DEVUELTO > V_TOTAL_ACTUAL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL SUBTOTAL DE LA DEVOLUCION EXCEDE EL TOTAL DE LA COMPRA.';
        END IF;

        -- 1. Baja el stock
        UPDATE INVENTARIO
           SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
         WHERE ID_PRODUCTO = V_ID_PRODUCTO;

        -- 2. Bitacora: la SALIDA hacia el proveedor
        INSERT INTO MOVIMIENTOS_INVENTARIO
            (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
        VALUES
            (V_ID_PRODUCTO, NEW.ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD,
             CONCAT('Devolucion a proveedor ID: ', NEW.ID_DEVOLUCION_COMPRA));

        -- 3. Historial UNA fila con el stock antes y despues
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO
            (ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION)
        VALUES
            (V_ID_PRODUCTO, 'DEVOLUCION', NEW.CANTIDAD, V_STOCK_ANTES, V_STOCK_ANTES - NEW.CANTIDAD,
             CONCAT('Devolucion a proveedor ID: ', NEW.ID_DEVOLUCION_COMPRA));

        -- 4. Baja el TOTAL de la compra (el detalle queda como evidencia)
        UPDATE COMPRAS
           SET TOTAL = TOTAL - NEW.SUBTOTAL_DEVUELTO
         WHERE ID_COMPRA = V_ID_COMPRA;

        -- 5. Si se devolvio todo, la compra queda DEVUELTA
        UPDATE COMPRAS
           SET ESTADO = 'DEVUELTA'
         WHERE ID_COMPRA = V_ID_COMPRA AND TOTAL <= 0;
    END IF;
END ;
DELIMITER ;
