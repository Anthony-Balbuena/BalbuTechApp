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
    CONSTRAINT CK_HIST_ESTADO_NUEVO CHECK (ESTADO_NUEVO IN ('ABIERTA', 'RECIBIDA', 'CANCELADA', 'DEVUELTA'))
) ENGINE = InnoDB;
-- Migracion para BDs ya creadas con VARCHAR(20): unifica al ENUM (re-ejecutable).
ALTER TABLE HISTORIAL_ESTADOS_COMPRA
    MODIFY COLUMN ESTADO_ANTERIOR ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NULL,
    MODIFY COLUMN ESTADO_NUEVO ENUM('ABIERTA','RECIBIDA','CANCELADA','DEVUELTA') NOT NULL;

/*
INDICE IX_HIST_ESTADO_FECHA
Trae el historial de estados por fecha para los reportes (por compra
ya lo cubre el FK).
*/
CREATE INDEX IX_HIST_ESTADO_FECHA ON HISTORIAL_ESTADOS_COMPRA (FECHA);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGGER}--------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

-- Trigger TR_HISTORIAL_ESTADO_COMPRA movido a 19 (su tabla).

-- Trigger TR_CAMBIO_ESTADO_COMPRA movido a 19 (su tabla).
