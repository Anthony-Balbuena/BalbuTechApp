CREATE TABLE COMPRAS (
    ID_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_PROVEEDOR INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    TOTAL DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (TOTAL >= 0),
    PRIMARY KEY (ID_COMPRA),
    CONSTRAINT FK_COMPRA_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR),
    CONSTRAINT FK_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
 
-- Para reportes de compras por mes, año o día (Cierres de caja)
CREATE INDEX IX_COMPRA_FECHA ON COMPRAS (FECHA);

-- Para análisis de gastos (Ej: "Busca compras mayores a 50,000 pesos")
CREATE INDEX IX_COMPRA_TOTAL ON COMPRAS (TOTAL);




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   



DELIMITER //

DROP PROCEDURE IF EXISTS 19_SP_INICIAR_COMPRA ;

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




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger: Actualiza Inventario al comprar
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_STOCK_COMPRA ;
CREATE TRIGGER TR_ACTUALIZAR_STOCK_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL + NEW.CANTIDAD
    WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
END //

-- Trigger: Actualiza Total de la Compra
DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_COMPRA ;
CREATE TRIGGER TR_CALCULAR_TOTAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    UPDATE COMPRAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_COMPRA = NEW.ID_COMPRA;
END //
DELIMITER ;






V-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

CREATE OR REPLACE VIEW VISTA_REPORTE_COMPRAS AS
SELECT 
    C.ID_COMPRA,
    P.NOMBRE AS PROVEEDOR,
    C.FECHA,
    C.TOTAL
FROM COMPRAS C
JOIN PROVEEDORES P ON C.ID_PROVEEDOR = P.ID_PROVEEDOR
ORDER BY C.FECHA DESC;
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


DELIMITER //

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