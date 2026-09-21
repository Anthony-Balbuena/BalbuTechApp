-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH

/*
MODULO: PERMISOS_EMPLEADOS — Descripción general

Este módulo contiene la definición de la tabla PERMISOS_EMPLEADOS y los
procedimientos almacenados necesarios para la gestión del ciclo de vida de los
permisos laborales (médicos, personales, estudio, licencia, sin sueldo).
Incluye validaciones de solapamiento de fechas, prohibición de solicitudes
retroactivas y control de estados (PENDIENTE, APROBADO, RECHAZADO).

Estructura clave:

ID_PERMISO: PK autoincremental.

ID_EMPLEADO: FK hacia la tabla EMPLEADOS.

TIPO_PERMISO: ENUM con las categorías permitidas.

FECHA_INICIO / FECHA_FIN: Rango de fechas del permiso (con validación de coherencia).

ESTADO: Control de aprobación (PENDIENTE por defecto).
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



/*ÍNDICES DE RENDIMIENTO (PERMISOS_EMPLEADOS)
X_PERMISO_EMPLEADO: Optimiza la búsqueda de historiales por empleado.  
IX_PERMISO_ESTADO: Facilita el filtrado por solicitudes pendientes.  
IX_PERMISO_FECHAS: Acelera las consultas para calendarios de ausencias.
*/
-- 1. Para ver todos los permisos de un empleado (Ej: "¿Cuántas veces ha pedido médico?")
CREATE INDEX IX_PERMISO_EMPLEADO ON PERMISOS_EMPLEADOS (ID_EMPLEADO);

-- 2. Para ver qué permisos están PENDIENTES de aprobar hoy
CREATE INDEX IX_PERMISO_ESTADO ON PERMISOS_EMPLEADOS (ESTADO);

-- 3. Para calendarios de ausencias (Ej: "¿Quiénes no vienen la próxima semana?")
CREATE INDEX IX_PERMISO_FECHAS ON PERMISOS_EMPLEADOS (FECHA_INICIO, FECHA_FIN);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/* SP_SOLICITAR_PERMISO:

Propósito: Este SP se utiliza para solicitar un permiso para un empleado. Los permisos pueden ser de tipo médico, personal, estudio, licencia o sin sueldo.
Datos utilizados:
P_ID_EMPLEADO: Identificador único del empleado que solicita el permiso.
P_TIPO_PERMISO: Tipo de permiso solicitado (por ejemplo, médico, personal, etc.).
P_FECHA_INICIO: Fecha de inicio de la solicitud del permiso.
P_FECHA_FIN: Fecha de fin de la solicitud del permiso.
P_DESCRIPCION: Descripción adicional del permiso (como código de procedimiento, etc.).

Operaciones realizadas:
Verifica que el empleado exista en la base de datos.
Verifica que las fechas ingresadas sean correctas (no retroactivas y sin solapamiento con otros permisos no rechazados).
Inserta el permiso solicitado en la base de datos.
Devuelve un mensaje de éxito.  */
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
END ;
DELIMITER ;

/*  SP_GESTIONAR_PERMISO:

Propósito: Este SP se utiliza para actualizar el estado de un permiso existente. Puede ser actualizado a un nuevo estado (por ejemplo, de "pendiente" a "aprobado").
Datos utilizados:
P_ID_PERMISO: Identificador único del permiso que se desea actualizar.
P_NUEVO_ESTADO: Nuevamente, este es un valor en una lista de estados posibles (por ejemplo, "pendiente", "aprobado", "rechazado").

Operaciones realizadas:
Verifica si el permiso existe antes de realizar cualquier actualización.
Actualiza el estado del permiso con el nuevo estado proporcionado.
Devuelve un mensaje de éxito que incluye el ID del permiso y su nuevo estado. */
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
END ;
DELIMITER ;




/*  SP_HISTORIAL_PERMISOS_EMPLEADO:
Propósito: Este SP se utiliza para recuperar un historial de permisos de un empleado. La información incluye el tipo de permiso, la fecha de inicio, la fecha de fin, el estado y la descripción del permiso.
Datos utilizados:
P_ID_EMPLEADO: Identificador único del empleado cuyo historial de permisos se desea recuperar.

Operaciones realizadas:
Selecciona los registros de la tabla PERMISOS_EMPLEADOS donde el ID_EMPLEADO coincide con el valor de P_ID_EMPLEADO. Luego, ordena los resultados por FECHA_INICIO en orden descendente y devuelve la información solicitada.
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