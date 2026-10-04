/*
TABLA MOVIMIENTOS_INVENTARIO
Bitacora de todo lo que le pasa al stock: entradas, salidas, ajustes y
devoluciones. Cada fila dice que producto, quien lo movio, cuanto, cuando
y por que motivo. Sirve para rastrear cualquier cambio de inventario.
*/
CREATE TABLE MOVIMIENTOS_INVENTARIO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM(
        'ENTRADA',
        'SALIDA',
        'AJUSTE',
        'DEVOLUCION'
    ) NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_MOVIMIENTO_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_MOVIMIENTO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- Tu índice para rastrear qué pasó con cada producto
/*
INDICE IX_MOVIMIENTO_PRODUCTO
Busca todos los movimientos de un producto en concreto, asi se rastrea
rapido que le paso al stock sin leer toda la tabla.
*/
CREATE INDEX IX_MOVIMIENTO_PRODUCTO ON MOVIMIENTOS_INVENTARIO (ID_PRODUCTO);

/*
INDICE IX_CANTIDAD_MOVIINVENTORIO
Busca movimientos por cantidad, util para revisar entradas o salidas
grandes de mercancia.
*/
CREATE INDEX IX_CANTIDAD_MOVIINVENTORIO ON MOVIMIENTOS_INVENTARIO (CANTIDAD);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER //

DROP PROCEDURE IF EXISTS 20_SP_REGISTRAR_AJUSTE_INVENTARIO ;
/*
20_SP_REGISTRAR_AJUSTE_INVENTARIO
Anota un movimiento de stock y lo refleja en el inventario.
Primero revisa que el producto exista, luego guarda el movimiento y al final
suma si es ENTRADA o DEVOLUCION, o resta si es SALIDA o AJUSTE.
*/
CREATE PROCEDURE 20_SP_REGISTRAR_AJUSTE_INVENTARIO(
    IN P_ID_PRODUCTO INT,
    IN P_ID_EMPLEADO INT,
    IN P_TIPO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION'),
    IN P_CANTIDAD INT,
    IN P_OBSERVACION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Validación de existencia
    IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Registro del movimiento
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION);

    -- 3. Actualización de Stock (Lógica de Ajuste)
    IF P_TIPO IN ('ENTRADA', 'DEVOLUCION') THEN
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    ELSE
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL - P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    END IF;

    SELECT 'EXITO: MOVIMIENTO REGISTRADO Y STOCK ACTUALIZADO.' AS MENSAJE;
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
--COMPRA
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_COMPRA ;
/*
TR_AUDITORIA_MOVIMIENTO_COMPRA
Cuando se registra una compra, anota automaticamente la ENTRADA de mercancia.
Toma el empleado de la compra y deja el movimiento con su observacion.
*/
CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    -- Obtenemos el empleado de la cabecera de la compra para el registro
    DECLARE V_ID_EMPLEADO INT;
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'ENTRADA', NEW.CANTIDAD, CONCAT('Compra registrada ID: ', NEW.ID_COMPRA));
END ;

--VENTAS
DELIMITER //

DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_VENTA ;

/*
TR_AUDITORIA_MOVIMIENTO_VENTA
Cuando se registra una venta, descuenta el stock y anota la SALIDA.
Deja el movimiento con el empleado de la venta para poder rastrearlo.
*/
CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_VENTA
AFTER INSERT ON DETALLES_VENTA -- <--- AQUÍ ESTABA EL ERROR
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;

    -- Obtenemos el empleado de la cabecera de la venta
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- Restamos del Inventario
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- Registramos el movimiento
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD, CONCAT('Venta realizada ID: ', NEW.ID_VENTA));
END ;

DELIMITER ;









-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------