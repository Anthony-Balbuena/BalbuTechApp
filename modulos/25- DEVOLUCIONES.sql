/*
TABLA DEVOLUCIONES
Guarda cada producto que un cliente devuelve: porque lo devuelve, en que
condicion llega cuanto se le reembolsa y en que estado esta la solicitud.
Puede ligarse a una garantia si el reclamo viene por ella.
*/
CREATE TABLE DEVOLUCIONES (
    ID_DEVOLUCION INT NOT NULL AUTO_INCREMENT,
    ID_DETALLE_VENTA INT NOT NULL,
    ID_GARANTIA INT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL DEFAULT (CURRENT_DATE),
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    MOTIVO VARCHAR(200),
    -- Definimos el ENUM y le asignamos un valor por defecto explícito
    CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO') NOT NULL DEFAULT 'BUENO',
    -- Valor por defecto en 0 para evitar errores de inserción inicial
    SUBTOTAL_REEMBOLSADO DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    ESTADO ENUM('PENDIENTE', 'APROBADA', 'RECHAZADA', 'REEMBOLSADA') NOT NULL DEFAULT 'PENDIENTE',
    
    PRIMARY KEY (ID_DEVOLUCION),
    CONSTRAINT FK_DEVOLUCION_VENTA FOREIGN KEY (ID_DETALLE_VENTA) REFERENCES DETALLES_VENTA (ID_DETALLE_VENTA) ON DELETE CASCADE,
    CONSTRAINT FK_DEVOLUCION_GARANTIA FOREIGN KEY (ID_GARANTIA) REFERENCES GARANTIAS (ID_GARANTIA),
    CONSTRAINT FK_DEVOLUCION_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
-- 1. Para rastrear devoluciones de una venta específica
/*
INDICE IX_DEVOLUCION_VENTA
Busca todas las devoluciones que vienen de una venta en concreto.
*/
CREATE INDEX IX_DEVOLUCION_VENTA ON DEVOLUCIONES (ID_DETALLE_VENTA);

-- 2. Para ver qué devoluciones están ligadas a un reclamo de garantía
/*
INDICE IX_DEVOLUCION_GARANTIA
Trae las devoluciones que estan ligadas a un reclamo de garantia.
*/
CREATE INDEX IX_DEVOLUCION_GARANTIA ON DEVOLUCIONES (ID_GARANTIA);

-- 3. Para el reporte de "Devoluciones Pendientes" del día
/*
INDICE IX_DEVOLUCION_ESTADO_FECHA
Busca devoluciones por estado y fecha, ideal para el reporte de
pendientes del dia.
*/
CREATE INDEX IX_DEVOLUCION_ESTADO_FECHA ON DEVOLUCIONES (ESTADO, FECHA);
-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //

DROP PROCEDURE IF EXISTS SP_REGISTRAR_DEVOLUCION ;

/*
SP_REGISTRAR_DEVOLUCION
Registra una devolucion nueva en estado PENDIENTE.
Valida que la cantidad sea posible (sin pasarse de lo ya devuelto), que la
garantia corresponda a esa venta y calcula el monto a reembolsar.
*/
CREATE PROCEDURE SP_REGISTRAR_DEVOLUCION(
    IN P_ID_DETALLE_VENTA INT,
    IN P_ID_GARANTIA INT, -- Puede ser NULL
    IN P_ID_EMPLEADO INT,
    IN P_CANTIDAD INT,
    IN P_MOTIVO VARCHAR(200),
    IN P_CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO') -- Añadido según estructura de tu tabla
)
proc_label: BEGIN
    DECLARE V_CANTIDAD_VENDIDA INT;
    DECLARE V_PRECIO_UNITARIO DECIMAL(10,2);
    DECLARE V_CANTIDAD_YA_DEVUELTA INT;
    DECLARE V_CANTIDAD_MAX_PERMITIDA INT;
    DECLARE V_SUBTOTAL_REEMBOLSADO DECIMAL(10,2);
    DECLARE V_GARANTIA_DETALLE INT;

    -- 1. Validar que la cantidad sea positiva
    IF P_CANTIDAD <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DEBE SER MAYOR A 0.';
        LEAVE proc_label; 
    END IF;

    -- 2. Validar existencia del detalle de venta y obtener datos básicos
    SELECT CANTIDAD, PRECIO_UNITARIO 
    INTO V_CANTIDAD_VENDIDA, V_PRECIO_UNITARIO
    FROM DETALLES_VENTA 
    WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA;

    IF V_CANTIDAD_VENDIDA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DETALLE DE VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Validar consistencia de la garantía si no es NULL
    IF P_ID_GARANTIA IS NOT NULL THEN
        SELECT ID_DETALLE_VENTA INTO V_GARANTIA_DETALLE 
        FROM GARANTIAS 
        WHERE ID_GARANTIA = P_ID_GARANTIA;

        IF V_GARANTIA_DETALLE IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA ESPECIFICADA NO EXISTE.';
            LEAVE proc_label;
        -- Verificar que la garantía pertenezca al detalle de venta que se quiere devolver
        ELSEIF V_GARANTIA_DETALLE <> P_ID_DETALLE_VENTA THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA NO CORRESPONDE A ESTE DETALLE DE VENTA.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- 4. Validar tope de cantidad acumulada (Evitar sobre-devoluciones)
    SELECT IFNULL(SUM(CANTIDAD), 0) INTO V_CANTIDAD_YA_DEVUELTA
    FROM DEVOLUCIONES
    WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA
      AND ESTADO IN ('PENDIENTE', 'APROBADA', 'REEMBOLSADA'); -- No contamos las RECHAZADAS

    SET V_CANTIDAD_MAX_PERMITIDA = V_CANTIDAD_VENDIDA - V_CANTIDAD_YA_DEVUELTA;

    IF P_CANTIDAD > V_CANTIDAD_MAX_PERMITIDA THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD SUPERA EL LÍMITE PERMITIDO (YA SE HAN DEVUELTO O ESTÁN PENDIENTES ALGUNAS UNIDADES).';
        LEAVE proc_label;
    END IF;

    -- 5. Calcular el subtotal que se va a reembolsar
    SET V_SUBTOTAL_REEMBOLSADO = P_CANTIDAD * V_PRECIO_UNITARIO;

    -- 6. Insertar el registro con todos los campos calculados y requeridos
    INSERT INTO DEVOLUCIONES (
        ID_DETALLE_VENTA, 
        ID_GARANTIA, 
        ID_EMPLEADO, 
        FECHA,
        CANTIDAD, 
        MOTIVO, 
        CONDICION_PRODUCTO, 
        SUBTOTAL_REEMBOLSADO, 
        ESTADO
    )
    VALUES (
        P_ID_DETALLE_VENTA, 
        P_ID_GARANTIA, 
        P_ID_EMPLEADO, 
        CURRENT_DATE,
        P_CANTIDAD, 
        P_MOTIVO, 
        IFNULL(P_CONDICION_PRODUCTO, 'BUENO'), 
        V_SUBTOTAL_REEMBOLSADO, 
        'PENDIENTE'
    );

    SELECT 'EXITO: DEVOLUCIÓN REGISTRADA COMO PENDIENTE.' AS MENSAJE, LAST_INSERT_ID() AS ID_DEVOLUCION;
END ;

DELIMITER ;




DELIMITER //
DROP PROCEDURE IF EXISTS 25_SP_PROCESAR_DEVOLUCION ;
/*
25_SP_PROCESAR_DEVOLUCION
Aprueba, rechaza o marca como reembolsada una devolucion.
Solo deja cambiar devoluciones que esten en PENDIENTE; si ya fue procesada
corta con error. Al cambiar el estado, el trigger devuelve el stock solo.
*/
CREATE PROCEDURE 25_SP_PROCESAR_DEVOLUCION(
    IN P_ID_DEVOLUCION INT,
    IN P_NUEVO_ESTADO ENUM('APROBADA', 'RECHAZADA', 'REEMBOLSADA')
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);

    -- 1. Validar que la devolución exista
    SELECT ESTADO INTO V_ESTADO_ACTUAL FROM DEVOLUCIONES WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;
    
    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCIÓN NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que no sea una devolución ya procesada
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA DEVOLUCIÓN YA FUE PROCESADA.';
        LEAVE proc_label;
    END IF;

    -- 3. Actualizar estado (Esto disparará automáticamente tu TRIGGER de inventario)
    UPDATE DEVOLUCIONES 
    SET ESTADO = P_NUEVO_ESTADO 
    WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;

    SELECT CONCAT('EXITO: DEVOLUCIÓN MARCADA COMO ', P_NUEVO_ESTADO) AS MENSAJE;
END ;
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_REINTEGRAR_STOCK_DEVOLUCION;
/*
TR_REINTEGRAR_STOCK_DEVOLUCION
Cuando una devolucion pasa de PENDIENTE a APROBADA o REEMBOLSADA,
regresa la cantidad al stock del producto y anota la ENTRADA en la
auditoria de movimientos. Si se rechaza, no toca el inventario.
*/
CREATE TRIGGER TR_REINTEGRAR_STOCK_DEVOLUCION
AFTER UPDATE ON DEVOLUCIONES
FOR EACH ROW
BEGIN
    -- Solo reintegramos si el estado cambia a APROBADA o REEMBOLSADA
    IF (NEW.ESTADO IN ('APROBADA', 'REEMBOLSADA') AND OLD.ESTADO = 'PENDIENTE') THEN
        
        -- 1. Regresar el stock
        UPDATE INVENTARIO 
        SET STOCK_ACTUAL = STOCK_ACTUAL + NEW.CANTIDAD
        WHERE ID_PRODUCTO = (SELECT ID_PRODUCTO FROM DETALLES_VENTA WHERE ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA);
        
        -- 2. Registrar en auditoría (con el empleado de la devolución)
        INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
        VALUES (
            (SELECT ID_PRODUCTO FROM DETALLES_VENTA WHERE ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA), 
            NEW.ID_EMPLEADO,
            'DEVOLUCION', 
            NEW.CANTIDAD, 
            CONCAT('Devolución aprobada ID: ', NEW.ID_DEVOLUCION)
        );
    END IF;
END ;
DELIMITER ;





------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_MARCAR_VENTA_DEVUELTA;
/*
TR_MARCAR_VENTA_DEVUELTA
Cuando una devolucion pasa de PENDIENTE a APROBADA o REEMBOLSADA revisa si
con esa ya se devolvio TODO lo de la venta: solo si no queda ni una unidad
por devolver marca la venta como DEVUELTA (si estaba REALIZADA). Una
devolucion parcial deja la venta como esta, porque el resto de la mercancia
sigue siendo buena. Cuentan solo las devoluciones ya procesadas (APROBADA o
REEMBOLSADA); las RECHAZADA no suman.
*/
CREATE TRIGGER TR_MARCAR_VENTA_DEVUELTA
AFTER UPDATE ON DEVOLUCIONES
FOR EACH ROW
BEGIN
    DECLARE V_ID_VENTA INT;
    DECLARE V_ESTADO VARCHAR(20);

    IF (NEW.ESTADO IN ('APROBADA', 'REEMBOLSADA') AND OLD.ESTADO = 'PENDIENTE') THEN

        SELECT DV.ID_VENTA, V.ESTADO INTO V_ID_VENTA, V_ESTADO
        FROM DETALLES_VENTA DV
        JOIN VENTAS V ON V.ID_VENTA = DV.ID_VENTA
        WHERE DV.ID_DETALLE_VENTA = NEW.ID_DETALLE_VENTA;

        IF V_ESTADO = 'REALIZADA' THEN
            -- queda alguna linea con unidades sin devolver?
            IF NOT EXISTS (
                SELECT 1
                FROM DETALLES_VENTA DV
                WHERE DV.ID_VENTA = V_ID_VENTA
                  AND DV.CANTIDAD > IFNULL(
                        (SELECT SUM(D.CANTIDAD)
                           FROM DEVOLUCIONES D
                          WHERE D.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
                            AND D.ESTADO IN ('APROBADA', 'REEMBOLSADA')), 0)
            ) THEN
                UPDATE VENTAS SET ESTADO = 'DEVUELTA' WHERE ID_VENTA = V_ID_VENTA;
            END IF;
        END IF;
    END IF;
END ;
DELIMITER ;




-----------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
VISTA_REPORTES_DEVOLUCIONES
Agrupa las devoluciones por producto, motivo y condicion.
Muestra cuantas veces se devolvio cada producto y porque, para reportes.
*/
CREATE OR REPLACE VIEW VISTA_REPORTES_DEVOLUCIONES AS
SELECT 
    P.NOMBRE AS PRODUCTO,
    COUNT(D.ID_DEVOLUCION) AS TOTAL_DEVOLUCIONES,
    D.MOTIVO,
    D.CONDICION_PRODUCTO
FROM DEVOLUCIONES D
JOIN DETALLES_VENTA DV ON D.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
JOIN PRODUCTOS P ON DV.ID_PRODUCTO = P.ID_PRODUCTO
GROUP BY P.ID_PRODUCTO, D.MOTIVO, D.CONDICION_PRODUCTO;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------