/*
TABLA COMPRAS
Guarda cada compra que hace la tienda a sus proveedores.
Anota quien la hizo, cuando, a que proveedor y el dinero total gastado.
Es la cabecera: los productos comprados van en DETALLE_COMPRA.
*/
CREATE TABLE COMPRAS (
    ID_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_PROVEEDOR INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    TOTAL DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (TOTAL >= 0),
    -- ABIERTA = se le pueden agregar productos (por defecto);
    -- RECIBIDA = reservado para la fase de pagos de compras;
    -- CANCELADA = no recibe mas productos y su stock fue revertido
    ESTADO ENUM('ABIERTA', 'RECIBIDA', 'CANCELADA') NOT NULL DEFAULT 'ABIERTA',
    PRIMARY KEY (ID_COMPRA),
    CONSTRAINT FK_COMPRA_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR),
    CONSTRAINT FK_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
 
-- Para reportes de compras por mes, año o día (Cierres de caja)
/*
INDICE IX_COMPRA_FECHA
Ordena las compras por fecha, asi los reportes por mes, dia o cierre de caja
salen rapidos sin recorrer toda la tabla.
*/
CREATE INDEX IX_COMPRA_FECHA ON COMPRAS (FECHA);

-- Para análisis de gastos (Ej: "Busca compras mayores a 50,000 pesos")
/*
INDICE IX_COMPRA_TOTAL
Busca compras por su monto, util para analizar gastos y encontrar las
compras mas grandes de un periodo.
*/
CREATE INDEX IX_COMPRA_TOTAL ON COMPRAS (TOTAL);

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




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   



DELIMITER //

DROP PROCEDURE IF EXISTS 19_SP_INICIAR_COMPRA ;

/*
19_SP_INICIAR_COMPRA
Abre una compra nueva en blanco antes de agregarle productos.
Revisa que el proveedor y el empleado existan; si algo falla no guarda nada,
y si esta todo bien crea la compra y devuelve su numero de ID.
*/
CREATE PROCEDURE 19_SP_INICIAR_COMPRA(
    IN P_ID_PROVEEDOR INT,
    IN P_ID_EMPLEADO INT,
    OUT P_ID_COMPRA_GENERADO INT
)
proc_label: BEGIN
    -- 1. Validaciones
    IF NOT EXISTS (SELECT 1 FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF IFNULL((SELECT ESTADO FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR), 'INACTIVO') <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO ESTA ACTIVO.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Inserción
    INSERT INTO COMPRAS (ID_PROVEEDOR, ID_EMPLEADO) 
    VALUES (P_ID_PROVEEDOR, P_ID_EMPLEADO);
    
    SET P_ID_COMPRA_GENERADO = LAST_INSERT_ID();

    SELECT CONCAT('EXITO: COMPRA #', P_ID_COMPRA_GENERADO, ' INICIADA CORRECTAMENTE.') AS MENSAJE;

END // 

DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CANCELAR_COMPRA ;
/*
SP_CANCELAR_COMPRA
Cancela una compra y le regresa la mercancia: baja el stock de cada
producto, anota la SALIDA en la bitacora y su fila en el historial del
producto, y deja la compra en estado CANCELADA (el detalle y el total se
conservan como evidencia).
Valida que el empleado sea el dueno de la compra y que la mercancia siga
en el almacen: si ya hubo ventas que consumieron ese stock no se puede
cancelar. Si algo falla no se cambia nada.
*/
CREATE PROCEDURE SP_CANCELAR_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ID_EMPLEADO_COMPRA INT;
    DECLARE V_ESTADO VARCHAR(20);

    -- 1. El empleado que cancela debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. La compra debe existir
    SELECT ID_EMPLEADO, ESTADO INTO V_ID_EMPLEADO_COMPRA, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    IF V_ID_EMPLEADO_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Solo quien hizo la compra puede cancelarla
    IF V_ID_EMPLEADO_COMPRA <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA COMPRA.';
        LEAVE proc_label;
    END IF;

    -- 4. Solo se cancela una compra que siga ABIERTA
    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE CANCELADA O RECIBIDA).';
        LEAVE proc_label;
    END IF;

    -- 5. No se cancela una compra con pagos registrados (antes anulelos
    --    con SP_ANULAR_PAGO_COMPRA; asi nunca se queda dinero colgado)
    IF EXISTS (SELECT 1 FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA TIENE PAGOS REGISTRADOS; ANULELOS ANTES DE CANCELAR.';
        LEAVE proc_label;
    END IF;

    -- 6. La mercancia debe seguir en el almacen: si algun producto ya se
    --    consumo en ventas no hay stock para devolver (se revisa todo ANTES
    --    de tocar nada, asi un rechazo no deja cambios a medias)
    IF EXISTS (
        SELECT 1 FROM DETALLE_COMPRA DC
        LEFT JOIN INVENTARIO I ON I.ID_PRODUCTO = DC.ID_PRODUCTO
        WHERE DC.ID_COMPRA = P_ID_COMPRA
          AND IFNULL(I.STOCK_ACTUAL, 0) < DC.CANTIDAD
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE CANCELAR: EL STOCK ACTUAL NO ALCANZA PARA REVERTIR (YA HUBO VENTAS DE ESA MERCANCIA).';
        LEAVE proc_label;
    END IF;

    -- 7. Bitacora: la SALIDA de cada producto
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    SELECT DC.ID_PRODUCTO, P_ID_EMPLEADO, 'SALIDA', DC.CANTIDAD, CONCAT('Compra cancelada ID: ', P_ID_COMPRA)
    FROM DETALLE_COMPRA DC
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 8. Bajar el stock (el detalle no se borra: queda como evidencia)
    UPDATE INVENTARIO I
    JOIN DETALLE_COMPRA DC ON DC.ID_PRODUCTO = I.ID_PRODUCTO
    SET I.STOCK_ACTUAL = I.STOCK_ACTUAL - DC.CANTIDAD
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 9. Historial del producto con el stock antes y despues (UNA fila)
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    )
    SELECT DC.ID_PRODUCTO, 'SALIDA', DC.CANTIDAD,
           I.STOCK_ACTUAL + DC.CANTIDAD, I.STOCK_ACTUAL,
           CONCAT('Compra cancelada ID: ', P_ID_COMPRA)
    FROM DETALLE_COMPRA DC
    JOIN INVENTARIO I ON I.ID_PRODUCTO = DC.ID_PRODUCTO
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 10. Cerrar la compra
    UPDATE COMPRAS SET ESTADO = 'CANCELADA' WHERE ID_COMPRA = P_ID_COMPRA;

    SELECT CONCAT('EXITO: COMPRA #', P_ID_COMPRA, ' CANCELADA Y MERCANCIA REVERTIDA.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CERRADA ;
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CANCELADA ;
/*
TR_BLOQUEAR_COMPRA_CERRADA
Una compra que no esta ABIERTA (RECIBIDA o CANCELADA) no acepta mas
productos, ni siquiera con un INSERT directo (misma idea que
TR_BLOQUEAR_VENTA_FINALIZADA en ventas). Si hay que agregar algo despues
de estar saldada, primero se anula el pago que cerro la compra con
SP_ANULAR_PAGO_COMPRA y vuelve a ABIERTA.
Reemplaza a TR_BLOQUEAR_COMPRA_CANCELADA (solo cubria CANCELADA).
*/
CREATE TRIGGER TR_BLOQUEAR_COMPRA_CERRADA
BEFORE INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA O CANCELADA).';
    END IF;
END //
DELIMITER ;

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
END //
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
    DECLARE V_ID_COMPRA INT;
    DECLARE V_MONTO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_PAGADO DECIMAL(10, 2);

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
    SELECT CONCAT('EXITO: PAGO #', P_ID_PAGO_COMPRA, ' ANULADO (', V_MONTO,
                  '). PAGADO DE LA COMPRA #', V_ID_COMPRA, ': ', V_PAGADO) AS MENSAJE;
END //
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

    IF IFNULL(NEW.MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
    END IF;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF (V_PAGADO + NEW.MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
    END IF;
END //
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
END //
DELIMITER ; 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger: Actualiza Inventario al comprar
DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_STOCK_COMPRA ;
/*
TR_ACTUALIZAR_STOCK_COMPRA
Cada vez que entra un producto en una compra, le suma la cantidad al stock.
Si el producto todavia no tiene fila en INVENTARIO, la crea primero
(mismos defaults que SP_RECIBIR_MERCANCIA) y le suma encima; asi nunca
se pierde una entrada por falta de registro en inventario.
*/
CREATE TRIGGER TR_ACTUALIZAR_STOCK_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
    VALUES (NEW.ID_PRODUCTO, NEW.CANTIDAD, 5, 'ALMACEN_PRINCIPAL')
    ON DUPLICATE KEY UPDATE STOCK_ACTUAL = STOCK_ACTUAL + NEW.CANTIDAD;
END //
DELIMITER ;

/*
VISTA_REPORTE_COMPRAS
Muestra las compras con el nombre de su proveedor, fecha y total.
Las ordena de la mas reciente a la mas vieja, lista para el reporte.
*/
CREATE OR REPLACE VIEW VISTA_REPORTE_COMPRAS AS
SELECT 
    C.ID_COMPRA,
    P.NOMBRE AS PROVEEDOR,
    C.FECHA,
    C.TOTAL,
    C.ESTADO
FROM COMPRAS C
JOIN PROVEEDORES P ON C.ID_PROVEEDOR = P.ID_PROVEEDOR
ORDER BY C.FECHA DESC;
DELIMITER //

DROP FUNCTION IF EXISTS FN_CONTAR_ITEMS_COMPRA ;

/*
FN_CONTAR_ITEMS_COMPRA
Cuenta cuantos productos distintos tiene una compra.
Se usa en reportes; si la compra no tiene nada devuelve 0.
*/
CREATE FUNCTION FN_CONTAR_ITEMS_COMPRA(P_ID_COMPRA INT) 
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE V_TOTAL_ITEMS INT;
    
    SELECT COUNT(*) INTO V_TOTAL_ITEMS 
    FROM DETALLE_COMPRA 
    WHERE ID_COMPRA = P_ID_COMPRA;
    
    RETURN IFNULL(V_TOTAL_ITEMS, 0);
END //

DELIMITER ;