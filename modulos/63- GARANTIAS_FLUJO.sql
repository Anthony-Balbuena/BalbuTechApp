/*
MODULO 63 - GARANTIAS: AUTOR, FECHAS Y FLUJO

Problema
--------
La garantia se abria con el paraguas GESTIONAR_VENTAS, no guardaba quien la
registro ni cuando, y el reclamo solo miraba ESTADO = 'ACTIVA': una garantia
con FECHA_FIN en el pasado seguia siendo reclamable. El estado VENCIDA estaba
en el ENUM pero ningun objeto lo escribia. La UI pedia IDs de detalle, de
garantia y de reclamo a ciegas.

Solucion
--------
  1. PRODUCTOS.DIAS_GARANTIA: dias de garantia por producto. NULL o 0 = sin
     garantia automatica.
  2. GARANTIAS: ID_EMPLEADO (quien registro) y FECHA_REGISTRO.
  3. RECLAMOS_GARANTIAS: ID_EMPLEADO, ID_EMPLEADO_CIERRE y FECHA_CIERRE.
  4. SP_REGISTRAR_GARANTIA recibe el empleado y valida los dias.
  5. 27_SP_REGISTRAR_RECLAMO_GARANTIA valida las fechas, no solo el estado.
  6. 27_SP_FINALIZAR_RECLAMO_TOTAL solo cierra PENDIENTE o APROBADO y guarda
     quien cerro y cuando.
  7. SP_MARCAR_GARANTIAS_VENCIDAS escribe VENCIDA; SP_CONSULTAR_GARANTIAS lo
     invoca antes de listar para no depender de un scheduler.
  8. SP_CONSULTAR_GARANTIAS, SP_CONSULTAR_RECLAMOS y
     SP_LINEAS_VENTA_CON_GARANTIA para que la UI liste en vez de pedir IDs.
  9. TR_REGISTRAR_GARANTIA_VENTA crea la garantia sola cuando la venta pasa a
     REALIZADA, con los dias del producto y el empleado de la venta.

Orden de despliegue
-------------------
  1. Backup de la base.
  2. Correr este modulo.
  3. Desplegar el binario nuevo.
El binario viejo llama a los SPs con la firma anterior y falla al registrar o
finalizar. Como GARANTIAS y RECLAMOS_GARANTIAS estan vacias y el flujo no se
usa, la ventana es de minutos y no se pierden datos.

Idempotente: las columnas usan IF NOT EXISTS, las FK se agregan solo si no
existen, y los SPs y el trigger se recrean con DROP IF EXISTS + CREATE.
*/

-- ---------------------------------------------------------------------------
-- 1. Dias de garantia por producto
-- ---------------------------------------------------------------------------
ALTER TABLE PRODUCTOS
    ADD COLUMN IF NOT EXISTS DIAS_GARANTIA INT NULL DEFAULT NULL
    COMMENT 'Dias de garantia automatica al confirmar la venta. NULL o 0 = sin garantia';

SET @hay_ck := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.CHECK_CONSTRAINTS
                WHERE CONSTRAINT_SCHEMA = DATABASE()
                  AND CONSTRAINT_NAME = 'CK_PRODUCTO_DIAS_GARANTIA');
SET @sql_ck := IF(@hay_ck = 0,
    'ALTER TABLE PRODUCTOS ADD CONSTRAINT CK_PRODUCTO_DIAS_GARANTIA CHECK (DIAS_GARANTIA IS NULL OR DIAS_GARANTIA >= 0)',
    'DO 0');
PREPARE st_ck FROM @sql_ck;
EXECUTE st_ck;
DEALLOCATE PREPARE st_ck;

-- ---------------------------------------------------------------------------
-- 2. GARANTIAS: autor y fecha de registro
-- ---------------------------------------------------------------------------
ALTER TABLE GARANTIAS
    ADD COLUMN IF NOT EXISTS ID_EMPLEADO INT NULL,
    ADD COLUMN IF NOT EXISTS FECHA_REGISTRO TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

SET @hay_fk := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                WHERE CONSTRAINT_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'GARANTIAS'
                  AND CONSTRAINT_NAME = 'FK_GARANTIA_EMPLEADO');
SET @sql_fk := IF(@hay_fk = 0,
    'ALTER TABLE GARANTIAS ADD CONSTRAINT FK_GARANTIA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)',
    'DO 0');
PREPARE st_fk FROM @sql_fk;
EXECUTE st_fk;
DEALLOCATE PREPARE st_fk;

-- ---------------------------------------------------------------------------
-- 3. RECLAMOS_GARANTIAS: autor, cierre y fecha de cierre
-- ---------------------------------------------------------------------------
ALTER TABLE RECLAMOS_GARANTIAS
    ADD COLUMN IF NOT EXISTS ID_EMPLEADO INT NULL,
    ADD COLUMN IF NOT EXISTS ID_EMPLEADO_CIERRE INT NULL,
    ADD COLUMN IF NOT EXISTS FECHA_CIERRE TIMESTAMP NULL DEFAULT NULL;

SET @hay_fk := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                WHERE CONSTRAINT_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'RECLAMOS_GARANTIAS'
                  AND CONSTRAINT_NAME = 'FK_RECLAMO_EMPLEADO');
SET @sql_fk := IF(@hay_fk = 0,
    'ALTER TABLE RECLAMOS_GARANTIAS ADD CONSTRAINT FK_RECLAMO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)',
    'DO 0');
PREPARE st_fk FROM @sql_fk;
EXECUTE st_fk;
DEALLOCATE PREPARE st_fk;

SET @hay_fk := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                WHERE CONSTRAINT_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'RECLAMOS_GARANTIAS'
                  AND CONSTRAINT_NAME = 'FK_RECLAMO_EMPLEADO_CIERRE');
SET @sql_fk := IF(@hay_fk = 0,
    'ALTER TABLE RECLAMOS_GARANTIAS ADD CONSTRAINT FK_RECLAMO_EMPLEADO_CIERRE FOREIGN KEY (ID_EMPLEADO_CIERRE) REFERENCES EMPLEADOS (ID_EMPLEADO)',
    'DO 0');
PREPARE st_fk FROM @sql_fk;
EXECUTE st_fk;
DEALLOCATE PREPARE st_fk;

-- ---------------------------------------------------------------------------
-- 4. Registrar garantia (manual, respaldo de ventas viejas)
-- ---------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS SP_REGISTRAR_GARANTIA //
CREATE PROCEDURE SP_REGISTRAR_GARANTIA(
    IN P_ID_DETALLE_VENTA INT,
    IN P_DIAS_VALIDEZ INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_EXISTE INT;
    DECLARE V_NUEVO_ID INT;

    IF NOT EXISTS (SELECT 1 FROM DETALLES_VENTA WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DETALLE DE VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_DIAS_VALIDEZ IS NULL OR P_DIAS_VALIDEZ < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LOS DIAS DE GARANTIA DEBEN SER MAYORES QUE CERO.';
        LEAVE proc_label;
    END IF;

    SELECT COUNT(*) INTO V_EXISTE FROM GARANTIAS WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA;
    IF V_EXISTE > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.';
        LEAVE proc_label;
    END IF;

    INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN, ID_EMPLEADO)
    VALUES (
        P_ID_DETALLE_VENTA,
        CURRENT_DATE,
        DATE_ADD(CURRENT_DATE, INTERVAL P_DIAS_VALIDEZ DAY),
        P_ID_EMPLEADO
    );

    SET V_NUEVO_ID = LAST_INSERT_ID();

    SELECT 'EXITO' AS ESTATUS,
           'GARANTÍA REGISTRADA CON ÉXITO.' AS MENSAJE,
           V_NUEVO_ID AS ID_GENERADO;
END //

-- ---------------------------------------------------------------------------
-- 5. Reclamar: valida fechas, no solo el estado
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS 27_SP_REGISTRAR_RECLAMO_GARANTIA //
CREATE PROCEDURE 27_SP_REGISTRAR_RECLAMO_GARANTIA(
    IN P_ID_GARANTIA INT,
    IN P_DESCRIPCION VARCHAR(255),
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ESTADO ENUM('ACTIVA', 'VENCIDA', 'CANCELADA');
    DECLARE V_INICIO DATE;
    DECLARE V_FIN DATE;

    SELECT ESTADO, FECHA_INICIO, FECHA_FIN
      INTO V_ESTADO, V_INICIO, V_FIN
      FROM GARANTIAS
     WHERE ID_GARANTIA = P_ID_GARANTIA;

    IF V_ESTADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO <> 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA GARANTÍA NO ESTÁ ACTIVA Y NO SE PUEDE RECLAMAR.';
        LEAVE proc_label;
    END IF;

    IF CURRENT_DATE < V_INICIO OR CURRENT_DATE > V_FIN THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA ESTÁ VENCIDA POR FECHA Y NO SE PUEDE RECLAMAR.';
        LEAVE proc_label;
    END IF;

    IF P_DESCRIPCION IS NULL OR TRIM(P_DESCRIPCION) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DESCRIPCIÓN DEL DAÑO ES OBLIGATORIA.';
        LEAVE proc_label;
    END IF;

    INSERT INTO RECLAMOS_GARANTIAS (ID_GARANTIA, DESCRIPCION, ID_EMPLEADO)
    VALUES (P_ID_GARANTIA, P_DESCRIPCION, P_ID_EMPLEADO);

    SELECT 'EXITO: RECLAMO REGISTRADO CORRECTAMENTE.' AS MENSAJE;
END //

-- ---------------------------------------------------------------------------
-- 6. Finalizar: solo PENDIENTE o APROBADO, y deja autor y fecha de cierre
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS 27_SP_FINALIZAR_RECLAMO_TOTAL //
CREATE PROCEDURE 27_SP_FINALIZAR_RECLAMO_TOTAL(
    IN P_ID_RECLAMO INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ESTADO_ANT VARCHAR(20);
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    SELECT ESTADO INTO V_ESTADO_ANT FROM RECLAMOS_GARANTIAS WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;

    IF V_ESTADO_ANT IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: RECLAMO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_ANT NOT IN ('PENDIENTE', 'APROBADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE CIERRAN RECLAMOS PENDIENTES O APROBADOS.';
        LEAVE proc_label;
    END IF;

    UPDATE RECLAMOS_GARANTIAS
       SET ESTADO = 'CERRADO',
           ID_EMPLEADO_CIERRE = P_ID_EMPLEADO,
           FECHA_CIERRE = CURRENT_TIMESTAMP
     WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;

    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES ('RECLAMOS_GARANTIAS', P_ID_RECLAMO, 'UPDATE', USER(), V_ESTADO_ANT, 'CERRADO');

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT 'EXITO: RECLAMO CERRADO.' AS MENSAJE;
END //

-- ---------------------------------------------------------------------------
-- 7. Marcar vencidas: el estado que nunca se escribia
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS SP_MARCAR_GARANTIAS_VENCIDAS //
CREATE PROCEDURE SP_MARCAR_GARANTIAS_VENCIDAS()
BEGIN
    UPDATE GARANTIAS
       SET ESTADO = 'VENCIDA'
     WHERE ESTADO = 'ACTIVA'
       AND FECHA_FIN < CURRENT_DATE;
END //

-- ---------------------------------------------------------------------------
-- 8. Consulta de garantias (filtro libre + solo reclamables)
-- ---------------------------------------------------------------------------
-- Antes de listar pone al dia el estado: una ACTIVA con FECHA_FIN pasada pasa
-- a VENCIDA. Asi la app no depende de un scheduler ni muestra estados falsos.
DROP PROCEDURE IF EXISTS SP_CONSULTAR_GARANTIAS //
CREATE PROCEDURE SP_CONSULTAR_GARANTIAS(
    IN P_FILTRO VARCHAR(100),
    IN P_SOLO_RECLAMABLES INT
)
BEGIN
    CALL SP_MARCAR_GARANTIAS_VENCIDAS();

    SELECT G.ID_GARANTIA,
           V.ID_VENTA,
           IFNULL(C.NOMBRE, '') AS CLIENTE,
           P.NOMBRE AS PRODUCTO,
           G.FECHA_INICIO,
           G.FECHA_FIN,
           G.ESTADO,
           IFNULL(E.NOMBRE, '') AS REGISTRO,
           G.FECHA_REGISTRO
      FROM GARANTIAS G
      JOIN DETALLES_VENTA DV ON DV.ID_DETALLE_VENTA = G.ID_DETALLE_VENTA
      JOIN VENTAS V ON V.ID_VENTA = DV.ID_VENTA
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
      LEFT JOIN CLIENTES C ON C.ID_CLIENTE = V.ID_CLIENTE
      LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = G.ID_EMPLEADO
     WHERE (P_SOLO_RECLAMABLES = 0
            OR (G.ESTADO = 'ACTIVA' AND CURRENT_DATE BETWEEN G.FECHA_INICIO AND G.FECHA_FIN))
       AND (P_FILTRO IS NULL OR P_FILTRO = ''
            OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR P.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR CAST(V.ID_VENTA AS CHAR) = P_FILTRO
            OR G.ESTADO = P_FILTRO)
     ORDER BY G.FECHA_FIN, G.ID_GARANTIA
     LIMIT 100;
END //

-- ---------------------------------------------------------------------------
-- 9. Consulta de reclamos (por garantia + solo abiertos)
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS SP_CONSULTAR_RECLAMOS //
CREATE PROCEDURE SP_CONSULTAR_RECLAMOS(
    IN P_ID_GARANTIA INT,
    IN P_SOLO_ABIERTOS INT
)
BEGIN
    SELECT R.ID_RECLAMO_GARAN,
           R.ID_GARANTIA,
           R.FECHA_RECLAMO,
           R.DESCRIPCION,
           R.ESTADO,
           IFNULL(E.NOMBRE, '') AS REGISTRO,
           IFNULL(EC.NOMBRE, '') AS CIERRE,
           R.FECHA_CIERRE
      FROM RECLAMOS_GARANTIAS R
      LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = R.ID_EMPLEADO
      LEFT JOIN EMPLEADOS EC ON EC.ID_EMPLEADO = R.ID_EMPLEADO_CIERRE
     WHERE (P_ID_GARANTIA = 0 OR R.ID_GARANTIA = P_ID_GARANTIA)
       AND (P_SOLO_ABIERTOS = 0 OR R.ESTADO IN ('PENDIENTE', 'APROBADO'))
     ORDER BY R.FECHA_RECLAMO DESC, R.ID_RECLAMO_GARAN DESC
     LIMIT 100;
END //

-- ---------------------------------------------------------------------------
-- 10. Lineas de una venta para elegir el detalle a garantizar
-- ---------------------------------------------------------------------------
-- SP_VENTA_LINEAS no devuelve el ID del detalle porque alimenta la factura.
-- Este SP es solo para el alta manual: trae el ID, los dias sugeridos del
-- producto y si la linea ya tiene garantia.
DROP PROCEDURE IF EXISTS SP_LINEAS_VENTA_CON_GARANTIA //
CREATE PROCEDURE SP_LINEAS_VENTA_CON_GARANTIA(IN P_ID_VENTA INT)
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_LINEAS_VENTA_CON_GARANTIA');
    SELECT DV.ID_DETALLE_VENTA,
           P.NOMBRE AS PRODUCTO,
           DV.CANTIDAD,
           IFNULL(P.DIAS_GARANTIA, 0) AS DIAS_SUGERIDOS,
           IF(G.ID_GARANTIA IS NULL, 'NO', 'SI') AS TIENE_GARANTIA
      FROM DETALLES_VENTA DV
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
      LEFT JOIN GARANTIAS G ON G.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
     WHERE DV.ID_VENTA = P_ID_VENTA
     ORDER BY DV.ID_DETALLE_VENTA;
END //

-- ---------------------------------------------------------------------------
-- 10.b Ventas que todavia admiten garantia (07/11/2026)
-- ---------------------------------------------------------------------------
-- El alta manual pedia el ID de la venta a ciegas. Este SP lista las ventas
-- REALIZADA con al menos una linea sin garantia, que son las unicas sobre las
-- que tiene sentido registrar una: las que ya la tienen (por el trigger
-- automatico o por un alta anterior) no aparecen. LIMIT 50 para que la
-- pantalla no escupa historico completo.
--
-- Permiso: GARANTIAS_REGISTRAR, el mismo que abre "Registrar garantia"; todo
-- rol que llega a esa pantalla lo tiene.
DROP PROCEDURE IF EXISTS SP_VENTAS_GARANTIZABLES //
CREATE PROCEDURE SP_VENTAS_GARANTIZABLES()
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_VENTAS_GARANTIZABLES');
    SELECT V.ID_VENTA,
           V.FECHA,
           C.NOMBRE AS CLIENTE,
           V.ESTADO,
           COUNT(*) AS LINEAS_SIN_GARANTIA
      FROM DETALLES_VENTA DV
      JOIN VENTAS V   ON V.ID_VENTA = DV.ID_VENTA
      JOIN CLIENTES C ON C.ID_CLIENTE = V.ID_CLIENTE
      LEFT JOIN GARANTIAS G ON G.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
     WHERE G.ID_GARANTIA IS NULL
       AND V.ESTADO = 'REALIZADA'
     GROUP BY V.ID_VENTA, V.FECHA, C.NOMBRE, V.ESTADO
     ORDER BY V.ID_VENTA DESC
     LIMIT 50;
END //

DELIMITER ;

-- ---------------------------------------------------------------------------
-- 11. Registro automatico al confirmar la venta
-- ---------------------------------------------------------------------------
-- Va despues de TR_CAMBIO_ESTADO_VENTA para que el historial de la venta ya
-- este escrito cuando se crean las garantias. Solo actua en el pase a
-- REALIZADA y solo con productos que tengan DIAS_GARANTIA > 0. El ON DUPLICATE
-- KEY evita duplicar si el detalle ya tiene garantia (UQ_GARANTIA_DETALLE).
DELIMITER //

DROP TRIGGER IF EXISTS TR_REGISTRAR_GARANTIA_VENTA //
CREATE TRIGGER TR_REGISTRAR_GARANTIA_VENTA
AFTER UPDATE ON VENTAS
FOR EACH ROW
FOLLOWS TR_CAMBIO_ESTADO_VENTA
BEGIN
    IF NEW.ESTADO = 'REALIZADA' AND OLD.ESTADO <> 'REALIZADA' THEN
        INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN, ID_EMPLEADO)
        SELECT DV.ID_DETALLE_VENTA,
               CURRENT_DATE,
               DATE_ADD(CURRENT_DATE, INTERVAL P.DIAS_GARANTIA DAY),
               NEW.ID_EMPLEADO
          FROM DETALLES_VENTA DV
          JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
         WHERE DV.ID_VENTA = NEW.ID_VENTA
           AND P.DIAS_GARANTIA IS NOT NULL
           AND P.DIAS_GARANTIA > 0
        ON DUPLICATE KEY UPDATE GARANTIAS.ID_GARANTIA = GARANTIAS.ID_GARANTIA;
    END IF;
END //

DELIMITER ;

SELECT 'MODULO 63 APLICADO: GARANTIAS CON AUTOR, FECHAS Y FLUJO.' AS RESULTADO;
