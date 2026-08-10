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

-- 1. Para ver la evolución de un empleado específico rápido
CREATE INDEX IX_HISTORIAL_EMPLEADO_ID ON HISTORIAL_LABORAL_EMPLEADO (ID_EMPLEADO);

-- 2. Para reportes anuales o mensuales de gastos en sueldos
CREATE INDEX IX_HISTORIAL_EMPLEADO_FECHA ON HISTORIAL_LABORAL_EMPLEADO (FECHA_CAMBIO);

-- 3. Para ver qué tanto estamos promoviendo vs solo ajustando sueldos
CREATE INDEX IX_HISTORIAL_EMPLEADO_TIPO ON HISTORIAL_LABORAL_EMPLEADO (TIPO_CAMBIO);

----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_PERFIL_EMPLEADO ;
CREATE TRIGGER TR_AUDITORIA_PERFIL_EMPLEADO
AFTER UPDATE ON EMPLEADOS
FOR EACH ROW
BEGIN
    -- Comparamos si cambió cualquier campo relevante
    IF OLD.SALARIO <> NEW.SALARIO OR 
       OLD.CARGO <> NEW.CARGO OR 
       OLD.ESTADO <> NEW.ESTADO THEN
       
        INSERT INTO HISTORIAL_LABORAL_EMPLEADO (
            ID_EMPLEADO, 
            CARGO_ANTERIOR, CARGO_NUEVO, 
            SALARIO_ANTERIOR, SALARIO_NEW, 
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
                WHEN NEW.ESTADO <> OLD.ESTADO THEN 'CAMBIO_PUESTO' -- O 'AJUSTE' según prefieras
                ELSE 'AJUSTE'
            END,
            CONCAT('Cambio automático: Cargo(', OLD.CARGO, '->', NEW.CARGO, ') Estado(', OLD.ESTADO, '->', NEW.ESTADO, ')')
        );
    END IF;
END ;
DELIMITER ;

SELECT * FROM `HISTORIAL_LABORAL_EMPLEADO`