-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
TABLA BONOS_EMPLEADOS
Guarda los bonos, horas extra y bonificaciones de los empleados: fecha,
tipo (DOBLE_SUELDO, HORAS_EXTRA o BONIFICACION), monto y estado
(PENDIENTE, PAGADO o ANULADO). El monto tiene que ser mayor a cero y el
bono siempre pertenece a un empleado existente.
*/ ----
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
    ESTADO ENUM('PENDIENTE', 'PAGADO', 'ANULADO') NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_BONO),
    CONSTRAINT FK_BONO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
 

SELECT * FROM BONOS_EMPLEADOS;

ALTER TABLE BONOS_EMPLEADOS 
MODIFY COLUMN ESTADO ENUM('PENDIENTE', 'PAGADO', 'ANULADO') NOT NULL DEFAULT 'PENDIENTE';



/*
INDICE IX_BONO_EMPLEADO
Encuentra al instante todo el historial de bonos de un empleado en
especifico, sin tener que revisar la tabla completa.
*/
CREATE INDEX IX_BONO_EMPLEADO ON BONOS_EMPLEADOS (ID_EMPLEADO);

/*
INDICE IX_BONO_FECHA
Acelera los reportes de contabilidad y los totales por mes o ano, que
ordenan y filtran por la fecha del bono.
*/
CREATE INDEX IX_BONO_FECHA ON BONOS_EMPLEADOS (FECHA);

/*
INDICE IX_BONO_TIPO
Permite calcular rapido cuanto dinero se gasta en cada tipo de bono
(doble sueldo, horas extra o bonificacion).
*/
CREATE INDEX IX_BONO_TIPO ON BONOS_EMPLEADOS (TIPO_BONO);

/*
INDICE IX_BONO_ESTADO
Filtra los bonos por su estado (PENDIENTE, PAGADO o ANULADO), que es lo
que usa la pantalla para mostrar cada lista.
*/
CREATE INDEX IX_BONO_ESTADO ON BONOS_EMPLEADOS (ESTADO);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


/*
SP_REGISTRAR_BONO
Registra un bono nuevo para un empleado.
Valida que el empleado exista y que el monto no pase de 100000; si todo
esta bien guarda el bono y responde con un mensaje que trae el monto, el
nombre del empleado y su ID.
*/
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
END //
DELIMITER ;




/*
SP_ACTUALIZAR_BONO
Cambia el monto y la descripcion de un bono existente.
Revisa que el bono exista y que el nuevo monto no pase de 100000; si todo
esta bien lo actualiza y confirma con un mensaje.
*/
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

/*
SP_PAGAR_BONO
Marca un bono como PAGADO.
Si el bono no existe manda error, si ya estaba pagado avisa y si esta
anulado no deja pagarlo; solo un bono pendiente se puede pagar.
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PAGAR_BONO;
CREATE PROCEDURE SP_PAGAR_BONO(
    IN P_ID_BONO INT
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. Verificar si el bono existe y ver su estado actual
    SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que no esté ya pagado o anulado
    IF v_estado_actual = 'PAGADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA HABIA SIDO PAGADO ANTERIORMENTE.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'ANULADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE PAGAR UN BONO QUE ESTA ANULADO.';
        LEAVE proc_label;
    END IF;

    -- 3. Actualizar el estado a PAGADO
    UPDATE BONOS_EMPLEADOS 
    SET ESTADO = 'PAGADO' 
    WHERE ID_BONO = P_ID_BONO;

    -- 4. Confirmación
    SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' HA SIDO MARCADO COMO PAGADO.') AS MENSAJE;
END//
DELIMITER ;

/*
SP_ANULAR_BONO
Anula un bono poniendolo en estado ANULADO.
Si el bono no existe manda error, si ya fue pagado no deja anularlo y si
ya estaba anulado solo avisa que no habia nada que hacer.
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ANULAR_BONO;
CREATE PROCEDURE SP_ANULAR_BONO(
    IN P_ID_BONO INT
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. Verificar existencia y estado
    SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'PAGADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE ANULAR UN BONO QUE YA FUE PAGADO.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'ANULADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA ESTABA ANULADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Cambiar estado a ANULADO
    UPDATE BONOS_EMPLEADOS 
    SET ESTADO = 'ANULADO' 
    WHERE ID_BONO = P_ID_BONO;

    -- 3. Confirmación
    SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' FUE ANULADO CORRECTAMENTE.') AS MENSAJE;
END//

DELIMITER ;


/*
SP_LISTAR_BONOS
Lista los bonos con el nombre del empleado, mas recientes primero.
Si llega un estado (PENDIENTE, PAGADO o ANULADO) filtra por el; si viene
NULL o vacio trae todos.
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_BONOS;
CREATE PROCEDURE SP_LISTAR_BONOS(
    IN P_ESTADO VARCHAR(20) -- Puedes pasarle 'PENDIENTE', 'PAGADO', 'ANULADO', o dejarlo en NULL para ver todos
)
BEGIN
    SELECT 
        b.ID_BONO,
        b.ID_EMPLEADO,
        e.NOMBRE AS NOMBRE_EMPLEADO,
        b.FECHA,
        b.TIPO_BONO,
        b.MONTO,
        b.DESCRIPCION,
        b.ESTADO,
        b.FECHA_REGISTRO
    FROM BONOS_EMPLEADOS b
    INNER JOIN EMPLEADOS e ON b.ID_EMPLEADO = e.ID_EMPLEADO
    WHERE (P_ESTADO IS NULL OR P_ESTADO = '' OR b.ESTADO = P_ESTADO)
    ORDER BY b.FECHA DESC;
END//
DELIMITER ;





----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------
/*
TR_VALIDAR_FECHA_BONO
Antes de insertar un bono revisa que la fecha no sea vieja: no deja
registrar bonos con mas de 60 dias de antiguedad y manda un error si es
asi. Trabaja en automatico.
*/
DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_FECHA_BONO;
CREATE TRIGGER TR_VALIDAR_FECHA_BONO
BEFORE INSERT ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN 
    -- No permitir bonos con fechas de más de 30 días atrás
    IF NEW.FECHA < DATE_SUB(CURDATE(), INTERVAL 60 DAY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 30 DÍAS.';
    END IF;
END//
DELIMITER ;

/*
LIMPIEZA DE TRIGGER MOVIDO AL COBRO
TR_CALCULAR_BONO_VENTA creaba el bono del 1% al AGREGAR el producto, o sea
antes de cobrar, y cancelar la venta no lo borraba. Ahora el bono lo crea
TR_AUTO_FINALIZAR_VENTA (archivo 24) en el momento en que se paga el total
de la venta. Solo queda el DROP para limpiar bases viejas.
*/
DROP TRIGGER IF EXISTS TR_CALCULAR_BONO_VENTA;
DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
/*
VISTA_TOTAL_BONOS_POR_EMPLEADO
Resume por empleado el total de dinero bonificado y cuantos bonos tiene,
incluyendo tambien a los que no tienen ningun bono (en cero).
*/

CREATE OR REPLACE VIEW VISTA_TOTAL_BONOS_POR_EMPLEADO AS
SELECT 
    E.ID_EMPLEADO,
    E.NOMBRE,
    SUM(B.MONTO) AS TOTAL_BONIFICADO,
    COUNT(B.ID_BONO) AS CANTIDAD_BONOS
FROM EMPLEADOS E
LEFT JOIN BONOS_EMPLEADOS B ON E.ID_EMPLEADO = B.ID_EMPLEADO
GROUP BY E.ID_EMPLEADO;

-----------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[TRIGGER]------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_CAMBIO_BONO ;
/*
TR_BLOQUEAR_CAMBIO_BONO (09/10/2026)
El bono PAGADO o ANULADO no cambia (monto, tipo, empleado ni estado): el monto
alimenta el cierre y lo ya pagado es historia. Solo un PENDIENTE se mueve
(PAGADO/ANULADO por sus SPs).
*/
CREATE TRIGGER TR_BLOQUEAR_CAMBIO_BONO
BEFORE UPDATE ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN
    IF OLD.ESTADO <> 'PENDIENTE' THEN
        IF NEW.ESTADO <> OLD.ESTADO
           OR NEW.MONTO <> OLD.MONTO
           OR NEW.TIPO_BONO <> OLD.TIPO_BONO
           OR NEW.ID_EMPLEADO <> OLD.ID_EMPLEADO THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.';
        END IF;
    END IF;
END //
DELIMITER ;
