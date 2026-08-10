CREATE TABLE BONOS_EMPLEADOS (
    ID_BONO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL,
    TIPO_BONO ENUM(
        'DOBLE_SUELDO',
        'HORAS_EXTRA',
        'BONIFICACION'
    ) NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    DESCRIPCION VARCHAR(200),
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_BONO),
    CONSTRAINT FK_BONO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- 1. Para ver todos los bonos que ha recibido un empleado en su carrera
CREATE INDEX IX_BONO_EMPLEADO ON BONOS_EMPLEADOS (ID_EMPLEADO);

-- 2. Para reportes contables por mes o año (Ej: "Total pagado en bonos en 2026")
CREATE INDEX IX_BONO_FECHA ON BONOS_EMPLEADOS (FECHA);

-- 3. Para estadísticas (Ej: "¿Cuánto hemos gastado solo en Horas Extra?")
CREATE INDEX IX_BONO_TIPO ON BONOS_EMPLEADOS (TIPO_BONO);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

--INSERTAR

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_BONO ;
CREATE PROCEDURE SP_REGISTRAR_BONO(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA DATE,
    IN P_TIPO_BONO VARCHAR(20),
    IN P_MONTO DECIMAL(10,2),
    IN P_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE v_nombre_empleado VARCHAR(100);

    -- 1. Validar existencia y obtener el nombre al mismo tiempo
    SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;

    IF v_nombre_empleado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar monto
    IF P_MONTO > 100000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.';
        LEAVE proc_label;
    END IF;
 
    -- 3. Insertar
    INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
    VALUES (P_ID_EMPLEADO, P_FECHA, P_TIPO_BONO, P_MONTO, P_DESCRIPCION);

    -- 4. Mensaje con ID y Nombre para confirmación total
    SELECT CONCAT('EXITO: BONO DE $', P_MONTO, ' REGISTRADO A: ', v_nombre_empleado, ' (ID: ', P_ID_EMPLEADO, ').') AS MENSAJE;
END ;
DELIMITER ;

---ACTUALIZAR
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_BONO //
CREATE PROCEDURE SP_ACTUALIZAR_BONO(
    IN P_ID_BONO INT,
    IN P_NUEVO_MONTO DECIMAL(10,2),
    IN P_NUEVA_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Validar si el bono existe
    IF NOT EXISTS (SELECT 1 FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: BONO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Aplicar actualización
    UPDATE BONOS_EMPLEADOS 
    SET MONTO = P_NUEVO_MONTO,
        DESCRIPCION = P_NUEVA_DESCRIPCION
    WHERE ID_BONO = P_ID_BONO;

    SELECT 'EXITO: BONO ACTUALIZADO CORRECTAMENTE.' AS MENSAJE;
END //
DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS SP_ELIMINAR_BONO //
CREATE PROCEDURE SP_ELIMINAR_BONO(
    IN P_ID_BONO INT,
    IN P_MOTIVO_ELIMINACION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Verificar si existe
    IF NOT EXISTS (SELECT 1 FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: BONO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Insertar en log de respaldo antes de borrar
    INSERT INTO AUDITORIA_BONOS (ID_BONO, ACCION, MONTO_ANTERIOR, USUARIO_DB)
    SELECT ID_BONO, 'BORRADO', MONTO, USER() 
    FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    -- 3. Borrar registro
    DELETE FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    SELECT CONCAT('EXITO: BONO ', P_ID_BONO, ' ELIMINADO. MOTIVO: ', P_MOTIVO_ELIMINACION) AS MENSAJE;
END //
DELIMITER ;




----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------
DELIMITER //
CREATE TRIGGER 14_TR_VALIDAR_FECHA_BONO
BEFORE INSERT ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN
    -- No permitir bonos con fechas de más de 30 días atrás
    IF NEW.FECHA < DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 30 DÍAS.';
    END IF;
END //
DELIMITER ;

----BONO POR VENTA 
DELIMITER //

DROP TRIGGER IF EXISTS TR_CALCULAR_BONO_VENTA ;

CREATE TRIGGER TR_CALCULAR_BONO_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;
    
    -- Obtenemos el empleado de la tabla VENTAS
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- Usamos la tabla BONOS_EMPLEADOS según tu estructura
    INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, MONTO, MOTIVO, FECHA_BONO)
    VALUES (V_ID_EMPLEADO, (NEW.SUBTOTAL * 0.01), 'Comisión por venta', CURRENT_DATE);
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


CREATE OR REPLACE VIEW VISTA_TOTAL_BONOS_POR_EMPLEADO AS
SELECT 
    E.ID_EMPLEADO,
    E.NOMBRE,
    SUM(B.MONTO) AS TOTAL_BONIFICADO,
    COUNT(B.ID_BONO) AS CANTIDAD_BONOS
FROM EMPLEADOS E
LEFT JOIN BONOS_EMPLEADOS B ON E.ID_EMPLEADO = B.ID_EMPLEADO
GROUP BY E.ID_EMPLEADO;