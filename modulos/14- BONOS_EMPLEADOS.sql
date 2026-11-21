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
    -- (18/11/2026) Rastro del pago. Antes "pagar" era solo pasar ESTADO a
    -- PAGADO: FECHA_REGISTRO es cuando el trigger de ventas creo el bono, no
    -- cuando salio la plata, y no habia forma de saber quien lo pago. Son NULL
    -- mientras el bono este PENDIENTE o ANULADO.
    FECHA_PAGO DATE NULL,
    -- El nombre de usuario, no un id: AUDITORIA_SISTEMA.USUARIO_SISTEMA ya
    -- guarda el nombre por la misma razon. Si la cuenta se borra, el bono
    -- todavia dice quien lo pago.
    PAGADO_POR VARCHAR(50) NULL,
    PRIMARY KEY (ID_BONO),
    CONSTRAINT FK_BONO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Encuentra al instante todo el historial de bonos de un empleado en especifico, sin
    -- tener que revisar la tabla completa.
    INDEX IX_BONO_EMPLEADO (ID_EMPLEADO),
    -- Acelera los reportes de contabilidad y los totales por mes o ano, que ordenan y
    -- filtran por la fecha del bono.
    INDEX IX_BONO_FECHA (FECHA),
    -- Permite calcular rapido cuanto dinero se gasta en cada tipo de bono (doble sueldo,
    -- horas extra o bonificacion).
    INDEX IX_BONO_TIPO (TIPO_BONO),
    -- Filtra los bonos por su estado (PENDIENTE, PAGADO o ANULADO), que es lo que usa la
    -- pantalla para mostrar cada lista.
    INDEX IX_BONO_ESTADO (ESTADO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
 

ALTER TABLE BONOS_EMPLEADOS
MODIFY COLUMN ESTADO ENUM('PENDIENTE', 'PAGADO', 'ANULADO') NOT NULL DEFAULT 'PENDIENTE';

-- ----------------------------------------------------------------
-- Bases que ya tienen la tabla sin las columnas de pago
-- ----------------------------------------------------------------
-- (18/11/2026) Mismo patron que el modulo 13: cada paso se pregunta antes a
-- INFORMATION_SCHEMA, asi que correr el modulo dos veces no rompe nada y una
-- instalacion nueva los saltea (las columnas ya vienen en el CREATE TABLE).
-- La viva llego a esta version ya con 11 bonos, uno de ellos PAGADO a mano: su
-- FECHA_PAGO y su PAGADO_POR quedan NULL y NO se rellenan con datos inventados.

SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'BONOS_EMPLEADOS'
                   AND COLUMN_NAME = 'FECHA_PAGO');
SET @sql := IF(@existe = 0,
    'ALTER TABLE BONOS_EMPLEADOS ADD COLUMN FECHA_PAGO DATE NULL AFTER ESTADO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'BONOS_EMPLEADOS'
                   AND COLUMN_NAME = 'PAGADO_POR');
SET @sql := IF(@existe = 0,
    'ALTER TABLE BONOS_EMPLEADOS ADD COLUMN PAGADO_POR VARCHAR(50) NULL AFTER FECHA_PAGO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;


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

    -- (10/10/2026) 2b. Tipo válido (antes caía al 1265 del ENUM).
    IF P_TIPO_BONO NOT IN ('DOBLE_SUELDO', 'HORAS_EXTRA', 'BONIFICACION') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: TIPO DE BONO DESCONOCIDO.';
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
    -- (10/10/2026) Monto válido: NULL/≤0/>100000 con mensaje (antes 1048/3819
    -- técnico o entraba sin tope). Mismo tope del alta.
    IF IFNULL(P_NUEVO_MONTO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    IF P_NUEVO_MONTO > 100000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.';
        LEAVE proc_label;
    END IF;
    UPDATE BONOS_EMPLEADOS 
    SET MONTO = P_NUEVO_MONTO,
        DESCRIPCION = P_NUEVA_DESCRIPCION
    WHERE ID_BONO = P_ID_BONO;

    SELECT 'EXITO: BONO ACTUALIZADO CORRECTAMENTE.' AS MENSAJE;
END //
DELIMITER ;

/*
SP_PAGAR_BONO
Marca un bono como PAGADO y deja registrado cuando (FECHA_PAGO) y quien
(PAGADO_POR, el usuario de la sesion).
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

    -- 3. Actualizar el estado a PAGADO y dejar el rastro del pago
    -- (18/11/2026) Antes solo cambiaba ESTADO: no quedaba ni cuando ni quien lo
    -- pago, asi que un bono pagado era indistinguible de uno que alguien
    -- tildo. PAGADO_POR toma el nombre de la sesion; si la conexion no trae una
    -- sesion valida el subselect da NULL y la columna queda vacia, que es la
    -- verdad (no se inventa el nombre de nadie).
    UPDATE BONOS_EMPLEADOS 
    SET ESTADO = 'PAGADO',
        FECHA_PAGO = CURRENT_DATE,
        PAGADO_POR = (SELECT USUARIO FROM USUARIOS
                       WHERE ID_USUARIO = FN_USUARIO_SESION())
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
SP_LISTAR_BONOS (RETIRADO 18/11/2026)
Tenía un único destino: la pantalla de bonos, que no existía. Al cablearla se
reemplazó por el par paginado de abajo: un listado sin LIMIT es una pared de
texto en cuanto pasan los meses (y en la viva ya hay bonos que crecen solos por
el trigger del 1% de las ventas). Queda el DROP para que una base que ya lo
tenía se limpie al reimportar.
*/

DROP PROCEDURE IF EXISTS SP_LISTAR_BONOS;


/*
SP_LISTAR_BONOS_PAGINADO
Una pagina de bonos con el nombre del empleado, mas recientes primero.
Si llega un estado (PENDIENTE, PAGADO o ANULADO) filtra por el; si viene
NULL o vacio trae todos. El LIMIT vive aca adentro porque el usuario de la app
no tiene SELECT directo sobre la tabla (recorte de balbu_app del 03/11).
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_BONOS_PAGINADO;
CREATE PROCEDURE SP_LISTAR_BONOS_PAGINADO(
    IN P_ESTADO     VARCHAR(20),
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

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
    ORDER BY b.FECHA DESC, b.ID_BONO DESC
    LIMIT P_POR_PAGINA OFFSET v_offset;
END//
DELIMITER ;


/*
SP_CONTAR_BONOS
Cuantos bonos hay con ese estado, para armar "Pagina 1 de N".
Mismo criterio de filtro que SP_LISTAR_BONOS_PAGINADO: si no llega estado,
cuenta todos.
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CONTAR_BONOS;
CREATE PROCEDURE SP_CONTAR_BONOS(
    IN P_ESTADO VARCHAR(20)
)
BEGIN
    SELECT COUNT(*) AS TOTAL
      FROM BONOS_EMPLEADOS b
     WHERE (P_ESTADO IS NULL OR P_ESTADO = '' OR b.ESTADO = P_ESTADO);
END//
DELIMITER ;


/*
SP_LISTAR_BONOS_PENDIENTES_EMPLEADO (18/11/2026)
Los bonos PENDIENTE de un empleado, para el recibo de nomina.
No pagina a proposito: es el detalle de UNA persona, no un listado del area.
Va aparte de SP_LISTAR_BONOS_PAGINADO porque ese filtra por estado para toda
la plantilla, y filtrar por empleado ahi obligaba a cambiar su firma (y la de
SP_CONTAR_BONOS) para algo que solo usa el recibo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_BONOS_PENDIENTES_EMPLEADO;
CREATE PROCEDURE SP_LISTAR_BONOS_PENDIENTES_EMPLEADO(
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    IF P_ID_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    SELECT b.ID_BONO,
           b.FECHA,
           b.TIPO_BONO,
           b.MONTO,
           b.DESCRIPCION
      FROM BONOS_EMPLEADOS b
     WHERE b.ID_EMPLEADO = P_ID_EMPLEADO
       AND b.ESTADO = 'PENDIENTE'
     ORDER BY b.FECHA, b.ID_BONO;
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
-- (10/10/2026) Se dio de baja en BD el huérfano 14_TR_VALIDAR_FECHA_BONO
-- (no existe en archivos; imponía 30 días y tapaba a este). Respaldo en
-- /tmp/opencode/backup/pre_drop_14trig.txt.
CREATE TRIGGER TR_VALIDAR_FECHA_BONO
BEFORE INSERT ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN 
    -- No permitir bonos con fechas de más de 60 días atrás
    IF NEW.FECHA < DATE_SUB(CURDATE(), INTERVAL 60 DAY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 60 DÍAS.';
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

(18/11/2026) Los ANULADO NO cuentan: un bono anulado es dinero que nunca se
otorgo. Antes el SUM los sumaba igual, y no se notaba porque nadie leia la
vista (ni habia pantalla para anular). Con la pantalla de bonos, anular uno
dejaba el total sin bajar: la vista mentia sobre plata.
*/

CREATE OR REPLACE VIEW VISTA_TOTAL_BONOS_POR_EMPLEADO AS
SELECT 
    E.ID_EMPLEADO,
    E.NOMBRE,
    SUM(CASE WHEN B.ESTADO <> 'ANULADO' THEN B.MONTO ELSE 0 END) AS TOTAL_BONIFICADO,
    COUNT(CASE WHEN B.ESTADO <> 'ANULADO' THEN 1 END) AS CANTIDAD_BONOS
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
           OR NEW.ID_EMPLEADO <> OLD.ID_EMPLEADO
           -- (18/11/2026) La auditoria del pago tambien es historia: un bono
           -- ya pagado no cambia de fecha ni de pagador. Va con <=> (igualdad
           -- segura con NULL) porque las columnas arrancan en NULL y un
           -- <> contra NULL da NULL, o sea que no frenaba nada.
           OR NOT (NEW.FECHA_PAGO <=> OLD.FECHA_PAGO)
           OR NOT (NEW.PAGADO_POR <=> OLD.PAGADO_POR) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: EL BONO PAGADO O ANULADO NO CAMBIA.';
        END IF;
    END IF;
END //
DELIMITER ;
