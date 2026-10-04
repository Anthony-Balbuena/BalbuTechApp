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


DROP PROCEDURE IF EXISTS SP_INCREMENTAR_STOCK ;
/*
SP_INCREMENTAR_STOCK (ELIMINADO)
Movia stock sin dejar rastro: no escribia en MOVIMIENTOS_INVENTARIO, el
parametro P_PROVEEDOR no se usaba y el log al que apuntaba
(LOG_ENTRADAS_INVENTARIO) ni siquiera existe en la base.
Rutas vigentes para mover stock:
  - Compra con proveedor .. 19_SP_INICIAR_COMPRA + 22_SP_AGREGAR_DETALLE_COMPRA
  - Movimiento manual .... 20_SP_REGISTRAR_AJUSTE_INVENTARIO (archivo 20)
    (deja el movimiento en la bitacora y la fila en el historial)
*/


DROP PROCEDURE IF EXISTS SP_RECIBIR_MERCANCIA;
/*
SP_RECIBIR_MERCANCIA (ELIMINADO)
Mismo problema que SP_INCREMENTAR_STOCK: sumaba stock sin movimiento en
MOVIMIENTOS_INVENTARIO y sin dejar quien recibio la mercancia.
La entrada de mercancia se hace por compra (con proveedor y empleado) o,
si es manual, por 20_SP_REGISTRAR_AJUSTE_INVENTARIO.
*/

DROP PROCEDURE IF EXISTS SP_AJUSTE_INVENTARIO;
/*
SP_AJUSTE_INVENTARIO (ELIMINADO)
Era duplicado de 20_SP_REGISTRAR_AJUSTE_INVENTARIO (archivo 20) y encima
no validaba el producto, admitia cantidad 0 y no dejaba movimiento en
MOVIMIENTOS_INVENTARIO (contaba con los triggers genericos de historial,
que fueron eliminados en esta misma fase).
El ajuste manual ahora tiene una sola via:
20_SP_REGISTRAR_AJUSTE_INVENTARIO(producto, empleado, tipo, cantidad, obs).
*/




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


DROP TRIGGER IF EXISTS 17_TR_REGISTRAR_HISTORIAL_INVENTARIO ;
/*
17_TR_REGISTRAR_HISTORIAL_INVENTARIO (ELIMINADO)
Era el trigger generico que anotaba TODA actualizacion de stock en
HISTORIAL_MOVIMIENTOS_PRODUCTO; junto con TR_HISTORIAL_AJUSTE (archivo 32)
dejaba DOS filas genericas por cada movimiento, ademas de la del trigger
de negocio: 3 filas por movimiento y observaciones falsas (por ejemplo
'Ajuste manual de inventario' en una venta).
Desde esta fase cada movimiento escribe UNA sola fila en el historial,
la de quien lo hace:
  - Compra .............. TR_HISTORIAL_COMPRA (32)
  - Venta ............... TR_HISTORIAL_VENTA (32)
  - Devolucion .......... TR_HISTORIAL_DEVOLUCION (32)
  - Cancelacion ......... SP_CANCELAR_VENTA (21)
  - Ajuste o entrada .... 20_SP_REGISTRAR_AJUSTE_INVENTARIO (20)
Se mantiene 17_TR_VALIDAR_STOCK_MINIMO: no escribe historial, solo alerta.
*/



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