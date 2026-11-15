/*
TABLA HISTORIAL_MOVIMIENTOS_PRODUCTO
Guarda cada movimiento de stock con el tipo, la cantidad y el stock antes
y despues del cambio. Sirve para reconstruir en que momento cambio el
stock de cualquier producto.
*/
CREATE TABLE HISTORIAL_MOVIMIENTOS_PRODUCTO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'VENTA', 'DEVOLUCION') NOT NULL,
    CANTIDAD INT NOT NULL,
    STOCK_ANTERIOR INT NOT NULL,
    STOCK_NUEVO INT NOT NULL,
    FECHA_MOVIMIENTO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_HISTORIAL_PROD FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO) ON DELETE CASCADE
) ENGINE = InnoDB; 

/*
INDICE IX_HIST_MOVIMIENTO_FECHA
Trae el historial de movimientos por fecha: hasta ahora solo estaba la PK
y el FK del producto, y todo lo que pide "que paso en tal dia" tenia que
recorrer la tabla entera.
*/
CREATE INDEX IX_HIST_MOVIMIENTO_FECHA ON HISTORIAL_MOVIMIENTOS_PRODUCTO (FECHA_MOVIMIENTO);


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
---VENTA
DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_VENTA ;

/*
TR_HISTORIAL_VENTA
Cuando se vende un producto, anota en el historial el stock antes y
despues de la venta con tipo VENTA. Solo registra: el que descuenta el
stock es TR_AUDITORIA_MOVIMIENTO_VENTA (21), que corre antes.
*/
CREATE TRIGGER TR_HISTORIAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
-- (09/10/2026) Orden fijo: despues del total (lee el stock ya descontado y sumado).
FOLLOWS TR_ACTUALIZAR_TOTAL_VENTA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Leemos el stock ya descontado (el trigger de la venta, archivo 21,
    -- se crea primero y por eso corre antes)
    SELECT STOCK_ACTUAL INTO v_stock_nuevo FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. El stock anterior era el actual mas lo vendido
    SET v_stock_anterior = v_stock_nuevo + NEW.CANTIDAD;

    -- 3. Insertamos en el historial de movimientos
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'VENTA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Venta registrada automáticamente'
    );
END //

DELIMITER ;

-----COMPRA

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_COMPRA ;

/*
TR_HISTORIAL_COMPRA
Al comprar, anota en el historial la ENTRADA con el stock antes y
despues. Solo registra: el que suma el stock es
TR_ACTUALIZAR_STOCK_COMPRA (19), que corre antes.
(20/10/2026) El orden de los triggers de alta ya no depende del orden de
creacion: esta declarado con FOLLOWS (total -> stock -> auditoria -> costo
-> historial), asi que este trigger corre al final de la cadena de la compra.
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_HISTORIAL_COMPRA
-- AFTER INSERT ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     DECLARE v_stock_anterior INT;
--     DECLARE v_stock_nuevo INT;
--
--     -- 1. Leemos el stock ya actualizado (el trigger de la compra, archivo 19,
--     -- se crea primero y por eso corre antes)
--     SELECT STOCK_ACTUAL INTO v_stock_nuevo FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
--
--     -- 2. El stock anterior era el actual menos lo comprado
--     SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;
--
--     -- 3. Registramos el movimiento en el historial
--     INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
--         ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
--     ) VALUES (
--         NEW.ID_PRODUCTO, 'ENTRADA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Compra registrada automáticamente'
--     );
-- END//
CREATE TRIGGER TR_HISTORIAL_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_ACTUALIZAR_COSTO_COMPRA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;

    -- 1. Leemos el stock ya actualizado (el trigger de stock, 22, ya corrio
    -- porque el orden de la cadena esta declarado con FOLLOWS)
    SELECT STOCK_ACTUAL INTO v_stock_nuevo FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    -- 2. El stock anterior era el actual menos lo comprado
    SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;

    -- 3. Registramos el movimiento en el historial
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        NEW.ID_PRODUCTO, 'ENTRADA', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Compra registrada automáticamente'
    );
END//

DELIMITER ;
/*
TR_HISTORIAL_BORRADO_COMPRA - NO SE CREA AQUI
El historial de cuando se quita una linea de una compra lo escribe
TR_ACTUALIZAR_STOCK_BORRADO_COMPRA (19) dentro del mismo trigger que baja
el stock: asi el antes/despues sale siempre bien.
(20/10/2026) Ademas el orden de los triggers de baja ya esta declarado con
FOLLOWS (total -> stock -> auditoria -> costo).
Aqui solo queda la nota.
*/
----DEVOLUCIONES (version vieja, comentada)

DELIMITER //

-- Limpieza por si existiera en alguna base vieja
DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION //

/*
TR_HISTORIAL_DEVOLUCION sobre DETALLES_DEVOLUCION
COMENTADO: la tabla DETALLES_DEVOLUCION no existe en la base (las
devoluciones se guardan completas en DEVOLUCIONES). El trigger de mas
abajo, sobre DEVOLUCIONES, es el que ahora lleva el historial.
*/
-- CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
-- AFTER INSERT ON DETALLES_DEVOLUCION
-- FOR EACH ROW
-- BEGIN
--     DECLARE v_stock_anterior INT;
--     DECLARE v_stock_nuevo INT;
--
--     SELECT STOCK_ACTUAL INTO v_stock_anterior FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
--     SET v_stock_nuevo = v_stock_anterior + NEW.CANTIDAD;
--
--     INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
--         ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
--     ) VALUES (
--         NEW.ID_PRODUCTO, 'AJUSTE', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo, 'Devolución de producto'
--     );
-- END //

DELIMITER ;

----DEVOLUCIONES

DELIMITER //

DROP TRIGGER IF EXISTS TR_HISTORIAL_DEVOLUCION;

/*
TR_HISTORIAL_DEVOLUCION (sobre DEVOLUCIONES)
Cuando una devolucion pasa de PENDIENTE a APROBADA o REEMBOLSADA, anota
en el historial el stock antes y despues con tipo DEVOLUCION. Solo registra:
el que devuelve el stock es TR_REINTEGRAR_STOCK_DEVOLUCION (25), que se
crea primero y por eso corre antes (los triggers van en orden de creacion).
*/
CREATE TRIGGER TR_HISTORIAL_DEVOLUCION
AFTER UPDATE ON DEVOLUCIONES
FOR EACH ROW
-- (09/10/2026) Orden fijo: despues de marcar la venta (usa el stock ya reintegrado).
FOLLOWS TR_MARCAR_VENTA_DEVUELTA
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE v_stock_nuevo INT;
    DECLARE v_id_producto INT;

    -- Solo cuando la devolucion es aprobada o reembolsada desde PENDIENTE
    IF NEW.ESTADO IN ('APROBADA', 'REEMBOLSADA') AND OLD.ESTADO = 'PENDIENTE' THEN

        -- 1. Producto de la venta relacionada
        SELECT ID_PRODUCTO INTO v_id_producto
        FROM DETALLES_VENTA
        WHERE ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA;

        -- 2. Stock actual: el reintegro (25) ya corrio y sumo la cantidad
        SELECT STOCK_ACTUAL INTO v_stock_nuevo
        FROM INVENTARIO
        WHERE ID_PRODUCTO = v_id_producto;

        SET v_stock_anterior = v_stock_nuevo - NEW.CANTIDAD;

        -- 3. Registramos en el historial
        INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
            ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
        ) VALUES (
            v_id_producto, 'DEVOLUCION', NEW.CANTIDAD, v_stock_anterior, v_stock_nuevo,
            CONCAT('Devolución aprobada: ', IFNULL(NEW.MOTIVO, ''))
        );
    END IF;
END//

DELIMITER ;

DROP TRIGGER IF EXISTS TR_HISTORIAL_AJUSTE ;
/*
TR_HISTORIAL_AJUSTE (ELIMINADO)
Era el segundo trigger generico sobre UPDATE de INVENTARIO: anotaba TODA
subida o bajada de stock como si fuera un 'Ajuste manual de inventario',
lo cual era falso para compras, ventas y devoluciones, y sumaba una fila
a la que ya escribia el trigger de negocio (o la de
17_TR_REGISTRAR_HISTORIAL_INVENTARIO, tambien eliminado): cada movimiento
dejaba 3 filas en el historial.
Desde esta fase el historial lo escribe UNA sola vez quien hace el
movimiento (lista completa en 17- INVENTARIO.sql).
*/


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------




-- ================================================================
-- PRODUCTO_PROVEEDOR (ex modulo 40)
-- ================================================================

/*
SECCION PRODUCTO_PROVEEDOR (ex modulo 40)
Mapa de quien vende que: la tabla guarda la ULTIMA compra por pareja
producto-proveedor (precio + fecha); el historial completo vive en las lineas de
compra (DETALLE_COMPRA + COMPRAS). Todo lo de esta seccion vive en este archivo:
la tabla, su trigger y los cuatro SP. El trigger es AFTER UPDATE ON COMPRAS y
declara FOLLOWS TR_RECALCULAR_COSTO_COMPRA_CANCELADA, del modulo 19.
*/
/*
ARCHIVO 40 - PRODUCTO_PROVEEDOR (mapa quién vende qué)
Un producto puede comprarse a N suplidores y un suplidor trae N productos.
La tabla guarda la ULTIMA compra por pareja (precio + fecha); el historial
completo vive en las lineas de compra (DETALLE_COMPRA + COMPRAS).
Lo actual no se toca: PRODUCTOS.ID_PROVEEDOR queda como preferido.
*/
CREATE TABLE PRODUCTO_PROVEEDOR (
    ID_PRODUCTO INT NOT NULL,
    ID_PROVEEDOR INT NOT NULL,
    ULTIMO_PRECIO DECIMAL(10, 2) NOT NULL CHECK (ULTIMO_PRECIO >= 0),
    ULTIMA_FECHA DATETIME NOT NULL,
    PRIMARY KEY (ID_PRODUCTO, ID_PROVEEDOR),
    CONSTRAINT FK_MAPA_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_MAPA_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR)
) ENGINE = InnoDB;

DELIMITER //
DROP TRIGGER IF EXISTS TR_MAPA_COMPRA_RECIBIDA ;
/*
TR_MAPA_COMPRA_RECIBIDA (14/10/2026)
Cuando una compra pasa a RECIBIDA, cada linea enseña al mapa (o actualiza
su precio/fecha). Solo las compras reales enseñan: ABIERTA/CANCELADA no.
(20/10/2026) El orden de los triggers de actualizacion de COMPRAS ahora
esta declarado con FOLLOWS: corre despues de
TR_RECALCULAR_COSTO_COMPRA_CANCELADA (19).
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_MAPA_COMPRA_RECIBIDA
-- AFTER UPDATE ON COMPRAS
-- FOR EACH ROW
-- BEGIN
--     IF NEW.ESTADO = 'RECIBIDA' AND OLD.ESTADO <> 'RECIBIDA' THEN
--         INSERT INTO PRODUCTO_PROVEEDOR (ID_PRODUCTO, ID_PROVEEDOR, ULTIMO_PRECIO, ULTIMA_FECHA)
--         SELECT DC.ID_PRODUCTO, NEW.ID_PROVEEDOR, DC.PRECIO_UNITARIO, NEW.FECHA
--           FROM DETALLE_COMPRA DC WHERE DC.ID_COMPRA = NEW.ID_COMPRA
--         ON DUPLICATE KEY UPDATE
--             ULTIMO_PRECIO = VALUES(ULTIMO_PRECIO),
--             ULTIMA_FECHA = VALUES(ULTIMA_FECHA);
--     END IF;
-- END //
CREATE TRIGGER TR_MAPA_COMPRA_RECIBIDA
AFTER UPDATE ON COMPRAS
FOR EACH ROW
FOLLOWS TR_RECALCULAR_COSTO_COMPRA_CANCELADA
BEGIN
    IF NEW.ESTADO = 'RECIBIDA' AND OLD.ESTADO <> 'RECIBIDA' THEN
        INSERT INTO PRODUCTO_PROVEEDOR (ID_PRODUCTO, ID_PROVEEDOR, ULTIMO_PRECIO, ULTIMA_FECHA)
        SELECT DC.ID_PRODUCTO, NEW.ID_PROVEEDOR, DC.PRECIO_UNITARIO, NEW.FECHA
          FROM DETALLE_COMPRA DC WHERE DC.ID_COMPRA = NEW.ID_COMPRA
        ON DUPLICATE KEY UPDATE
            ULTIMO_PRECIO = VALUES(ULTIMO_PRECIO),
            ULTIMA_FECHA = VALUES(ULTIMA_FECHA);
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PRODUCTO_SUPLIDORES ;
/*
SP_PRODUCTO_SUPLIDORES (14/10/2026)
Quienes venden un producto con su ultimo precio y fecha, del mas barato
al mas caro. Para elegir en el carrito.
*/
CREATE PROCEDURE SP_PRODUCTO_SUPLIDORES(IN P_ID_PRODUCTO INT)
BEGIN
    SELECT M.ID_PROVEEDOR, P.NOMBRE AS PROVEEDOR, M.ULTIMO_PRECIO, M.ULTIMA_FECHA
      FROM PRODUCTO_PROVEEDOR M
      JOIN PROVEEDORES P ON P.ID_PROVEEDOR = M.ID_PROVEEDOR
     WHERE M.ID_PRODUCTO = P_ID_PRODUCTO
     ORDER BY M.ULTIMO_PRECIO ASC;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PRODUCTO_HISTORIAL_PRECIOS ;
/*
SP_PRODUCTO_HISTORIAL_PRECIOS (14/10/2026)
Historial de precios pagados por un producto: suplidor | precio | fecha,
de lo mas nuevo a lo mas viejo. Solo compras RECIBIDA.
*/
CREATE PROCEDURE SP_PRODUCTO_HISTORIAL_PRECIOS(IN P_ID_PRODUCTO INT)
BEGIN
    SELECT PR.NOMBRE AS PROVEEDOR, DC.PRECIO_UNITARIO AS PRECIO, C.FECHA,
           DC.CANTIDAD, C.ID_COMPRA
      FROM DETALLE_COMPRA DC
      JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
      JOIN PROVEEDORES PR ON PR.ID_PROVEEDOR = C.ID_PROVEEDOR
     WHERE DC.ID_PRODUCTO = P_ID_PRODUCTO AND C.ESTADO = 'RECIBIDA'
     ORDER BY C.FECHA DESC, C.ID_COMPRA DESC LIMIT 20;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTE_PRECIOS_COMPRA ;
/*
SP_REPORTE_PRECIOS_COMPRA (14/10/2026, 15/10/2026: + mas caro)
Por producto: cuantos suplidores, el mas barato y el mas caro con su
precio y suplidor, y la fecha de la ultima compra. Para ver subidas
de un vistazo.
*/
CREATE PROCEDURE SP_REPORTE_PRECIOS_COMPRA()
BEGIN
    SELECT P.NOMBRE AS PRODUCTO,
           COUNT(*) AS SUPLIDORES,
           MIN(M.ULTIMO_PRECIO) AS MAS_BARATO,
           (SELECT PR2.NOMBRE
              FROM PRODUCTO_PROVEEDOR M2
              JOIN PROVEEDORES PR2 ON PR2.ID_PROVEEDOR = M2.ID_PROVEEDOR
             WHERE M2.ID_PRODUCTO = P.ID_PRODUCTO
             ORDER BY M2.ULTIMO_PRECIO ASC, M2.ULTIMA_FECHA DESC LIMIT 1) AS DONDE_BARATO,
           MAX(M.ULTIMO_PRECIO) AS MAS_CARO,
           (SELECT PR3.NOMBRE
              FROM PRODUCTO_PROVEEDOR M3
              JOIN PROVEEDORES PR3 ON PR3.ID_PROVEEDOR = M3.ID_PROVEEDOR
             WHERE M3.ID_PRODUCTO = P.ID_PRODUCTO
             ORDER BY M3.ULTIMO_PRECIO DESC, M3.ULTIMA_FECHA DESC LIMIT 1) AS DONDE_CARO,
           MAX(M.ULTIMA_FECHA) AS ULTIMA_COMPRA
      FROM PRODUCTO_PROVEEDOR M
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = M.ID_PRODUCTO
      JOIN PROVEEDORES PR ON PR.ID_PROVEEDOR = M.ID_PROVEEDOR
     GROUP BY P.ID_PRODUCTO, P.NOMBRE
     ORDER BY P.NOMBRE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PROVEEDOR_ACTIVO ;
/*
SP_PROVEEDOR_ACTIVO (14/10/2026)
Nombre de un suplidor si existe y esta ACTIVO; vacio si no. Para validar
la eleccion por linea en el carrito de compras.
*/
CREATE PROCEDURE SP_PROVEEDOR_ACTIVO(IN P_ID_PROVEEDOR INT)
BEGIN
    SELECT NOMBRE FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR AND ESTADO = 'ACTIVO';
END //
DELIMITER ;
