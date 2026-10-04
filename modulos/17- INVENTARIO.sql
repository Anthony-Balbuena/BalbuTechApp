/*
TABLA INVENTARIO
Guarda cuanto stock tiene cada producto y en que parte de la tienda.
Cada fila es un producto: su cantidad actual, el minimo que debe haber
y el lugar donde esta guardado. Si el stock baja del minimo, el sistema
avisa automaticamente. Solo puede haber un registro por producto.
*/

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

/*
INDICE IX_INVENTARIO_FECHA
Sirve para ordenar y buscar el inventario por su ultima fecha de cambio,
asi los reportes salen rapidos sin recorrer toda la tabla.
*/
CREATE INDEX IX_INVENTARIO_FECHA ON INVENTARIO (FECHA_ACTUALIZACION);


--INSERTAR

DELIMITER //

DROP PROCEDURE IF EXISTS SP_INSERTAR_INVENTARIO;

/*
SP_INSERTAR_INVENTARIO
Da de alta un producto en el inventario con stock en 0.
Antes de insertar revisa que el producto exista y que no este ya registrado;
si algo esta mal, devuelve un error y no guarda nada.
*/
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


-- ===== VERSIÓN NUEVA (con ROLLBACK) — la vigente =====
/*
SP_INCREMENTAR_STOCK (versión con transacción)
Suma unidades al stock cuando llega mercancia nueva.
Valida cantidad > 0 y que el producto exista, luego aumenta el stock
dentro de una transacción: si cualquier paso posterior falla,
se ejecuta ROLLBACK y el stock queda como estaba.
*/
DELIMITER //

DROP PROCEDURE IF EXISTS SP_INCREMENTAR_STOCK ;

CREATE PROCEDURE SP_INCREMENTAR_STOCK(
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD_ENTRADA INT,
    IN P_PROVEEDOR VARCHAR(100)
)
proc_label: BEGIN
    -- 1. Validar que la cantidad sea lógica (fuera del handler:
    --    un error esperado NO debe provocar ROLLBACK)
    IF P_CANTIDAD_ENTRADA <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD A SUMAR DEBE SER MAYOR A CERO.';
    END IF;

    -- 2. Verificar que el producto exista en la tabla de inventario
    IF NOT EXISTS (SELECT 1 FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO NO ENCONTRADO EN EL INVENTARIO.';
    END IF;

    -- 3. Bloque transaccional: si algo falla después de aquí, se deshace todo
    BEGIN
        DECLARE v_transaccion_propia INT DEFAULT 0;

        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            IF v_transaccion_propia = 1 THEN
                ROLLBACK;
            END IF;
            RESIGNAL;
        END;

        -- Iniciar transacción solo si no hay una activa
        -- (@@in_transaction detecta la tx del llamador aunque este vacía;
        --  information_schema.INNODB_TRX no la ve de forma confiable)
        IF @@in_transaction = 0 THEN
            START TRANSACTION;
            SET v_transaccion_propia = 1;
        END IF;

        -- 4. Incrementar el stock
        UPDATE INVENTARIO
        SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD_ENTRADA
        WHERE ID_PRODUCTO = P_ID_PRODUCTO;

        -- 5. Log para trazabilidad de la entrada.
        --    OMITIDO: la tabla LOG_ENTRADAS_INVENTARIO no existe en la BD;
        --    con el INSERT activo el SP siempre fallaba (y sin transacción
        --    el UPDATE ya quedaba commiteado). Si se crea la tabla, descomentar:
        -- INSERT INTO LOG_ENTRADAS_INVENTARIO (ID_PRODUCTO, CANTIDAD, PROVEEDOR, FECHA)
        -- VALUES (P_ID_PRODUCTO, P_CANTIDAD_ENTRADA, P_PROVEEDOR, CURRENT_TIMESTAMP);

        -- Solo se commitea si la transacción la inició este SP;
        -- si la abrió el llamador, él decide (COMMIT/ROLLBACK).
        IF v_transaccion_propia = 1 THEN
            COMMIT;
        END IF;
    END;

    SELECT 'EXITO: STOCK AUMENTADO CORRECTAMENTE.' AS MENSAJE;
END//

DELIMITER ;


--- RECIBIR MERCANCIA 

DELIMITER //

DROP PROCEDURE IF EXISTS SP_RECIBIR_MERCANCIA;

/*
SP_RECIBIR_MERCANCIA
Recibe mercancia de un producto y la refleja en el stock.
Si el producto aun no tiene registro en inventario, lo crea primero en el
ALMACEN_PRINCIPAL y enseguida le suma la cantidad recibida.
Valida que la cantidad sea mayor a cero; el INSERT y el UPDATE corren en una
transaccion, asi que si algo falla a mitad se ejecuta ROLLBACK y el inventario
queda como estaba (sin filas fantasma ni stock a medias).
*/
CREATE PROCEDURE SP_RECIBIR_MERCANCIA(
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT
)
proc_label: BEGIN
    -- 1. Validacion (fuera del handler: un error esperado NO debe provocar ROLLBACK)
    IF P_CANTIDAD <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD A RECIBIR DEBE SER MAYOR A CERO.';
    END IF;

    -- 2. Bloque transaccional: si algo falla despues de aqui, se deshace todo
    BEGIN
        DECLARE v_transaccion_propia INT DEFAULT 0;

        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            IF v_transaccion_propia = 1 THEN
                ROLLBACK;
            END IF;
            RESIGNAL;
        END;

        -- Iniciar transaccion solo si no hay una activa
        -- (@@in_transaction detecta la tx del llamador aunque este vacia;
        --  information_schema.INNODB_TRX no la ve de forma confiable)
        IF @@in_transaction = 0 THEN
            START TRANSACTION;
            SET v_transaccion_propia = 1;
        END IF;

        -- 3. Crear el registro en inventario si no existe (o ignorar si ya existe)
        INSERT IGNORE INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
        VALUES (P_ID_PRODUCTO, 0, 5, 'ALMACEN_PRINCIPAL');

        -- 4. Incrementar el stock
        UPDATE INVENTARIO
        SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD
        WHERE ID_PRODUCTO = P_ID_PRODUCTO;

        -- Solo se commitea si la transaccion la inicio este SP;
        -- si la abrio el llamador, el decide (COMMIT/ROLLBACK).
        IF v_transaccion_propia = 1 THEN
            COMMIT;
        END IF;
    END;

    SELECT 'EXITO: MERCANCIA RECIBIDA, STOCK ACTUALIZADO.' AS MENSAJE;
END//

DELIMITER ;

---AJUSTE INVENTARI

DELIMITER //
DROP PROCEDURE IF EXISTS SP_AJUSTE_INVENTARIO;

/*
SP_AJUSTE_INVENTARIO
Corrige el stock a mano por un motivo (faltante, sobrante, error de conteo).
Suma si la cantidad es positiva y resta si es negativa; el historial lo
guarda solo el trigger, sin tener que escribir nada extra.
*/
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
/*
17_TR_VALIDAR_STOCK_MINIMO
Cada vez que cambia el stock, revisa si quedo en o bajo el minimo.
Si es asi, escribe una alerta en LOG_USUARIOS para que alguien compre mas.
*/
DROP TRIGGER IF EXISTS 17_TR_VALIDAR_STOCK_MINIMO ;
CREATE TRIGGER 17_TR_VALIDAR_STOCK_MINIMO
AFTER UPDATE ON INVENTARIO
FOR EACH ROW
BEGIN
    IF NEW.STOCK_ACTUAL <= NEW.STOCK_MINIMO THEN
        INSERT INTO LOG_USUARIOS (ID_USUARIO, ACCION, VALOR_ANTERIOR, VALOR_NUEVO)
        VALUES (NULL, 'ALERTA_STOCK_BAJO',
                CONCAT('Producto ', NEW.ID_PRODUCTO, ' llego al stock minimo (', NEW.STOCK_MINIMO, ')'),
                'PENDIENTE');
    END IF;
END ;
DELIMITER ;


----HISTORIAL DE INVENTARIO

DELIMITER //

DROP TRIGGER IF EXISTS 17_TR_REGISTRAR_HISTORIAL_INVENTARIO ;

/*
17_TR_REGISTRAR_HISTORIAL_INVENTARIO
Vigila cada cambio de stock y lo anota en HISTORIAL_MOVIMIENTOS_PRODUCTO.
Guarda cuanto habia antes, cuanto hay ahora y si fue entrada o salida,
asi siempre se puede rastrear quien movio que y cuando.
*/
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


/*
VISTA_PRODUCTOS_CRITICOS
Lista los productos que se estan quedando sin stock.
Muestra el nombre, lo que queda, lo minimo y cuanto falta para llegar al minimo.
*/
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






/*
VISTA_VALOR_PRODUCTOS
Muestra cuanta dinero representa cada producto en bodega.
Multiplica el stock por su precio y ordena de mayor a menor valor.
*/
CREATE OR REPLACE VIEW VISTA_VALOR_PRODUCTOS AS
SELECT 
    P.NOMBRE,
    I.STOCK_ACTUAL,
    P.PRECIO,
    (I.STOCK_ACTUAL * P.PRECIO) AS VALOR_TOTAL_ITEM
FROM INVENTARIO I
JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
ORDER BY VALOR_TOTAL_ITEM DESC;



-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


DELIMITER //

/*
FN_VALOR_TOTAL_INVENTARIO
Suma el valor de todo el inventario: stock multiplicado por precio.
Se usa en reportes para saber cuanto dinero hay en bodega; devuelve 0 si no hay nada.
*/
CREATE FUNCTION FN_VALOR_TOTAL_INVENTARIO() 
RETURNS DECIMAL(15,2)
DETERMINISTIC
BEGIN
    DECLARE V_TOTAL DECIMAL(15,2);
    
    SELECT SUM(I.STOCK_ACTUAL * P.PRECIO) INTO V_TOTAL
    FROM INVENTARIO I
    JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO;
    
    RETURN IFNULL(V_TOTAL, 0);
END //

DELIMITER ;

















DESCRIBE PRODUCTOS;
DESCRIBE INVENTARIO;