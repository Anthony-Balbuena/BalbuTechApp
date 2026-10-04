/*
TABLA DETALLE_COMPRA
Guarda que productos forman parte de cada compra, con su cantidad y precio.
El subtotal se calcula solo al multiplicar cantidad por precio.
No se puede repetir el mismo producto dentro de la misma compra.
*/
CREATE TABLE DETALLE_COMPRA (
    ID_DETALLE_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_COMPRA INT NOT NULL,
    ID_PRODUCTO INT NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    PRECIO_UNITARIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO_UNITARIO > 0),
    -- En MariaDB usamos STORED para que el valor se guarde físicamente
    SUBTOTAL DECIMAL(10, 2) AS (CANTIDAD * PRECIO_UNITARIO) STORED,
    PRIMARY KEY (ID_DETALLE_COMPRA),
    CONSTRAINT UQ_COMPRA_PRODUCTO UNIQUE (ID_COMPRA, ID_PRODUCTO),
    CONSTRAINT FK_DETALLE_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA) ON DELETE CASCADE,
    CONSTRAINT FK_DETALLE_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO)
) ENGINE = InnoDB;

-- 1. Optimiza la búsqueda de compras por cada Proveedor
/*
INDICE IX_COMPRA_PROVEEDOR
Busca todas las compras de un proveedor en concreto,
util para ver el historial de compras hechas a cada proveedor.
*/
CREATE INDEX IX_COMPRA_PROVEEDOR ON COMPRAS (ID_PROVEEDOR);

-- 2. Acelera la carga de los productos de una factura de compra específica
/*
INDICE IX_DETALLE_COMPRA_COMPRA
Trae rapidamente todos los productos que trae una factura de compra.
*/
CREATE INDEX IX_DETALLE_COMPRA_COMPRA ON DETALLE_COMPRA (ID_COMPRA);

-- 3. Permite rastrear el historial de precios y compras de un solo Producto
/*
INDICE IX_DETALLE_COMPRA_PRODUCTO
Sirve para rastrear el historial de precios y compras de un solo producto.
*/
CREATE INDEX IX_DETALLE_COMPRA_PRODUCTO ON DETALLE_COMPRA (ID_PRODUCTO);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER // 
DROP PROCEDURE IF EXISTS 22_SP_AGREGAR_DETALLE_COMPRA ;
/*
22_SP_AGREGAR_DETALLE_COMPRA
Agrega un producto a una compra que ya esta abierta.
Revisa que la compra y el producto existan, que la cantidad y el precio sean
positivos y que el producto no este repetido; si algo falla no guarda nada.
*/
CREATE PROCEDURE 22_SP_AGREGAR_DETALLE_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT,
    IN P_PRECIO DECIMAL(10, 2)
)
proc_label: BEGIN
    -- 1. VALIDACIONES DE INTEGRIDAD
    IF NOT EXISTS (SELECT 1 FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF IFNULL((SELECT ESTADO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO), 'INACTIVO') <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO ESTA ACTIVO.';
        LEAVE proc_label;
    END IF;

    IF P_CANTIDAD <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CANTIDAD INVALIDA.';
        LEAVE proc_label;
    END IF;

    IF P_PRECIO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRECIO INVALIDA.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM DETALLE_COMPRA WHERE ID_COMPRA = P_ID_COMPRA AND ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO YA AGREGADO.';
        LEAVE proc_label;
    END IF;

    -- 2. INSERCIÓN
    INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO);

    SELECT 'EXITO: PRODUCTO AGREGADO.' AS MENSAJE;
END //
DELIMITER ;

------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}----------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_COMPRA ;
/*
TR_CALCULAR_TOTAL_COMPRA
Le va sumando el subtotal de cada producto al TOTAL de la compra.
Asi el total de la compra queda actualizado sin calcularlo a mano.
*/
CREATE TRIGGER TR_CALCULAR_TOTAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    UPDATE COMPRAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_COMPRA = NEW.ID_COMPRA;
END //
DELIMITER ;

-----

DROP TRIGGER IF EXISTS TR_PROCESAR_COMPRA ;
/*
TR_PROCESAR_COMPRA
ELIMINADO: era redundante. Sumaba el stock dos veces y registraba la
ENTRADA en MOVIMIENTOS_INVENTARIO dos veces (una con empleado fijo 1).
Ya lo hacen TR_ACTUALIZAR_STOCK_COMPRA (19- COMPRAS) y
TR_AUDITORIA_MOVIMIENTO_COMPRA (20- MOVIMIENTOS_INVENTARIO).
*/








------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}--------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------

/*
VISTA_DETALLE_COMPRA
Muestra los productos de cada compra con cantidad, precio y subtotal.
Trae el nombre del producto en lugar de su ID, lista para ver en pantalla.
*/
CREATE OR REPLACE VIEW VISTA_DETALLE_COMPRA AS
SELECT 
    DC.ID_COMPRA,
    P.NOMBRE AS PRODUCTO,
    DC.CANTIDAD,
    DC.PRECIO_UNITARIO,
    DC.SUBTOTAL
FROM DETALLE_COMPRA DC
JOIN PRODUCTOS P ON DC.ID_PRODUCTO = P.ID_PRODUCTO;

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------