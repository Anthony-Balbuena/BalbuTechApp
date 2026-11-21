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
    CONSTRAINT FK_INVENTARIO_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO) ON DELETE CASCADE,
    -- Sirve para ordenar y buscar el inventario por su ultima fecha de cambio, asi los
    -- reportes salen rapidos sin recorrer toda la tabla.
    INDEX IX_INVENTARIO_FECHA (FECHA_ACTUALIZACION)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


--INSERTAR

/* SP_INSERTAR_INVENTARIO (ELIMINADO 15/11/2026)
Daba de alta la fila de INVENTARIO con STOCK_ACTUAL = 0. Nadie la llamaba:
el alta la hace 20_SP_REGISTRAR_AJUSTE_INVENTARIO, la puerta del ajuste, y la
app no inserta inventario directo. Item 12c de PENDIENTES.md. El DROP limpia
las bases que ya la tenian.
*/
DROP PROCEDURE IF EXISTS SP_INSERTAR_INVENTARIO;


DROP PROCEDURE IF EXISTS SP_INCREMENTAR_STOCK ;
/*
SP_INCREMENTAR_STOCK (ELIMINADO)
Movia stock sin dejar rastro: no escribia en MOVIMIENTOS_INVENTARIO, el
parametro P_PROVEEDOR no se usaba y el log al que apuntaba
(LOG_ENTRADAS_INVENTARIO) ni siquiera existe en la base.
Rutas vigentes para mover stock:
  - Compra con proveedor .. 19_SP_INICIAR_COMPRA + 22_SP_AGREGAR_DETALLE_COMPRA
  - Movimiento manual .... 20_SP_REGISTRAR_AJUSTE_INVENTARIO (este archivo)
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
Era duplicado de 20_SP_REGISTRAR_AJUSTE_INVENTARIO (este archivo) y encima
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
END //
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
  - Ajuste o entrada .... 20_SP_REGISTRAR_AJUSTE_INVENTARIO (este archivo)
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
    -- (15/11/2026) Un repuesto de garantia NO se vende: valorarlo a PRECIO de
    -- venta inflaba el reporte de inventario. Se valora a costo (P_COMPRA).
    (I.STOCK_ACTUAL * IF(P.ES_REPUESTO = 1, P.P_COMPRA, P.PRECIO)) AS VALOR_TOTAL_ITEM
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
-- (08/11/2026) Faltaba el DROP: reimportar el modulo fallaba con 1304.
DROP FUNCTION IF EXISTS FN_VALOR_TOTAL_INVENTARIO;
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


-- ================================================================
-- MOVIMIENTOS_INVENTARIO (ex modulo 20)
-- ================================================================

/*
SECCION MOVIMIENTOS_INVENTARIO (ex modulo 20)
Bitacora de todo lo que le pasa al stock: entradas, salidas, ajustes y
devoluciones, mas el ajuste manual y las consultas del kardex. Todo lo de
esta seccion vive en este archivo: la tabla MOVIMIENTOS_INVENTARIO, sus
tres indices y los cinco SP.
Los triggers que escriben en la tabla NO viven aca: se mudaron a la tabla
que los dispara (19, 21 y 26).
*/
/*
TABLA MOVIMIENTOS_INVENTARIO
Bitacora de todo lo que le pasa al stock: entradas, salidas, ajustes y
devoluciones. Cada fila dice que producto, quien lo movio, cuanto, cuando
y por que motivo. Sirve para rastrear cualquier cambio de inventario.
*/
CREATE TABLE MOVIMIENTOS_INVENTARIO (
    ID_MOVIMIENTO INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    TIPO_MOVIMIENTO ENUM(
        'ENTRADA',
        'SALIDA',
        'AJUSTE',
        'DEVOLUCION'
    ) NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_MOVIMIENTO),
    CONSTRAINT FK_MOVIMIENTO_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_MOVIMIENTO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Busca todos los movimientos de un producto en concreto, asi se rastrea
    -- rapido que le paso al stock sin leer toda la tabla.
    INDEX IX_MOVIMIENTO_PRODUCTO (ID_PRODUCTO),
    -- Busca movimientos por cantidad, util para revisar entradas o salidas grandes de
    -- mercancia.
    INDEX IX_CANTIDAD_MOVIINVENTORIO (CANTIDAD),
    -- Trae los movimientos por fecha: es el que usan los reportes de kardex y el cierre
    -- del dia, que recorren el dia completo de mas reciente a viejo.
    INDEX IX_MOVIMIENTO_FECHA (FECHA)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
DELIMITER //
DROP PROCEDURE IF EXISTS SP_MOVER_STOCK ;
/*
SP_MOVER_STOCK  (15/11/2026)
Mueve stock en UN solo lugar: valida producto, empleado y cantidad > 0; si el
producto no tiene fila en INVENTARIO la crea primero; para SALIDA y AJUSTE no
deja bajar el stock de 0; y escribe bitacora (MOVIMIENTOS_INVENTARIO) +
INVENTARIO + historial del producto, atados en una transaccion.

SIN GUARDA A PROPOSITO. Es el nivel de abajo: no decide QUIEN puede mover stock,
solo COMO se mueve. Las puertas con permiso son las que lo llaman:
  - 20_SP_REGISTRAR_AJUSTE_INVENTARIO (guarda INVENTARIO_AJUSTAR)
  - SP_REGISTRAR_AVANCE_REPARACION    (guarda GARANTIAS_AVANZAR)
Asi la regla de "no dejar stock negativo" vive en UNA copia: dos copias se
desincronizan. Esta en la lista EXCLUIR de db/injectar-guardas.py.
*/
CREATE PROCEDURE SP_MOVER_STOCK(
    IN P_ID_PRODUCTO INT,
    IN P_ID_EMPLEADO INT,
    IN P_TIPO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION'),
    IN P_CANTIDAD INT,
    IN P_OBSERVACION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE V_STOCK_ANTERIOR INT;
    DECLARE V_STOCK_NUEVO INT;
    -- BLINDAJE (09/10/2026, patron fase I): bitacora + stock + historial atados.
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
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

    -- 1. Validaciones
    IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF IFNULL(P_CANTIDAD, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 2. En inventario debe existir la fila (si no, se crea con stock 0)
    INSERT IGNORE INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
    VALUES (P_ID_PRODUCTO, 0, 5, 'ALMACEN_PRINCIPAL');

    SELECT STOCK_ACTUAL INTO V_STOCK_ANTERIOR
    FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 3. Para salidas y ajustes a la baja, no dejar el stock en negativo
    IF P_TIPO IN ('SALIDA', 'AJUSTE') AND V_STOCK_ANTERIOR < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE PARA EL MOVIMIENTO.';
        LEAVE proc_label;
    END IF;

    -- 4. Bitacora: el movimiento con quien lo hizo
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION);

    -- 5. Actualizar stock
    IF P_TIPO IN ('ENTRADA', 'DEVOLUCION') THEN
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL + P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    ELSE
        UPDATE INVENTARIO SET STOCK_ACTUAL = STOCK_ACTUAL - P_CANTIDAD WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    END IF;

    -- 6. Historial del producto: UNA fila, con el stock antes y despues
    SELECT STOCK_ACTUAL INTO V_STOCK_NUEVO
    FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    ) VALUES (
        P_ID_PRODUCTO, P_TIPO, P_CANTIDAD, V_STOCK_ANTERIOR, V_STOCK_NUEVO, P_OBSERVACION
    );

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: MOVIMIENTO ', P_TIPO, ' REGISTRADO Y STOCK ACTUALIZADO.') AS MENSAJE;
END //

DROP PROCEDURE IF EXISTS 20_SP_REGISTRAR_AJUSTE_INVENTARIO ;
/*
20_SP_REGISTRAR_AJUSTE_INVENTARIO  (15/11/2026)
Puerta con guarda del ajuste manual de stock desde la pantalla de Inventario.
El movimiento vive en SP_MOVER_STOCK; aca queda solo la guarda
(INVENTARIO_AJUSTAR, inyectada por db/injectar-guardas.py). Se separo para que
el avance de reparacion pueda consumir el repuesto sin que el tecnico herede
INVENTARIO_AJUSTAR, y para que la regla de stock no exista dos veces.
*/
CREATE PROCEDURE 20_SP_REGISTRAR_AJUSTE_INVENTARIO(
    IN P_ID_PRODUCTO INT,
    IN P_ID_EMPLEADO INT,
    IN P_TIPO ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION'),
    IN P_CANTIDAD INT,
    IN P_OBSERVACION VARCHAR(200)
)
proc_label: BEGIN
    CALL SP_MOVER_STOCK(P_ID_PRODUCTO, P_ID_EMPLEADO, P_TIPO, P_CANTIDAD, P_OBSERVACION);
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
--COMPRA
-- Trigger TR_AUDITORIA_MOVIMIENTO_COMPRA movido a 19 (su tabla).
-- Trigger TR_AUDITORIA_BORRADO_COMPRA movido a 19 (su tabla).

--VENTAS
DELIMITER ;
-- Trigger TR_AUDITORIA_MOVIMIENTO_VENTA movido a 21 (su tabla).


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
-- SIN USO: SP_KARDEX_PRODUCTO (08/11/2026)
-- Reemplazada por SP_KARDEX_PAGINADO con un ID de producto.
-- Se conserva sin uso desde 08/11/2026.
DROP PROCEDURE IF EXISTS SP_KARDEX_PRODUCTO ;
/*
SP_KARDEX_PRODUCTO (14/10/2026)
Kardex de un producto: sus movimientos de stock del mas nuevo al mas viejo,
con quien lo hizo y el motivo. Solo lectura.
*/
CREATE PROCEDURE SP_KARDEX_PRODUCTO(IN P_ID_PRODUCTO INT)
BEGIN
    SELECT M.ID_MOVIMIENTO, P.NOMBRE AS PRODUCTO, M.FECHA, M.TIPO_MOVIMIENTO,
           M.CANTIDAD, E.NOMBRE AS EMPLEADO, M.OBSERVACION
      FROM MOVIMIENTOS_INVENTARIO M
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = M.ID_PRODUCTO
      JOIN EMPLEADOS E ON E.ID_EMPLEADO = M.ID_EMPLEADO
     WHERE M.ID_PRODUCTO = P_ID_PRODUCTO
     ORDER BY M.ID_MOVIMIENTO DESC LIMIT 50;
END //
DELIMITER ;

DELIMITER //
-- SIN USO: SP_KARDEX_TODOS (08/11/2026)
-- Reemplazada por SP_KARDEX_PAGINADO (P_ID_PRODUCTO = 0 = todos).
-- Se conserva sin uso desde 08/11/2026.
DROP PROCEDURE IF EXISTS SP_KARDEX_TODOS ;
/*
SP_KARDEX_TODOS (14/10/2026)
Ultimos 50 movimientos de stock de todos los productos. Solo lectura.

(08/11/2026) La app ya no la usa: con 47 movimientos en la viva el tope de 50
dejaba el historial inalcanzable. La reemplaza SP_KARDEX_PAGINADO.
*/
CREATE PROCEDURE SP_KARDEX_TODOS()
BEGIN
    SELECT M.ID_MOVIMIENTO, P.NOMBRE AS PRODUCTO, M.FECHA, M.TIPO_MOVIMIENTO,
           M.CANTIDAD, E.NOMBRE AS EMPLEADO, M.OBSERVACION
      FROM MOVIMIENTOS_INVENTARIO M
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = M.ID_PRODUCTO
      JOIN EMPLEADOS E ON E.ID_EMPLEADO = M.ID_EMPLEADO
     ORDER BY M.ID_MOVIMIENTO DESC LIMIT 50;
END //
DELIMITER ;

-- ================================================================
-- 4.b KARDEX PAGINADO (08/11/2026)
-- ================================================================
-- Un solo par para las dos vistas del kardex: con P_ID_PRODUCTO = 0 (o NULL)
-- lista todos los movimientos; con un ID, solo los de ese producto. Asi la
-- pantalla no necesita dos SPs ni dos formas de paginar.
-- OJO: MOVIMIENTOS_INVENTARIO no tiene SELECT para balbu_app (recorte del
-- 03/11), asi que la lectura tiene que pasar por aca.
DELIMITER //
/*
SP_KARDEX_PAGINADO
Una pagina del kardex, del movimiento mas nuevo al mas viejo.
Permiso: INVENTARIO_VER (el mismo que SP_KARDEX_TODOS / SP_KARDEX_PRODUCTO).
*/
DROP PROCEDURE IF EXISTS SP_KARDEX_PAGINADO ;
CREATE PROCEDURE SP_KARDEX_PAGINADO(
    IN P_ID_PRODUCTO INT,
    IN P_PAGINA      INT,
    IN P_POR_PAGINA  INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    IF P_ID_PRODUCTO IS NULL THEN
        SET P_ID_PRODUCTO = 0;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT M.ID_MOVIMIENTO, P.NOMBRE AS PRODUCTO, M.FECHA, M.TIPO_MOVIMIENTO,
           M.CANTIDAD, E.NOMBRE AS EMPLEADO, M.OBSERVACION
      FROM MOVIMIENTOS_INVENTARIO M
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = M.ID_PRODUCTO
      JOIN EMPLEADOS E ON E.ID_EMPLEADO = M.ID_EMPLEADO
     WHERE (P_ID_PRODUCTO = 0 OR M.ID_PRODUCTO = P_ID_PRODUCTO)
     ORDER BY M.ID_MOVIMIENTO DESC
     LIMIT P_POR_PAGINA OFFSET v_offset;
END //
DELIMITER ;

DELIMITER //
/*
SP_CONTAR_MOVIMIENTOS
Cuantos movimientos hay (todos, o los de un producto), para el "Pagina 1 de N".
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_MOVIMIENTOS ;
CREATE PROCEDURE SP_CONTAR_MOVIMIENTOS(
    IN P_ID_PRODUCTO INT
)
BEGIN
    IF P_ID_PRODUCTO IS NULL THEN
        SET P_ID_PRODUCTO = 0;
    END IF;

    SELECT COUNT(*) AS TOTAL
      FROM MOVIMIENTOS_INVENTARIO M
     WHERE (P_ID_PRODUCTO = 0 OR M.ID_PRODUCTO = P_ID_PRODUCTO);
END //
DELIMITER ;
