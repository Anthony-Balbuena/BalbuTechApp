/*
TABLA PAGOS
Guarda cada pago que se recibe por una venta: cuanto, cuando y con que
metodo de pago. Puede haber varios pagos por venta (parciales o completos).
CAMBIO P8 (06/10/2026): se agrego ID_EMPLEADO (+ su FK) para dejar
constancia de QUIEN COBRO el pago, igual que ya hace PAGOS_COMPRA.
Antes el empleado solo servia para el mensaje del SP.
CAMBIO P9 (07/10/2026): se agrego MONTO_RECIBIDO (lo que el cliente
entrego, nullable) para poder registrar el VUELTO. MONTO no cambia de
significado: sigue siendo lo que se aplica a la venta, por eso saldos,
cierre automatico, cancelaciones y devoluciones no se tocaron. El CHECK
evita recibir menos de lo cobrado (el NULL pasa: significa 'no aplica').
*/
CREATE TABLE PAGOS (
    ID_PAGO INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_METODO_PAGO INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    MONTO_RECIBIDO DECIMAL(10, 2) NULL CHECK (MONTO_RECIBIDO >= MONTO),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO),
    CONSTRAINT FK_PAGO_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_PAGO_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO),
    CONSTRAINT FK_PAGO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
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
NOTA P8 (06/10/2026): ahora guarda ID_EMPLEADO en PAGOS (quien cobro) y
valida que el empleado exista; antes seguia igual aunque no existiera,
poniendo 'DESCONOCIDO' unicamente en el mensaje.
NOTA (Parte 2, 07/10/2026): este SP es la PUERTA DE ENTRADA de una cadena
de tres. Su INSERT dispara en el mismo movimiento a TR_VALIDAR_MONTO_PAGO
(BEFORE: el freno) y a TR_AUTO_FINALIZAR_VENTA (AFTER: el cierre + bono).
El SP valida lo suyo (venta, empleado y vuelto); lo demas lo resuelven los
triggers, incluso si el pago llega a pelo sin pasar por aqui.
*/
-- ============================================================
-- VERSION ANTERIOR (guardada para revision, NO se ejecuta)
-- ============================================================
-- CREATE PROCEDURE 24_SP_REGISTRAR_PAGO(
--     IN P_ID_VENTA INT,
--     IN P_ID_METODO_PAGO INT,
--     IN P_MONTO DECIMAL(10, 2),
--     IN P_ID_EMPLEADO INT -- Recibimos el ID del empleado que procesa el pago
-- )
-- proc_label: BEGIN
--     DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
--     DECLARE V_NOMBRE_EMPLEADO VARCHAR(100);
--
--     -- 1. Validar venta
--     SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
--     IF V_TOTAL_VENTA IS NULL THEN
--         SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
--         LEAVE proc_label;
--     END IF;
--
--     -- 2. Obtener nombre del empleado para el mensaje
--     SELECT NOMBRE INTO V_NOMBRE_EMPLEADO FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
--
--     -- Si el empleado no existe, ponemos uno genérico o lanzamos error
--     IF V_NOMBRE_EMPLEADO IS NULL THEN
--         SET V_NOMBRE_EMPLEADO = 'DESCONOCIDO';
--     END IF;
--
--     -- 3. Insertar el pago
--     INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, MONTO)
--     VALUES (P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO);
--
--     -- 4. Mensaje personalizado
--     SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO POR EL EMPLEADO: ', V_NOMBRE_EMPLEADO) AS MENSAJE;
-- END ;

-- ============================================================
-- VERSION P8 (guardada para revision, NO se ejecuta)
-- ============================================================
-- CREATE PROCEDURE 24_SP_REGISTRAR_PAGO(
--     IN P_ID_VENTA INT,
--     IN P_ID_METODO_PAGO INT,
--     IN P_MONTO DECIMAL(10, 2),
--     IN P_ID_EMPLEADO INT -- El empleado que procesa el pago (P8)
-- )
-- proc_label: BEGIN
--     DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
--     DECLARE V_NOMBRE_EMPLEADO VARCHAR(100);
--
--     -- 1. Validar venta
--     SELECT TOTAL INTO V_TOTAL_VENTA FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
--     IF V_TOTAL_VENTA IS NULL THEN
--         SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
--         LEAVE proc_label;
--     END IF;
--
--     -- 2. Validar el empleado que cobra (P8): si no existe, no se guarda
--     SELECT NOMBRE INTO V_NOMBRE_EMPLEADO FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
--     IF V_NOMBRE_EMPLEADO IS NULL THEN
--         SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
--         LEAVE proc_label;
--     END IF;
--
--     -- 3. Insertar el pago con quien lo cobro (P8)
--     INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, MONTO, ID_EMPLEADO)
--     VALUES (P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO, P_ID_EMPLEADO);
--
--     -- 4. Mensaje personalizado
--     SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO POR EL EMPLEADO: ', V_NOMBRE_EMPLEADO) AS MENSAJE;
-- END ;

-- ============================================================
-- VERSION NUEVA (la que se crea) - P9
-- ============================================================
CREATE PROCEDURE 24_SP_REGISTRAR_PAGO(
    IN P_ID_VENTA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_ID_EMPLEADO INT, -- El empleado que procesa el pago (P8)
    -- (09/10/2026) V3. DEFAULT NULL: el cuerpo ya lo maneja (vuelto 0);
    -- sin esto las llamadas viejas de 4 args fallaban por aridad.
    IN P_MONTO_RECIBIDO DECIMAL(10, 2) DEFAULT NULL -- Lo que entrego el cliente; NULL = no aplica (P9)
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

    -- 2. Validar el empleado que cobra (P8): si no existe, no se guarda
    SELECT NOMBRE INTO V_NOMBRE_EMPLEADO FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    IF V_NOMBRE_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) V4. Metodo inexistente (1452) y monto nulo o no positivo (1048/3819).
    IF NOT EXISTS (SELECT 1 FROM METODOS_PAGO WHERE ID_METODO_PAGO = P_ID_METODO_PAGO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL METODO DE PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF IFNULL(P_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 3. Validar el monto recibido (P9): si viene, no puede ser menor que lo cobrado
    IF P_MONTO_RECIBIDO IS NOT NULL AND P_MONTO_RECIBIDO < P_MONTO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO RECIBIDO ES MENOR QUE EL PAGO.';
        LEAVE proc_label;
    END IF;

    -- 4. Insertar el pago: lo aplicado (MONTO) y lo entregado (MONTO_RECIBIDO);
    --    si el parametro no viene, se guarda igual a MONTO (vuelto 0)
    INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, MONTO, ID_EMPLEADO, MONTO_RECIBIDO)
    VALUES (P_ID_VENTA, P_ID_METODO_PAGO, P_MONTO, P_ID_EMPLEADO, IFNULL(P_MONTO_RECIBIDO, P_MONTO));

    -- 5. Mensaje personalizado (con vuelto si lo hay)
    SELECT CONCAT('EXITO: PAGO DE ', P_MONTO,
                  IF(IFNULL(P_MONTO_RECIBIDO, P_MONTO) > P_MONTO,
                     CONCAT(' (VUELTO ', IFNULL(P_MONTO_RECIBIDO, P_MONTO) - P_MONTO, ')'), ''),
                  ' REGISTRADO POR EL EMPLEADO: ', V_NOMBRE_EMPLEADO) AS MENSAJE;
END //
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
NOTA (Parte 4, 07/10/2026): es el unico camino para deshacer un cobro.
Patron de TRANSACCION PROPIA: si nadie abrio una (@@in_transaction = 0)
la abre y la cierra con COMMIT; si venimos de adentro de otra, no la
toca y el EXIT HANDLER hace ROLLBACK solo cuando la transaccion es suya
(y RESIGNAL para que el que llama decida). Al borrar el pago, si la
venta deja de estar cobrada al 100%: se reabre a EN_PROCESO y se borra
el bono del 1% PENDIENTE (si ya esta APROBADO se deja - lo resuelve
nomina). Con la venta reaberta y sin pagos, ya califica para
SP_CANCELAR_VENTA (ese era el bloqueo del paso 3 de alla).
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
END //
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
NOTA (Parte 2, 07/10/2026): es el FRENO de la cadena de cobro. Corre
dentro del MISMO INSERT que hace 24_SP_REGISTRAR_PAGO, antes de guardar:
1) la venta esta abierta (EN_PROCESO) y 2) pagado + nuevo <= TOTAL; si no
cuadra, SIGNAL y no se guarda nada. Nunca mira MONTO_RECIBIDO (el vuelto):
solo MONTO, lo que se aplica a la venta.
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
END //
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
END //
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_FINALIZAR_VENTA;
/*
TR_AUTO_FINALIZAR_VENTA
Cuando entra un pago, revisa si ya se cubrio el total de la venta.
Si se pago todo, marca la venta REALIZADA y ahi si crea el bono del 1%
al empleado: el bono se gana al cobrar, no al agregar productos.
NOTA (Parte 2, 07/10/2026): es el CIERRE de la cadena. Corre despues de
guardar el pago, en el mismo INSERT. El bono del 1% se calcula sobre el
TOTAL de la venta (no sobre lo pagado) y solo dispara la PRIMERA vez que
se cubre: la condicion V_ESTADO = 'EN_PROCESO' es el guardia
anti-doble-bono (un pago extra o un UPDATE ya no vuelve a crear bono).
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
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_UPDATE_PAGO ;
/*
TR_VALIDAR_UPDATE_PAGO
El pago de una venta tampoco se edita a pelo: un UPDATE directo no puede
moverlo a otra venta, no puede pasarse del total y no toca pagos de una
venta que ya esta CANCELADA o DEVUELTA (ahi la plata ya quedo resuelta).
Misma regla que TR_VALIDAR_MONTO_PAGO al insertar y que
TR_VALIDAR_BORRADO_PAGO al borrar.
*/
CREATE TRIGGER TR_VALIDAR_UPDATE_PAGO
BEFORE UPDATE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);

    -- El pago se queda en su venta
    IF NEW.ID_VENTA <> OLD.ID_VENTA THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL PAGO NO CAMBIA DE VENTA.';
    END IF;

    SELECT TOTAL, ESTADO INTO V_TOTAL_VENTA, V_ESTADO
      FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

    IF V_ESTADO IS NULL OR V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).';
    END IF;

    -- La suma con el cambio aplicado no puede pasarse del total
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
      FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    IF (V_TOTAL_PAGADO - OLD.MONTO + NEW.MONTO) > V_TOTAL_VENTA THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_UPDATE ;
/*
TR_RECALCULAR_ESTADO_PAGO_UPDATE
Si alguien le cambia el monto a un pago, la venta puede quedar cobrada al
100% o dejar de estarlo: aqui se vuelve a sumar lo cobrado y se mueve el
estado (con su bono del 1% y su reapertura) igual que al insertar o al
anular, para que un UPDATE directo no deje la venta mintiendo.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_UPDATE
AFTER UPDATE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;

    IF NEW.MONTO <> OLD.MONTO THEN
        SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
          FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

        SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
          FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

        -- Quedo cobrada al 100%: se cierra y nace el bono del 1%
        IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_VENTA > 0 AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
            UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = NEW.ID_VENTA;

            INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
            VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                    ROUND(V_TOTAL_VENTA * 0.01, 2),
                    CONCAT('Comisión por venta #', NEW.ID_VENTA),
                    'PENDIENTE');
        END IF;

        -- Dejo de estar cobrada: se reabre y se va el bono pendiente
        IF V_ESTADO = 'REALIZADA' AND V_TOTAL_PAGADO < V_TOTAL_VENTA THEN
            UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = NEW.ID_VENTA;

            DELETE FROM BONOS_EMPLEADOS
            WHERE ID_EMPLEADO = V_ID_EMPLEADO
              AND DESCRIPCION = CONCAT('Comisión por venta #', NEW.ID_VENTA)
              AND ESTADO = 'PENDIENTE';
        END IF;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_BORRADO ;
/*
TR_RECALCULAR_ESTADO_PAGO_BORRADO
Cuando un pago desaparece (DELETE directo, no por SP) la venta puede dejar
de estar cobrada: aqui se vuelve a sumar lo cobrado y se mueve el estado,
mismo trabajo que hace SP_ANULAR_PAGO pero para el borrado que no pasa por
el. Con su bono del 1% pendiente, que ya no corresponde si se fue el pago.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_BORRADO
AFTER DELETE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;

    SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
      FROM VENTAS WHERE ID_VENTA = OLD.ID_VENTA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
      FROM PAGOS WHERE ID_VENTA = OLD.ID_VENTA;

    IF V_ESTADO = 'REALIZADA' AND V_TOTAL_PAGADO < V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = OLD.ID_VENTA;

        DELETE FROM BONOS_EMPLEADOS
        WHERE ID_EMPLEADO = V_ID_EMPLEADO
          AND DESCRIPCION = CONCAT('Comisión por venta #', OLD.ID_VENTA)
          AND ESTADO = 'PENDIENTE';
    END IF;

    IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_VENTA > 0 AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = OLD.ID_VENTA;

        INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
        VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                ROUND(V_TOTAL_VENTA * 0.01, 2),
                CONCAT('Comisión por venta #', OLD.ID_VENTA),
                'PENDIENTE');
    END IF;
END //
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
/*
VISTA_RESUMEN_PAGOS
Muestra los pagos con el nombre de su metodo de pago, monto y fecha.
Sirve como resumen de cobros para revisar en pantalla o en reportes.
Ahora trae tambien al empleado que cobro (P8).
Ahora trae tambien el monto recibido y el VUELTO (P9).
*/
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS AS
SELECT 
    P.ID_PAGO,
    P.ID_VENTA,
    MP.NOMBRE AS NOMBRE_METODO, 
    E.NOMBRE AS NOMBRE_EMPLEADO,
    P.MONTO,
    P.MONTO_RECIBIDO,
    P.MONTO_RECIBIDO - P.MONTO AS VUELTO,
    P.FECHA
FROM PAGOS P
JOIN METODOS_PAGO MP ON P.ID_METODO_PAGO = MP.ID_METODO_PAGO
JOIN EMPLEADOS E ON P.ID_EMPLEADO = E.ID_EMPLEADO;





/*
VISTA_VENTAS_PENDIENTES_PAGO
Cuanto le falta por cobrar cada venta. El trigger de pagos no deja que se
pague de mas, asi que el saldo nunca queda negativo. Se excluyen las ventas
CANCELADAS (ya no se les cobra nada) y las DEVUELTAS, ademas de las que ya
estan saldadas (saldo 0).
*/
CREATE OR REPLACE VIEW VISTA_VENTAS_PENDIENTES_PAGO AS
SELECT 
    V.ID_VENTA,
    V.ID_CLIENTE,
    V.ESTADO,
    V.TOTAL,
    IFNULL(SUM(P.MONTO), 0) AS PAGADO,
    V.TOTAL - IFNULL(SUM(P.MONTO), 0) AS SALDO
FROM VENTAS V
LEFT JOIN PAGOS P ON P.ID_VENTA = V.ID_VENTA
WHERE V.ESTADO NOT IN ('CANCELADA', 'DEVUELTA')
GROUP BY V.ID_VENTA, V.ID_CLIENTE, V.ESTADO, V.TOTAL
HAVING V.TOTAL - IFNULL(SUM(P.MONTO), 0) <> 0;










-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------