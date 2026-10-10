/*
TABLA VENTAS
Cabecera de cada venta: quien la compro, quien la atendio, cuando y cuanto
gasto. El estado indica si esta en proceso, realizada, cancelada o devuelta.
Los productos vendidos van en DETALLES_VENTA.
*/
CREATE TABLE VENTAS (
    ID_VENTA INT NOT NULL AUTO_INCREMENT,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ESTADO ENUM(
        'REALIZADA',
        'EN_PROCESO',
        'CANCELADA',
        'DEVUELTA'
    ) NOT NULL DEFAULT 'EN_PROCESO',
    ID_EMPLEADO INT NOT NULL,
    ID_CLIENTE INT NOT NULL,
    TOTAL DECIMAL(12, 2) NOT NULL CHECK (TOTAL >= 0),
    FACTURA VARCHAR(30) NULL, -- Factura del cliente (opcional, unica por cliente)
    PRIMARY KEY (ID_VENTA),
    CONSTRAINT FK_VENTA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    CONSTRAINT FK_VENTA_CLIENTE FOREIGN KEY (ID_CLIENTE) REFERENCES CLIENTES (ID_CLIENTE)
) ENGINE = InnoDB;

/*
INDICE IX_VENTAS_CLIENTE
Busca todas las ventas de un cliente en concreto,
util para ver su historial de compras.
*/
CREATE INDEX IX_VENTAS_CLIENTE ON VENTAS (ID_CLIENTE);

/*
INDICE IX_VENTAS_EMPLEADO
Busca todas las ventas atendidas por un empleado,
util para reportes de desempeno.
*/
CREATE INDEX IX_VENTAS_EMPLEADO ON VENTAS (ID_EMPLEADO);


/*
INDICE UQ_VENTA_FACTURA
Una factura no se repite dentro del mismo cliente. Tambien lo bloquea el
indice aunque alguien intente el UPDATE a pelo (mismo rol que
UQ_COMPRA_FACTURA).
*/
CREATE UNIQUE INDEX UQ_VENTA_FACTURA ON VENTAS (ID_CLIENTE, FACTURA);

-- La tabla HISTORIAL_ESTADOS_VENTA, su indice y los dos triggers que la
-- alimentan (TR_HISTORIAL_ESTADO_VENTA y TR_CAMBIO_ESTADO_VENTA) se mudaron
-- al archivo 21.5- HISTORIAL_ESTADOS_VENTA.sql.

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS 21_SP_INICIAR_VENTA ;
/*
21_SP_INICIAR_VENTA
Abre una venta nueva en 0 antes de agregarle productos.
Revisa que el empleado y el cliente existan; si algo falla no guarda nada,
y si esta todo bien crea la venta y devuelve su numero de ID.
*/
CREATE PROCEDURE 21_SP_INICIAR_VENTA(
    IN P_ID_EMPLEADO INT,
    IN P_ID_CLIENTE INT,
    OUT P_ID_VENTA_GENERADO INT
)
proc_label: BEGIN
    -- 1. Validaciones
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM CLIENTES WHERE ID_CLIENTE = P_ID_CLIENTE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: CLIENTE NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Inserción
    INSERT INTO VENTAS (ID_EMPLEADO, ID_CLIENTE, TOTAL) 
    VALUES (P_ID_EMPLEADO, P_ID_CLIENTE, 0.00);
    
    SET P_ID_VENTA_GENERADO = LAST_INSERT_ID();

    SELECT CONCAT('EXITO: VENTA #', P_ID_VENTA_GENERADO, ' INICIADA.') AS MENSAJE;

END //
DELIMITER ;



/*
LIMPIEZA DE SP DUPLICADO
21_SP_AGREGAR_PRODUCTO_VENTA hacia lo mismo que SP_AGREGAR_DETALLE_VENTA
(archivo 23) pero sin validar que el empleado sea el dueño de la venta.
Ahora la alta de detalle es solo por ese SP; aqui queda el DROP para
limpiar bases viejas que lo tengan todavia.
*/
DROP PROCEDURE IF EXISTS 21_SP_AGREGAR_PRODUCTO_VENTA ;



DELIMITER //
DROP PROCEDURE IF EXISTS SP_CANCELAR_VENTA ;
/*
SP_CANCELAR_VENTA
Cancela una venta que sigue en proceso y le regresa todo el stock.
Valida que el empleado sea el dueño de la venta y que no tenga pagos;
si todo esta bien devuelve las unidades al inventario, deja el movimiento
de ENTRADA en la bitacora, anota la reposicion en el historial del producto
y deja la venta en estado CANCELADA.
NOTA (Parte 4, 07/10/2026): la cancelacion es una cadena de 5 pasos
que se ejecutan juntos - (3) valida que NO tenga pagos (si tiene, antes
va SP_ANULAR_PAGO), (4) repone el stock, (5) deja ENTRADA en la bitacora,
(6) anota la reposicion en HISTORIAL_MOVIMIENTOS_PRODUCTO y (7) cierra
con la bandera @VENTAS_INTERNO. El paso 3 duplica la regla del candado
TR_VALIDAR_ACTUALIZACION_VENTA pero con mensaje amigable (el candado
tambien exige bandera + EN_PROCESO + cero pagos). Ojo: reponer stock
puede disparar la alerta de stock minimo del trigger del archivo 17.
Es la unica puerta a estado CANCELADA; una venta CANCELADA no tiene
vuelta (candado) y sus pagos quedan blindados por
TR_VALIDAR_BORRADO_PAGO / TR_VALIDAR_UPDATE_PAGO.
P11 (07/10/2026): EXIT HANDLER FOR SQLEXCEPTION apaga la bandera
si algo falla despues de levantarla (ver hallazgo Parte 3).
*/
CREATE PROCEDURE SP_CANCELAR_VENTA(
    IN P_ID_VENTA INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ID_VENTA_EMPLEADO INT;
    DECLARE V_ESTADO VARCHAR(20);
    -- P11 (07/10/2026): si algo falla despues de levantar la bandera,
    -- se apaga aqui antes de propagar el error.
    -- V1 (09/10/2026, patron fase I como SP_CANCELAR_COMPRA): 3 escrituras
    -- atadas + FOR UPDATE contra doble cancel concurrente.
    -- DECLARE EXIT HANDLER FOR SQLEXCEPTION
    -- BEGIN
    --     SET @VENTAS_INTERNO = 0;
    --     RESIGNAL;
    -- END;
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        SET @VENTAS_INTERNO = 0;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;


    -- 1. Validar que la venta exista y sea del empleado
    SELECT ID_EMPLEADO, ESTADO INTO V_ID_VENTA_EMPLEADO, V_ESTADO
    FROM VENTAS
    WHERE ID_VENTA = P_ID_VENTA
    FOR UPDATE;

    IF V_ID_VENTA_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF V_ID_VENTA_EMPLEADO <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.';
        LEAVE proc_label;
    END IF;

    -- 2. Solo se cancelan ventas abiertas
    IF V_ESTADO <> 'EN_PROCESO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN CANCELAR VENTAS EN PROCESO.';
        LEAVE proc_label;
    END IF;

    -- 3. Si ya tiene pagos, primero hay que resolverlos afuera
    IF EXISTS (SELECT 1 FROM PAGOS WHERE ID_VENTA = P_ID_VENTA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA TIENE PAGOS REGISTRADOS, NO SE PUEDE CANCELAR.';
        LEAVE proc_label;
    END IF;

    -- 4. Regresar el stock de cada producto
    UPDATE INVENTARIO I
    JOIN DETALLES_VENTA DV ON DV.ID_PRODUCTO = I.ID_PRODUCTO
    SET I.STOCK_ACTUAL = I.STOCK_ACTUAL + DV.CANTIDAD
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 5. Anotar las entradas en la bitacora
    INSERT INTO MOVIMIENTOS_INVENTARIO (ID_PRODUCTO, ID_EMPLEADO, TIPO_MOVIMIENTO, CANTIDAD, OBSERVACION)
    SELECT DV.ID_PRODUCTO, P_ID_EMPLEADO, 'ENTRADA', DV.CANTIDAD, CONCAT('Venta cancelada ID: ', P_ID_VENTA)
    FROM DETALLES_VENTA DV
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 6. Anotar la reposicion en el historial del producto (stock ya repuesto:
    --    STOCK_ANTERIOR es el actual menos lo que se acaba de devolver)
    INSERT INTO HISTORIAL_MOVIMIENTOS_PRODUCTO (
        ID_PRODUCTO, TIPO_MOVIMIENTO, CANTIDAD, STOCK_ANTERIOR, STOCK_NUEVO, OBSERVACION
    )
    SELECT DV.ID_PRODUCTO, 'ENTRADA', DV.CANTIDAD,
           I.STOCK_ACTUAL - DV.CANTIDAD, I.STOCK_ACTUAL,
           CONCAT('Venta cancelada ID: ', P_ID_VENTA)
    FROM DETALLES_VENTA DV
    JOIN INVENTARIO I ON I.ID_PRODUCTO = DV.ID_PRODUCTO
    WHERE DV.ID_VENTA = P_ID_VENTA;

    -- 7. Cerrar la venta (el candado interno avisa al trigger de validacion
    --    de que esta cancelacion viene de un SP y no de un UPDATE a pelo)
    SET @VENTAS_INTERNO = 1;
    UPDATE VENTAS SET ESTADO = 'CANCELADA' WHERE ID_VENTA = P_ID_VENTA;
    SET @VENTAS_INTERNO = 0;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: VENTA #', P_ID_VENTA, ' CANCELADA Y STOCK RESTITUIDO.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ASIGNAR_FACTURA_VENTA ;
/*
SP_ASIGNAR_FACTURA_VENTA
Le pone numero de factura a una venta (opcional, muchas ventas de
mostrador no llevan). Valida que no venga vacia, que la venta exista y
que no este cancelada ni devuelta, y que esa factura no este ya usada
por otra venta del mismo cliente (el indice UQ_VENTA_FACTURA tambien la
bloquea solo).
*/
CREATE PROCEDURE SP_ASIGNAR_FACTURA_VENTA(
    IN P_ID_VENTA INT,
    IN P_FACTURA VARCHAR(30)
)
proc_label: BEGIN
    DECLARE V_ID_CLIENTE INT;
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_FACTURA_LIMPIA VARCHAR(30);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;

    -- V2 (09/10/2026, espejo de SP_ASIGNAR_FACTURA_COMPRA): transaccion
    -- propia + traduccion del choque con UQ_VENTA_FACTURA (carrera de
    -- 2 sesiones = 1062 tecnico; aqui sale el mensaje amigable).
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE V_ESTADO_SQL CHAR(5) DEFAULT '';

        GET DIAGNOSTICS CONDITION 1 V_ESTADO_SQL = RETURNED_SQLSTATE;

        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;

        IF V_ESTADO_SQL = '23000' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: ESA FACTURA YA EXISTE PARA ESTE CLIENTE.';
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

    -- 2. La venta debe existir
    SELECT ID_CLIENTE, ESTADO INTO V_ID_CLIENTE, V_ESTADO
      FROM VENTAS WHERE ID_VENTA = P_ID_VENTA;

    IF V_ID_CLIENTE IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Una venta cancelada o devuelta ya no tiene factura que llevar
    IF V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA VENTA ESTA CANCELADA O DEVUELTA.';
        LEAVE proc_label;
    END IF;

    -- 4. Esa factura no puede repetirse en el mismo cliente
    IF EXISTS (
        SELECT 1 FROM VENTAS
         WHERE ID_CLIENTE = V_ID_CLIENTE
           AND FACTURA = V_FACTURA_LIMPIA
           AND ID_VENTA <> P_ID_VENTA
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: ESA FACTURA YA EXISTE PARA ESTE CLIENTE.';
        LEAVE proc_label;
    END IF;

    -- 5. Asignar
    UPDATE VENTAS SET FACTURA = V_FACTURA_LIMPIA WHERE ID_VENTA = P_ID_VENTA;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT CONCAT('EXITO: FACTURA ', V_FACTURA_LIMPIA,
                  ' ASIGNADA A LA VENTA #', P_ID_VENTA, '.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_VENTA ;
/*
TR_BLOQUEAR_BORRADO_VENTA
Las ventas tampoco se borran: ahi cuelgan sus lineas, sus pagos, sus
devoluciones y el bono del 1%. Para deshacer una venta se usa
SP_CANCELAR_VENTA, que la deja en CANCELADA con su motivo. Vale tambien
para un DELETE directo sobre VENTAS (el cascade no llega a correr).
*/
CREATE TRIGGER TR_BLOQUEAR_BORRADO_VENTA
BEFORE DELETE ON VENTAS
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.';
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

/*
LIMPIEZA DE TRIGGERS DUPLICADOS
Estos dos triggers hacian lo mismo que TR_ACTUALIZAR_TOTAL_VENTA (23) y
TR_AUDITORIA_MOVIMIENTO_VENTA (20), asi que el total y el stock se
aplicaban dos veces. Solo queda el DROP para limpiar bases viejas.
*/
DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_VENTA ;
DROP TRIGGER IF EXISTS TR_PROCESAR_VENTA ;

-- Los triggers TR_HISTORIAL_ESTADO_VENTA y TR_CAMBIO_ESTADO_VENTA (los que
-- escriben en HISTORIAL_ESTADOS_VENTA) se mudaron al archivo
-- 21.5- HISTORIAL_ESTADOS_VENTA.sql.

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_ACTUALIZACION_VENTA ;
/*
TR_VALIDAR_ACTUALIZACION_VENTA
El candado de la cabecera de la venta: nadie cambia el ESTADO ni el TOTAL
con un UPDATE a pelo. El TOTAL solo lo mueve su trigger de detalle (que
levanta @VENTAS_INTERNO), REALIZADA exige cobro al 100%, CANCELADA solo
sale de SP_CANCELAR_VENTA (asi nadie se salta la reversión del stock) y
DEVUELTA solo cuando no queda ni una unidad por devolver. Una venta ya
CANCELADA o DEVUELTA no vuelve a cambiar jamas.
NOTA (Parte 3, 07/10/2026): resumen del candado - el TOTAL solo se
mueve con la bandera @VENTAS_INTERNO; -> REALIZADA exige cobro al 100%
(por eso el auto-cierre del 24 pasa SIN bandera); -> CANCELADA exige
bandera + EN_PROCESO + cero pagos; CANCELADA/DEVUELTA no salen jamas.
La bandera la levantan solo SP_CANCELAR_VENTA (21) y
TR_ACTUALIZAR_TOTAL_VENTA (23). RIESGO VIGILADO: el par SET 1/0 no
tiene EXIT HANDLER - si el UPDATE interno falla, la credencial queda
prendida en la sesion y, como las variables de usuario no se revierten
con ROLLBACK, un UPDATE a pelo posterior se colaria (demostrado en
Pruebas/test_blindaje_p3.sql). OBSERVACION: la rama 'SOLO SE REABRE
UNA VENTA REALIZADA' es inalcanzable con los 4 estados (pasar de
EN_PROCESO al mismo valor no es cambio; CANCELADA/DEVUELTA las corta
el primer if) - queda como codigo defensivo.
*/
CREATE TRIGGER TR_VALIDAR_ACTUALIZACION_VENTA
BEFORE UPDATE ON VENTAS
FOR EACH ROW
BEGIN
    DECLARE V_COBRADO DECIMAL(12, 2);

    -- El TOTAL solo lo toca TR_ACTUALIZAR_TOTAL_VENTA
    IF NEW.TOTAL <> OLD.TOTAL AND IFNULL(@VENTAS_INTERNO, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL TOTAL DE LA VENTA SOLO CAMBIA CON SU DETALLE.';
    END IF;

    IF NEW.ESTADO <> OLD.ESTADO THEN
        IF OLD.ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA VENTA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA.';
        END IF;

        IF NEW.ESTADO = 'REALIZADA' THEN
            -- Solo se marca REALIZADA una venta cobrada al 100%
            SELECT IFNULL(SUM(MONTO), 0) INTO V_COBRADO
              FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;
            IF OLD.ESTADO <> 'EN_PROCESO' OR NEW.TOTAL <= 0 OR V_COBRADO < NEW.TOTAL THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA REALIZADA UNA VENTA COBRADA AL 100%.';
            END IF;

        ELSEIF NEW.ESTADO = 'EN_PROCESO' THEN
            -- Reapertura: solo de una REALIZADA (se anulo un pago)
            IF OLD.ESTADO <> 'REALIZADA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE REABRE UNA VENTA REALIZADA.';
            END IF;

        ELSEIF NEW.ESTADO = 'CANCELADA' THEN
            -- La cancelacion revierte stock y bitacora: solo por el SP
            IF IFNULL(@VENTAS_INTERNO, 0) <> 1 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: USE SP_CANCELAR_VENTA; LA CANCELACION REVERSIA EL STOCK.';
            END IF;
            IF OLD.ESTADO <> 'EN_PROCESO' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE CANCELA UNA VENTA EN PROCESO.';
            END IF;
            IF EXISTS (SELECT 1 FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA VENTA TIENE PAGOS; ANULELOS ANTES DE CANCELAR.';
            END IF;

        ELSEIF NEW.ESTADO = 'DEVUELTA' THEN
            -- Solo llega devuelta enterita (mismo criterio que
            -- TR_MARCAR_VENTA_DEVUELTA en el archivo 25)
            IF OLD.ESTADO <> 'REALIZADA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA DEVUELTA UNA VENTA REALIZADA.';
            END IF;
            IF EXISTS (
                SELECT 1
                FROM DETALLES_VENTA DV
                WHERE DV.ID_VENTA = NEW.ID_VENTA
                  AND DV.CANTIDAD > IFNULL(
                        (SELECT SUM(D.CANTIDAD)
                           FROM DEVOLUCIONES D
                          WHERE D.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
                            AND D.ESTADO IN ('APROBADA', 'REEMBOLSADA')), 0)
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ESTA DEVUELTA ENTERA; QUEDAN UNIDADES.';
            END IF;

        ELSE
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: ESTADO DE VENTA DESCONOCIDO.';
        END IF;
    END IF;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
VISTA_DETALLE_VENTA
Muestra los productos de cada venta con su cantidad, precio y subtotal.
Trae el nombre del producto en lugar de su ID, lista para ver en pantalla.
*/
-- Vista VISTA_DETALLE_VENTA movida a 23- DETALLE_VENTA.sql.

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------