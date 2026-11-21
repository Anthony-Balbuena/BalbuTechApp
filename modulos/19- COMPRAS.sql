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
    -- RECIBIDA = saldada al 100% con pagos (seccion PAGOS_COMPRA de este archivo);
    -- CANCELADA = no recibe mas productos y su stock fue revertido;
    -- DEVUELTA = se devolvio toda la mercancia al proveedor (seccion DEVOLUCION_COMPRA de este archivo)
    ESTADO ENUM('ABIERTA', 'RECIBIDA', 'CANCELADA', 'DEVUELTA') NOT NULL DEFAULT 'ABIERTA',
    FACTURA VARCHAR(30) NULL, -- Factura del proveedor (opcional, unica por proveedor)
    PRIMARY KEY (ID_COMPRA),
    CONSTRAINT FK_COMPRA_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR),
    CONSTRAINT FK_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Ordena las compras por fecha, asi los reportes por mes, dia o cierre de caja salen
    -- rapidos sin recorrer toda la tabla.
    INDEX IX_COMPRA_FECHA (FECHA),
    -- Busca compras por su monto, util para analizar gastos y encontrar las compras mas
    -- grandes de un periodo.
    INDEX IX_COMPRA_TOTAL (TOTAL),
    -- Cada factura vale una sola vez por proveedor: dos compras del mismo proveedor no
    -- pueden repetir numero (distintos proveedores si pueden y las compras sin factura no
    -- chocan). Si alguien la fuerza con un UPDATE el indice la rechaza solo; el SP da el
    -- mensaje amable.
    CONSTRAINT UQ_COMPRA_FACTURA UNIQUE (ID_PROVEEDOR, FACTURA),
    -- Busca las compras que hizo cada empleado, para reportes de quien compra que (mismo
    -- rol que IX_VENTAS_EMPLEADO en el archivo 21).
    INDEX IX_COMPRA_EMPLEADO (ID_EMPLEADO),
    -- Busca todas las compras de un proveedor en concreto, util para ver el historial de
    -- compras hechas a cada proveedor.
    INDEX IX_COMPRA_PROVEEDOR (ID_PROVEEDOR)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*
TABLA HISTORIAL_ESTADOS_COMPRA
Quien, cuando y como cambio el estado de cada compra: iniciada,
saldada, reabierta, cancelada o devuelta. Una fila por cada cambio,
escrita por triggers, asi que tambien cuenta si alguien cambia el
estado con un UPDATE directo.
*/
CREATE TABLE HISTORIAL_ESTADOS_COMPRA (
    ID_HISTORIAL_ESTADO INT NOT NULL AUTO_INCREMENT,
    ID_COMPRA INT NOT NULL,
    ESTADO_ANTERIOR ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NULL,
    ESTADO_NUEVO ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    MOTIVO VARCHAR(100) NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_HISTORIAL_ESTADO),
    CONSTRAINT FK_HIST_ESTADO_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA),
    CONSTRAINT FK_HIST_ESTADO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- (09/10/2026) CHECKs: el historial no admite estados inventados (solo los del ENUM de COMPRAS).
    CONSTRAINT CK_HIST_ESTADO_ANTERIOR CHECK (ESTADO_ANTERIOR IS NULL OR ESTADO_ANTERIOR IN ('ABIERTA', 'RECIBIDA', 'CANCELADA', 'DEVUELTA')),
    CONSTRAINT CK_HIST_ESTADO_NUEVO CHECK (ESTADO_NUEVO IN ('ABIERTA', 'RECIBIDA', 'CANCELADA', 'DEVUELTA')),
    -- Trae el historial de estados por fecha para los reportes (por compra ya lo cubre el
    -- FK).
    INDEX IX_HIST_ESTADO_FECHA (FECHA)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- Migracion para BDs ya creadas con VARCHAR(20): unifica al ENUM (re-ejecutable).
ALTER TABLE HISTORIAL_ESTADOS_COMPRA
    MODIFY COLUMN ESTADO_ANTERIOR ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NULL,
    MODIFY COLUMN ESTADO_NUEVO ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NOT NULL;


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
    --    con SP_ANULAR_PAGO_COMPRA, mas abajo en este mismo archivo; asi nunca
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

-- Trigger TR_BLOQUEAR_COMPRA_CERRADA: mas abajo en este archivo.

-- Trigger TR_BLOQUEAR_UPDATE_DETALLE_COMPRA: mas abajo en este archivo.


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger: Actualiza Inventario al comprar
-- Trigger TR_ACTUALIZAR_STOCK_COMPRA: mas abajo en este archivo.

-- Trigger TR_BLOQUEAR_BORRADO_COMPRA_CERRADA: mas abajo en este archivo.

-- Trigger TR_ACTUALIZAR_STOCK_BORRADO_COMPRA: mas abajo en este archivo.


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


/*
SP_REPORTE_PERIODO_COMPRA (14/10/2026)
Reporte de compras RECIBIDAS en un rango de fechas (inclusive).
Devuelve una fila: transacciones, subtotal (base), ITBIS real y BRUTO.
Mismo BRUTO de VISTA_COMPRA_CON_IVA (solo PROCESADA mueve dinero).
Espejo de SP_REPORTE_PERIODO (ventas).
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTE_PERIODO_COMPRA //
CREATE PROCEDURE SP_REPORTE_PERIODO_COMPRA(
    IN P_DESDE DATE,
    IN P_HASTA DATE
)
proc_label: BEGIN
    IF P_DESDE IS NULL OR P_HASTA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE INDICAR DESDE Y HASTA.';
        LEAVE proc_label;
    END IF;

    IF P_DESDE > P_HASTA THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.';
        LEAVE proc_label;
    END IF;

    SELECT
        COUNT(DISTINCT N.ID_COMPRA) AS TRANSACCIONES,
        ROUND(IFNULL(SUM(N.SUBTOTAL_ORIGINAL), 0), 2) AS SUBTOTAL,
        ROUND(IFNULL(SUM(N.ITBIS_NETO), 0), 2) AS ITBIS,
        ROUND(IFNULL(SUM(N.BRUTO_NETO), 0), 2) AS BRUTO,
        -- (15/11/2026) Repuesto vs reventa. Va como SUBQUERY y no como JOIN al
        -- nivel principal a proposito: un JOIN directo a DETALLE_COMPRA
        -- multiplicaria SUM(N.SUBTOTAL_ORIGINAL) por la cantidad de lineas de
        -- cada compra.
        ROUND(IFNULL(SUM(DR.REPUESTO), 0), 2) AS COMPRAS_REPUESTO,
        ROUND(IFNULL(SUM(DR.REVENTA), 0), 2)  AS COMPRAS_REVENTA
    -- (15/11/2026) SUBTOTAL/ITBIS/BRUTO salen de VW_COMPRA_NETA, igual que el
    -- resto del flujo: antes este reporte era el ultimo lugar con la formula
    -- escrita a mano, y podia desincronizarse de las vistas.
    FROM VW_COMPRA_NETA N
    LEFT JOIN (
        SELECT DC.ID_COMPRA,
               SUM(CASE WHEN P.ES_REPUESTO = 1 THEN DC.SUBTOTAL ELSE 0 END) AS REPUESTO,
               SUM(CASE WHEN P.ES_REPUESTO = 0 THEN DC.SUBTOTAL ELSE 0 END) AS REVENTA
          FROM DETALLE_COMPRA DC
          JOIN PRODUCTOS P ON P.ID_PRODUCTO = DC.ID_PRODUCTO
         GROUP BY DC.ID_COMPRA
    ) DR ON DR.ID_COMPRA = N.ID_COMPRA
    WHERE N.ESTADO = 'RECIBIDA'
      AND DATE(N.FECHA) BETWEEN P_DESDE AND P_HASTA;
END //
DELIMITER ;


-- ================================================================
-- PAGOS_COMPRA (ex modulo 19.5)
-- ================================================================

/*
SECCION PAGOS_COMPRA (ex modulo 19.5)
Pagos a proveedores por una compra: cuanto, cuando y con que metodo.
Pueden ser parciales o totales; cuando la suma cubre el total, la compra
queda RECIBIDA sola. Todo lo de esta tabla vive en esta seccion: la tabla,
los indices, los 4 SP, los 7 triggers y la vista.
La guarda de no cancelar una compra con pagos esta en SP_CANCELAR_COMPRA,
mas arriba en este mismo archivo.
*/
/*
TABLA PAGOS_COMPRA
Guarda cada pago que se hace a un proveedor por una compra: cuanto, cuando
y con que metodo. Puede haber varios pagos por compra (parciales o totales);
cuando la suma cubre el total, la compra queda RECIBIDA sola.
*/
CREATE TABLE PAGOS_COMPRA (
    ID_PAGO_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_COMPRA INT NOT NULL,
    -- NULL en las notas de credito: ahi no hay plata moviendose
    ID_METODO_PAGO INT NULL,
    -- Quien paga (o quien firma la nota). Si el llamador no manda el
    -- empleado, TR_AUTOCOMPLETAR_EMPLEADO_PAGO pone al dueno de la compra.
    ID_EMPLEADO INT NOT NULL,
    -- PAGO = plata que se le entrega al proveedor;
    -- NOTA_CREDITO = descuento o devolucion que le baja la deuda (monto negativo)
    TIPO ENUM('PAGO', 'NOTA_CREDITO') NOT NULL DEFAULT 'PAGO',
    MONTO DECIMAL(10, 2) NOT NULL,
    OBSERVACION VARCHAR(100) NULL, -- motivo de la nota de credito (los pagos no llevan)
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PAGO_COMPRA),
    CONSTRAINT CHK_PAGOS_COMPRA_MONTO CHECK (MONTO <> 0),
    CONSTRAINT FK_PAGO_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA),
    CONSTRAINT FK_PAGO_COMPRA_METODO FOREIGN KEY (ID_METODO_PAGO) REFERENCES METODOS_PAGO (ID_METODO_PAGO),
    CONSTRAINT FK_PAGO_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Trae todos los pagos de una compra en concreto, para ver como se fue saldando.
    INDEX IX_PAGOS_COMPRA_COMPRA (ID_COMPRA),
    -- Trae los pagos por fecha para el cierre de caja y los reportes del dia (mismo rol
    -- que IX_PAGOS_FECHA en PAGOS de ventas).
    INDEX IX_PAGOS_COMPRA_FECHA (FECHA)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Deja al dia una BD que ya tenia esta tabla (como la real): agrega las
-- columnas, le pone el dueno de la compra a los pagos viejos, cambia el
-- CHECK viejo de MONTO > 0 por MONTO <> 0 (ahi entran las notas) y le
-- pone el FK del empleado si la BD vieja no lo trajo. En una BD recien
-- creada nada de esto hace falta, el CREATE de arriba ya lo trae.
-- ============================================================
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS ID_EMPLEADO INT NULL;
UPDATE PAGOS_COMPRA PC JOIN COMPRAS C ON C.ID_COMPRA = PC.ID_COMPRA
   SET PC.ID_EMPLEADO = C.ID_EMPLEADO
 WHERE PC.ID_EMPLEADO IS NULL;
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN ID_EMPLEADO INT NOT NULL;
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS TIPO ENUM('PAGO', 'NOTA_CREDITO') NOT NULL DEFAULT 'PAGO';
ALTER TABLE PAGOS_COMPRA ADD COLUMN IF NOT EXISTS OBSERVACION VARCHAR(100) NULL;
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN ID_METODO_PAGO INT NULL;
-- El CHECK viejo MONTO > 0 no se puede borrar con DROP CONSTRAINT (esta
-- version de MariaDB lo ignora en silencio) ni con DROP CHECK (syntax
-- error): al redefinir la columna sin el CHECK inline se va solo. En una
-- BD vieja que tenga el check en la columna, esto lo limpia.
ALTER TABLE PAGOS_COMPRA MODIFY COLUMN MONTO DECIMAL(10, 2) NOT NULL;
ALTER TABLE PAGOS_COMPRA ADD CONSTRAINT IF NOT EXISTS CHK_PAGOS_COMPRA_MONTO CHECK (MONTO <> 0);
-- El FK del empleado: las BDs viejas (como la real) crearon esta tabla
-- antes de que el CREATE de arriba lo trajera, y como el CREATE no corre
-- (table already exists) hay que agregarlo aparte. Si ya existe tira el
-- error 1826 'Duplicate foreign key constraint name', que es inofensivo
-- (mismo criterio que los ERROR 1050/1061 de toda la carga).
-- NEUTRALIZADO: duplica el FK inline del CREATE (error 1826 inofensivo pero ensucia el log).
-- ALTER TABLE PAGOS_COMPRA ADD CONSTRAINT FK_PAGO_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO);


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[PAGOS DE LA COMPRA}-----------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_PAGO_COMPRA ;
/*
SP_REGISTRAR_PAGO_COMPRA
Registra un pago (parcial o total) a un proveedor por una compra.
Valida todo antes de guardar: que la compra exista y este ABIERTA, que el
metodo de pago exista, que el monto sea mayor a cero y que no exceda el
total (suma de pagos anteriores + este monto). Al cubrir el total,
TR_AUTO_RECIBIR_COMPRA deja la compra en estado RECIBIDA sola.
El empleado que paga es opcional: si no viene, se toma al dueno de la
compra (asi nunca queda un pago sin responsable).
*/
CREATE PROCEDURE SP_REGISTRAR_PAGO_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_ID_METODO_PAGO INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_ID_EMPLEADO INT -- quien paga; si no viene (NULL), el dueno de la compra
)
proc_label: BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
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

    -- 1. La compra debe existir
    -- BLINDAJE (07/10/2026): FOR UPDATE congela la fila de la compra para
    -- que dos movimientos a la vez no pasen juntos su validacion de montos
    -- (evita exceder el total por carrera).
    -- SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    -- FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;
    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
      FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA
      FOR UPDATE;

    -- (13/10/2026) Cobro por BRUTO (mismo de VISTA_COMPRA_CON_IVA).
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = P_ID_COMPRA);

    IF V_TOTAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo una compra ABIERTA admite pagos
    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'RECIBIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA.';
        LEAVE proc_label;
    END IF;

    -- 3. El metodo de pago debe existir
    IF NOT EXISTS (SELECT 1 FROM METODOS_PAGO WHERE ID_METODO_PAGO = P_ID_METODO_PAGO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL METODO DE PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 4. Monto valido
    IF IFNULL(P_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 5. No exceder el total de la compra
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA;

    IF (V_PAGADO + P_MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
        LEAVE proc_label;
    END IF;

    -- 6. Si mandaron el empleado que paga, tiene que existir
    IF P_ID_EMPLEADO IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 7. Guardar el pago (TR_AUTO_RECIBIR_COMPRA puede cerrar la compra).
    --    Si P_ID_EMPLEADO viene NULL lo completa el trigger de la tabla.
    INSERT INTO PAGOS_COMPRA (ID_COMPRA, ID_METODO_PAGO, ID_EMPLEADO, TIPO, MONTO)
    VALUES (P_ID_COMPRA, P_ID_METODO_PAGO, P_ID_EMPLEADO, 'PAGO', P_MONTO);

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 8. Mensaje con el estado final
    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;

    SELECT CONCAT('EXITO: PAGO DE ', P_MONTO, ' REGISTRADO PARA LA COMPRA #', P_ID_COMPRA,
                  IF(V_ESTADO = 'RECIBIDA', ' - COMPRA SALDADA (RECIBIDA).', '')) AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ANULAR_PAGO_COMPRA ;
/*
SP_ANULAR_PAGO_COMPRA
Anula un pago de compra que se registro por error. Al borrarlo los totales
vuelven a cuadrar solos (todo se calcula con SUM sobre PAGOS_COMPRA). Si
con eso la compra deja de estar saldada, vuelve a ABIERTA y vuelve a
aceptar productos y pagos. No se puede anular el pago de una compra
CANCELADA. Tambien sirve para deshacer una nota de credito.
*/
CREATE PROCEDURE SP_ANULAR_PAGO_COMPRA(
    IN P_ID_PAGO_COMPRA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ID_COMPRA INT;
    DECLARE V_MONTO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_PAGADO DECIMAL(10, 2);
    DECLARE V_TIPO VARCHAR(15);
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

    -- 1. El empleado que anula debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. El pago debe existir
    SELECT ID_COMPRA, MONTO, TIPO INTO V_ID_COMPRA, V_MONTO, V_TIPO
    FROM PAGOS_COMPRA WHERE ID_PAGO_COMPRA = P_ID_PAGO_COMPRA;

    IF V_ID_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PAGO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. La compra no puede estar CANCELADA
    SELECT ESTADO, TOTAL INTO V_ESTADO, V_TOTAL
    FROM COMPRAS WHERE ID_COMPRA = V_ID_COMPRA;

    -- (13/10/2026) Reapertura contra BRUTO.
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = V_ID_COMPRA);

    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA, NO ADMITE CAMBIOS DE PAGO.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA, NO ADMITE CAMBIOS DE PAGO.';
        LEAVE proc_label;
    END IF;

    -- 4. Borra el pago
    DELETE FROM PAGOS_COMPRA WHERE ID_PAGO_COMPRA = P_ID_PAGO_COMPRA;

    -- 5. Recalcula lo pagado
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = V_ID_COMPRA;

    -- 6. Si dejo de estar saldada, vuelve a ABIERTA
    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = V_ID_COMPRA;
    END IF;

    -- 7. Mensaje

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: ', IF(V_TIPO = 'NOTA_CREDITO', 'NOTA DE CREDITO #', 'PAGO #'),
                  P_ID_PAGO_COMPRA, ' ANULADO (', V_MONTO,
                  '). PAGADO DE LA COMPRA #', V_ID_COMPRA, ': ', V_PAGADO) AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_NOTA_CREDITO_COMPRA ;
/*
SP_REGISTRAR_NOTA_CREDITO_COMPRA
Le anota una nota de credito a una compra: un descuento o una devolucion
que le baja la deuda al proveedor. Se guarda con MONTO negativo para que
el SUM(MONTO) de las vistas netee solo, sin tener que restar a mano.
Pide el motivo en observacion (obligatorio) y el empleado que la firma;
si no viene empleado se toma al dueno de la compra. Si con eso la compra
deja de estar saldada, TR_AUTO_RECIBIR_COMPRA la reabre sola.
*/
CREATE PROCEDURE SP_REGISTRAR_NOTA_CREDITO_COMPRA(
    IN P_ID_COMPRA INT,
    IN P_MONTO DECIMAL(10, 2),
    IN P_OBSERVACION VARCHAR(100),
    IN P_ID_EMPLEADO INT -- quien la firma; si no viene (NULL), el dueno de la compra
)
proc_label: BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
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

    -- 1. La compra debe existir
    -- BLINDAJE (07/10/2026): FOR UPDATE congela la fila de la compra para
    -- que dos movimientos a la vez no pasen juntos su validacion de montos
    -- (evita exceder el total por carrera).
    -- SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    -- FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA;
    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
      FROM COMPRAS WHERE ID_COMPRA = P_ID_COMPRA
      FOR UPDATE;

    IF V_TOTAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Una compra cancelada o devuelta ya cerro su cuenta con el proveedor
    IF V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE NOTAS DE CREDITO.';
        LEAVE proc_label;
    END IF;

    -- 3. El monto viene en positivo: quien lo guarda negativo es el SP
    IF IFNULL(P_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DE LA NOTA DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 4. Sin motivo no hay nota: es plata que se mueve
    IF IFNULL(TRIM(P_OBSERVACION), '') = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA NOTA DE CREDITO REQUIERE UNA OBSERVACION.';
        LEAVE proc_label;
    END IF;

    -- 5. Si mandaron el empleado que la firma, tiene que existir
    IF P_ID_EMPLEADO IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 6. Se guarda con el signo cambiado (la fila siempre es negativa)
    INSERT INTO PAGOS_COMPRA (ID_COMPRA, ID_METODO_PAGO, ID_EMPLEADO, TIPO, MONTO, OBSERVACION)
    VALUES (P_ID_COMPRA, NULL, P_ID_EMPLEADO, 'NOTA_CREDITO', -ABS(P_MONTO), TRIM(P_OBSERVACION));

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 7. Mensaje con lo que queda pagado
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = P_ID_COMPRA;

    SELECT CONCAT('EXITO: NOTA DE CREDITO DE ', P_MONTO,
                  ' REGISTRADA CONTRA LA COMPRA #', P_ID_COMPRA,
                  ' (PAGADO: ', V_PAGADO, ').') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTOCOMPLETAR_EMPLEADO_PAGO ;
/*
TR_AUTOCOMPLETAR_EMPLEADO_PAGO
Ningun pago se queda sin responsable: si la fila entra sin ID_EMPLEADO
(un INSERT directo o un llamado viejo del SP), le pone al dueno de la
compra. Si la compra no existe no hay a quien culpar y corta con error.
*/
CREATE TRIGGER TR_AUTOCOMPLETAR_EMPLEADO_PAGO
BEFORE INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_EMPLEADO INT;

    IF NEW.ID_EMPLEADO IS NULL THEN
        SELECT C.ID_EMPLEADO INTO V_EMPLEADO
        FROM COMPRAS C WHERE C.ID_COMPRA = NEW.ID_COMPRA;

        IF V_EMPLEADO IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO EXISTE, NO SE QUIEN DEJAR COMO RESPONSABLE.';
        END IF;

        SET NEW.ID_EMPLEADO = V_EMPLEADO;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_PAGO_COMPRA ;
/*
TR_VALIDAR_PAGO_COMPRA
Antes de guardar un pago de compra revisa que la compra este ABIERTA (no
cancelada ni ya saldada) y que el monto no exceda el total, sumando los
pagos anteriores. Vale tambien para INSERT directo: tambien revisa que el
signo del MONTO concuerde con el TIPO (un pago entra, una nota de credito
sale) y que nadie meta un monto en cero.
*/
CREATE TRIGGER TR_VALIDAR_PAGO_COMPRA
BEFORE INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    -- (13/10/2026) Tope por BRUTO.
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = NEW.ID_COMPRA);

    IF V_ESTADO = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA.';
    END IF;

    -- Un pago positivo sobre una compra ya saldada no tiene sentido;
    -- la nota de credito (montos negativos) si entra: es plata que vuelve.
    IF V_ESTADO = 'RECIBIDA' AND NEW.MONTO > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA YA ESTA RECIBIDA (SALDADA).';
    END IF;

    IF V_ESTADO = 'DEVUELTA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA DEVUELTA.';
    END IF;

    IF IFNULL(NEW.MONTO, 0) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO NO PUEDE SER CERO.';
    END IF;

    -- El signo tiene que ver con el tipo: un PAGO entra y una NOTA sale
    IF (NEW.TIPO = 'PAGO' AND NEW.MONTO < 0)
       OR (NEW.TIPO = 'NOTA_CREDITO' AND NEW.MONTO > 0) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO Y EL TIPO NO COINCIDEN (LA NOTA DE CREDITO ES NEGATIVA).';
    END IF;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF (V_PAGADO + NEW.MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_RECIBIR_COMPRA ;
/*
TR_AUTO_RECIBIR_COMPRA
Cuando entra un pago, revisa si con eso se cubrio el total de la compra.
Si ya se pago todo, deja la compra en RECIBIDA (el equivalente a
REALIZADA en ventas). Si despues se anula un pago con
SP_ANULAR_PAGO_COMPRA o entra una nota de credito que baja lo pagado,
la compra vuelve a ABIERTA. No crea bonos:
los bonos son por ventas, no por compras.
*/
CREATE TRIGGER TR_AUTO_RECIBIR_COMPRA
AFTER INSERT ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    -- (13/10/2026) Cierre por BRUTO (sin bono: los bonos son por ventas).
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = NEW.ID_COMPRA);

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF V_ESTADO = 'ABIERTA' AND V_TOTAL > 0 AND V_PAGADO >= V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'RECIBIDA' WHERE ID_COMPRA = NEW.ID_COMPRA;
    END IF;

    -- Una nota de credito que baja lo pagado deja la compra a medias:
    -- se reabre para que vuelva a aceptar productos.
    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = NEW.ID_COMPRA;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_BORRADO_PAGO_COMPRA ;
/*
TR_VALIDAR_BORRADO_PAGO_COMPRA
El pago de una compra CANCELADA o DEVUELTA no se toca, ni con DELETE directo:
ahi la plata ya quedo resuelta por otro camino y borrarla dejaria el
resumen mintiendo. Es la misma regla que aplica SP_ANULAR_PAGO_COMPRA antes
de borrar, ahora hecha valer tambien cuando el borrado viene a pelo.
*/
CREATE TRIGGER TR_VALIDAR_BORRADO_PAGO_COMPRA
BEFORE DELETE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    IF V_ESTADO IS NULL OR V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE CAMBIOS DE PAGO.';
    END IF;
END //
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_COMPRA ;
/*
TR_RECALCULAR_ESTADO_PAGO_COMPRA
Cuando desaparece un pago vuelve a sumar lo pagado de la compra: si dejo de
estar saldada le quita la RECIBIDA y la deja otra vez en ABIERTA, para que
vuelva a aceptar productos y pagos. Y si lo que se borro es una nota de
credito que dejaba todo saldado, la marca RECIBIDA otra vez. Hace lo mismo
que el paso 6 de SP_ANULAR_PAGO_COMPRA, pero sirve tambien si el borrado
no paso por el SP.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_COMPRA
AFTER DELETE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
    FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    -- (13/10/2026) Comparaciones por BRUTO.
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = OLD.ID_COMPRA);

    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
    FROM PAGOS_COMPRA WHERE ID_COMPRA = OLD.ID_COMPRA;

    IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = OLD.ID_COMPRA;
    END IF;

    -- Al reves: si borrar esa fila dejo todo saldado (se fue una nota de
    -- credito), la compra vuelve a estar RECIBIDA.
    IF V_ESTADO = 'ABIERTA' AND V_TOTAL > 0 AND V_PAGADO >= V_TOTAL THEN
        UPDATE COMPRAS SET ESTADO = 'RECIBIDA' WHERE ID_COMPRA = OLD.ID_COMPRA;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_UPDATE_PAGO_COMPRA ;
/*
TR_VALIDAR_UPDATE_PAGO_COMPRA
El pago de una compra tampoco se edita a pelo: un UPDATE directo no puede
moverlo a otra compra, no puede cambiarle el signo (el PAGO entra y la
NOTA sale) ni pasarse del total de la compra. Las compras CANCELADA o
DEVUELTA no admiten ni siquiera eso, igual que en el borrado.
*/
CREATE TRIGGER TR_VALIDAR_UPDATE_PAGO_COMPRA
BEFORE UPDATE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    -- El pago se queda en su compra
    IF NEW.ID_COMPRA <> OLD.ID_COMPRA THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL PAGO NO CAMBIA DE COMPRA.';
    END IF;

    SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
      FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    -- (13/10/2026) Tope por BRUTO.
    -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
    -- (VW_VENTA_NETA): una sola definicion de la formula.
    SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = NEW.ID_COMPRA);

    IF V_ESTADO IS NULL OR V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA ESTA CANCELADA O DEVUELTA, NO ADMITE CAMBIOS DE PAGO.';
    END IF;

    IF IFNULL(NEW.MONTO, 0) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO NO PUEDE SER CERO.';
    END IF;

    -- El signo tiene que ver con el tipo: un PAGO entra y una NOTA sale
    IF (NEW.TIPO = 'PAGO' AND NEW.MONTO < 0)
       OR (NEW.TIPO = 'NOTA_CREDITO' AND NEW.MONTO > 0) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO Y EL TIPO NO COINCIDEN (LA NOTA DE CREDITO ES NEGATIVA).';
    END IF;

    -- La suma con el cambio aplicado no puede pasarse del total
    SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
      FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

    IF (V_PAGADO - OLD.MONTO + NEW.MONTO) > V_TOTAL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA COMPRA.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_COMPRA_UPDATE ;
/*
TR_RECALCULAR_ESTADO_PAGO_COMPRA_UPDATE
Si alguien le cambia el monto o el tipo a un pago, la compra puede dejar de
estar saldada (o quedarlo): aqui se vuelve a sumar lo pagado y se mueve el
estado igual que al insertar. Mismo cuerpo que TR_AUTO_RECIBIR_COMPRA, para
que un UPDATE directo no deje la compra mintiendo.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_COMPRA_UPDATE
AFTER UPDATE ON PAGOS_COMPRA
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_PAGADO DECIMAL(10, 2);

    IF NEW.MONTO <> OLD.MONTO OR NEW.TIPO <> OLD.TIPO THEN
        SELECT TOTAL, ESTADO INTO V_TOTAL, V_ESTADO
          FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

        -- (13/10/2026) Comparaciones por BRUTO.
        -- (15/11/2026) El BRUTO sale de VW_COMPRA_NETA, igual que en ventas
        -- (VW_VENTA_NETA): una sola definicion de la formula.
        SET V_TOTAL = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = NEW.ID_COMPRA);

        SELECT IFNULL(SUM(MONTO), 0) INTO V_PAGADO
          FROM PAGOS_COMPRA WHERE ID_COMPRA = NEW.ID_COMPRA;

        IF V_ESTADO = 'ABIERTA' AND V_TOTAL > 0 AND V_PAGADO >= V_TOTAL THEN
            UPDATE COMPRAS SET ESTADO = 'RECIBIDA' WHERE ID_COMPRA = NEW.ID_COMPRA;
        END IF;

        IF V_ESTADO = 'RECIBIDA' AND V_PAGADO < V_TOTAL THEN
            UPDATE COMPRAS SET ESTADO = 'ABIERTA' WHERE ID_COMPRA = NEW.ID_COMPRA;
        END IF;
    END IF;
END //
DELIMITER ;


-------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}---------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------
/*
VISTA_RESUMEN_PAGOS_COMPRA
Lista los pagos a proveedores con el nombre del metodo de pago, igual
que la VISTA_RESUMEN_PAGOS de ventas pero para las compras.
*/
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS_COMPRA AS
SELECT
    PC.ID_PAGO_COMPRA,
    PC.ID_COMPRA,
    PC.TIPO,
    MP.NOMBRE AS NOMBRE_METODO,
    PC.ID_EMPLEADO,
    PC.MONTO,
    PC.OBSERVACION,
    PC.FECHA
FROM PAGOS_COMPRA PC
-- LEFT: las notas de credito no traen metodo de pago
LEFT JOIN METODOS_PAGO MP ON PC.ID_METODO_PAGO = MP.ID_METODO_PAGO;


/*
SP_COMPRAS_PENDIENTES (14/10/2026)
Compras con dinero de por medio para "Cobrar compra".
Espejo de SP_VENTAS_PENDIENTES (39).
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_COMPRAS_PENDIENTES //
CREATE PROCEDURE SP_COMPRAS_PENDIENTES()
BEGIN
    SELECT ID_COMPRA, PROVEEDOR, ESTADO, PAGADO, SALDO
      FROM VISTA_COMPRAS_PENDIENTES_PAGO ORDER BY ID_COMPRA DESC LIMIT 20;
END //
DELIMITER ;


-- ================================================================
-- DEVOLUCION_COMPRA (ex modulo 19.6)
-- ================================================================

/*
SECCION DEVOLUCION_COMPRA (ex modulo 19.6)
Devoluciones de mercancia al proveedor: que se devuelve, cuando, porque y
en que condicion. Solo se devuelve de una compra RECIBIDA; al procesar la
devolucion baja el stock, anota la SALIDA, escribe el historial y baja el
TOTAL de la compra. Si se devuelve todo, la compra queda DEVUELTA.
Los dos SP se pueden definir antes de que existan DEVOLUCION_COMPRA y
DETALLE_COMPRA: MariaDB no valida las tablas del cuerpo al crear la rutina,
solo al ejecutarla. La tabla, sus indices y sus 3 triggers viven en el 22.
*/
-- TABLA DEVOLUCION_COMPRA (+indices): mas abajo en este archivo, despues de DETALLE_COMPRA.


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_DEVOLUCION_COMPRA ;
/*
SP_REGISTRAR_DEVOLUCION_COMPRA
Deja anotada la intencion de devolver mercancia (queda PENDIENTE, sin
tocar stock ni totales). Valida empleado, que el detalle exista, que la
compra este RECIBIDA y que la cantidad no pase de lo comprado (contando
las devoluciones pendientes o ya procesadas). Devuelve el ID para
procesarla despues con SP_PROCESAR_DEVOLUCION_COMPRA.
*/
CREATE PROCEDURE SP_REGISTRAR_DEVOLUCION_COMPRA(
    IN P_ID_DETALLE_COMPRA INT,
    IN P_ID_EMPLEADO INT,
    IN P_CANTIDAD INT,
    IN P_MOTIVO VARCHAR(200),
    IN P_CONDICION_PRODUCTO ENUM('BUENO', 'DANADO', 'USADO'),
    OUT P_ID_DEVOLUCION_GENERADO INT
)
proc_label: BEGIN
    DECLARE V_ID_COMPRA INT;
    DECLARE V_ESTADO_COMPRA VARCHAR(20);
    DECLARE V_CANTIDAD_COMPRADA INT;
    DECLARE V_PRECIO_UNITARIO DECIMAL(10, 2);
    DECLARE V_YA_DEVUELTA INT;
    -- (21/11/2026) ITBIS devuelto: se prorratea desde la linea de compra
    -- guardada, igual que la ganancia en la devolucion de venta. Con un
    -- producto exento (MONTO_ITBIS = 0) recalcularlo con la tasa vigente
    -- inventaria un credito fiscal que el suplidor no cobro.
    DECLARE V_ITBIS_LINEA DECIMAL(10, 2);
    DECLARE V_ITBIS_DEVUELTO DECIMAL(10, 2);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
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

    -- 1. Cantidad valida
    IF IFNULL(P_CANTIDAD, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 2. El empleado debe existir
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. El detalle debe existir (trae compra, cantidad, precio, ITBIS y estado)
    SELECT DC.ID_COMPRA, DC.CANTIDAD, DC.PRECIO_UNITARIO, IFNULL(DC.MONTO_ITBIS, 0), C.ESTADO
      INTO V_ID_COMPRA, V_CANTIDAD_COMPRADA, V_PRECIO_UNITARIO, V_ITBIS_LINEA, V_ESTADO_COMPRA
      FROM DETALLE_COMPRA DC
      JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
     -- BLINDAJE (07/10/2026): FOR UPDATE congela el detalle y la compra
     -- para que dos devoluciones a la vez no pasen juntas la validacion
     -- del paso 5 (evita devolver de mas por carrera).
     -- WHERE DC.ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA;
     WHERE DC.ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA
       FOR UPDATE;

    IF V_ID_COMPRA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DETALLE DE LA COMPRA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 4. Solo se devuelve de una compra RECIBIDA (de una ABIERTA se cancela,
    --    de una CANCELADA o DEVUELTA ya no hay nada que devolver)
    IF V_ESTADO_COMPRA <> 'RECIBIDA' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA COMPRA NO ESTA RECIBIDA; SOLO SE DEVUELVE MERCANCIA DE UNA COMPRA RECIBIDA.';
        LEAVE proc_label;
    END IF;

    -- 5. No devolver de mas: lo pendiente ya cuenta contra lo comprado
    SELECT IFNULL(SUM(CANTIDAD), 0) INTO V_YA_DEVUELTA
      FROM DEVOLUCION_COMPRA
     WHERE ID_DETALLE_COMPRA = P_ID_DETALLE_COMPRA
       AND ESTADO IN ('PENDIENTE', 'PROCESADA');

    IF P_CANTIDAD > (V_CANTIDAD_COMPRADA - V_YA_DEVUELTA) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD SUPERA LO COMPRADO (YA HAY DEVOLUCIONES REGISTRADAS DE ESTE PRODUCTO).';
        LEAVE proc_label;
    END IF;

    -- 6. Guarda la devolucion pendiente con su subtotal al dia de hoy
    -- (21/11/2026) El ITBIS sale de la linea guardada (foto historica), no de la
    -- tasa vigente: con un producto exento (MONTO_ITBIS = 0) la devolucion
    -- devolvia un credito fiscal que el suplidor nunca cobro.
    SET V_ITBIS_DEVUELTO = ROUND(V_ITBIS_LINEA * P_CANTIDAD / V_CANTIDAD_COMPRADA, 2);
    INSERT INTO DEVOLUCION_COMPRA
        (ID_DETALLE_COMPRA, ID_EMPLEADO, CANTIDAD, MOTIVO, CONDICION_PRODUCTO, SUBTOTAL_DEVUELTO, MONTO_ITBIS_DEVUELTO)
    VALUES
        (P_ID_DETALLE_COMPRA, P_ID_EMPLEADO, P_CANTIDAD, P_MOTIVO, P_CONDICION_PRODUCTO,
         P_CANTIDAD * V_PRECIO_UNITARIO, V_ITBIS_DEVUELTO);

    SET P_ID_DEVOLUCION_GENERADO = LAST_INSERT_ID();

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_GENERADO,
                  ' REGISTRADA (PENDIENTE).') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PROCESAR_DEVOLUCION_COMPRA ;
/*
SP_PROCESAR_DEVOLUCION_COMPRA
Cierra una devolucion pendiente: PROCESADA devuelve la mercancia al
proveedor (baja stock, anota SALIDA + historial, baja el TOTAL y deja la
compra DEVUELTA si se devolvio todo); RECHAZADA no toca efectos (stock, total ni bitacora) pero si
anota el motivo del rechazo en MOTIVO encima del motivo original
(P12C). Valida que
exista y que siga PENDIENTE; los efectos los hace
TR_PROCESAR_DEVOLUCION_COMPRA, que tambien valen en un UPDATE directo.
*/
-- P12C (07/10/2026): el rechazo no dejaba rastro del por que; ahora el
-- SP acepta el motivo del rechazo y lo anota en MOTIVO encima del motivo
-- original. Los llamados pasan NULL explicito si no hay motivo
-- (MariaDB no admite DEFAULT en parametros de procedures).
-- CREATE PROCEDURE SP_PROCESAR_DEVOLUCION_COMPRA(
--     IN P_ID_DEVOLUCION_COMPRA INT,
--     IN P_NUEVO_ESTADO ENUM('PROCESADA', 'RECHAZADA')
-- )
CREATE PROCEDURE SP_PROCESAR_DEVOLUCION_COMPRA(
    IN P_ID_DEVOLUCION_COMPRA INT,
    IN P_NUEVO_ESTADO ENUM('PROCESADA', 'RECHAZADA'),
    IN P_MOTIVO_RECHAZO VARCHAR(200)
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- Transaccion propia: si nadie la abrio antes, la abre y la cierra
    -- este SP; si venimos de adentro de otra, no la toca (mismo patron
    -- de la fase I en SP_ANULAR_PAGO_COMPRA).
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

    -- 1. La devolucion debe existir
    -- BLINDAJE (07/10/2026): FOR UPDATE congela la fila; dos procesos
    -- a la vez se serializan y el segundo ve el estado ya cambiado.
    -- SELECT ESTADO INTO V_ESTADO_ACTUAL
    --   FROM DEVOLUCION_COMPRA
    --  WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;
    SELECT ESTADO INTO V_ESTADO_ACTUAL
      FROM DEVOLUCION_COMPRA
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA
       FOR UPDATE;

    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCION NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo se procesa una vez
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA DEVOLUCION YA FUE PROCESADA.';
        LEAVE proc_label;
    END IF;

    -- 3. Cambiar el estado dispara TR_PROCESAR_DEVOLUCION_COMPRA.
    -- P12C (07/10/2026): al rechazar se anota el motivo encima del
    -- original (LEFT: MOTIVO es VARCHAR(200) y la concatenacion no
    -- puede pasarse de largo); a PROCESADA no se le toca el motivo.
    -- UPDATE DEVOLUCION_COMPRA
    --    SET ESTADO = P_NUEVO_ESTADO
    --  WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;
    UPDATE DEVOLUCION_COMPRA
       SET ESTADO = P_NUEVO_ESTADO,
           MOTIVO = CASE
                        WHEN P_NUEVO_ESTADO = 'RECHAZADA' THEN
                            LEFT(CONCAT(IFNULL(CONCAT(MOTIVO, ' | '), ''),
                                        'RECHAZO: ',
                                        IFNULL(P_MOTIVO_RECHAZO, 'NO ESPECIFICADO')),
                                 200)
                        ELSE MOTIVO
                    END
     WHERE ID_DEVOLUCION_COMPRA = P_ID_DEVOLUCION_COMPRA;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: DEVOLUCION #', P_ID_DEVOLUCION_COMPRA, ' ', P_NUEVO_ESTADO, '.') AS MENSAJE;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Trigger TR_PROCESAR_DEVOLUCION_COMPRA: mas abajo en este archivo, junto a su tabla.

-- Trigger TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA: mas abajo en este archivo.

-- Trigger TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA: mas abajo en este archivo.


-- ================================================================
-- DETALLE_COMPRA Y DEVOLUCION_COMPRA (ex modulo 22)
-- ================================================================

/*
SECCION DETALLE_COMPRA Y DEVOLUCION_COMPRA (ex modulo 22)
Lineas de compra, devoluciones al proveedor, costo vigente y los triggers que
mueven stock, totales y costos. La cabecera COMPRAS, el historial de estados y
los pagos estan mas arriba en este mismo archivo.
Todo lo que vivia en 22-DETALLE_COMPRA.sql esta aca, en el mismo orden, con sus
FOLLOWS intactos: TR_CALCULAR_TOTAL_COMPRA -> TR_ACTUALIZAR_STOCK_COMPRA ->
TR_AUDITORIA_MOVIMIENTO_COMPRA -> TR_ACTUALIZAR_COSTO_COMPRA, y sus pares de
borrado.
*/

CREATE TABLE DETALLE_COMPRA (
    ID_DETALLE_COMPRA INT NOT NULL AUTO_INCREMENT,
    ID_COMPRA INT NOT NULL,
    ID_PRODUCTO INT NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    PRECIO_UNITARIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO_UNITARIO > 0),
    -- En MariaDB usamos STORED para que el valor se guarde físicamente
    SUBTOTAL DECIMAL(10, 2) AS (CANTIDAD * PRECIO_UNITARIO) STORED,
    -- (11/10/2026) ITBIS de la línea con la tasa vigente al registrar
    -- (las generadas no pueden leer CONFIGURACION, lo pone el SP).
    MONTO_ITBIS DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (ID_DETALLE_COMPRA),
    CONSTRAINT UQ_COMPRA_PRODUCTO UNIQUE (ID_COMPRA, ID_PRODUCTO),
    CONSTRAINT FK_DETALLE_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA) ON DELETE CASCADE,
    CONSTRAINT FK_DETALLE_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    -- Trae rapidamente todos los productos que trae una factura de compra.
    INDEX IX_DETALLE_COMPRA_COMPRA (ID_COMPRA),
    -- Sirve para rastrear el historial de precios y compras de un solo producto.
    INDEX IX_DETALLE_COMPRA_PRODUCTO (ID_PRODUCTO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    -- (11/10/2026) ITBIS por línea con tasa vigente.
    -- (13/10/2026) P_PRECIO es el DE FACTURA (con ITBIS): se descuenta.
    DECLARE V_TASA_TXT VARCHAR(100);
    DECLARE V_TASA DECIMAL(5, 2);
    DECLARE V_ITBIS DECIMAL(10, 2);
    DECLARE V_BRUTO_LINEA DECIMAL(12, 2);
    DECLARE V_PRECIO_NETO DECIMAL(10, 2);
    -- (21/11/2026) Exento de ITBIS: si el producto lo esta, el precio escrito
    -- ES el neto (el suplidor no cobra impuesto) y no se desglosa nada.
    DECLARE V_EXENTO TINYINT(1) DEFAULT 0;
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

    -- (21/11/2026) Exencion del producto: decide si el precio escrito es neto.
    SELECT IFNULL(EXENTO_ITBIS, 0) INTO V_EXENTO
      FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

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
    -- (11/10/2026) ITBIS con la tasa vigente (foto histórica por línea).
    SELECT VALOR INTO V_TASA_TXT FROM CONFIGURACION WHERE CLAVE = 'ITBIS';
    IF V_TASA_TXT IS NULL OR V_TASA_TXT + 0 <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.';
        LEAVE proc_label;
    END IF;
    SET V_TASA = V_TASA_TXT + 0;
    -- (21/11/2026) Producto exento: el precio escrito ES el neto y no hay ITBIS
    -- que desglosar. La factura del suplidor de un exento no trae impuesto, asi
    -- que desglosar como si lo trajera inventaria un credito fiscal inexistente.
    IF V_EXENTO = 1 THEN
        SET V_PRECIO_NETO = P_PRECIO;
        SET V_ITBIS = 0.00;
    ELSE
        -- (13/10/2026) La factura del suplidor trae ITBIS incluido: se descuenta.
        SET V_BRUTO_LINEA = P_CANTIDAD * P_PRECIO;
        -- (15/10/2026) El ITBIS absorbe el redondeo: el TOTAL siempre cuadra
        -- al centavo con la factura del suplidor.
        SET V_PRECIO_NETO = ROUND((V_BRUTO_LINEA - ROUND(V_BRUTO_LINEA * V_TASA / (100 + V_TASA), 2)) / P_CANTIDAD, 2);
        SET V_ITBIS = ROUND(V_BRUTO_LINEA - P_CANTIDAD * V_PRECIO_NETO, 2);
    END IF;
    INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
    VALUES (P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO_NETO, V_ITBIS);


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 3. Aviso de margen: si este precio de compra ya alcanza (o pasa)
    --    el precio de venta, se esta comprando a perdida o sin margen
    IF V_PRECIO_NETO >= (SELECT PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
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
    -- (11/10/2026) ITBIS por línea con tasa vigente.
    -- (13/10/2026) P_PRECIO es el DE FACTURA (con ITBIS): se descuenta.
    DECLARE V_TASA_TXT VARCHAR(100);
    DECLARE V_TASA DECIMAL(5, 2);
    DECLARE V_ITBIS DECIMAL(10, 2);
    DECLARE V_BRUTO_LINEA DECIMAL(12, 2);
    DECLARE V_PRECIO_NETO DECIMAL(10, 2);
    -- (21/11/2026) Exento de ITBIS: si el producto lo esta, el precio escrito
    -- ES el neto (el suplidor no cobra impuesto) y no se desglosa nada.
    DECLARE V_EXENTO TINYINT(1) DEFAULT 0;
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

    -- (21/11/2026) Exencion del producto: decide si el precio escrito es neto.
    SELECT IFNULL(EXENTO_ITBIS, 0) INTO V_EXENTO
      FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. Se va la linea vieja: regresa el stock y recalcula el TOTAL
    DELETE FROM DETALLE_COMPRA WHERE ID_DETALLE_COMPRA = V_ID_DETALLE;

    -- 5. Entra la linea nueva: vuelve a sumar stock y TOTAL
    -- (11/10/2026) ITBIS con la tasa vigente (foto histórica por línea).
    SELECT VALOR INTO V_TASA_TXT FROM CONFIGURACION WHERE CLAVE = 'ITBIS';
    IF V_TASA_TXT IS NULL OR V_TASA_TXT + 0 <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.';
        LEAVE proc_label;
    END IF;
    SET V_TASA = V_TASA_TXT + 0;
    -- (21/11/2026) Producto exento: el precio escrito ES el neto, sin ITBIS que
    -- desglosar (misma regla que el alta de linea).
    IF V_EXENTO = 1 THEN
        SET V_PRECIO_NETO = P_PRECIO;
        SET V_ITBIS = 0.00;
    ELSE
        -- (13/10/2026) La factura del suplidor trae ITBIS incluido: se descuenta.
        SET V_BRUTO_LINEA = P_CANTIDAD * P_PRECIO;
        -- (15/10/2026) El ITBIS absorbe el redondeo: el TOTAL siempre cuadra
        -- al centavo con la factura del suplidor.
        SET V_PRECIO_NETO = ROUND((V_BRUTO_LINEA - ROUND(V_BRUTO_LINEA * V_TASA / (100 + V_TASA), 2)) / P_CANTIDAD, 2);
        SET V_ITBIS = ROUND(V_BRUTO_LINEA - P_CANTIDAD * V_PRECIO_NETO, 2);
    END IF;
    INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
    VALUES (P_ID_COMPRA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO_NETO, V_ITBIS);


    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    -- 6. Aviso de margen, igual que al agregar
    IF V_PRECIO_NETO >= (SELECT PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
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
TR_AUDITORIA_MOVIMIENTO_COMPRA (17- INVENTARIO).
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
-- Trigger TR_BLOQUEAR_COMPRA_CERRADA: mas abajo en este archivo, sobre su tabla.
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CERRADA ;
DROP TRIGGER IF EXISTS TR_BLOQUEAR_COMPRA_CANCELADA ;
/*
TR_BLOQUEAR_COMPRA_CERRADA
Una compra que no esta ABIERTA (RECIBIDA o CANCELADA) no acepta mas
productos, ni siquiera con un INSERT directo (misma idea que
TR_BLOQUEAR_VENTA_FINALIZADA en ventas). Si hay que agregar algo despues
de estar saldada, primero se anula el pago que cerro la compra con
SP_ANULAR_PAGO_COMPRA (modulo 19) y vuelve a ABIERTA.
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
-- Trigger TR_BLOQUEAR_UPDATE_DETALLE_COMPRA: mas abajo en este archivo.
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_UPDATE_DETALLE_COMPRA ;
/*
TR_BLOQUEAR_UPDATE_DETALLE_COMPRA
Nadie cambia una linea de compra con UPDATE a pelo: la cantidad y el precio
son la prueba de lo que se acordo con el proveedor. Para corregir algo se
usa SP_MODIFICAR_LINEA_COMPRA (este modulo), o se quita la linea con
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
-- Trigger TR_ACTUALIZAR_STOCK_COMPRA: mas abajo en este archivo.
DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_STOCK_COMPRA ;
/*
TR_ACTUALIZAR_STOCK_COMPRA
Cada vez que entra un producto en una compra, le suma la cantidad al stock.
Si el producto todavia no tiene fila en INVENTARIO, la crea primero
(mismos defaults que SP_RECIBIR_MERCANCIA) y le suma encima; asi nunca
se pierde una entrada por falta de registro en inventario.
(20/10/2026) El orden de los triggers de alta ahora esta declarado con
FOLLOWS: corre despues de TR_CALCULAR_TOTAL_COMPRA.
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_ACTUALIZAR_STOCK_COMPRA
-- AFTER INSERT ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
--     VALUES (NEW.ID_PRODUCTO, NEW.CANTIDAD, 5, 'ALMACEN_PRINCIPAL')
--     ON DUPLICATE KEY UPDATE STOCK_ACTUAL = STOCK_ACTUAL + NEW.CANTIDAD;
-- END //
CREATE TRIGGER TR_ACTUALIZAR_STOCK_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_CALCULAR_TOTAL_COMPRA
BEGIN
    INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
    VALUES (NEW.ID_PRODUCTO, NEW.CANTIDAD, 5, 'ALMACEN_PRINCIPAL')
    ON DUPLICATE KEY UPDATE STOCK_ACTUAL = STOCK_ACTUAL + NEW.CANTIDAD;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_BLOQUEAR_BORRADO_COMPRA_CERRADA: mas abajo en este archivo.
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
-- Trigger TR_ACTUALIZAR_STOCK_BORRADO_COMPRA: mas abajo en este archivo.
DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_STOCK_BORRADO_COMPRA ;
/*
TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
Cuando se quita una linea de una compra, le resta la cantidad al stock
(lo inverso de TR_ACTUALIZAR_STOCK_COMPRA) y en el MISMO trigger anota
la SALIDA en el historial con el stock antes y despues. Van juntos a
proposito: asi el antes/despues sale bien siempre.
(20/10/2026) El orden de los triggers de baja ahora esta declarado con
FOLLOWS: corre despues de TR_RECALCULAR_TOTAL_COMPRA.
El guard de stock y de estado esta en el BEFORE, que corre primero.
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
-- AFTER DELETE ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     DECLARE V_STOCK_ANTES INT;
--     DECLARE V_STOCK_DESPUES INT;
--
--     -- 1. Stock antes de restar
--     SELECT STOCK_ACTUAL INTO V_STOCK_ANTES
--       FROM INVENTARIO WHERE ID_PRODUCTO = OLD.ID_PRODUCTO;
--
--     SET V_STOCK_DESPUES = V_STOCK_ANTES - OLD.CANTIDAD;
--
--     -- 2. Bajar el stock
--     UPDATE INVENTARIO
--        SET STOCK_ACTUAL = V_STOCK_DESPUES
--      WHERE ID_PRODUCTO = OLD.ID_PRODUCTO;
--
--     -- 3. UNA fila de historial con el antes y el despues
--     INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
--         ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
--     ) VALUES (
--         OLD.ID_PRODUCTO, 'SALIDA', OLD.CANTIDAD, V_STOCK_ANTES, V_STOCK_DESPUES,
--         'Producto quitado de la compra'
--     );
-- END //
CREATE TRIGGER TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_RECALCULAR_TOTAL_COMPRA
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
-- Trigger TR_AUDITORIA_MOVIMIENTO_COMPRA: mas abajo en este archivo.
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_MOVIMIENTO_COMPRA ;
/*
TR_AUDITORIA_MOVIMIENTO_COMPRA
Cuando se registra una compra, anota automaticamente la ENTRADA de mercancia.
Toma el empleado de la compra y deja el movimiento con su observacion.
(20/10/2026) El orden de los triggers de alta ahora esta declarado con
FOLLOWS: corre despues de TR_ACTUALIZAR_STOCK_COMPRA.
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_COMPRA
-- AFTER INSERT ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     -- Obtenemos el empleado de la cabecera de la compra para el registro
--     DECLARE V_ID_EMPLEADO INT;
--     SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;
--
--     INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
--     VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'ENTRADA', NEW.CANTIDAD, CONCAT('Compra registrada ID: ', NEW.ID_COMPRA));
-- END //
CREATE TRIGGER TR_AUDITORIA_MOVIMIENTO_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_ACTUALIZAR_STOCK_COMPRA
BEGIN
    -- Obtenemos el empleado de la cabecera de la compra para el registro
    DECLARE V_ID_EMPLEADO INT;
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = NEW.ID_COMPRA;

    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (NEW.ID_PRODUCTO, V_ID_EMPLEADO, 'ENTRADA', NEW.CANTIDAD, CONCAT('Compra registrada ID: ', NEW.ID_COMPRA));
END //

DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_AUDITORIA_BORRADO_COMPRA: mas abajo en este archivo.
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_BORRADO_COMPRA ;

/*
TR_AUDITORIA_BORRADO_COMPRA
Cuando se quita una linea de una compra, anota la SALIDA de esa
mercancia (el stock que se regresa al inventario). El empleado lo toma
de la compra, igual que en la ENTRADA.
(20/10/2026) El orden de los triggers de baja ahora esta declarado con
FOLLOWS: corre despues de TR_ACTUALIZAR_STOCK_BORRADO_COMPRA.
*/
-- Version anterior (20/10/2026): sin orden declarado (dependia del orden
-- accidentado de creacion).
-- CREATE TRIGGER TR_AUDITORIA_BORRADO_COMPRA
-- AFTER DELETE ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     DECLARE V_ID_EMPLEADO INT;
--     SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;
--
--     INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
--     VALUES (OLD.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', OLD.CANTIDAD,
--             CONCAT('Producto quitado de la compra ID: ', OLD.ID_COMPRA));
-- END //
CREATE TRIGGER TR_AUDITORIA_BORRADO_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_ACTUALIZAR_STOCK_BORRADO_COMPRA
BEGIN
    DECLARE V_ID_EMPLEADO INT;
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = OLD.ID_COMPRA;

    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    VALUES (OLD.ID_PRODUCTO, V_ID_EMPLEADO, 'SALIDA', OLD.CANTIDAD,
            CONCAT('Producto quitado de la compra ID: ', OLD.ID_COMPRA));
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-- Tabla DEVOLUCION_COMPRA: vive aca porque requiere DETALLE_COMPRA ya creada.
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
    -- (11/10/2026) ITBIS devuelto con la tasa vigente al registrar.
    MONTO_ITBIS_DEVUELTO DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    ESTADO ENUM('PENDIENTE', 'PROCESADA', 'RECHAZADA') NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_DEVOLUCION_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_DETALLE FOREIGN KEY (ID_DETALLE_COMPRA) REFERENCES DETALLE_COMPRA (ID_DETALLE_COMPRA),
    CONSTRAINT FK_DEVOLUCION_COMPRA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Busca las devoluciones por fecha, igual que las demas tablas de compra, para los
    -- reportes del periodo.
    INDEX IX_DEVOLUCION_COMPRA_FECHA (FECHA),
    -- Trae las devoluciones por estado y fecha: es el de "devoluciones pendientes del
    -- dia". Sin este indice ese reporte recorria la tabla entera (ventas si lo tiene:
    -- IX_DEVOLUCION_ESTADO_FECHA en el archivo 25).
    INDEX IX_DEVOLUCION_COMPRA_ESTADO_FECHA (ESTADO, FECHA)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Deja al dia una BD que ya tenia esta tabla (como la real): le pone el
-- CHECK de que el subtotal nunca sea cero. Un INSERT a pelo con subtotal 0
-- devolveria mercancia sin bajar el TOTAL y la compra nunca llegaria a
-- DEVUELTA. En una BD recien creada el CREATE de arriba ya lo trae.
-- ============================================================
ALTER TABLE DEVOLUCION_COMPRA MODIFY COLUMN SUBTOTAL_DEVUELTO DECIMAL(10, 2) NOT NULL CHECK (SUBTOTAL_DEVUELTO > 0);


-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_PROCESAR_DEVOLUCION_COMPRA: mas abajo en este archivo, junto a su tabla.
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
-- Trigger TR_BLOQUEAR_CAMBIO_DEVOLUCION_COMPRA: mas abajo en este archivo.
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
-- Trigger TR_BLOQUEAR_BORRADO_DEVOLUCION_COMPRA: mas abajo en este archivo.
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
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[COSTO: ultima compra}----------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
-- (20/10/2026) La regla del costo de compra vive en una sola funcion
-- (FN_COSTO_COMPRA_VIGENTE) y la usan todos los triggers que tocan
-- PRODUCTOS.P_COMPRA. Antes cada trigger repetia su propia version de la
-- regla y ninguna miraba si la compra estaba CANCELADA: por eso una compra
-- cancelada dejaba su precio pegado en P_COMPRA (costo fantasma).
DELIMITER //
DROP FUNCTION IF EXISTS FN_COSTO_COMPRA_VIGENTE ;
/*
FN_COSTO_COMPRA_VIGENTE (20/10/2026)
Devuelve el precio de la ultima linea de compra del producto cuya compra NO
esta cancelada. Si el producto no tiene ninguna compra valida, devuelve 0
(nunca se compro: el costo queda en 0 y la ganancia de la venta queda NULL).
Es la unica definicion de la regla del costo de compra: la usan todos los
triggers que tocan PRODUCTOS.P_COMPRA.
*/
CREATE FUNCTION FN_COSTO_COMPRA_VIGENTE(P_ID_PRODUCTO INT)
  RETURNS DECIMAL(10,2)
  DETERMINISTIC
  READS SQL DATA
BEGIN
    DECLARE V_COSTO DECIMAL(10,2);

    SELECT DC.PRECIO_UNITARIO INTO V_COSTO
      FROM DETALLE_COMPRA DC
      INNER JOIN COMPRAS C ON C.ID_COMPRA = DC.ID_COMPRA
     WHERE DC.ID_PRODUCTO = P_ID_PRODUCTO
       AND C.ESTADO <> 'CANCELADA'
     ORDER BY DC.ID_DETALLE_COMPRA DESC
     LIMIT 1;

    RETURN IFNULL(V_COSTO, 0);
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_ACTUALIZAR_COSTO_COMPRA ;
/*
TR_ACTUALIZAR_COSTO_COMPRA (12/10/2026)
Cada linea de compra que entra deja su precio como COSTO del producto
(ultima compra manda). Corre al final (orden por creacion) y solo toca
PRODUCTOS.P_COMPRA: no interfiere con total, stock ni auditoria.
*/
-- Version anterior (20/10/2026): el costo era el precio de la linea que
-- entraba, sin preguntar si su compra estaba cancelada y sin declarar el
-- orden de ejecucion.
-- CREATE TRIGGER TR_ACTUALIZAR_COSTO_COMPRA
-- AFTER INSERT ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     UPDATE PRODUCTOS SET P_COMPRA = NEW.PRECIO_UNITARIO
--      WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
-- END //
/*
TR_ACTUALIZAR_COSTO_COMPRA (20/10/2026)
Cada linea de compra que entra deja su precio como COSTO del producto
(ultima compra manda). Ahora el precio sale de FN_COSTO_COMPRA_VIGENTE (que
ignora las compras canceladas) y el trigger declara su orden: corre despues
de la auditoria del movimiento, igual que antes, pero eso ya no depende del
orden accidentado de creacion.
*/
CREATE TRIGGER TR_ACTUALIZAR_COSTO_COMPRA
AFTER INSERT ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_AUDITORIA_MOVIMIENTO_COMPRA
BEGIN
    UPDATE PRODUCTOS SET P_COMPRA = FN_COSTO_COMPRA_VIGENTE(NEW.ID_PRODUCTO)
     WHERE ID_PRODUCTO = NEW.ID_PRODUCTO;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_COSTO_BORRADO_COMPRA ;
/*
TR_RECALCULAR_COSTO_BORRADO_COMPRA (12/10/2026)
Si se quita la ultima linea comprada, el COSTO vuelve a la compra anterior
que quede (o NULL si nunca se compro). Asi una compra cancelada no deja un
costo fantasma.
*/
-- Version anterior (20/10/2026): tomaba la ultima linea que quedara, aunque
-- su compra estuviera cancelada, y no declaraba su orden de ejecucion.
-- CREATE TRIGGER TR_RECALCULAR_COSTO_BORRADO_COMPRA
-- AFTER DELETE ON DETALLE_COMPRA
-- FOR EACH ROW
-- BEGIN
--     UPDATE PRODUCTOS P SET P_COMPRA = COALESCE((
--         SELECT DC.PRECIO_UNITARIO FROM DETALLE_COMPRA DC
--          WHERE DC.ID_PRODUCTO = OLD.ID_PRODUCTO
--          ORDER BY DC.ID_DETALLE_COMPRA DESC LIMIT 1), 0)
--      WHERE P.ID_PRODUCTO = OLD.ID_PRODUCTO;
-- END //
/*
TR_RECALCULAR_COSTO_BORRADO_COMPRA (20/10/2026)
Si se quita la ultima linea comprada, el COSTO vuelve a la compra VALIDA
anterior (la que no este cancelada), o a 0 si ya no queda ninguna. El precio
sale de FN_COSTO_COMPRA_VIGENTE, la misma regla que usa el resto.
*/
CREATE TRIGGER TR_RECALCULAR_COSTO_BORRADO_COMPRA
AFTER DELETE ON DETALLE_COMPRA
FOR EACH ROW
FOLLOWS TR_AUDITORIA_BORRADO_COMPRA
BEGIN
    UPDATE PRODUCTOS P SET P_COMPRA = FN_COSTO_COMPRA_VIGENTE(OLD.ID_PRODUCTO)
     WHERE P.ID_PRODUCTO = OLD.ID_PRODUCTO;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_COSTO_COMPRA_CANCELADA ;
/*
TR_RECALCULAR_COSTO_COMPRA_CANCELADA (20/10/2026)
Cuando una compra pasa a CANCELADA, el costo de sus productos vuelve al de
la ultima compra VALIDA. Antes el precio de la compra cancelada se quedaba
pegado en PRODUCTOS.P_COMPRA (costo fantasma) y contaminaba la ganancia de
las ventas de ese producto.
Corre despues de TR_CAMBIO_ESTADO_COMPRA (modulo 19) y antes de
TR_MAPA_COMPRA_RECIBIDA (modulo 32).
*/
CREATE TRIGGER TR_RECALCULAR_COSTO_COMPRA_CANCELADA
AFTER UPDATE ON COMPRAS
FOR EACH ROW
FOLLOWS TR_CAMBIO_ESTADO_COMPRA
BEGIN
    IF NEW.ESTADO = 'CANCELADA' AND IFNULL(OLD.ESTADO, '') <> 'CANCELADA' THEN
        UPDATE PRODUCTOS P
           SET P.P_COMPRA = FN_COSTO_COMPRA_VIGENTE(P.ID_PRODUCTO)
         WHERE P.ID_PRODUCTO IN (
               SELECT DC.ID_PRODUCTO
                 FROM DETALLE_COMPRA DC
                WHERE DC.ID_COMPRA = NEW.ID_COMPRA
        );
    END IF;
END //
DELIMITER ;

-- (14/10/2026) Migración para BDs vivas anteriores al 11/10: columnas que
-- ya define el CREATE TABLE de arriba pero faltan donde la tabla ya existía.
ALTER TABLE DETALLE_COMPRA ADD COLUMN IF NOT EXISTS MONTO_ITBIS DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE DEVOLUCION_COMPRA ADD COLUMN IF NOT EXISTS MONTO_ITBIS_DEVUELTO DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
