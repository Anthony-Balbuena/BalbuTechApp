-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH

/*
TABLA PERMISOS_EMPLEADOS
Guarda los permisos que pide cada empleado: tipo (medico, personal,
estudio, licencia o sin sueldo), rango de fechas y estado (PENDIENTE,
APROBADO o RECHAZADO). No permite fechas invertidas ni permisos que se
cruzen con otro que no este rechazado.
*/
CREATE TABLE PERMISOS_EMPLEADOS (
    ID_PERMISO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    TIPO_PERMISO ENUM(
        'MEDICO',
        'PERSONAL',
        'ESTUDIO',
        'LICENCIA',
        'SIN_SUELDO'
    ) NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    DESCRIPCION VARCHAR(200),
    ESTADO ENUM( 
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO'
    ) NOT NULL DEFAULT 'PENDIENTE',
    FECHA_SOLICITUD TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PERMISO),
    CONSTRAINT CK_PERMISO_FECHAS CHECK (FECHA_FIN >= FECHA_INICIO),
    CONSTRAINT FK_PERMISO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;



-- 1. Para ver todos los permisos de un empleado (Ej: "¿Cuántas veces ha pedido médico?")
/*
INDICE IX_PERMISO_EMPLEADO
Acelera el historial de permisos de un empleado, que es la consulta que
mas se usa para ver cuantas veces ha pedido permiso y de que tipo.
*/
CREATE INDEX IX_PERMISO_EMPLEADO ON PERMISOS_EMPLEADOS (ID_EMPLEADO);

-- 2. Para ver qué permisos están PENDIENTES de aprobar hoy
/*
INDICE IX_PERMISO_ESTADO
Permite filtrar rapidamente los permisos pendientes de aprobar, que es lo
que ve la pantalla del dia a dia.
*/
CREATE INDEX IX_PERMISO_ESTADO ON PERMISOS_EMPLEADOS (ESTADO);

-- 3. Para calendarios de ausencias (Ej: "¿Quiénes no vienen la próxima semana?")
/*
INDICE IX_PERMISO_FECHAS
Acelera los calendarios de ausencias, que buscan por rango de fechas para
saber quien no viene en un periodo.
*/
CREATE INDEX IX_PERMISO_FECHAS ON PERMISOS_EMPLEADOS (FECHA_INICIO, FECHA_FIN);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
SP_SOLICITAR_PERMISO
Pide un permiso nuevo para un empleado.
Valida que el empleado exista, que las fechas no sean retroactivas ni
invertidas y que no se cruce con otro permiso pendiente o aprobado; si
todo esta bien lo guarda y responde con un mensaje de exito.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_SOLICITAR_PERMISO ;
CREATE PROCEDURE SP_SOLICITAR_PERMISO(
    IN P_ID_EMPLEADO INT,
    IN P_TIPO_PERMISO ENUM('MEDICO', 'PERSONAL', 'ESTUDIO', 'LICENCIA', 'SIN_SUELDO'),
    IN P_FECHA_INICIO DATE,
    IN P_FECHA_FIN DATE,
    IN P_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE v_nombre_empleado VARCHAR(100);

    -- 1. VALIDAR EMPLEADO
    SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    IF v_nombre_empleado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN DE FECHAS
    IF P_FECHA_INICIO < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO PUEDES SOLICITAR PERMISOS RETROACTIVOS.';
        LEAVE proc_label;
    END IF;

    -- 3. VALIDACIÓN DE SOLAPAMIENTO (Solo para permisos no rechazados)
    IF EXISTS (
        SELECT 1 FROM PERMISOS_EMPLEADOS 
        WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO <> 'RECHAZADO'
        AND (P_FECHA_INICIO BETWEEN FECHA_INICIO AND FECHA_FIN OR P_FECHA_FIN BETWEEN FECHA_INICIO AND FECHA_FIN)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA TIENES UNA SOLICITUD DE PERMISO PENDIENTE O APROBADA EN ESTAS FECHAS.';
        LEAVE proc_label;
    END IF;

    -- 4. INSERCIÓN
    INSERT INTO PERMISOS_EMPLEADOS (ID_EMPLEADO, TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, DESCRIPCION)
    VALUES (P_ID_EMPLEADO, P_TIPO_PERMISO, P_FECHA_INICIO, P_FECHA_FIN, REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' '));

    SELECT CONCAT('EXITO: SOLICITUD DE PERMISO CREADA PARA "', v_nombre_empleado, '".') AS MENSAJE;
END //
DELIMITER ;

/*
SP_GESTIONAR_PERMISO
Aprueba, rechaza o deja pendiente un permiso existente.
Si el ID no existe manda un error; si existe cambia el estado y confirma
con un mensaje que trae el ID y el nuevo estado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_GESTIONAR_PERMISO ;
CREATE PROCEDURE SP_GESTIONAR_PERMISO(
    IN P_ID_PERMISO INT,
    IN P_NUEVO_ESTADO ENUM('PENDIENTE', 'APROBADO','RECHAZADO')
)
proc_label: BEGIN
    -- 1. VALIDAR EXISTENCIA
    IF NOT EXISTS (SELECT 1 FROM PERMISOS_EMPLEADOS WHERE ID_PERMISO = P_ID_PERMISO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PERMISO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;
 
    -- 2. ACTUALIZAR ESTADO
    UPDATE PERMISOS_EMPLEADOS 
    SET ESTADO = P_NUEVO_ESTADO 
    WHERE ID_PERMISO = P_ID_PERMISO;

    SELECT CONCAT('EXITO: PERMISO ID ', P_ID_PERMISO, ' ACTUALIZADO A ESTADO: ', P_NUEVO_ESTADO) AS MENSAJE;
END //
DELIMITER ;




/*
SP_HISTORIAL_PERMISOS_EMPLEADO
Lista todos los permisos de un empleado (tipo, fechas, estado y
descripcion) del mas reciente al mas antiguo, para ver su historial
completo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_HISTORIAL_PERMISOS_EMPLEADO //
CREATE PROCEDURE SP_HISTORIAL_PERMISOS_EMPLEADO(IN P_ID_EMPLEADO INT)
BEGIN
    SELECT 
        TIPO_PERMISO,
        FECHA_INICIO,
        FECHA_FIN,
        ESTADO,
        DESCRIPCION
    FROM PERMISOS_EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO
    ORDER BY FECHA_INICIO DESC;
END //
DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


/*
VISTA_PERMISOS_ACTIVOS
Muestra solo los permisos aprobados que estan vigentes hoy, con el nombre
del empleado, el tipo y el rango de fechas. Sirve para pintar quienes
estan ausentes en este momento.
*/
CREATE OR REPLACE VIEW VISTA_PERMISOS_ACTIVOS AS
SELECT 
    E.NOMBRE,
    P.TIPO_PERMISO,
    P.FECHA_INICIO,
    P.FECHA_FIN,
    P.ESTADO
FROM PERMISOS_EMPLEADOS P
JOIN EMPLEADOS E ON P.ID_EMPLEADO = E.ID_EMPLEADO
WHERE CURDATE() BETWEEN P.FECHA_INICIO AND P.FECHA_FIN
AND P.ESTADO = 'APROBADO';