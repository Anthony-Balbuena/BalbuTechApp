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

/*
TABLA HISTORIAL_ESTADOS_VENTA
Un renglon por cada vez que una venta cambia de estado: quien fue, cuando
y hacia donde paso. El primer renglon (sin estado anterior) se escribe
solo al nacer la venta; los demas los ponen los triggers de cambio.
*/
CREATE TABLE HISTORIAL_ESTADOS_VENTA (
    ID_HISTORIAL_ESTADO INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ESTADO_ANTERIOR ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA') NULL,
    ESTADO_NUEVO ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA') NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    MOTIVO VARCHAR(100) NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_HISTORIAL_ESTADO),
    CONSTRAINT FK_HIST_ESTADO_VENTA FOREIGN KEY (ID_VENTA) REFERENCES VENTAS (ID_VENTA),
    CONSTRAINT FK_HIST_ESTADO_VTA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- (09/10/2026) CHECKs: el historial no admite estados inventados (solo los del ENUM de VENTAS).
    CONSTRAINT CK_HIST_VENTA_ANTERIOR CHECK (ESTADO_ANTERIOR IS NULL OR ESTADO_ANTERIOR IN ('REALIZADA', 'EN_PROCESO', 'CANCELADA', 'DEVUELTA')),
    CONSTRAINT CK_HIST_VENTA_NUEVO CHECK (ESTADO_NUEVO IN ('REALIZADA', 'EN_PROCESO', 'CANCELADA', 'DEVUELTA'))
) ENGINE = InnoDB;
-- Migracion para BDs ya creadas con VARCHAR(20): unifica al ENUM (re-ejecutable).
ALTER TABLE HISTORIAL_ESTADOS_VENTA
    MODIFY COLUMN ESTADO_ANTERIOR ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA') NULL,
    MODIFY COLUMN ESTADO_NUEVO ENUM('REALIZADA','EN_PROCESO','CANCELADA','DEVUELTA') NOT NULL;

/*
INDICE IX_HIST_ESTADO_VENTA_FECHA
Trae el historial de estados por fecha para los reportes (por venta
ya lo cubre el FK).
*/
CREATE INDEX IX_HIST_ESTADO_VENTA_FECHA ON HISTORIAL_ESTADOS_VENTA (FECHA);

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
(seccion DETALLES_VENTA de este archivo) pero sin validar que el empleado sea el dueño de la venta.
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
DROP PROCEDURE IF EXISTS SP_HISTORIAL_VENTA ;
/*
SP_HISTORIAL_VENTA (14/10/2026)
Historial de estados de una venta, del mas nuevo al mas viejo. Solo lectura.

(07/11/2026) P_ID_VENTA = 0 lista el historial de todas las ventas: la UI
pide "ID venta o Enter para ver todas". Se agrega ID_VENTA a la salida para
poder distinguir las filas cuando se listan todas; con un ID puntual el
resultado es el mismo de antes.
*/
CREATE PROCEDURE SP_HISTORIAL_VENTA(IN P_ID_VENTA INT)
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_HISTORIAL_VENTA');
    SELECT H.ID_VENTA, H.FECHA, H.ESTADO_ANTERIOR, H.ESTADO_NUEVO,
           E.NOMBRE AS EMPLEADO, H.MOTIVO
      FROM HISTORIAL_ESTADOS_VENTA H
      JOIN EMPLEADOS E ON E.ID_EMPLEADO = H.ID_EMPLEADO
     WHERE (P_ID_VENTA = 0 OR H.ID_VENTA = P_ID_VENTA)
     ORDER BY H.ID_HISTORIAL_ESTADO DESC;
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
Estos dos triggers hacian lo mismo que TR_ACTUALIZAR_TOTAL_VENTA (este archivo) y
TR_AUDITORIA_MOVIMIENTO_VENTA (21), asi que el total y el stock se
aplicaban dos veces. Solo queda el DROP para limpiar bases viejas.
*/
DROP TRIGGER IF EXISTS TR_CALCULAR_TOTAL_VENTA ;
DROP TRIGGER IF EXISTS TR_PROCESAR_VENTA ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_HISTORIAL_ESTADO_VENTA ;
/*
TR_HISTORIAL_ESTADO_VENTA
Cuando nace una venta deja su primera fila en el historial de estados
(EN_PROCESO, con el empleado que la atendio). Solo registra el
nacimiento: los cambios de ahi en adelante los anota
TR_CAMBIO_ESTADO_VENTA.
*/
CREATE TRIGGER TR_HISTORIAL_ESTADO_VENTA
AFTER INSERT ON VENTAS
FOR EACH ROW
BEGIN
    INSERT INTO HISTORIAL_ESTADOS_VENTA
        (ID_VENTA, ESTADO_ANTERIOR, ESTADO_NUEVO, ID_EMPLEADO, MOTIVO)
    VALUES
        (NEW.ID_VENTA, NULL, NEW.ESTADO, NEW.ID_EMPLEADO, 'Venta iniciada');
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_CAMBIO_ESTADO_VENTA ;
/*
TR_CAMBIO_ESTADO_VENTA
Cada vez que una venta cambia de estado (realizada, cancelada o
devuelta) anota una fila con el antes y el despues en
HISTORIAL_ESTADOS_VENTA. Si el estado no cambia no anota nada y
tambien vale si alguien lo cambia con un UPDATE directo. El empleado
es el dueno de la venta.
*/
CREATE TRIGGER TR_CAMBIO_ESTADO_VENTA
AFTER UPDATE ON VENTAS
FOR EACH ROW
BEGIN
    IF NEW.ESTADO <> OLD.ESTADO THEN
        INSERT INTO HISTORIAL_ESTADOS_VENTA
            (ID_VENTA, ESTADO_ANTERIOR, ESTADO_NUEVO, ID_EMPLEADO, MOTIVO)
        VALUES
            (NEW.ID_VENTA, OLD.ESTADO, NEW.ESTADO, NEW.ID_EMPLEADO,
             CONCAT('Estado: ', OLD.ESTADO, ' -> ', NEW.ESTADO));
    END IF;
END //
DELIMITER ;

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
TR_ACTUALIZAR_TOTAL_VENTA (este archivo). RIESGO VIGILADO: el par SET 1/0 no
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
    DECLARE V_BRUTO DECIMAL(12, 2);

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
            -- Solo se marca REALIZADA una venta cobrada al 100% de su
            -- BRUTO neto (29/10/2026: descuenta las devoluciones).
            SELECT IFNULL(SUM(MONTO), 0) INTO V_COBRADO
              FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;
            SELECT BRUTO_NETO INTO V_BRUTO
              FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;
            IF OLD.ESTADO <> 'EN_PROCESO' OR V_BRUTO <= 0 OR V_COBRADO < V_BRUTO THEN
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
-- Vista VISTA_DETALLE_VENTA: mas abajo en este archivo.

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


-- ================================================================
-- DETALLES_VENTA (ex modulo 23)
-- ================================================================

/*
SECCION DETALLES_VENTA (ex modulo 23)
Lineas de venta con descuento por linea y los triggers que mueven stock y
totales. La cabecera VENTAS y el historial de estados estan mas arriba en este
mismo archivo.
Todo lo que vivia en 23- DETALLE_VENTA.sql esta aca, en el mismo orden, con sus
FOLLOWS intactos: TR_AUDITORIA_MOVIMIENTO_VENTA -> TR_ACTUALIZAR_TOTAL_VENTA.
*/
 
CREATE TABLE DETALLES_VENTA (
    ID_DETALLE_VENTA INT NOT NULL AUTO_INCREMENT,
    ID_VENTA INT NOT NULL,
    ID_PRODUCTO INT NOT NULL,
    CANTIDAD INT NOT NULL CHECK (CANTIDAD > 0),
    PRECIO_UNITARIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO_UNITARIO > 0),
    -- (16/10/2026) Descuento de la línea en % (0 = sin descuento).
    PORCENTAJE_DESCUENTO DECIMAL(5, 2) NOT NULL DEFAULT 0.00 CHECK (PORCENTAJE_DESCUENTO BETWEEN 0 AND 100),
    SUBTOTAL DECIMAL(10, 2) GENERATED ALWAYS AS (ROUND(CANTIDAD * PRECIO_UNITARIO * (1 - PORCENTAJE_DESCUENTO / 100), 2)) STORED,
    -- (11/10/2026) ITBIS de la línea con la tasa vigente al registrar.
    MONTO_ITBIS DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    -- (12/10/2026) Ganancia snapshot: (precio - costo) x cantidad al vender.
    -- NULL = costo desconocido (nunca comprado), no se inventa.
    MONTO_GANANCIA DECIMAL(10, 2) NULL,
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
numero viejo. La garantia de verdad vive en el archivo 21: el descuento
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
    IN P_ID_EMPLEADO INT,
    IN P_DESCUENTO_PCT DECIMAL(5, 2) -- (16/10/2026) % de descuento de la línea; (19/10/2026) sin DEFAULT 0.00: el server 10.11 no soporta DEFAULT en parametros
)
proc_label: BEGIN
    DECLARE V_PRECIO DECIMAL(10, 2);
    DECLARE V_STOCK_DISPONIBLE INT;
    DECLARE V_ID_VENTA_EMPLEADO INT;
    -- (11/10/2026) ITBIS por línea con tasa vigente.
    DECLARE V_TASA_TXT VARCHAR(100);
    DECLARE V_TASA DECIMAL(5, 2);
    DECLARE V_ITBIS DECIMAL(10, 2);
    -- (12/10/2026) Ganancia snapshot con el costo vigente al vender.
    DECLARE V_COSTO DECIMAL(10, 2);
    DECLARE V_GANANCIA DECIMAL(10, 2);

    -- P10 (06/10/2026): traduce el ERROR 1020 de una carrera en el
    -- descuento de stock (trigger del archivo 21) a mensaje amigable.
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
    -- (09/10/2026) V4. NULL burlaba el <> (da NULL y pasa): se rechaza antes.
    IF P_ID_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;
    IF V_ID_VENTA_EMPLEADO <> P_ID_EMPLEADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO COINCIDE CON EL DE LA VENTA.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) V4. Cantidad invalida (NULL/0/negativa pasaba el stock y reventaba 1048).
    IF IFNULL(P_CANTIDAD, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- (16/10/2026) Descuento: NULL cuenta como 0; fuera de 0-100 se corta amable.
    IF IFNULL(P_DESCUENTO_PCT, 0) < 0 OR P_DESCUENTO_PCT > 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DESCUENTO DEBE ESTAR ENTRE 0 Y 100.';
        LEAVE proc_label;
    END IF;

    -- 2. Obtener precio (antes que el stock: un producto inexistente no
    -- tiene fila y el mensaje debe decirlo, no "STOCK INSUFICIENTE")
    SELECT PRECIO INTO V_PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- (09/10/2026) V4. Producto inexistente (NULL reventaba 1048).
    IF V_PRECIO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- (15/11/2026) Un repuesto de garantia NO se vende: es un producto con su
    -- propio CODIGO, guardado para reparar. Esta es la guarda fuerte (la pantalla
    -- solo lo esconde); sin ella un vendedor lo vende y la reparacion se queda sin
    -- pieza. Va antes del stock para que el mensaje diga la verdad.
    IF EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO AND ES_REPUESTO = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESE PRODUCTO ES UN REPUESTO DE GARANTIA Y NO SE VENDE.';
        LEAVE proc_label;
    END IF;

    -- 3. Validar stock (si el producto no esta en INVENTARIO, cuenta como 0)
    SELECT STOCK_ACTUAL INTO V_STOCK_DISPONIBLE FROM INVENTARIO WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    IF IFNULL(V_STOCK_DISPONIBLE, 0) < P_CANTIDAD THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: STOCK INSUFICIENTE.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) V4. Duplicado en la misma venta (1062 del UQ_VENTA_PRODUCTO).
    IF EXISTS (SELECT 1 FROM DETALLES_VENTA WHERE ID_VENTA = P_ID_VENTA AND ID_PRODUCTO = P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO YA ESTA EN ESTA VENTA.';
        LEAVE proc_label;
    END IF;

    -- 4. Insertar
    -- (11/10/2026) ITBIS con la tasa vigente (foto histórica por línea).
    SELECT VALOR INTO V_TASA_TXT FROM CONFIGURACION WHERE CLAVE = 'ITBIS';
    IF V_TASA_TXT IS NULL OR V_TASA_TXT + 0 <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: FALTA LA TASA ITBIS EN CONFIGURACION.';
        LEAVE proc_label;
    END IF;
    SET V_TASA = V_TASA_TXT + 0;
    -- (16/10/2026) El descuento baja el bruto: el ITBIS sale sobre lo cobrado.
    SET V_ITBIS = ROUND(ROUND(P_CANTIDAD * V_PRECIO * (1 - IFNULL(P_DESCUENTO_PCT, 0) / 100), 2) * V_TASA / 100, 2);
    -- (12/10/2026) Si nunca se compro (P_COMPRA 0 = pendiente), la ganancia queda NULL.
    SELECT P_COMPRA INTO V_COSTO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;
    IF V_COSTO IS NULL OR V_COSTO = 0 THEN
        SET V_GANANCIA = NULL;
    ELSE
        -- (16/10/2026) La ganancia tambien descuenta: bruto con descuento menos costo.
        SET V_GANANCIA = ROUND(ROUND(P_CANTIDAD * V_PRECIO * (1 - IFNULL(P_DESCUENTO_PCT, 0) / 100), 2) - P_CANTIDAD * V_COSTO, 2);
    END IF;
    INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, PORCENTAJE_DESCUENTO, MONTO_ITBIS, MONTO_GANANCIA)
    VALUES (P_ID_VENTA, P_ID_PRODUCTO, P_CANTIDAD, V_PRECIO, IFNULL(P_DESCUENTO_PCT, 0), V_ITBIS, V_GANANCIA);

    SELECT 'EXITO: PRODUCTO AGREGADO CORRECTAMENTE.' AS MENSAJE;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


-- Trigger TR_AUDITORIA_MOVIMIENTO_VENTA: mas abajo en este archivo.
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

    -- (09/10/2026) V4. Venta inexistente (NULL pasaba y reventaba 1452).
    IF V_ESTADO IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO EXISTE.';
    END IF;
    
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
descuento condicional del archivo 21 (o el ERROR 1020 del servidor). Sea
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


