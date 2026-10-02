/*
TABLA HISTORIAL_LABORAL_EMPLEADO
Bitacora del historial laboral: cada vez que cambia el cargo, el salario
o el estado de un empleado, aqui quedan los valores antes y despues, el
tipo de cambio y la fecha. Si se borra el empleado se borra su historial.
*/
CREATE TABLE HISTORIAL_LABORAL_EMPLEADO (
    ID_HISTORIAL_EMPLEADO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    CARGO_ANTERIOR VARCHAR(30) NOT NULL,
    CARGO_NUEVO VARCHAR(30) NOT NULL,
    SALARIO_ANTERIOR DECIMAL(10, 2) NOT NULL,
    SALARIO_NUEVO DECIMAL(10, 2) NOT NULL,
    TIPO_CAMBIO ENUM(
        'AUMENTO',
        'PROMOCION',
        'CAMBIO_PUESTO',
        'AJUSTE'
    ) NOT NULL,
    ESTADO_ANTERIOR VARCHAR(20),
    ESTADO_NUEVO VARCHAR(20),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    OBSERVACION VARCHAR(280),
    PRIMARY KEY (ID_HISTORIAL_EMPLEADO),
    CONSTRAINT FK_HISTORIAL_EMPLEADO_REF FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
) ENGINE = InnoDB;

-- Índices para búsquedas rápidas por empleado, fecha o tipo de cambio


/*
INDICE IX_HISTORIAL_EMPLEADO_ID
Encuentra al instante todo el historial de un empleado en especifico,
ordenado por lo que le ha pasado a lo largo del tiempo.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_ID ON HISTORIAL_LABORAL_EMPLEADO (ID_EMPLEADO);


/*
INDICE IX_HISTORIAL_EMPLEADO_FECHA
Ordena y filtra el historial por fecha de cambio, que es lo que usan los
reportes para ver que paso en un periodo.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_FECHA ON HISTORIAL_LABORAL_EMPLEADO (FECHA_CAMBIO);


/*
INDICE IX_HISTORIAL_EMPLEADO_TIPO
Agrupa y filtra el historial por tipo de cambio (AUMENTO, PROMOCION,
CAMBIO_PUESTO o AJUSTE) para los reportes.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_TIPO ON HISTORIAL_LABORAL_EMPLEADO (TIPO_CAMBIO);

----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

/*
TR_AUDITORIA_PERFIL_EMPLEADO
Vigila la tabla EMPLEADOS: cuando a alguien le cambia el salario, el
cargo o el estado, guarda sola una copia del antes y despues en el
historial. Trabaja en automatico.
*/


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_PERFIL_EMPLEADO ;
CREATE TRIGGER TR_AUDITORIA_PERFIL_EMPLEADO
AFTER UPDATE ON EMPLEADOS
FOR EACH ROW
BEGIN
    -- Comparamos si cambió el salario, el cargo o el estado del empleado
    IF OLD.SALARIO <> NEW.SALARIO OR 
       OLD.CARGO <> NEW.CARGO OR 
       OLD.ESTADO <> NEW.ESTADO THEN
       
        INSERT INTO HISTORIAL_LABORAL_EMPLEADO (
            ID_EMPLEADO, 
            CARGO_ANTERIOR, CARGO_NUEVO, 
            SALARIO_ANTERIOR, SALARIO_NUEVO, -- Corregido de SALARIO_NEW a SALARIO_NUEVO
            ESTADO_ANTERIOR, ESTADO_NUEVO,
            TIPO_CAMBIO, 
            OBSERVACION
        )
        VALUES (
            NEW.ID_EMPLEADO, 
            OLD.CARGO, NEW.CARGO, 
            OLD.SALARIO, NEW.SALARIO, 
            OLD.ESTADO, NEW.ESTADO,
            CASE 
                WHEN NEW.CARGO <> OLD.CARGO THEN 'PROMOCION'
                WHEN NEW.SALARIO > OLD.SALARIO THEN 'AUMENTO'
                WHEN NEW.ESTADO <> OLD.ESTADO THEN 'CAMBIO_PUESTO'
                ELSE 'AJUSTE'
            END,
            CONCAT('Cambio automático: Cargo(', OLD.CARGO, '->', NEW.CARGO, ') Estado(', OLD.ESTADO, '->', NEW.ESTADO, ')')
        );
    END IF;
END ;
DELIMITER ;

SELECT * FROM `HISTORIAL_LABORAL_EMPLEADO`