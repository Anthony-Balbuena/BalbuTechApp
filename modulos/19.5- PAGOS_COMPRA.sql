/*
ARCHIVO 19.5 - PAGOS_COMPRA
Pagos a proveedores por una compra: cuanto, cuando y con que metodo.
Pueden ser parciales o totales; cuando la suma cubre el total, la compra
queda RECIBIDA sola. Todo lo de esta tabla vive aqui (tabla, indice, SPs y
triggers); en 19- COMPRAS.sql solo quedo la guarda de no cancelar compras
con pagos. Carga despues del 19 y antes del 20.
*/
/*
TABLA PAGOS_COMPRA
Guarda cada pago que se hace a un proveedor por una compra: cuanto, cuando
y con que metodo. Puede haber varios pagos por compra (parciales o totales);
cuando la suma cubre el total, la compra queda RECIBIDA sola.
*/
CREATE TABLE PAGOS_COMPRA (
    ID_PAGO_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_COMPRA INT NOT NULL,
    ID_METODO_PAGO INT NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO_COMPRA),
    CONSTRAINT FK_PAGO_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA),
    CONSTRAINT FK_PAGO_COMPRA_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO)
) ENGINE = InnoDB;

/*
INDICE IX_PAGOS_COMPRA_COMPRA
Trae todos los pagos de una compra en concreto, para ver como se fue
saldando.
*/
CREATE INDEX IX_PAGOS_COMPRA_COMPRA ON PAGOS_COMPRA (ID_COMPRA);

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[PAGOS DE LA COMPRA}-----------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_PAGO_COMPRA ;
/*
SP_REGISTRAR_PAGO_COMPRA
Registra un pago (parcial o total) a un proveedor por una compra.
Valida todo antes de guardar: que la compra exista y este ABIERTA, que el
metodo de pago exista, que el monto sea mayor a cero y que no exceda el
total (suma de pagos anteriores + este monto). Al cubrir el total,
TR_AUTO_RECIBIR_COMPRA deja la compra en estado RECIBIDA sola.
*/
CREATE PROCEDURE SP_REGISTRAR_PAGO_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2)
)
proc_label: BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    -- 1. La compra debe existir
    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    IF V_TOTAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo una compra ABIERTA admite pagos
    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'RECIBIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA.';
        LEAVE proc_label;
    END IF;

    -- 3. El metodo de pago debe existir
    IF NOT EXISTS (SELECT 1 FROM METODOS_PAGO WHERE ID_METODO_PAGO = P_ID_METODO_PAGO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL METODO DE PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 4. Monto valido
    IF IFNULL(P_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 5. No exceder el total de la compra
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA;

    IF (V_PAGADO + P_MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
        LEAVE proc_label;
    END IF;

    -- 6. Guardar el pago (TR_AUTO_RECIBIR_COMPRA puede cerrar la compra)
    INSERT INTO PAGOS_COMPRA (ID_COMPRA, ID_METODO_PAGO, MONTO)
    VALUES (P_ID_COMPRA, P_ID_METODO_PAGO, P_MONTO);

    -- 7. Mensaje con el estado final
    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO PARA LA COMPRA #', P_ID_COMPRA,
                  IF(V_ESTADO = 'RECIBIDA', ' - COMPRA SALDADA (RECIBIDA).', '')) AS MENSAJE;
END ;
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ANULAR_PAGO_COMPRA ;
/*
SP_ANULAR_PAGO_COMPRA
Anula un pago de compra que se registro por error. Al borrarlo los totales
vuelven a cuadrar solos (todo se calcula con SUM sobre PAGOS_COMPRA). Si
con eso la compra deja de estar saldada, vuelve a ABIERTA y vuelve a
aceptar productos y pagos. No se puede anular el pago de una compra
CANCELADA.
*/
CREATE PROCEDURE SP_ANULAR_PAGO_COMPRA(
    IN P_ID_PAGO_COMPRA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_COMPRA INT;
    DECLARE V_MONTO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_PAGADO DECIMAL(10, 2);
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
    SELECT ID_COMPRA, MONTO INTO V_ID_COMPRA, V_MONTO
    FROM PAGOS_COMPRA WHERE ID_PAGO_COMPRA = P_ID_PAGO_COMPRA;

    IF V_ID_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. La compra no puede estar CANCELADA
    SELECT ESTADO, TOTAL INTO V_ESTADO, V_TOTAL
    FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA, NO ADMITE CAMBIOS DE PAGO.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA, NO ADMITE CAMBIOS DE PAGO.';
        LEAVE proc_label;
    END IF;

    -- 4. Borra el pago
    DELETE FROM PAGOS_COMPRA WHERE ID_PAGO_COMPRA = P_ID_PAGO_COMPRA;

    -- 5. Recalcula lo pagado
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = V_ID_COMPRA;

    -- 6. Si dejo de estar saldada, vuelve a ABIERTA
    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = V_ID_COMPRA;
    END IF;

    -- 7. Mensaje

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: PAGO #', P_ID_PAGO_COMPRA, ' ANULADO (', V_MONTO,
                  '). PAGADO DE LA COMPRA #', V_ID_COMPRA, ': ', V_PAGADO) AS MENSAJE;
END ;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_PAGO_COMPRA ;
/*
TR_VALIDAR_PAGO_COMPRA
Antes de guardar un pago de compra revisa que la compra este ABIERTA (no
cancelada ni ya saldada) y que el monto no exceda el total, sumando los
pagos anteriores. Vale tambien para INSERT directo.
*/
CREATE TRIGGER TR_VALIDAR_PAGO_COMPRA
BEFORE INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA.';
    END IF;

    IF V_ESTADO = 'RECIBIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).';
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA.';
    END IF;

    IF IFNULL(NEW.MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
    END IF;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF (V_PAGADO + NEW.MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
    END IF;
END ;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_RECIBIR_COMPRA ;
/*
TR_AUTO_RECIBIR_COMPRA
Cuando entra un pago, revisa si con eso se cubrio el total de la compra.
Si ya se pago todo, deja la compra en RECIBIDA (el equivalente a
REALIZADA en ventas). Si despues se anula un pago con
SP_ANULAR_PAGO_COMPRA, la compra vuelve a ABIERTA. No crea bonos:
los bonos son por ventas, no por compras.
*/
CREATE TRIGGER TR_AUTO_RECIBIR_COMPRA
AFTER INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF V_ESTADO = 'ABIERTA' AND V_TOTAL > 0 AND V_PAGADO >= V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'RECIBIDA' WHERE ID_COMPRA = NEW.ID_COMPRA;
    END IF;
END ;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_BORRADO_PAGO_COMPRA ;
/*
TR_VALIDAR_BORRADO_PAGO_COMPRA
El pago de una compra CANCELADA o DEVUELTA no se toca, ni con DELETE directo:
ahi la plata ya quedo resuelta por otro camino y borrarla dejaria el
resumen mintiendo. Es la misma regla que aplica SP_ANULAR_PAGO_COMPRA antes
de borrar, ahora hecha valer tambien cuando el borrado viene a pelo.
*/
CREATE TRIGGER TR_VALIDAR_BORRADO_PAGO_COMPRA
BEFORE DELETE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    IF V_ESTADO IS NULL OR V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE CAMBIOS DE PAGO.';
    END IF;
END ;
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_COMPRA ;
/*
TR_RECALCULAR_ESTADO_PAGO_COMPRA
Cuando desaparece un pago vuelve a sumar lo pagado de la compra: si dejo de
estar saldada le quita la RECIBIDA y la deja otra vez en ABIERTA, para que
vuelva a aceptar productos y pagos. Hace lo mismo que el paso 6 de
SP_ANULAR_PAGO_COMPRA, pero sirve tambien si el borrado no paso por el SP.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_COMPRA
AFTER DELETE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = OLD.ID_COMPRA;

    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = OLD.ID_COMPRA;
    END IF;
END ;
DELIMITER ;


-------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}---------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------
/*
VISTA_RESUMEN_PAGOS_COMPRA
Lista los pagos a proveedores con el nombre del metodo de pago, igual
que la VISTA_RESUMEN_PAGOS de ventas pero para las compras.
*/
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS_COMPRA AS
SELECT
    PC.ID_PAGO_COMPRA,
    PC.ID_COMPRA,
    MP.NOMBRE AS NOMBRE_METODO,
    PC.MONTO,
    PC.FECHA
FROM PAGOS_COMPRA PC
JOIN METODOS_PAGO MP ON PC.ID_METODO_PAGO = MP.ID_METODO_PAGO;

/*
VISTA_COMPRAS_PENDIENTES_PAGO
Las compras que aun tienen dinero de por medio: cuanto se le paga al
proveedor y cuanto falta por pagar (SALDO). Si el saldo sale negativo
es dinero de mas a favor (compra devuelta ya pagada). Excluye las
CANCELADAS: esas nunca se pagaron.
*/
CREATE OR REPLACE VIEW VISTA_COMPRAS_PENDIENTES_PAGO AS
SELECT
    C.ID_COMPRA,
    P.NOMBRE AS PROVEEDOR,
    C.FECHA,
    C.TOTAL,
    IFNULL(PG.PAGADO, 0) AS PAGADO,
    C.TOTAL - IFNULL(PG.PAGADO, 0) AS SALDO,
    C.ESTADO
FROM COMPRAS C
JOIN PROVEEDORES P ON P.ID_PROVEEDOR = C.ID_PROVEEDOR
LEFT JOIN (
    SELECT ID_COMPRA, SUM(MONTO) AS PAGADO
      FROM PAGOS_COMPRA
     GROUP BY ID_COMPRA
) PG ON PG.ID_COMPRA = C.ID_COMPRA
WHERE C.ESTADO <> 'CANCELADA'
  AND C.TOTAL - IFNULL(PG.PAGADO, 0) <> 0
ORDER BY C.FECHA DESC;
