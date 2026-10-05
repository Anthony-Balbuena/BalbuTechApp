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
    -- NULL en las notas de credito: ahi no hay plata moviendose
    ID_METODO_PAGO INT NULL,
    -- Quien paga (o quien firma la nota). Si el llamador no manda el
    -- empleado, TR_AUTOCOMPLETAR_EMPLEADO_PAGO pone al dueno de la compra.
    ID_EMPLEADO INT NOT NULL,
    -- PAGO = plata que se le entrega al proveedor;
    -- NOTA_CREDITO = descuento o devolucion que le baja la deuda (monto negativo)
    TIPO ENUM('PAGO', 'NOTA_CREDITO') NOT NULL DEFAULT 'PAGO',
    MONTO DECIMAL(10, 2) NOT NULL,
    OBSERVACION VARCHAR(100) NULL, -- motivo de la nota de credito (los pagos no llevan)
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO_COMPRA),
    CONSTRAINT CHK_PAGOS_COMPRA_MONTO CHECK (MONTO <> 0),
    CONSTRAINT FK_PAGO_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA),
    CONSTRAINT FK_PAGO_COMPRA_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO),
    CONSTRAINT FK_PAGO_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- ============================================================
-- Deja al dia una BD que ya tenia esta tabla (como la real): agrega las
-- columnas, le pone el dueno de la compra a los pagos viejos, cambia el
-- CHECK viejo de MONTO > 0 por MONTO <> 0 (ahi entran las notas) y le
-- pone el FK del empleado si la BD vieja no lo trajo. En una BD recien
-- creada nada de esto hace falta, el CREATE de arriba ya lo trae.
-- ============================================================
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS ID_EMPLEADO INT NULL;
UPDATE PAGOS_COMPRA PC JOIN COMPRAS C ON C.ID_COMPRA = PC.ID_COMPRA
   SET PC.ID_EMPLEADO = C.ID_EMPLEADO
 WHERE PC.ID_EMPLEADO IS NULL;
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN ID_EMPLEADO INT NOT NULL;
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS TIPO ENUM('PAGO', 'NOTA_CREDITO') NOT NULL DEFAULT 'PAGO';
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS OBSERVACION VARCHAR(100) NULL;
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN ID_METODO_PAGO INT NULL;
-- El CHECK viejo MONTO > 0 no se puede borrar con DROP CONSTRAINT (esta
-- version de MariaDB lo ignora en silencio) ni con DROP CHECK (syntax
-- error): al redefinir la columna sin el CHECK inline se va solo. En una
-- BD vieja que tenga el check en la columna, esto lo limpia.
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN MONTO DECIMAL(10, 2) NOT NULL;
ALTER TABLE PAGOS_COMPRA ADD CONSTRAINT IF NOT EXISTS CHK_PAGOS_COMPRA_MONTO CHECK (MONTO <> 0);
-- El FK del empleado: las BDs viejas (como la real) crearon esta tabla
-- antes de que el CREATE de arriba lo trajera, y como el CREATE no corre
-- (table already exists) hay que agregarlo aparte. Si ya existe tira el
-- error 1826 'Duplicate foreign key constraint name', que es inofensivo
-- (mismo criterio que los ERROR 1050/1061 de toda la carga).
ALTER TABLE PAGOS_COMPRA ADD CONSTRAINT FK_PAGO_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO);

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
El empleado que paga es opcional: si no viene, se toma al dueno de la
compra (asi nunca queda un pago sin responsable).
*/
CREATE PROCEDURE SP_REGISTRAR_PAGO_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_ID_EMPLEADO INT DEFAULT NULL -- quien paga; si no viene, el dueno de la compra
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

    -- 6. Si mandaron el empleado que paga, tiene que existir
    IF P_ID_EMPLEADO IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 7. Guardar el pago (TR_AUTO_RECIBIR_COMPRA puede cerrar la compra).
    --    Si P_ID_EMPLEADO viene NULL lo completa el trigger de la tabla.
    INSERT INTO PAGOS_COMPRA (ID_COMPRA, ID_METODO_PAGO, ID_EMPLEADO, TIPO, MONTO)
    VALUES (P_ID_COMPRA, P_ID_METODO_PAGO, P_ID_EMPLEADO, 'PAGO', P_MONTO);

    -- 8. Mensaje con el estado final
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
CANCELADA. Tambien sirve para deshacer una nota de credito.
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
    DECLARE V_TIPO VARCHAR(15);
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
    SELECT ID_COMPRA, MONTO, TIPO INTO V_ID_COMPRA, V_MONTO, V_TIPO
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

    SELECT CONCAT('EXITO: ', IF(V_TIPO = 'NOTA_CREDITO', 'NOTA DE CREDITO #', 'PAGO #'),
                  P_ID_PAGO_COMPRA, ' ANULADO (', V_MONTO,
                  '). PAGADO DE LA COMPRA #', V_ID_COMPRA, ': ', V_PAGADO) AS MENSAJE;
END ;
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_NOTA_CREDITO_COMPRA ;
/*
SP_REGISTRAR_NOTA_CREDITO_COMPRA
Le anota una nota de credito a una compra: un descuento o una devolucion
que le baja la deuda al proveedor. Se guarda con MONTO negativo para que
el SUM(MONTO) de las vistas netee solo, sin tener que restar a mano.
Pide el motivo en observacion (obligatorio) y el empleado que la firma;
si no viene empleado se toma al dueno de la compra. Si con eso la compra
deja de estar saldada, TR_AUTO_RECIBIR_COMPRA la reabre sola.
*/
CREATE PROCEDURE SP_REGISTRAR_NOTA_CREDITO_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_OBSERVACION VARCHAR(100),
    IN P_ID_EMPLEADO INT DEFAULT NULL -- quien la firma; si no viene, el dueno de la compra
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

    -- 2. Una compra cancelada o devuelta ya cerro su cuenta con el proveedor
    IF V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE NOTAS DE CREDITO.';
        LEAVE proc_label;
    END IF;

    -- 3. El monto viene en positivo: quien lo guarda negativo es el SP
    IF IFNULL(P_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DE LA NOTA DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 4. Sin motivo no hay nota: es plata que se mueve
    IF IFNULL(TRIM(P_OBSERVACION), '') = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA NOTA DE CREDITO REQUIERE UNA OBSERVACION.';
        LEAVE proc_label;
    END IF;

    -- 5. Si mandaron el empleado que la firma, tiene que existir
    IF P_ID_EMPLEADO IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 6. Se guarda con el signo cambiado (la fila siempre es negativa)
    INSERT INTO PAGOS_COMPRA (ID_COMPRA, ID_METODO_PAGO, ID_EMPLEADO, TIPO, MONTO, OBSERVACION)
    VALUES (P_ID_COMPRA, NULL, P_ID_EMPLEADO, 'NOTA_CREDITO', -ABS(P_MONTO), TRIM(P_OBSERVACION));

    -- 7. Mensaje con lo que queda pagado
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA;

    SELECT CONCAT('EXITO: NOTA DE CREDITO DE ', P_MONTO,
                  ' REGISTRADA CONTRA LA COMPRA #', P_ID_COMPRA,
                  ' (PAGADO: ', V_PAGADO, ').') AS MENSAJE;
END ;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTOCOMPLETAR_EMPLEADO_PAGO ;
/*
TR_AUTOCOMPLETAR_EMPLEADO_PAGO
Ningun pago se queda sin responsable: si la fila entra sin ID_EMPLEADO
(un INSERT directo o un llamado viejo del SP), le pone al dueno de la
compra. Si la compra no existe no hay a quien culpar y corta con error.
*/
CREATE TRIGGER TR_AUTOCOMPLETAR_EMPLEADO_PAGO
BEFORE INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_EMPLEADO INT;

    IF NEW.ID_EMPLEADO IS NULL THEN
        SELECT C.ID_EMPLEADO INTO V_EMPLEADO
        FROM COMPRAS C WHERE C.ID_COMPRA = NEW.ID_COMPRA;

        IF V_EMPLEADO IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE, NO SE QUIEN DEJAR COMO RESPONSABLE.';
        END IF;

        SET NEW.ID_EMPLEADO = V_EMPLEADO;
    END IF;
END ;
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_PAGO_COMPRA ;
/*
TR_VALIDAR_PAGO_COMPRA
Antes de guardar un pago de compra revisa que la compra este ABIERTA (no
cancelada ni ya saldada) y que el monto no exceda el total, sumando los
pagos anteriores. Vale tambien para INSERT directo: tambien revisa que el
signo del MONTO concuerde con el TIPO (un pago entra, una nota de credito
sale) y que nadie meta un monto en cero.
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

    -- Un pago positivo sobre una compra ya saldada no tiene sentido;
    -- la nota de credito (montos negativos) si entra: es plata que vuelve.
    IF V_ESTADO = 'RECIBIDA' AND NEW.MONTO > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).';
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA.';
    END IF;

    IF IFNULL(NEW.MONTO, 0) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO NO PUEDE SER CERO.';
    END IF;

    -- El signo tiene que ver con el tipo: un PAGO entra y una NOTA sale
    IF (NEW.TIPO = 'PAGO' AND NEW.MONTO < 0)
       OR (NEW.TIPO = 'NOTA_CREDITO' AND NEW.MONTO > 0) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO Y EL TIPO NO COINCIDEN (LA NOTA DE CREDITO ES NEGATIVA).';
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
SP_ANULAR_PAGO_COMPRA o entra una nota de credito que baja lo pagado,
la compra vuelve a ABIERTA. No crea bonos:
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

    -- Una nota de credito que baja lo pagado deja la compra a medias:
    -- se reabre para que vuelva a aceptar productos.
    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = NEW.ID_COMPRA;
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
vuelva a aceptar productos y pagos. Y si lo que se borro es una nota de
credito que dejaba todo saldado, la marca RECIBIDA otra vez. Hace lo mismo
que el paso 6 de SP_ANULAR_PAGO_COMPRA, pero sirve tambien si el borrado
no paso por el SP.
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

    -- Al reves: si borrar esa fila dejo todo saldado (se fue una nota de
    -- credito), la compra vuelve a estar RECIBIDA.
    IF V_ESTADO = 'ABIERTA' AND V_TOTAL > 0 AND V_PAGADO >= V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'RECIBIDA' WHERE ID_COMPRA = OLD.ID_COMPRA;
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
    PC.TIPO,
    MP.NOMBRE AS NOMBRE_METODO,
    PC.ID_EMPLEADO,
    PC.MONTO,
    PC.OBSERVACION,
    PC.FECHA
FROM PAGOS_COMPRA PC
-- LEFT: las notas de credito no traen metodo de pago
LEFT JOIN METODOS_PAGO MP ON PC.ID_METODO_PAGO = MP.ID_METODO_PAGO;

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
