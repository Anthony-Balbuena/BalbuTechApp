/*
TABLA PAGOS
Guarda cada pago que se recibe por una venta: cuanto, cuando y con que
metodo de pago. Puede haber varios pagos por venta (parciales o completos).
*/
CREATE TABLE PAGOS (
    ID_PAGO INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_METODO_PAGO INT NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO),
    CONSTRAINT FK_PAGO_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_PAGO_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO)
) ENGINE = InnoDB;

/*
INDICE IX_PAGOS_FECHA
Busca y ordena los pagos por fecha, util para los reportes de caja
y el cierre del dia.
*/
CREATE INDEX IX_PAGOS_FECHA ON PAGOS (FECHA);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS 24_SP_REGISTRAR_PAGO;
/*
24_SP_REGISTRAR_PAGO
Registra un pago de una venta con su metodo de pago.
Revisa que la venta exista, guarda el pago y devuelve un mensaje
confirmando el monto con el nombre del empleado que lo proceso.
*/
CREATE PROCEDURE 24_SP_REGISTRAR_PAGO(
    IN P_ID_VENTA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_ID_EMPLEADO INT -- Recibimos el ID del empleado que procesa el pago
)
proc_label: BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_NOMBRE_EMPLEADO VARCHAR(100);

    -- 1. Validar venta
    SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
    IF V_TOTAL_VENTA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Obtener nombre del empleado para el mensaje
    SELECT NOMBRE INTO V_NOMBRE_EMPLEADO FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    
    -- Si el empleado no existe, ponemos uno genérico o lanzamos error
    IF V_NOMBRE_EMPLEADO IS NULL THEN
        SET V_NOMBRE_EMPLEADO = 'DESCONOCIDO';
    END IF;

    -- 3. Insertar el pago
    INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, MONTO)
    VALUES (P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO);

    -- 4. Mensaje personalizado
    SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO POR EL EMPLEADO: ', V_NOMBRE_EMPLEADO) AS MENSAJE;
END;
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ANULAR_PAGO ;
/*
SP_ANULAR_PAGO
Anula un pago que se registro por error. Al borrarlo los totales vuelven a
cuadrar solos, porque todo se calcula con SUM sobre PAGOS. Si con eso la venta
deja de estar cobrada al 100%, la venta vuelve a EN_PROCESO y se elimina el
bono del 1% que se habia creado al cobrar (solo si sigue PENDIENTE; si ya
fue aprobado se deja para que lo resuelva nomina).
No se puede anular un pago de una venta CANCELADA ni DEVUELTA.
*/
CREATE PROCEDURE SP_ANULAR_PAGO(
    IN P_ID_PAGO INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_VENTA INT;
    DECLARE V_MONTO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ID_EMPLEADO_VENTA INT;
    DECLARE V_BONOS_BORRADOS INT DEFAULT 0;
    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra este
    -- SP; si venimos de adentro de otra (llamada anidada o cierre de caja),
    -- no la toca y cualquier error se propaga para que el que llama decida.
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

    -- 1. El empleado que anula debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. El pago debe existir
    SELECT ID_VENTA, MONTO INTO V_ID_VENTA, V_MONTO
    FROM PAGOS WHERE ID_PAGO = P_ID_PAGO;

    IF V_ID_VENTA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. La venta debe seguir viva (no cancelada ni devuelta)
    SELECT ESTADO, TOTAL, ID_EMPLEADO
    INTO V_ESTADO, V_TOTAL_VENTA, V_ID_EMPLEADO_VENTA
    FROM VENTAS WHERE ID_VENTA = V_ID_VENTA;

    IF V_ESTADO NOT IN ('EN_PROCESO', 'REALIZADA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).';
        LEAVE proc_label;
    END IF;

    -- 4. Borra el pago
    DELETE FROM PAGOS WHERE ID_PAGO = P_ID_PAGO;

    -- 5. Recalcula lo cobrado
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
    FROM PAGOS WHERE ID_VENTA = V_ID_VENTA;

    -- 6. Si dejo de estar cobrada al 100%, se reabre y se quita el bono del 1%
    IF V_ESTADO = 'REALIZADA' AND V_TOTAL_PAGADO < V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = V_ID_VENTA;

        DELETE FROM BONOS_EMPLEADOS
        WHERE ID_EMPLEADO = V_ID_EMPLEADO_VENTA
          AND DESCRIPCION = CONCAT('Comisión por venta #', V_ID_VENTA)
          AND ESTADO = 'PENDIENTE';
        SET V_BONOS_BORRADOS = ROW_COUNT();
    END IF;

    -- 7. Mensaje

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: PAGO #', P_ID_PAGO, ' ANULADO (', V_MONTO,
                  '). COBRADO DE LA VENTA #', V_ID_VENTA, ': ', V_TOTAL_PAGADO,
                  IF(V_BONOS_BORRADOS > 0, ' - SE RETIRO EL BONO DEL 1%', '')
                 ) AS MENSAJE;
END ;
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_MONTO_PAGO ;
/*
TR_VALIDAR_MONTO_PAGO
Solo acepta pagos mientras la venta siga abierta (EN_PROCESO) y no deja
que se pague mas de lo que vale la venta. Antes de guardar, revisa el
estado y suma lo ya pagado; si algo no cuadra corta con error.
*/
CREATE TRIGGER TR_VALIDAR_MONTO_PAGO
BEFORE INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);

    SELECT TOTAL, ESTADO INTO V_TOTAL_VENTA, V_ESTADO FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    IF V_ESTADO <> 'EN_PROCESO' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ESTA ABIERTA PARA RECIBIR PAGOS.';
    END IF;

    IF (V_TOTAL_PAGADO + NEW.MONTO) > V_TOTAL_VENTA THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.';
    END IF;
END;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_BORRADO_PAGO ;
/*
TR_VALIDAR_BORRADO_PAGO
Un pago de una venta CANCELADA o DEVUELTA no se borra, ni con DELETE directo:
ahi la plata ya quedo resuelta y el cobro dejaria de cuadrar. Es la misma
regla que aplica SP_ANULAR_PAGO (que ademas quita el bono del 1%) ahora
hecha valer tambien cuando el borrado no pasa por el SP.
*/
CREATE TRIGGER TR_VALIDAR_BORRADO_PAGO
BEFORE DELETE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM VENTAS WHERE ID_VENTA = OLD.ID_VENTA;

    IF V_ESTADO IS NULL OR V_ESTADO NOT IN ('EN_PROCESO', 'REALIZADA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).';
    END IF;
END ;
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_FINALIZAR_VENTA;
/*
TR_AUTO_FINALIZAR_VENTA
Cuando entra un pago, revisa si ya se cubrio el total de la venta.
Si se pago todo, marca la venta REALIZADA y ahi si crea el bono del 1%
al empleado: el bono se gana al cobrar, no al agregar productos.
*/
CREATE TRIGGER TR_AUTO_FINALIZAR_VENTA
AFTER INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;

    SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
    FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
    FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    -- Solo la primera vez que se cubre el total (la venta sigue EN_PROCESO)
    IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = NEW.ID_VENTA;

        INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
        VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                ROUND(V_TOTAL_VENTA * 0.01, 2),
                CONCAT('Comisión por venta #', NEW.ID_VENTA),
                'PENDIENTE');
    END IF;
END;
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
/*
VISTA_RESUMEN_PAGOS
Muestra los pagos con el nombre de su metodo de pago, monto y fecha.
Sirve como resumen de cobros para revisar en pantalla o en reportes.
*/
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS AS
SELECT 
    P.ID_PAGO,
    P.ID_VENTA,
    MP.NOMBRE AS NOMBRE_METODO, 
    P.MONTO,
    P.FECHA
FROM PAGOS P
JOIN METODOS_PAGO MP ON P.ID_METODO_PAGO = MP.ID_METODO_PAGO;










-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------