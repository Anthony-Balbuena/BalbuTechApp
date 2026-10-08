/*
ARCHIVO 19.1 - HISTORIAL_ESTADOS_COMPRA
Un renglon por cada vez que una compra cambia de estado: quien fue, cuando
y hacia donde paso. Todo lo de esta tabla vive aqui (tabla, indice y los
dos triggers que la alimentan); en 19- COMPRAS.sql solo quedo la compra en
si. Carga despues del 19 y antes del 19.5.
NOTA (07/10/2026): extraccion hecha por consistencia con
21.5- HISTORIAL_ESTADOS_VENTA.sql. Orden verificado en
information_schema.TRIGGERS.ACTION_ORDER: en COMPRAS el candado
TR_VALIDAR_ACTUALIZACION_COMPRA (BEFORE UPDATE) corre antes que el historial
TR_CAMBIO_ESTADO_COMPRA (AFTER UPDATE), el nacimiento
TR_HISTORIAL_ESTADO_COMPRA es AFTER INSERT orden 1, y en DETALLE_COMPRA el
AFTER INSERT va stock(1) -> auditoria(2) -> total(3) -> historial(4).
*/
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
    ESTADO_ANTERIOR VARCHAR(20) NULL,
    ESTADO_NUEVO VARCHAR(20) NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    MOTIVO VARCHAR(100) NOT NULL,
    FECHA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_HISTORIAL_ESTADO),
    CONSTRAINT FK_HIST_ESTADO_COMPRA FOREIGN KEY (ID_COMPRA) REFERENCES COMPRAS (ID_COMPRA),
    CONSTRAINT FK_HIST_ESTADO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

/*
INDICE IX_HIST_ESTADO_FECHA
Trae el historial de estados por fecha para los reportes (por compra
ya lo cubre el FK).
*/
CREATE INDEX IX_HIST_ESTADO_FECHA ON HISTORIAL_ESTADOS_COMPRA (FECHA);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGGER}--------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

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
END ;
DELIMITER ;

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
END ;
DELIMITER ;
