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



/*
LIMPIEZA DE SP DUPLICADO
21_SP_AGREGAR_PRODUCTO_VENTA hacia lo mismo que SP_AGREGAR_DETALLE_VENTA
(archivo 23) pero sin validar que el empleado sea el dueño de la venta.
Ahora la alta de detalle es solo por ese SP; aqui queda el DROP para
limpiar bases viejas que lo tengan todavia.
*/
DROP PROCEDURE IF EXISTS 21_SP_AGREGAR_PRODUCTO_VENTA ;



DELIMITER //
DROP PROCEDURE IF EXISTS SP_CANCELAR_VENTA ;
/*
SP_CANCELAR_VENTA
Cancela una venta que sigue en proceso y le regresa todo el stock.
Valida que el empleado sea el dueño de la venta y que no tenga pagos;
si todo esta bien devuelve las unidades al inventario, deja el movimiento
de ENTRADA en la bitacora, anota la reposicion en el historial del producto
y deja la venta en estado CANCELADA.
*/
CREATE PROCEDURE SP_CANCELAR_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ID_VENTA_EMPLEADO INT;
    DECLARE V_ESTADO VARCHAR(20);

    -- 1. Validar que la venta exista y sea del empleado
    SELECT ID_EMPLEADO, ESTADO INTO V_ID_VENTA_EMPLEADO, V_ESTADO
    FROM VENTAS
    WHERE ID_VENTA = P_ID_VENTA;

    IF V_ID_VENTA_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF V_ID_VENTA_EMPLEADO <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo se cancelan ventas abiertas
    IF V_ESTADO <> 'EN_PROCESO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN CANCELAR VENTAS EN PROCESO.';
        LEAVE proc_label;
    END IF;

    -- 3. Si ya tiene pagos, primero hay que resolverlos afuera
    IF EXISTS (SELECT 1 FROM PAGOS WHERE ID_VENTA = P_ID_VENTA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA TIENE PAGOS REGISTRADOS, NO SE PUEDE CANCELAR.';
        LEAVE proc_label;
    END IF;

    -- 4. Regresar el stock de cada producto
    UPDATE INVENTARIO I
    JOIN DETALLES_VENTA DV ON DV.ID_PRODUCTO = I.ID_PRODUCTO
    SET I.STOCK_ACTUAL = I.STOCK_ACTUAL + DV.CANTIDAD
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 5. Anotar las entradas en la bitacora
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    SELECT DV.ID_PRODUCTO, P_ID_EMPLEADO, 'ENTRADA', DV.CANTIDAD, CONCAT('Venta cancelada ID: ', P_ID_VENTA)
    FROM DETALLES_VENTA DV
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 6. Anotar la reposicion en el historial del producto (stock ya repuesto:
    --    STOCK_ANTERIOR es el actual menos lo que se acaba de devolver)
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    )
    SELECT DV.ID_PRODUCTO, 'ENTRADA', DV.CANTIDAD,
           I.STOCK_ACTUAL - DV.CANTIDAD, I.STOCK_ACTUAL,
           CONCAT('Venta cancelada ID: ', P_ID_VENTA)
    FROM DETALLES_VENTA DV
    JOIN INVENTARIO I ON I.ID_PRODUCTO = DV.ID_PRODUCTO
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 7. Cerrar la venta
    UPDATE VENTAS SET ESTADO = 'CANCELADA' WHERE ID_VENTA = P_ID_VENTA;

    SELECT CONCAT('EXITO: VENTA #', P_ID_VENTA, ' CANCELADA Y STOCK RESTITUIDO.') AS MENSAJE;
END ;
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

/*
LIMPIEZA DE TRIGGERS DUPLICADOS
Estos dos triggers hacian lo mismo que TR_ACTUALIZAR_TOTAL_VENTA (23) y
TR_AUDITORIA_MOVIMIENTO_VENTA (20), asi que el total y el stock se
aplicaban dos veces. Solo queda el DROP para limpiar bases viejas.
*/
DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_VENTA ;
DROP TRIGGER IF EXISTS TR_PROCESAR_VENTA ;


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