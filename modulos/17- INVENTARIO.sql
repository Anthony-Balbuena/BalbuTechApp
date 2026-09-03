CREATE TABLE INVENTARIO (
    ID_INVENTARIO INT NOT NULL AUTO_INCREMENT, 
    ID_PRODUCTO INT NOT NULL,
    STOCK_ACTUAL INT NOT NULL DEFAULT 0 CHECK (STOCK_ACTUAL >= 0),
    STOCK_MINIMO INT NOT NULL DEFAULT 5 CHECK (STOCK_MINIMO >= 0),
    UBICACION VARCHAR(100) NOT NULL,
    FECHA_ACTUALIZACION TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_INVENTARIO),
    CONSTRAINT UQ_INVENTARIO_PRODUCTO UNIQUE (ID_PRODUCTO),
    CONSTRAINT FK_INVENTARIO_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE INDEX IX_INVENTARIO_FECHA ON INVENTARIO (FECHA_ACTUALIZACION);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

--INSERTAR

DELIMITER //

DROP PROCEDURE IF EXISTS SP_INSERTAR_INVENTARIO;

CREATE PROCEDURE SP_INSERTAR_INVENTARIO(
    IN P_ID_PRODUCTO INT,
    IN P_STOCK_MINIMO INT,
    IN P_UBICACION VARCHAR(100)
)
proc_label: BEGIN
    DECLARE V_NOMBRE_PRODUCTO VARCHAR(100);

    -- 1. Validar que el producto exista y obtener su nombre al mismo tiempo
    SELECT NOMBRE INTO V_NOMBRE_PRODUCTO 
    FROM PRODUCTOS 
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    IF V_NOMBRE_PRODUCTO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE ID DE PRODUCTO NO EXISTE EN EL CATÁLOGO.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar duplicados en inventario
    IF EXISTS (SELECT 1 FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE PRODUCTO YA TIENE UN REGISTRO EN INVENTARIO.';
        LEAVE proc_label;
    END IF;

    -- 3. Insertar
    INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
    VALUES (P_ID_PRODUCTO, 0, P_STOCK_MINIMO, P_UBICACION);

    -- 4. Devolver confirmación con datos del producto
    SELECT 
        'EXITO' AS ESTADO,
        P_ID_PRODUCTO AS ID, 
        V_NOMBRE_PRODUCTO AS PRODUCTO, 
        'AGREGADO AL INVENTARIO CON STOCK 0' AS MENSAJE;
END;

DELIMITER ;


call `SP_INSERTAR_INVENTARIO` (3,10,'Caja');

----INCREMENTAR
DELIMITER //

DROP PROCEDURE IF EXISTS 17_SP_INCREMENTAR_STOCK ;

CREATE PROCEDURE 17_SP_INCREMENTAR_STOCK(
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD_ENTRADA INT,
    IN P_PROVEEDOR VARCHAR(100)
)
proc_label: BEGIN
    -- 1. Validar que la cantidad sea lógica
    IF P_CANTIDAD_ENTRADA <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD A SUMAR DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 2. Verificar que el producto exista en la tabla de inventario
    IF NOT EXISTS (SELECT 1 FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO NO ENCONTRADO EN EL INVENTARIO.';
        LEAVE proc_label;
    END IF;

    -- 3. Incrementar el stock
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD_ENTRADA
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. Log para trazabilidad de la entrada
    INSERT INTO LOG_ENTRADAS_INVENTARIO (ID_PRODUCTO, CANTIDAD, PROVEEDOR, FECHA)
    VALUES (P_ID_PRODUCTO, P_CANTIDAD_ENTRADA, P_PROVEEDOR, CURRENT_TIMESTAMP);

    SELECT 'EXITO: STOCK AUMENTADO CORRECTAMENTE.' AS MENSAJE;
END;

DELIMITER ;


--- RECIBIR MERCANCIA 

DELIMITER //

DROP PROCEDURE IF EXISTS SP_RECIBIR_MERCANCIA;

CREATE PROCEDURE SP_RECIBIR_MERCANCIA(
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT
)
BEGIN
    -- Intentar insertar si no existe (o ignorar si ya existe)
    INSERT IGNORE INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
    VALUES (P_ID_PRODUCTO, 0, 5, 'ALMACEN_PRINCIPAL');

    -- Ahora sí, incrementar el stock
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;
END;

DELIMITER ;

---AJUSTE INVENTARI

DELIMITER //
DROP PROCEDURE IF EXISTS SP_AJUSTE_INVENTARIO;
CREATE PROCEDURE SP_AJUSTE_INVENTARIO(
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD_AJUSTE INT, -- Positivo para sumar, negativo para restar
    IN P_MOTIVO VARCHAR(100)
)
BEGIN
    UPDATE INVENTARIO 
    SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD_AJUSTE
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    
    -- El trigger que ya creamos registrará esto automáticamente en el historial
    SELECT 'EXITO: AJUSTE REALIZADO.' AS MENSAJE;
END ;

DELIMITER ;




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
CREATE TRIGGER 17_TR_VALIDAR_STOCK_MINIMO
AFTER UPDATE ON INVENTARIO
FOR EACH ROW
BEGIN
    IF NEW.STOCK_ACTUAL <= NEW.STOCK_MINIMO THEN
        -- Aquí podrías insertar en una tabla de 'ALERTAS' si quisieras
        INSERT INTO LOG_USUARIOS (USERNAME, ACCION, RESULTADO, FECHA)
        VALUES ('SYSTEM', CONCAT('ALERTA: STOCK BAJO EN PRODUCTO ID ', NEW.ID_PRODUCTO), 'PENDIENTE', CURRENT_TIMESTAMP);
    END IF;
END ;
DELIMITER ;


----HISTORIAL DE INVENTARIO

DELIMITER //

DROP TRIGGER IF EXISTS 17_TR_REGISTRAR_HISTORIAL_INVENTARIO ;

CREATE TRIGGER 17_TR_REGISTRAR_HISTORIAL_INVENTARIO
AFTER UPDATE ON INVENTARIO
FOR EACH ROW
BEGIN
    IF OLD.STOCK_ACTUAL <> NEW.STOCK_ACTUAL THEN
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
            ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
        )
        VALUES (
            NEW.ID_PRODUCTO,
            IF(NEW.STOCK_ACTUAL > OLD.STOCK_ACTUAL, 'ENTRADA', 'SALIDA'),
            ABS(NEW.STOCK_ACTUAL - OLD.STOCK_ACTUAL),
            OLD.STOCK_ACTUAL,
            NEW.STOCK_ACTUAL,
            'Actualización automática de stock'
        );
    END IF;
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


CREATE OR REPLACE VIEW VISTA_PRODUCTOS_CRITICOS AS
SELECT 
    I.ID_PRODUCTO,
    P.NOMBRE, -- <--- POSIBLE ERROR AQUÍ: ¿Tu tabla productos se llama 'NOMBRE' o 'NOMBRE_PRODUCTO'?
    I.STOCK_ACTUAL,
    I.STOCK_MINIMO,
    (I.STOCK_MINIMO - I.STOCK_ACTUAL) AS CANTIDAD_FALTANTE
FROM INVENTARIO I
JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
WHERE I.STOCK_ACTUAL <= I.STOCK_MINIMO;






CREATE OR REPLACE VIEW VISTA_VALOR_PRODUCTOS AS
SELECT 
    P.NOMBRE,
    I.STOCK_ACTUAL,
    P.PRECIO_COMPRA,
    (I.STOCK_ACTUAL * P.PRECIO_COMPRA) AS VALOR_TOTAL_ITEM
FROM INVENTARIO I
JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
ORDER BY VALOR_TOTAL_ITEM DESC;



-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


DELIMITER //

CREATE FUNCTION FN_VALOR_TOTAL_INVENTARIO() 
RETURNS DECIMAL(15,2)
DETERMINISTIC
BEGIN
    DECLARE V_TOTAL DECIMAL(15,2);
    
    SELECT SUM(I.STOCK_ACTUAL * P.PRECIO_COMPRA) INTO V_TOTAL
    FROM INVENTARIO I
    JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO;
    
    RETURN IFNULL(V_TOTAL, 0);
END //

DELIMITER ;

















DESCRIBE PRODUCTOS;
DESCRIBE INVENTARIO;