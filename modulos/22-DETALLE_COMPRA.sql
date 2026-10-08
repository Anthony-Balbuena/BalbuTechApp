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
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
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


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 3. Aviso de margen: si este precio de compra ya alcanza (o pasa)
    --    el precio de venta, se esta comprando a perdida o sin margen
    IF P_PRECIO >= (SELECT PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SELECT 'EXITO: PRODUCTO AGREGADO (ADVERTENCIA: PRECIO DE COMPRA IGUAL O MAYOR AL DE VENTA).' AS MENSAJE;
    ELSE
        SELECT 'EXITO: PRODUCTO AGREGADO.' AS MENSAJE;
    END IF;
END //
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
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_DETALLE INT;
    DECLARE V_CANTIDAD INT;
    DECLARE V_ESTADO VARCHAR(20);
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


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: PRODUCTO #', P_ID_PRODUCTO,
                  ' QUITADO DE LA COMPRA #', P_ID_COMPRA, '.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_MODIFICAR_LINEA_COMPRA ;
/*
SP_MODIFICAR_LINEA_COMPRA
Cambia la cantidad o el precio de un producto que ya esta dentro de una
compra ABIERTA. Como las lineas no se pueden editar a pelo (esta el trigger
TR_BLOQUEAR_UPDATE_DETALLE_COMPRA), aqui se borra la linea vieja y se escribe
la nueva: el stock y el TOTAL los reajustan solos los mismos triggers del
alta y de la baja, y ademas queda el movimiento en el historial.
El stock tiene que alcanzar para devolver la linea vieja, igual que para
quitarla con SP_QUITAR_DETALLE_COMPRA.
*/
CREATE PROCEDURE SP_MODIFICAR_LINEA_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT,
    IN P_PRECIO DECIMAL(10, 2)
)
proc_label: BEGIN
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_DETALLE INT;
    DECLARE V_ESTADO VARCHAR(20);
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

    -- 1. El producto debe estar en una compra que siga ABIERTA
    SELECT DC.ID_DETALLE_COMPRA, C.ESTADO
      INTO V_ID_DETALLE, V_ESTADO
      FROM DETALLE_COMPRA DC
      JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
     WHERE DC.ID_COMPRA = P_ID_COMPRA
       AND DC.ID_PRODUCTO = P_ID_PRODUCTO;

    IF V_ID_DETALLE IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO ESTA EN ESTA COMPRA.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
        LEAVE proc_label;
    END IF;

    -- 2. Los valores nuevos tienen que ser validos
    IF P_CANTIDAD <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CANTIDAD INVALIDA.';
        LEAVE proc_label;
    END IF;

    IF P_PRECIO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRECIO INVALIDA.';
        LEAVE proc_label;
    END IF;

    -- 3. El producto debe seguir ACTIVO
    IF IFNULL((SELECT ESTADO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO), 'INACTIVO') <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO ESTA ACTIVO.';
        LEAVE proc_label;
    END IF;

    -- 4. Se va la linea vieja: regresa el stock y recalcula el TOTAL
    DELETE FROM DETALLE_COMPRA WHERE ID_DETALLE_COMPRA = V_ID_DETALLE;

    -- 5. Entra la linea nueva: vuelve a sumar stock y TOTAL
    INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, P_PRECIO);


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 6. Aviso de margen, igual que al agregar
    IF P_PRECIO >= (SELECT PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SELECT 'EXITO: LINEA MODIFICADA (ADVERTENCIA: PRECIO DE COMPRA IGUAL O MAYOR AL DE VENTA).' AS MENSAJE;
    ELSE
        SELECT 'EXITO: LINEA MODIFICADA.' AS MENSAJE;
    END IF;
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
Si se quita una linea, el total lo recalcula TR_RECALCULAR_TOTAL_COMPRA.
*/
CREATE TRIGGER TR_CALCULAR_TOTAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    -- P11C (07/10/2026): si el UPDATE de TOTAL falla, apagar la bandera
    -- antes de propagar el error (las variables de usuario no se
    -- revierten con ROLLBACK); patron P11 del flujo de ventas.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @COMPRAS_INTERNO = 0;
        RESIGNAL;
    END;

    -- @COMPRAS_INTERNO le avisa al candado de cabecera que este cambio de
    -- TOTAL viene del detalle y no de un UPDATE a pelo
    SET @COMPRAS_INTERNO = 1;
    UPDATE COMPRAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_COMPRA = NEW.ID_COMPRA;
    SET @COMPRAS_INTERNO = 0;
END //
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
    -- P11C (07/10/2026): si el UPDATE de TOTAL falla, apagar la bandera
    -- antes de propagar el error (las variables de usuario no se
    -- revierten con ROLLBACK); patron P11 del flujo de ventas.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @COMPRAS_INTERNO = 0;
        RESIGNAL;
    END;

    -- Mismo candado interno que TR_CALCULAR_TOTAL_COMPRA: el TOTAL aqui
    -- lo pone el recalculo contra el detalle, no un UPDATE a mano
    SET @COMPRAS_INTERNO = 1;
    UPDATE COMPRAS
       SET TOTAL = (
            SELECT IFNULL(SUM(SUBTOTAL), 0)
              FROM DETALLE_COMPRA
             WHERE ID_COMPRA = OLD.ID_COMPRA
       )
     WHERE ID_COMPRA = OLD.ID_COMPRA;
    SET @COMPRAS_INTERNO = 0;
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

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_COMPRA_CERRADA movido a 22 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CERRADA ;
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CANCELADA ;
/*
TR_BLOQUEAR_COMPRA_CERRADA
Una compra que no esta ABIERTA (RECIBIDA o CANCELADA) no acepta mas
productos, ni siquiera con un INSERT directo (misma idea que
TR_BLOQUEAR_VENTA_FINALIZADA en ventas). Si hay que agregar algo despues
de estar saldada, primero se anula el pago que cerro la compra con
SP_ANULAR_PAGO_COMPRA (archivo 19.5) y vuelve a ABIERTA.
Reemplaza a TR_BLOQUEAR_COMPRA_CANCELADA (solo cubria CANCELADA).
*/
CREATE TRIGGER TR_BLOQUEAR_COMPRA_CERRADA
BEFORE INSERT ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
    END IF;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_UPDATE_DETALLE_COMPRA movido a 22 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_UPDATE_DETALLE_COMPRA ;
/*
TR_BLOQUEAR_UPDATE_DETALLE_COMPRA
Nadie cambia una linea de compra con UPDATE a pelo: la cantidad y el precio
son la prueba de lo que se acordo con el proveedor. Para corregir algo se
usa SP_MODIFICAR_LINEA_COMPRA (archivo 22), o se quita la linea con
SP_QUITAR_DETALLE_COMPRA y se vuelve a agregar. Trabaja en automatico.
*/
CREATE TRIGGER TR_BLOQUEAR_UPDATE_DETALLE_COMPRA
BEFORE UPDATE ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA LINEA DE UNA COMPRA NO SE PUEDE EDITAR; USE SP_MODIFICAR_LINEA_COMPRA.';
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_ACTUALIZAR_STOCK_COMPRA movido a 22 (su tabla).
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

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_BORRADO_COMPRA_CERRADA movido a 22 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_COMPRA_CERRADA ;
/*
TR_BLOQUEAR_BORRADO_COMPRA_CERRADA
Lo mismo que TR_BLOQUEAR_COMPRA_CERRADA pero cuando se borra una linea:
solo una compra ABIERTA deja quitarle productos y ademas el stock tiene
que alcanzar (la mercancia se regresa del inventario). En RECIBIDA,
CANCELADA o DEVUELTA el detalle queda como evidencia y nadie lo puede
borrar, ni siquiera con un DELETE directo.
*/
CREATE TRIGGER TR_BLOQUEAR_BORRADO_COMPRA_CERRADA
BEFORE DELETE ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_STOCK INT;

    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    IF V_ESTADO IS NOT NULL AND V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
    END IF;

    -- El stock tiene que alcanzar para regresar la mercancia
    SET V_STOCK = IFNULL((
        SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = OLD.ID_PRODUCTO
    ), 0);

    IF V_STOCK < OLD.CANTIDAD THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL STOCK ACTUAL NO ALCANZA PARA QUITAR ESTE PRODUCTO (YA HUBO VENTAS DE ESA MERCANCIA).';
    END IF;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_ACTUALIZAR_STOCK_BORRADO_COMPRA movido a 22 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_STOCK_BORRADO_COMPRA ;
/*
TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
Cuando se quita una linea de una compra, le resta la cantidad al stock
(lo inverso de TR_ACTUALIZAR_STOCK_COMPRA) y en el MISMO trigger anota
la SALIDA en el historial con el stock antes y despues. Van juntos a
proposito: los triggers de DELETE no se pueden ordenar a gusto y asi el
antes/despues sale bien sin importar en que orden disparen los demas.
El guard de stock y de estado esta en el BEFORE, que corre primero.
*/
CREATE TRIGGER TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_STOCK_ANTES INT;
    DECLARE V_STOCK_DESPUES INT;

    -- 1. Stock antes de restar
    SELECT STOCK_ACTUAL INTO V_STOCK_ANTES
      FROM INVENTARIO WHERE ID_PRODUCTO = OLD.ID_PRODUCTO;

    SET V_STOCK_DESPUES = V_STOCK_ANTES - OLD.CANTIDAD;

    -- 2. Bajar el stock
    UPDATE INVENTARIO
       SET STOCK_ACTUAL = V_STOCK_DESPUES
     WHERE ID_PRODUCTO = OLD.ID_PRODUCTO;

    -- 3. UNA fila de historial con el antes y el despues
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        OLD.ID_PRODUCTO, 'SALIDA', OLD.CANTIDAD, V_STOCK_ANTES, V_STOCK_DESPUES,
        'Producto quitado de la compra'
    );
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_AUDITORIA_MOVIMIENTO_COMPRA movido a 22 (su tabla).
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
END //

DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_AUDITORIA_BORRADO_COMPRA movido a 22 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_BORRADO_COMPRA ;

/*
TR_AUDITORIA_BORRADO_COMPRA
Cuando se quita una linea de una compra, anota la SALIDA de esa
mercancia (el stock que se regresa al inventario). El empleado lo toma
de la compra, igual que en la ENTRADA.
*/
CREATE TRIGGER TR_AUDITORIA_BORRADO_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (OLD.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', OLD.CANTIDAD,
            CONCAT('Producto quitado de la compra ID: ', OLD.ID_COMPRA));
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Tabla DEVOLUCION_COMPRA reubicada desde 19.6 (requiere DETALLE_COMPRA ya creada).
-----------------------------------------------------------------------------------------------------------------------
/*
TABLA DEVOLUCION_COMPRA
Guarda cada devolucion al proveedor con su cantidad, motivo y condicion.
Nace PENDIENTE; al procesarla devuelve la mercancia y al rechazarla no
toca nada. El subtotal se guarda al registrar para no depender de
precios que puedan cambiar despues.
*/
CREATE TABLE DEVOLUCION_COMPRA (
    ID_DEVOLUCION_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_DETALLE_COMPRA INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL DEFAULT (CURRENT_DATE),
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    MOTIVO VARCHAR(200),
    CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO') NOT NULL DEFAULT 'BUENO',
    SUBTOTAL_DEVUELTO DECIMAL(10, 2) NOT NULL CHECK (SUBTOTAL_DEVUELTO > 0),
    ESTADO ENUM('PENDIENTE', 'PROCESADA', 'RECHAZADA') NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_DEVOLUCION_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_DETALLE FOREIGN KEY (ID_DETALLE_COMPRA) REFERENCES DETALLE_COMPRA (ID_DETALLE_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- ============================================================
-- Deja al dia una BD que ya tenia esta tabla (como la real): le pone el
-- CHECK de que el subtotal nunca sea cero. Un INSERT a pelo con subtotal 0
-- devolveria mercancia sin bajar el TOTAL y la compra nunca llegaria a
-- DEVUELTA. En una BD recien creada el CREATE de arriba ya lo trae.
-- ============================================================
ALTER TABLE DEVOLUCION_COMPRA MODIFY COLUMN SUBTOTAL_DEVUELTO DECIMAL(10, 2) NOT NULL CHECK (SUBTOTAL_DEVUELTO > 0);

/*
INDICE IX_DEVOLUCION_COMPRA_FECHA
Busca las devoluciones por fecha, igual que las demas tablas de compra,
para los reportes del periodo.
*/
CREATE INDEX IX_DEVOLUCION_COMPRA_FECHA ON DEVOLUCION_COMPRA (FECHA);

/*
INDICE IX_DEVOLUCION_COMPRA_ESTADO_FECHA
Trae las devoluciones por estado y fecha: es el de "devoluciones
pendientes del dia". Sin este indice ese reporte recorria la tabla entera
(ventas si lo tiene: IX_DEVOLUCION_ESTADO_FECHA en el archivo 25).
*/
CREATE INDEX IX_DEVOLUCION_COMPRA_ESTADO_FECHA ON DEVOLUCION_COMPRA (ESTADO, FECHA);

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_PROCESAR_DEVOLUCION_COMPRA movido a 22 (tabla DEVOLUCION_COMPRA vive ahi).
DELIMITER //
DROP TRIGGER IF EXISTS TR_PROCESAR_DEVOLUCION_COMPRA ;
/*
TR_PROCESAR_DEVOLUCION_COMPRA
Cuando una devolucion pasa de PENDIENTE a PROCESADA: valida que la compra
sigue RECIBIDA y que el stock alcanza (si no, todo falla sin cambios),
baja el stock, anota la SALIDA en movimientos, escribe UNA fila de
historial con el stock antes y despues, y baja el TOTAL de la compra; si
el TOTAL llega a 0 la compra queda DEVUELTA. RECHAZADA no toca nada.
Tambien se aplica si alguien cambia el estado con un UPDATE directo.
*/
CREATE TRIGGER TR_PROCESAR_DEVOLUCION_COMPRA
AFTER UPDATE ON DEVOLUCION_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ID_COMPRA INT;
    DECLARE V_ID_PRODUCTO INT;
    DECLARE V_ESTADO_COMPRA VARCHAR(20);
    DECLARE V_STOCK_ANTES INT;
    DECLARE V_TOTAL_ACTUAL DECIMAL(10, 2);

    -- P11C (07/10/2026): el paso 4 prende @COMPRAS_INTERNO; si el UPDATE
    -- de TOTAL falla, apagar la bandera antes de propagar (las variables
    -- de usuario no se revierten con ROLLBACK).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @COMPRAS_INTERNO = 0;
        RESIGNAL;
    END;

    IF NEW.ESTADO = 'PROCESADA' AND OLD.ESTADO = 'PENDIENTE' THEN

        -- Datos del detalle que se devuelve
        SELECT DC.ID_COMPRA, DC.ID_PRODUCTO
          INTO V_ID_COMPRA, V_ID_PRODUCTO
          FROM DETALLE_COMPRA DC
         WHERE DC.ID_DETALLE_COMPRA = NEW.ID_DETALLE_COMPRA;

        -- La compra debe seguir RECIBIDA
        SELECT ESTADO INTO V_ESTADO_COMPRA
          FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

        IF V_ESTADO_COMPRA <> 'RECIBIDA' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA RECIBIDA; NO SE PUEDE PROCESAR LA DEVOLUCION.';
        END IF;

        -- El stock tiene que alcanzar (si alguien ya se lo vendio, no hay)
        SET V_STOCK_ANTES = IFNULL((
            SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = V_ID_PRODUCTO
        ), 0);

        IF V_STOCK_ANTES < NEW.CANTIDAD THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL STOCK ACTUAL NO ALCANZA PARA DEVOLVER (YA HUBO VENTAS DE ESA MERCANCIA).';
        END IF;

        -- El subtotal nunca puede pasarse del total (candado ante UPDATE directo)
        SELECT TOTAL INTO V_TOTAL_ACTUAL
          FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

        IF NEW.SUBTOTAL_DEVUELTO > V_TOTAL_ACTUAL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL SUBTOTAL DE LA DEVOLUCION EXCEDE EL TOTAL DE LA COMPRA.';
        END IF;

        -- 1. Baja el stock
        UPDATE INVENTARIO
           SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
         WHERE ID_PRODUCTO = V_ID_PRODUCTO;

        -- 2. Bitacora: la SALIDA hacia el proveedor
        INSERT INTO MOVIMIENTOS_INVENTARIO
            (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
        VALUES
            (V_ID_PRODUCTO, NEW.ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD,
             CONCAT('Devolucion a proveedor ID: ', NEW.ID_DEVOLUCION_COMPRA));

        -- 3. Historial UNA fila con el stock antes y despues
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO
            (ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION)
        VALUES
            (V_ID_PRODUCTO, 'DEVOLUCION', NEW.CANTIDAD, V_STOCK_ANTES, V_STOCK_ANTES - NEW.CANTIDAD,
             CONCAT('Devolucion a proveedor ID: ', NEW.ID_DEVOLUCION_COMPRA));

        -- 4. Baja el TOTAL de la compra (el detalle queda como evidencia).
        --    El candado interno avisa a TR_VALIDAR_ACTUALIZACION_COMPRA de
        --    que este cambio de TOTAL viene de la devolucion y no a pelo.
        SET @COMPRAS_INTERNO = 1;
        UPDATE COMPRAS
           SET TOTAL = TOTAL - NEW.SUBTOTAL_DEVUELTO
         WHERE ID_COMPRA = V_ID_COMPRA;
        SET @COMPRAS_INTERNO = 0;

        -- 5. Si se devolvio todo, la compra queda DEVUELTA
        UPDATE COMPRAS
           SET ESTADO = 'DEVUELTA'
         WHERE ID_COMPRA = V_ID_COMPRA AND TOTAL <= 0;
    END IF;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA movido a 22 (idem).
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA ;
/*
TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA
Una devolucion que ya salio de PENDIENTE no se edita mas: si alguien la
pasara de PROCESADA a RECHAZADA a pelo, el stock y el TOTAL ya estarian
bajados y encima se liberaria la cuota para devolver otra vez. Mientras
sigue PENDIENTE si se puede tocar la cantidad, pero volviendo a validar
que no se pase de lo comprado.
*/
CREATE TRIGGER TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA
BEFORE UPDATE ON DEVOLUCION_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_CANTIDAD_COMPRADA INT;
    DECLARE V_YA_DEVUELTA INT;

    IF OLD.ESTADO <> 'PENDIENTE' THEN
        IF NEW.ESTADO <> OLD.ESTADO
           OR NEW.CANTIDAD <> OLD.CANTIDAD
           OR NEW.SUBTOTAL_DEVUELTO <> OLD.SUBTOTAL_DEVUELTO
           OR NEW.ID_DETALLE_COMPRA <> OLD.ID_DETALLE_COMPRA THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCION YA FUE PROCESADA O RECHAZADA; SU FILA NO CAMBIA.';
        END IF;
    ELSEIF NEW.CANTIDAD <> OLD.CANTIDAD THEN
        -- La cuota: lo comprado menos lo demas devuelto o pendiente de este detalle
        SELECT DC.CANTIDAD INTO V_CANTIDAD_COMPRADA
          FROM DETALLE_COMPRA DC
         WHERE DC.ID_DETALLE_COMPRA = NEW.ID_DETALLE_COMPRA;

        SELECT IFNULL(SUM(CANTIDAD), 0) INTO V_YA_DEVUELTA
          FROM DEVOLUCION_COMPRA
         WHERE ID_DETALLE_COMPRA = NEW.ID_DETALLE_COMPRA
           AND ID_DEVOLUCION_COMPRA <> NEW.ID_DEVOLUCION_COMPRA
           AND ESTADO IN ('PENDIENTE', 'PROCESADA');

        IF NEW.CANTIDAD < 1 OR NEW.CANTIDAD > (V_CANTIDAD_COMPRADA - V_YA_DEVUELTA) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES DE ESTE PRODUCTO).';
        END IF;
    END IF;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA movido a 22 (idem).
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA ;
/*
TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA
La devolucion PROCESADA no se borra: en ese punto ya movio stock, bitacora,
historial y TOTAL; borrarla dejaria todo eso sin respaldo. Las PENDIENTE y
RECHAZADA si se pueden descartar.
*/
CREATE TRIGGER TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA
BEFORE DELETE ON DEVOLUCION_COMPRA
FOR EACH ROW
BEGIN
    IF OLD.ESTADO = 'PROCESADA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCION PROCESADA NO SE BORRA; EL STOCK Y EL TOTAL YA SE MOVIERON.';
    END IF;
END //
DELIMITER ;