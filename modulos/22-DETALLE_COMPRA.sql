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
Revisa que la compra exista y este ABIERTA, que el producto exista,
que la cantidad y el precio sean
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

    IF (SELECT ESTADO FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA) <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
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

    -- 3. Aviso de margen: si este precio de compra ya alcanza (o pasa)
    --    el precio de venta, se esta comprando a perdida o sin margen
    IF P_PRECIO >= (SELECT PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SELECT 'EXITO: PRODUCTO AGREGADO (ADVERTENCIA: PRECIO DE COMPRA IGUAL O MAYOR AL DE VENTA).' AS MENSAJE;
    ELSE
        SELECT 'EXITO: PRODUCTO AGREGADO.' AS MENSAJE;
    END IF;
END ;
DELIMITER ;
DELIMITER //
DROP PROCEDURE IF EXISTS SP_QUITAR_DETALLE_COMPRA ;
/*
SP_QUITAR_DETALLE_COMPRA
Quita un producto de una compra que sigue ABIERTA: regresa su stock,
anota la SALIDA y recalcula el TOTAL. Revisa que el producto este en la
compra y que el stock alcance; los efectos los hacen los triggers de
DELETE, asi que tambien valen con un DELETE directo.
*/
CREATE PROCEDURE SP_QUITAR_DETALLE_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_PRODUCTO INT
)
proc_label: BEGIN
    DECLARE V_ID_DETALLE INT;
    DECLARE V_CANTIDAD INT;
    DECLARE V_ESTADO VARCHAR(20);

    -- 1. El producto debe estar en la compra
    SELECT DC.ID_DETALLE_COMPRA, DC.CANTIDAD, C.ESTADO
      INTO V_ID_DETALLE, V_CANTIDAD, V_ESTADO
      FROM DETALLE_COMPRA DC
      JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
     WHERE DC.ID_COMPRA = P_ID_COMPRA
       AND DC.ID_PRODUCTO = P_ID_PRODUCTO;

    IF V_ID_DETALLE IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO ESTA EN ESTA COMPRA.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo de una compra ABIERTA (los triggers lo re-aplican)
    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
        LEAVE proc_label;
    END IF;

    -- 3. Stock alcanzante: la linea se va del inventario
    IF IFNULL((SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO), 0) < V_CANTIDAD THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).';
        LEAVE proc_label;
    END IF;

    -- 4. Borrar el detalle dispara los triggers de DELETE
    DELETE FROM DETALLE_COMPRA
     WHERE ID_DETALLE_COMPRA = V_ID_DETALLE;

    SELECT CONCAT('EXITO: PRODUCTO #', P_ID_PRODUCTO,
                  ' QUITADO DE LA COMPRA #', P_ID_COMPRA, '.') AS MENSAJE;
END ;
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
Si se quita una linea, el total lo recalcula TR_RECALCULAR_TOTAL_COMPRA.
*/
CREATE TRIGGER TR_CALCULAR_TOTAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    UPDATE COMPRAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_COMPRA = NEW.ID_COMPRA;
END ;
DELIMITER ;
DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_TOTAL_COMPRA ;
/*
TR_RECALCULAR_TOTAL_COMPRA
Cuando se borra una linea de una compra, vuelve a sumar todo lo que
quede en DETALLE_COMPRA y deja ese numero en el TOTAL. Como sale de la
propia tabla el total queda exacto aunque se borren varias lineas.
*/
CREATE TRIGGER TR_RECALCULAR_TOTAL_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    UPDATE COMPRAS
       SET TOTAL = (
            SELECT IFNULL(SUM(SUBTOTAL), 0)
              FROM DETALLE_COMPRA
             WHERE ID_COMPRA = OLD.ID_COMPRA
       )
     WHERE ID_COMPRA = OLD.ID_COMPRA;
END ;
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