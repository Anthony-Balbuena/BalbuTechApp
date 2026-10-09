/*
ARCHIVO 21.5 - HISTORIAL_ESTADOS_VENTA
Un renglon por cada vez que una venta cambia de estado: quien fue, cuando
y hacia donde paso. Todo lo de esta tabla vive aqui (tabla, indice y los
dos triggers que la alimentan); en 21- VENTAS.sql solo quedo la venta en
si. Carga despues del 21 y antes del 22.
NOTA (Parte 3, 07/10/2026): orden verificado en
information_schema.TRIGGERS.ACTION_ORDER - en VENTAS el candado
(BEFORE UPDATE) corre ANTES que el historial (AFTER UPDATE), y en
DETALLES_VENTA el AFTER INSERT va stock(20) -> total(23) ->
historial(32). Pruebas: Pruebas/test_blindaje_p3.sql (los 5 candados
responden, la cancelacion deja 2 filas de historial y la bandera
@VENTAS_INTERNO demostrada riesgosa).
*/
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


 -----------------------------------------------------------------------------------------------------------------------
 -----------------------------------------[TRIGERR}---------------------------------------------------------------------
 -----------------------------------------------------------------------------------------------------------------------

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
