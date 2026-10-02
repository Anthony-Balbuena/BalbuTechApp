/*
TABLA VENTAS
Cabecera de cada venta: quien la compro, quien la atendio, cuando y cuanto
gasto. El estado indica si esta en proceso, realizada, cancelada o devuelta.
Los productos vendidos van en DETALLES_VENTA.
*/
CREATE TABLE VENTAS (
    ID_VENTA INT NOT NULL AUTO_INCREMENT,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ESTADO ENUM(
        'REALIZADA',
        'EN_PROCESO',
        'CANCELADA',
        'DEVUELTA'
    ) NOT NULL DEFAULT 'EN_PROCESO',
    ID_EMPLEADO INT NOT NULL,
    ID_CLIENTE INT NOT NULL,
    TOTAL DECIMAL(12, 2) NOT NULL CHECK (TOTAL >= 0),
    PRIMARY KEY (ID_VENTA),
    CONSTRAINT FK_VENTA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    CONSTRAINT FK_VENTA_CLIENTE FOREIGN KEY (ID_CLIENTE) REFERENCES CLIENTES (ID_CLIENTE)
) ENGINE = InnoDB;

/*
INDICE IX_VENTAS_CLIENTE
Busca todas las ventas de un cliente en concreto,
util para ver su historial de compras.
*/
CREATE INDEX IX_VENTAS_CLIENTE ON VENTAS (ID_CLIENTE);

/*
INDICE IX_VENTAS_EMPLEADO
Busca todas las ventas atendidas por un empleado,
util para reportes de desempeno.
*/
CREATE INDEX IX_VENTAS_EMPLEADO ON VENTAS (ID_EMPLEADO);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS 21_SP_INICIAR_VENTA ;
/*
21_SP_INICIAR_VENTA
Abre una venta nueva en 0 antes de agregarle productos.
Revisa que el empleado y el cliente existan; si algo falla no guarda nada,
y si esta todo bien crea la venta y devuelve su numero de ID.
*/
CREATE PROCEDURE 21_SP_INICIAR_VENTA(
    IN P_ID_EMPLEADO INT,
    IN P_ID_CLIENTE INT,
    OUT P_ID_VENTA_GENERADO INT
)
proc_label: BEGIN
    -- 1. Validaciones
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM CLIENTES WHERE ID_CLIENTE = P_ID_CLIENTE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CLIENTE NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Inserción
    INSERT INTO VENTAS (ID_EMPLEADO, ID_CLIENTE, TOTAL) 
    VALUES (P_ID_EMPLEADO, P_ID_CLIENTE, 0.00);
    
    SET P_ID_VENTA_GENERADO = LAST_INSERT_ID();

    SELECT CONCAT('EXITO: VENTA #', P_ID_VENTA_GENERADO, ' INICIADA.') AS MENSAJE;

END ;
DELIMITER ;



DELIMITER //
DROP PROCEDURE IF EXISTS 21_SP_AGREGAR_PRODUCTO_VENTA ;
/*
21_SP_AGREGAR_PRODUCTO_VENTA
Agrega un producto a la venta que ya esta abierta.
Revisa que la venta exista y que haya stock suficiente; si todo esta bien
toma el precio actual del producto y agrega la linea del detalle.
*/
CREATE PROCEDURE 21_SP_AGREGAR_PRODUCTO_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT
)
proc_label: BEGIN
    DECLARE V_PRECIO DECIMAL(12, 2);
    DECLARE V_STOCK_DISPONIBLE INT;

    -- 1. Validar que la venta exista
    IF NOT EXISTS (SELECT 1 FROM VENTAS WHERE ID_VENTA = P_ID_VENTA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar stock disponible
    SELECT STOCK_ACTUAL INTO V_STOCK_DISPONIBLE FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    IF V_STOCK_DISPONIBLE < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Obtener precio actual del producto
    SELECT PRECIO INTO V_PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. Insertar detalle
    INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO);

    SELECT 'EXITO: PRODUCTO AGREGADO.' AS MENSAJE;
END ;
DELIMITER ;
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_VENTA ;
/*
TR_CALCULAR_TOTAL_VENTA
Le va sumando el subtotal de cada producto al TOTAL de la venta.
Asi el total siempre queda actualizado sin calcularlo a mano.
*/
CREATE TRIGGER TR_CALCULAR_TOTAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    UPDATE VENTAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_VENTA = NEW.ID_VENTA;
END ;
DELIMITER ;





DELIMITER //

DROP TRIGGER IF EXISTS TR_PROCESAR_VENTA ;
/*
TR_PROCESAR_VENTA
Al vender, descuenta el stock del producto y deja la SALIDA registrada.
Anota el movimiento en la auditoria con el empleado de la venta.
*/
CREATE TRIGGER TR_PROCESAR_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;

    -- 1. Descontar del inventario
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. Obtener el empleado de la cabecera de la venta para la auditoría
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- 3. Registrar el movimiento en la auditoría
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD, CONCAT('Venta realizada ID: ', NEW.ID_VENTA));

END ;
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
VISTA_DETALLE_VENTA
Muestra los productos de cada venta con su cantidad, precio y subtotal.
Trae el nombre del producto en lugar de su ID, lista para ver en pantalla.
*/
CREATE OR REPLACE VIEW VISTA_DETALLE_VENTA AS
SELECT 
    DV.ID_VENTA,
    P.NOMBRE AS PRODUCTO,
    DV.CANTIDAD,
    DV.PRECIO_UNITARIO,
    DV.SUBTOTAL
FROM DETALLES_VENTA DV
JOIN PRODUCTOS P ON DV.ID_PRODUCTO = P.ID_PRODUCTO;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------