/*
TABLA LIQUIDACIONES
Guarda las liquidaciones de los empleados que salen: fecha, anos
trabajados, salario base, monto total y motivo (RENUNCIA, DESPIDO,
FIN_CONTRATO o DESAHUCIO). Si se borra el empleado se borran tambien sus
liquidaciones.
*/
CREATE TABLE LIQUIDACIONES (
    ID_LIQUIDACION INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA_LIQUIDACION DATE NOT NULL,
    ANIOS_TRABAJADOS INT,
    SALARIO_BASE DECIMAL(10, 2) NOT NULL,
    MONTO_LIQUIDACION DECIMAL(10, 2) NOT NULL,
    MOTIVO ENUM(
        'RENUNCIA',
        'DESPIDO',
        'FIN_CONTRATO',
        'DESAHUCIO'
    ) NOT NULL,
    OBSERVACION VARCHAR(200),
    PRIMARY KEY (ID_LIQUIDACION),
    CONSTRAINT FK_LIQUIDACION_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
) ENGINE = InnoDB;

-- 1. Para buscar liquidaciones por empleado al instante
/*
INDICE IX_LIQUIDACION_EMPLEADO
Busca al instante todas las liquidaciones de un empleado en especifico,
por ejemplo para revisar su expediente de salida.
*/
CREATE INDEX IX_LIQUIDACION_EMPLEADO ON LIQUIDACIONES (ID_EMPLEADO);

-- 2. Para reportes de gastos por prestaciones laborales en un rango de tiempo
/*
INDICE IX_LIQUIDACION_FECHA
Acelera los reportes de gastos por prestaciones en un rango de tiempo,
que filtran por la fecha de la liquidacion.
*/
CREATE INDEX IX_LIQUIDACION_FECHA ON LIQUIDACIONES (FECHA_LIQUIDACION);

-- 3. Para estadísticas de rotación (Ej: "¿Cuántos se fueron por Renuncia?")
/*
INDICE IX_LIQUIDACION_MOTIVO
Permite contar rapido cuanto se fue por renuncia, despido, fin de
contrato o desahucio, para las estadisticas de rotacion.
*/
CREATE INDEX IX_LIQUIDACION_MOTIVO ON LIQUIDACIONES (MOTIVO);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------                



/*
SP_REGISTRAR_LIQUIDACION
Registra la liquidacion de un empleado y lo deja INACTIVO.
Valida que el empleado este ACTIVO, calcula el monto (salario por anos
trabajados), guarda la liquidacion, apaga al empleado y responde con el
monto procesado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_LIQUIDACION ;
CREATE PROCEDURE SP_REGISTRAR_LIQUIDACION(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA DATE,
    IN P_ANIOS INT,
    IN P_SALARIO DECIMAL(10,2),
    IN P_MOTIVO VARCHAR(20),
    IN P_OBSERVACION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE v_monto DECIMAL(10,2);
    
    -- 1. Validar que el empleado no esté ya liquidado
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO = 'ACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO ESTA ACTIVO O NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Lógica simple de cálculo (puedes ajustarla a la Ley 16-92)
    -- Ejemplo: 1 mes de salario por año trabajado
    SET v_monto = P_SALARIO * P_ANIOS;

    -- 3. Insertar liquidación
    INSERT INTO LIQUIDACIONES (ID_EMPLEADO, FECHA_LIQUIDACION, ANIOS_TRABAJADOS, SALARIO_BASE, MONTO_LIQUIDACION, MOTIVO, OBSERVACION)
    VALUES (P_ID_EMPLEADO, P_FECHA, P_ANIOS, P_SALARIO, v_monto, P_MOTIVO, P_OBSERVACION);

    -- 4. Inactivar al empleado
    UPDATE EMPLEADOS SET ESTADO = 'INACTIVO' WHERE ID_EMPLEADO = P_ID_EMPLEADO;

    SELECT CONCAT('EXITO: LIQUIDACION DE $', v_monto, ' PROCESADA.') AS MENSAJE;
END ;
DELIMITER ;
 

----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------


/*
16_TR_BLOQUEAR_BORRADO_LIQUIDACION
No deja borrar liquidaciones: antes de eliminar cualquier fila manda un
error explicando que por auditoria legal solo se pueden anular o
modificar. Trabaja en automatico.
*/
DELIMITER //

CREATE TRIGGER 16_TR_BLOQUEAR_BORRADO_LIQUIDACION
BEFORE DELETE ON LIQUIDACIONES
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'ERROR: PROHIBIDO BORRAR LIQUIDACIONES. POR AUDITORIA LEGAL, SOLO SE PUEDEN ANULAR O MODIFICAR MEDIANTE SP.';
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 



/*
VISTA_ESTADISTICAS_SALIDAS
Agrupa las liquidaciones por motivo y muestra cuantas salidas hubo de
cada tipo y cuanto costaron en prestaciones.
*/
CREATE OR REPLACE VIEW VISTA_ESTADISTICAS_SALIDAS AS
SELECT 
    MOTIVO, 
    COUNT(*) AS TOTAL_SALIDAS,
    SUM(MONTO_LIQUIDACION) AS COSTO_TOTAL_PRESTACIONES
FROM LIQUIDACIONES
GROUP BY MOTIVO;




/*
VISTA_LIQUIDACIONES_RECIENTES
Lista las liquidaciones de los ultimos 30 dias con el nombre del
empleado, el monto, el motivo y cuantos dias han pasado desde la salida.
*/
CREATE OR REPLACE VIEW VISTA_LIQUIDACIONES_RECIENTES AS
SELECT 
    L.ID_LIQUIDACION,
    E.NOMBRE AS EMPLEADO,
    L.FECHA_LIQUIDACION,
    L.MONTO_LIQUIDACION,
    L.MOTIVO,
    DATEDIFF(CURDATE(), L.FECHA_LIQUIDACION) AS DIAS_DESDE_LIQUIDACION
FROM LIQUIDACIONES L
JOIN EMPLEADOS E ON L.ID_EMPLEADO = E.ID_EMPLEADO
WHERE L.FECHA_LIQUIDACION >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
ORDER BY L.FECHA_LIQUIDACION DESC;