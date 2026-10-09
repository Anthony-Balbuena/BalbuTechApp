/*
TABLA DETALLES_VENTA
Guarda que productos forman parte de cada venta, con su cantidad y precio.
El subtotal se calcula solo al multiplicar cantidad por precio.
No se puede repetir el mismo producto dentro de la misma venta.
*/
CREATE TABLE DETALLES_VENTA (
    ID_DETALLE_VENTA INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_PRODUCTO INT NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    PRECIO_UNITARIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO_UNITARIO > 0),
    SUBTOTAL DECIMAL(10, 2) GENERATED ALWAYS AS (CANTIDAD * PRECIO_UNITARIO) STORED,
    PRIMARY KEY (ID_DETALLE_VENTA),
    CONSTRAINT UQ_VENTA_PRODUCTO UNIQUE (ID_VENTA, ID_PRODUCTO),
    CONSTRAINT FK_DETALLE_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_DETALLE_VENTA_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO)
) ENGINE = InnoDB;

/*
INDICE IX_CLIENTE_NOMBRE
Busca clientes por su nombre, util para localizarlos rapido en el sistema.
*/
CREATE INDEX IX_CLIENTE_NOMBRE ON CLIENTES (NOMBRE);

/*
INDICE IX_VENTAS_FECHA
Ordena las ventas por fecha, util para reportes por dia, mes o cierre de caja.
*/
CREATE INDEX IX_VENTAS_FECHA ON VENTAS (FECHA);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //

DROP PROCEDURE IF EXISTS SP_AGREGAR_DETALLE_VENTA ;
/*
SP_AGREGAR_DETALLE_VENTA
Agrega un producto a una venta validando todo antes de guardar.
Revisa que la venta exista, que el empleado sea el dueño de la venta y que
haya stock suficiente; luego toma el precio actual y agrega la linea.

NOTA (fase A2): este chequeo de stock es la PRIMERA RED, no la garantia.
Lee sin candado, asi que en una carrera entre dos cajeros puede ver un
numero viejo. La garantia de verdad vive en el archivo 20: el descuento
condicional de TR_AUDITORIA_MOVIMIENTO_VENTA comprueba y resta en la
misma sentencia y corta con 'ERROR: STOCK INSUFICIENTE.' si no alcanza.
NOTA P10 (06/10/2026): el ERROR 1020 si es alcanzable en produccion.
Un INSERT cuyo trigger lee el stock y luego lo descuenta comparte
transaccion; si otro cajero commitea un cambio en INVENTARIO en medio,
InnoDB aborta con 'Record has changed since last read' en vez del
mensaje amigable. Por eso este SP trae un EXIT HANDLER FOR 1020 que
lo traduce a 'ERROR: STOCK INSUFICIENTE, INTENTE DE NUEVO.' (la
sentencia siempre revirtio, cero residuos; solo cambiaba el mensaje).
*/
CREATE PROCEDURE SP_AGREGAR_DETALLE_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD INT,
    IN P_ID_EMPLEADO INT -- Nuevo parámetro 
)
proc_label: BEGIN
    DECLARE V_PRECIO DECIMAL(10, 2);
    DECLARE V_STOCK_DISPONIBLE INT;
    DECLARE V_ID_VENTA_EMPLEADO INT;

    -- P10 (06/10/2026): traduce el ERROR 1020 de una carrera en el
    -- descuento de stock (trigger del archivo 20) a mensaje amigable.
    DECLARE EXIT HANDLER FOR 1020
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE, INTENTE DE NUEVO.';

    -- 1. Validar que la venta exista y verificar empleado
    SELECT ID_EMPLEADO INTO V_ID_VENTA_EMPLEADO FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;
    
    IF V_ID_VENTA_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- Opcional: Validar que el empleado sea el mismo que inició la venta
    IF V_ID_VENTA_EMPLEADO <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar stock (si el producto no esta en INVENTARIO, cuenta como 0)
    SELECT STOCK_ACTUAL INTO V_STOCK_DISPONIBLE FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    IF IFNULL(V_STOCK_DISPONIBLE, 0) < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Obtener precio
    SELECT PRECIO INTO V_PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. Insertar
    INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
    VALUES (P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO);

    SELECT 'EXITO: PRODUCTO AGREGADO CORRECTAMENTE.' AS MENSAJE;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


-- Trigger TR_AUDITORIA_MOVIMIENTO_VENTA movido a 23 (su tabla).
DELIMITER //

DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_VENTA ;

/*
TR_AUDITORIA_MOVIMIENTO_VENTA
Cuando se inserta una linea de venta descuenta el stock con UNA SOLA
sentencia: comprueba y resta a la vez (un solo golpe). Si no alcanza el
stock corta con error y la linea se revierte sola, asi nunca queda una
venta sin su salida de inventario. La bitacora SALIDA va igual que antes.
*/

-- ============================================================
-- VERSION ANTERIOR (guardada para revision, NO se ejecuta)
-- Restaba el stock sin comprobar: en una carrera entre dos cajeros
-- podia dejar el inventario negativo; lo frenaba recien el CHECK
-- de INVENTARIO, con un error tecnico y no un mensaje claro.
-- ============================================================
-- CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_VENTA
-- AFTER INSERT ON DETALLES_VENTA -- <--- AQUÍ ESTABA EL ERROR
-- FOR EACH ROW
-- BEGIN
--     DECLARE V_ID_EMPLEADO INT;
--
--     -- Obtenemos el empleado de la cabecera de la venta
--     SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
--     FROM VENTAS 
--     WHERE ID_VENTA = NEW.ID_VENTA;
--
--     -- Restamos del Inventario
--     UPDATE INVENTARIO 
--     SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
--     WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
--
--     -- Registramos el movimiento
--     INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
--     VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD, CONCAT('Venta realizada ID: ', NEW.ID_VENTA));
-- END ;

-- ============================================================
-- VERSION NUEVA (la que se crea) - "un solo golpe"
-- ============================================================
CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;

    -- Obtenemos el empleado de la cabecera de la venta
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- UN SOLO GOLPE: la comprobacion y la resta en la misma sentencia.
    -- Si no alcanza el stock, no descuenta nada y corta con error.
    UPDATE INVENTARIO 
       SET STOCK_ACTUAL = STOCK_ACTUAL - NEW.CANTIDAD
     WHERE ID_PRODUCTO = NEW.ID_PRODUCTO
       AND STOCK_ACTUAL >= NEW.CANTIDAD;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
    END IF;

    -- Registramos el movimiento (igual que antes)
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', NEW.CANTIDAD, CONCAT('Venta realizada ID: ', NEW.ID_VENTA));
END //

DELIMITER ;
DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_TOTAL_VENTA ;
/*
TR_ACTUALIZAR_TOTAL_VENTA
Le va sumando el subtotal de cada producto al TOTAL de la venta.
Asi el total queda actualizado sin calcularlo a mano.
*/
CREATE TRIGGER TR_ACTUALIZAR_TOTAL_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
-- (09/10/2026) Orden fijo: despues de la auditoria (antes dependia del orden de creacion).
FOLLOWS TR_AUDITORIA_MOVIMIENTO_VENTA
BEGIN
    -- P11 (07/10/2026): si el UPDATE falla, apagar la bandera antes
    -- de propagar el error (las variables de usuario no se revierten
    -- con ROLLBACK).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @VENTAS_INTERNO = 0;
        RESIGNAL;
    END;

    -- @VENTAS_INTERNO le avisa al candado de cabecera que este cambio de
    -- TOTAL viene del detalle y no de un UPDATE a pelo
    SET @VENTAS_INTERNO = 1;
    UPDATE VENTAS 
    SET TOTAL = TOTAL + NEW.SUBTOTAL
    WHERE ID_VENTA = NEW.ID_VENTA;
    SET @VENTAS_INTERNO = 0;
END //
DELIMITER ;




DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_VENTA_FINALIZADA ;
/*
TR_BLOQUEAR_VENTA_FINALIZADA
No deja agregar productos a una venta que ya no este abierta: ni
realizada, ni cancelada ni devuelta. Si alguien lo intenta, corta la
operacion con un mensaje de error.
P11 (07/10/2026): EXIT HANDLER apaga la bandera si el UPDATE falla.
*/
CREATE TRIGGER TR_BLOQUEAR_VENTA_FINALIZADA
BEFORE INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);
    SELECT ESTADO INTO V_ESTADO FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    
    IF V_ESTADO IN ('REALIZADA', 'CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN AGREGAR PRODUCTOS A UNA VENTA QUE YA NO ESTA ABIERTA.';
    END IF;
END //
DELIMITER ;



DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_STOCK_DETALLE_VENTA ;
/*
TR_VALIDAR_STOCK_DETALLE_VENTA
No deja vender mas unidades de las que hay en el inventario, aunque el
INSERT venga a pelo y no pase por ningun SP. Si el producto ni siquiera
tiene fila en INVENTARIO, tampoco lo deja pasar.

NOTA (fase A2): tambien es red, no garantia: valida contra lo que ve en su
momento y sin candado. Si su lectura queda vieja por una carrera, manda el
mensaje amigable; si otro cambio el stock en el medio, el que corta es el
descuento condicional del archivo 20 (o el ERROR 1020 del servidor). Sea
cual sea el caso, la sentencia se revierte entera: nunca queda una linea
de venta sin su descuento.
*/
CREATE TRIGGER TR_VALIDAR_STOCK_DETALLE_VENTA
BEFORE INSERT ON DETALLES_VENTA
FOR EACH ROW
-- Orden fijo: despues del bloqueo de venta finalizada (el candado barato va primero).
FOLLOWS TR_BLOQUEAR_VENTA_FINALIZADA
BEGIN
    DECLARE V_STOCK INT;
    SELECT STOCK_ACTUAL INTO V_STOCK FROM INVENTARIO WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;

    IF V_STOCK IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO TIENE REGISTRO EN INVENTARIO.';
    END IF;

    IF V_STOCK < NEW.CANTIDAD THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_UPDATE_DETALLE_VENTA ;
/*
TR_BLOQUEAR_UPDATE_DETALLE_VENTA
Lo mismo que en las compras: la linea de una venta no se edita a pelo, ni
siquiera estando abierta. Asi el TOTAL siempre cuadra con lo que se cobro
y la cantidad que salio del inventario es la que dice el renglon. Si se
equivoco el cajero, se cancela la venta y se vuelve a hacer.
*/
CREATE TRIGGER TR_BLOQUEAR_UPDATE_DETALLE_VENTA
BEFORE UPDATE ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA LINEA DE UNA VENTA NO SE PUEDE EDITAR.';
END //
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_DETALLE_VENTA ;
/*
TR_BLOQUEAR_BORRADO_DETALLE_VENTA
Tampoco se borran renglones de una venta, ni estando EN_PROCESO: a diferencia
de las compras aqui no hay un SP que quite lineas, y borrarla a pelo dejaria
el TOTAL y el stock destruidos (nadie los devolveria). Si algo salio mal se
cancela la venta completa con SP_CANCELAR_VENTA.
*/
CREATE TRIGGER TR_BLOQUEAR_BORRADO_DETALLE_VENTA
BEFORE DELETE ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA LINEA DE UNA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA.';
END //
DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------------------------------

-- Vista VISTA_DETALLE_VENTA movida (21- VENTAS.sql).
CREATE OR REPLACE VIEW VISTA_DETALLE_VENTA AS
SELECT 
    DV.ID_VENTA,
    V.FACTURA,
    P.NOMBRE AS PRODUCTO,
    DV.CANTIDAD,
    DV.PRECIO_UNITARIO,
    DV.SUBTOTAL
FROM DETALLES_VENTA DV
JOIN VENTAS V ON V.ID_VENTA = DV.ID_VENTA
JOIN PRODUCTOS P ON DV.ID_PRODUCTO = P.ID_PRODUCTO;