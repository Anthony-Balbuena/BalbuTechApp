/*
TABLA COMPRAS
Guarda cada compra que hace la tienda a sus proveedores.
Anota quien la hizo, cuando, a que proveedor, el dinero total gastado
y la factura del proveedor si ya llego.
Es la cabecera: los productos comprados van en DETALLE_COMPRA.
*/
CREATE TABLE COMPRAS (
    ID_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_PROVEEDOR INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    TOTAL DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (TOTAL >= 0),
    -- ABIERTA = se le pueden agregar productos (por defecto);
    -- RECIBIDA = saldada al 100% con pagos (archivo 19.5);
    -- CANCELADA = no recibe mas productos y su stock fue revertido;
    -- DEVUELTA = se devolvio toda la mercancia al proveedor (19.6)
    ESTADO ENUM('ABIERTA', 'RECIBIDA', 'CANCELADA', 'DEVUELTA') NOT NULL DEFAULT 'ABIERTA',
    FACTURA VARCHAR(30) NULL, -- Factura del proveedor (opcional, unica por proveedor)
    PRIMARY KEY (ID_COMPRA),
    CONSTRAINT FK_COMPRA_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR),
    CONSTRAINT FK_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
 
-- Para reportes de compras por mes, año o día (Cierres de caja)
/*
INDICE IX_COMPRA_FECHA
Ordena las compras por fecha, asi los reportes por mes, dia o cierre de caja
salen rapidos sin recorrer toda la tabla.
*/
CREATE INDEX IX_COMPRA_FECHA ON COMPRAS (FECHA);

-- Para análisis de gastos (Ej: "Busca compras mayores a 50,000 pesos")
/*
INDICE IX_COMPRA_TOTAL
Busca compras por su monto, util para analizar gastos y encontrar las
compras mas grandes de un periodo.
*/
CREATE INDEX IX_COMPRA_TOTAL ON COMPRAS (TOTAL);

/*
INDICE UQ_COMPRA_FACTURA
Cada factura vale una sola vez por proveedor: dos compras del mismo
proveedor no pueden repetir numero (distintos proveedores si pueden y
las compras sin factura no chocan). Si alguien la fuerza con un UPDATE
el indice la rechaza solo; el SP da el mensaje amable.
*/
CREATE UNIQUE INDEX UQ_COMPRA_FACTURA ON COMPRAS (ID_PROVEEDOR, FACTURA);

/*
INDICE IX_COMPRA_EMPLEADO
Busca las compras que hizo cada empleado, para reportes de quien compra
que (mismo rol que IX_VENTAS_EMPLEADO en el archivo 21).
*/
CREATE INDEX IX_COMPRA_EMPLEADO ON COMPRAS (ID_EMPLEADO);

-- La tabla HISTORIAL_ESTADOS_COMPRA, su indice y los dos triggers que la
-- alimentan (TR_HISTORIAL_ESTADO_COMPRA y TR_CAMBIO_ESTADO_COMPRA) se
-- mudaron al archivo 19.1- HISTORIAL_ESTADOS_COMPRA.sql (07/10/2026).




-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   



DELIMITER //

DROP PROCEDURE IF EXISTS 19_SP_INICIAR_COMPRA ;

/*
19_SP_INICIAR_COMPRA
Abre una compra nueva en blanco antes de agregarle productos.
Revisa que el proveedor y el empleado existan; si algo falla no guarda nada,
y si esta todo bien crea la compra y devuelve su numero de ID.
*/
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

    IF IFNULL((SELECT ESTADO FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR), 'INACTIVO') <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO ESTA ACTIVO.';
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

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CANCELAR_COMPRA ;
/*
SP_CANCELAR_COMPRA
Cancela una compra y le regresa la mercancia: baja el stock de cada
producto, anota la SALIDA en la bitacora y su fila en el historial del
producto, y deja la compra en estado CANCELADA (el detalle y el total se
conservan como evidencia).
Valida que el empleado sea el dueno de la compra y que la mercancia siga
en el almacen: si ya hubo ventas que consumieron ese stock no se puede
cancelar. Si algo falla no se cambia nada.
*/
CREATE PROCEDURE SP_CANCELAR_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_EMPLEADO_COMPRA INT;
    DECLARE V_ESTADO VARCHAR(20);
    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra este
    -- SP; si venimos de adentro de otra (llamada anidada o cierre de caja),
    -- no la toca y cualquier error se propaga para que el que llama decida.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        SET @COMPRAS_INTERNO = 0;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 1. El empleado que cancela debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. La compra debe existir
    SELECT ID_EMPLEADO, ESTADO INTO V_ID_EMPLEADO_COMPRA, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    IF V_ID_EMPLEADO_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Solo quien hizo la compra puede cancelarla
    IF V_ID_EMPLEADO_COMPRA <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA COMPRA.';
        LEAVE proc_label;
    END IF;

    -- 4. Solo se cancela una compra que siga ABIERTA
    IF V_ESTADO <> 'ABIERTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA ABIERTA (YA FUE RECIBIDA, CANCELADA O DEVUELTA).';
        LEAVE proc_label;
    END IF;

    -- 5. No se cancela una compra con pagos registrados (antes anulelos
    --    con SP_ANULAR_PAGO_COMPRA del archivo 19.5; asi nunca
    --    se queda dinero colgado)
    IF EXISTS (SELECT 1 FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA TIENE PAGOS REGISTRADOS; ANULELOS ANTES DE CANCELAR.';
        LEAVE proc_label;
    END IF;

    -- 6. La mercancia debe seguir en el almacen: si algun producto ya se
    --    consumo en ventas no hay stock para devolver (se revisa todo ANTES
    --    de tocar nada, asi un rechazo no deja cambios a medias)
    IF EXISTS (
        SELECT 1 FROM DETALLE_COMPRA DC
        LEFT JOIN INVENTARIO I ON I.ID_PRODUCTO = DC.ID_PRODUCTO
        WHERE DC.ID_COMPRA = P_ID_COMPRA
          AND IFNULL(I.STOCK_ACTUAL, 0) < DC.CANTIDAD
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE CANCELAR: EL STOCK ACTUAL NO ALCANZA PARA REVERTIR (YA HUBO VENTAS DE ESA MERCANCIA).';
        LEAVE proc_label;
    END IF;

    -- 7. Bitacora: la SALIDA de cada producto
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    SELECT DC.ID_PRODUCTO, P_ID_EMPLEADO, 'SALIDA', DC.CANTIDAD, CONCAT('Compra cancelada ID: ', P_ID_COMPRA)
    FROM DETALLE_COMPRA DC
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 8. Bajar el stock (el detalle no se borra: queda como evidencia)
    UPDATE INVENTARIO I
    JOIN DETALLE_COMPRA DC ON DC.ID_PRODUCTO = I.ID_PRODUCTO
    SET I.STOCK_ACTUAL = I.STOCK_ACTUAL - DC.CANTIDAD
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 9. Historial del producto con el stock antes y despues (UNA fila)
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    )
    SELECT DC.ID_PRODUCTO, 'SALIDA', DC.CANTIDAD,
           I.STOCK_ACTUAL + DC.CANTIDAD, I.STOCK_ACTUAL,
           CONCAT('Compra cancelada ID: ', P_ID_COMPRA)
    FROM DETALLE_COMPRA DC
    JOIN INVENTARIO I ON I.ID_PRODUCTO = DC.ID_PRODUCTO
    WHERE DC.ID_COMPRA = P_ID_COMPRA;

    -- 10. Cerrar la compra (el candado interno avisa al trigger de validacion
    --     de que esta cancelacion viene de un SP y no de un UPDATE a pelo)
    SET @COMPRAS_INTERNO = 1;
    UPDATE COMPRAS SET ESTADO = 'CANCELADA' WHERE ID_COMPRA = P_ID_COMPRA;
    SET @COMPRAS_INTERNO = 0;


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: COMPRA #', P_ID_COMPRA, ' CANCELADA Y MERCANCIA REVERTIDA.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ASIGNAR_FACTURA_COMPRA ;
/*
SP_ASIGNAR_FACTURA_COMPRA
Le pone el numero de factura del proveedor a una compra. Revisa que no
venga vacia, que la compra exista, que no este CANCELADA y que ese mismo
numero no se le haya usado ya a otra compra del mismo proveedor (el
indice UQ_COMPRA_FACTURA tambien lo bloquea solo).
*/
CREATE PROCEDURE SP_ASIGNAR_FACTURA_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_FACTURA VARCHAR(30)
)
proc_label: BEGIN
    DECLARE V_ID_PROVEEDOR INT;
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_FACTURA_LIMPIA VARCHAR(30);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia (mismo patron de la fase I) + traduccion del
    -- choque con el indice UQ_COMPRA_FACTURA: si dos sesiones asignan la
    -- misma factura a la vez, la validacion del paso 4 pasa en ambas y
    -- el indice corta con el error tecnico 1062 (SQLSTATE 23000); aqui
    -- se devuelve el mismo mensaje amigable que la validacion.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE V_ESTADO_SQL CHAR(5) DEFAULT '';

        GET DIAGNOSTICS CONDITION 1 V_ESTADO_SQL = RETURNED_SQLSTATE;

        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;

        IF V_ESTADO_SQL = '23000' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: ESA FACTURA YA EXISTE PARA ESTE PROVEEDOR.';
        END IF;

        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 1. La factura no puede venir vacia
    SET V_FACTURA_LIMPIA = TRIM(IFNULL(P_FACTURA, ''));
    IF V_FACTURA_LIMPIA = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FACTURA NO PUEDE ESTAR VACIA.';
        LEAVE proc_label;
    END IF;

    -- 2. La compra debe existir
    SELECT ID_PROVEEDOR, ESTADO INTO V_ID_PROVEEDOR, V_ESTADO
      FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    IF V_ID_PROVEEDOR IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Una compra cancelada o devuelta ya no tiene factura que llevar
    IF V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA.';
        LEAVE proc_label;
    END IF;

    -- 4. Esa factura no puede repetirse en el mismo proveedor
    IF EXISTS (
        SELECT 1 FROM COMPRAS
         WHERE ID_PROVEEDOR = V_ID_PROVEEDOR
           AND FACTURA = V_FACTURA_LIMPIA
           AND ID_COMPRA <> P_ID_COMPRA
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: ESA FACTURA YA EXISTE PARA ESTE PROVEEDOR.';
        LEAVE proc_label;
    END IF;

    -- 5. Asignar
    UPDATE COMPRAS SET FACTURA = V_FACTURA_LIMPIA WHERE ID_COMPRA = P_ID_COMPRA;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: FACTURA ', V_FACTURA_LIMPIA,
                  ' ASIGNADA A LA COMPRA #', P_ID_COMPRA, '.') AS MENSAJE;
END //
DELIMITER ;

-- Trigger TR_BLOQUEAR_COMPRA_CERRADA movido a 22 (su tabla).

-- Trigger TR_BLOQUEAR_UPDATE_DETALLE_COMPRA movido a 22 (su tabla).




-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger: Actualiza Inventario al comprar
-- Trigger TR_ACTUALIZAR_STOCK_COMPRA movido a 22 (su tabla).

-- Trigger TR_BLOQUEAR_BORRADO_COMPRA_CERRADA movido a 22 (su tabla).

-- Trigger TR_ACTUALIZAR_STOCK_BORRADO_COMPRA movido a 22 (su tabla).

-- El trigger TR_HISTORIAL_ESTADO_COMPRA (la primera fila del historial al
-- nacer la compra) se mudo al archivo 19.1- HISTORIAL_ESTADOS_COMPRA.sql.

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_ACTUALIZACION_COMPRA ;
/*
TR_VALIDAR_ACTUALIZACION_COMPRA
El candado de la cabecera: nadie cambia el ESTADO ni el TOTAL de una compra
con un UPDATE a pelo. El TOTAL solo lo mueven sus triggers internos (que
levantan @COMPRAS_INTERNO), RECIBIDA exige estar saldada al 100%, CANCELADA
solo sale de SP_CANCELAR_COMPRA (asi nadie se salta la reversión del stock)
y DEVUELTA solo con el TOTAL en cero. Una compra ya CANCELADA o DEVUELTA no
vuelve a cambiar jamas.
*/
CREATE TRIGGER TR_VALIDAR_ACTUALIZACION_COMPRA
BEFORE UPDATE ON COMPRAS
FOR EACH ROW
BEGIN
    DECLARE V_PAGADO DECIMAL(12, 2);

    -- El TOTAL solo lo tocan los triggers de detalle y el de devolucion
    IF NEW.TOTAL <> OLD.TOTAL AND IFNULL(@COMPRAS_INTERNO, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL TOTAL DE LA COMPRA SOLO CAMBIA CON SU DETALLE O SU DEVOLUCION.';
    END IF;

    IF NEW.ESTADO <> OLD.ESTADO THEN
        IF OLD.ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA.';
        END IF;

        IF NEW.ESTADO = 'RECIBIDA' THEN
            -- Solo se marca RECIBIDA una compra pagada al 100%
            SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
              FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;
            IF NEW.TOTAL <= 0 OR V_PAGADO < NEW.TOTAL THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA RECIBIDA UNA COMPRA PAGADA AL 100%.';
            END IF;

        ELSEIF NEW.ESTADO = 'ABIERTA' THEN
            -- Reapertura: solo de una RECIBIDA (anulacion o nota de credito)
            IF OLD.ESTADO <> 'RECIBIDA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE REABRE UNA COMPRA RECIBIDA.';
            END IF;

        ELSEIF NEW.ESTADO = 'CANCELADA' THEN
            -- La cancelacion revierte stock y bitacora: solo por el SP
            IF IFNULL(@COMPRAS_INTERNO, 0) <> 1 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: USE SP_CANCELAR_COMPRA; LA CANCELACION REVERSIA EL STOCK.';
            END IF;
            IF OLD.ESTADO <> 'ABIERTA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE CANCELA UNA COMPRA ABIERTA.';
            END IF;
            IF EXISTS (SELECT 1 FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA COMPRA TIENE PAGOS; ANULELOS ANTES DE CANCELAR.';
            END IF;

        ELSEIF NEW.ESTADO = 'DEVUELTA' THEN
            -- Solo llega con todo devuelto (el TOTAL ya quedo en cero)
            IF OLD.ESTADO <> 'RECIBIDA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA DEVUELTA UNA COMPRA RECIBIDA.';
            END IF;
            IF NEW.TOTAL > 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA DEVUELTA ENTERA; EL TOTAL SIGUE EN PIE.';
            END IF;

        ELSE
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: ESTADO DE COMPRA DESCONOCIDO.';
        END IF;
    END IF;
END //
DELIMITER ;

-- El trigger TR_CAMBIO_ESTADO_COMPRA (los cambios de estado del historial)
-- se mudo al archivo 19.1- HISTORIAL_ESTADOS_COMPRA.sql.

DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_COMPRA ;
/*
TR_BLOQUEAR_BORRADO_COMPRA
Las compras no se borran: de ahi cuelgan sus pagos, su detalle, sus
devoluciones y su historial de estados. Para deshacer una compra se usa
SP_CANCELAR_COMPRA, que la deja en CANCELADA con el motivo y la fila de
historial. Vale tambien para un DELETE directo sobre COMPRAS.
*/
CREATE TRIGGER TR_BLOQUEAR_BORRADO_COMPRA
BEFORE DELETE ON COMPRAS
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO SE PUEDE BORRAR; USE SP_CANCELAR_COMPRA PARA ANULARLA.';
END //
DELIMITER ;

/*
VISTA_REPORTE_COMPRAS
Muestra las compras con el nombre de su proveedor, fecha y total.
Las ordena de la mas reciente a la mas vieja, lista para el reporte.
*/
CREATE OR REPLACE VIEW VISTA_REPORTE_COMPRAS AS
SELECT 
    C.ID_COMPRA,
    P.NOMBRE AS PROVEEDOR,
    C.FECHA,
    C.TOTAL,
    C.FACTURA,
    C.ESTADO
FROM COMPRAS C
JOIN PROVEEDORES P ON C.ID_PROVEEDOR = P.ID_PROVEEDOR
ORDER BY C.FECHA DESC;

/*
VISTA_GASTOS_PROVEEDOR
Cuanto le hemos comprado a cada proveedor en total y cuantas compras
llevo. Las CANCELADAS no cuentan como gasto. Para rangos de fechas se
filtra en la consulta sobre VISTA_REPORTE_COMPRAS.
*/
CREATE OR REPLACE VIEW VISTA_GASTOS_PROVEEDOR AS
SELECT
    P.ID_PROVEEDOR,
    P.NOMBRE AS PROVEEDOR,
    COUNT(C.ID_COMPRA) AS COMPRAS_REALIZADAS,
    IFNULL(SUM(C.TOTAL), 0) AS GASTO_TOTAL
FROM PROVEEDORES P
LEFT JOIN COMPRAS C ON C.ID_PROVEEDOR = P.ID_PROVEEDOR
                   AND C.ESTADO <> 'CANCELADA'
GROUP BY P.ID_PROVEEDOR, P.NOMBRE
ORDER BY GASTO_TOTAL DESC;
DELIMITER //

DROP FUNCTION IF EXISTS FN_CONTAR_ITEMS_COMPRA ;

/*
FN_CONTAR_ITEMS_COMPRA
Cuenta cuantos productos distintos tiene una compra.
Se usa en reportes; si la compra no tiene nada devuelve 0.
*/
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

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_HISTORIAL_ESTADO_COMPRA movido a 19 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_HISTORIAL_ESTADO_COMPRA ;
/*
TR_HISTORIAL_ESTADO_COMPRA
Cuando nace una compra deja su primera fila en el historial de estados
(ABIERTA, con el empleado que la abrio). Solo registra el nacimiento:
los cambios de ahi en adelante los anota TR_CAMBIO_ESTADO_COMPRA.
*/
CREATE TRIGGER TR_HISTORIAL_ESTADO_COMPRA
AFTER INSERT ON COMPRAS
FOR EACH ROW
BEGIN
    INSERT INTO HISTORIAL_ESTADOS_COMPRA
        (ID_COMPRA, ESTADO_ANTERIOR, ESTADO_NUEVO, ID_EMPLEADO, MOTIVO)
    VALUES
        (NEW.ID_COMPRA, NULL, NEW.ESTADO, NEW.ID_EMPLEADO, 'Compra iniciada');
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_CAMBIO_ESTADO_COMPRA movido a 19 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_CAMBIO_ESTADO_COMPRA ;
/*
TR_CAMBIO_ESTADO_COMPRA
Cada vez que una compra cambia de estado (saldada, reabierta,
cancelada o devuelta) anota una fila con el antes y el despues en
HISTORIAL_ESTADOS_COMPRA. Si el estado no cambia no anota nada y
tambien vale si alguien lo cambia con un UPDATE directo. El empleado
es el dueno de la compra (los pagos no traen empleado propio).
*/
CREATE TRIGGER TR_CAMBIO_ESTADO_COMPRA
AFTER UPDATE ON COMPRAS
FOR EACH ROW
BEGIN
    IF NEW.ESTADO <> OLD.ESTADO THEN
        INSERT INTO HISTORIAL_ESTADOS_COMPRA
            (ID_COMPRA, ESTADO_ANTERIOR, ESTADO_NUEVO, ID_EMPLEADO, MOTIVO)
        VALUES
            (NEW.ID_COMPRA, OLD.ESTADO, NEW.ESTADO, NEW.ID_EMPLEADO,
             CONCAT('Estado: ', OLD.ESTADO, ' -> ', NEW.ESTADO));
    END IF;
END //
DELIMITER ;