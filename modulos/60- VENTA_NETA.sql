-- ================================================================
-- BALBU_TECH - VENTA NETA Y REPORTES CON DEVOLUCIONES
-- ================================================================
-- (29/10/2026) Hasta hoy los reportes restaban el ITBIS reembolsado pero
-- no el SUBTOTAL reembolsado: una devolucion parcial dejaba el bruto y el
-- saldo inflados. VENTAS.TOTAL es el subtotal original y no se toca.
-- VW_VENTA_NETA centraliza el neto y de ahi leen las vistas, el cierre de
-- caja, el reporte por periodo y los topes de pago.
--
-- ORDEN DE DESPLIEGUE:
--   1. Backup de la base.
--   2. Correr este modulo.
--   3. Probar una venta con devolucion parcial y el cierre del dia.
--
-- Depende de: 21 VENTAS, 23 DETALLE_VENTA, 24 PAGOS, 26 DEVOLUCIONES.
-- Idempotente: CREATE OR REPLACE VIEW y DROP/CREATE de triggers y SPs.
--
-- Este modulo es la correccion aplicada sobre 24 y 43. Si se reinstala
-- desde cero, 24 y 43 ya traen la version corregida; correr el 60 despues
-- no cambia nada.
/*
VW_VENTA_NETA (29/10/2026)
El neto de una venta despues de sus devoluciones APROBADAS o REEMBOLSADAS.
VENTAS.TOTAL es el subtotal original y no se toca: la historia no se
reescribe. Esta vista es la unica definicion del BRUTO neto; la usan los
reportes, el cierre de caja y los topes de pago.
*/
CREATE OR REPLACE VIEW VW_VENTA_NETA AS
SELECT
    V.ID_VENTA,
    V.ID_CLIENTE,
    V.FECHA,
    V.ESTADO,
    V.TOTAL AS SUBTOTAL_ORIGINAL,
    IFNULL(D.ITBIS, 0) AS ITBIS_ORIGINAL,
    IFNULL(DV.SUBTOTAL_DEV, 0) AS SUBTOTAL_REEMBOLSADO,
    IFNULL(DV.ITBIS_DEV, 0) AS ITBIS_REEMBOLSADO,
    ROUND(V.TOTAL - IFNULL(DV.SUBTOTAL_DEV, 0), 2) AS SUBTOTAL_NETO,
    ROUND(IFNULL(D.ITBIS, 0) - IFNULL(DV.ITBIS_DEV, 0), 2) AS ITBIS_NETO,
    ROUND(V.TOTAL - IFNULL(DV.SUBTOTAL_DEV, 0)
          + IFNULL(D.ITBIS, 0) - IFNULL(DV.ITBIS_DEV, 0), 2) AS BRUTO_NETO,
    IFNULL(PG.PAGADO, 0) AS PAGADO,
    ROUND(V.TOTAL - IFNULL(DV.SUBTOTAL_DEV, 0)
          + IFNULL(D.ITBIS, 0) - IFNULL(DV.ITBIS_DEV, 0)
          - IFNULL(PG.PAGADO, 0), 2) AS SALDO
FROM VENTAS V
LEFT JOIN (
    SELECT ID_VENTA, SUM(MONTO_ITBIS) AS ITBIS
      FROM DETALLES_VENTA GROUP BY ID_VENTA
) D ON D.ID_VENTA = V.ID_VENTA
LEFT JOIN (
    SELECT DD.ID_VENTA,
           SUM(DV2.SUBTOTAL_REEMBOLSADO) AS SUBTOTAL_DEV,
           SUM(DV2.MONTO_ITBIS_REEMBOLSADO) AS ITBIS_DEV
      FROM DEVOLUCIONES DV2
      JOIN DETALLES_VENTA DD ON DD.ID_DETALLE_VENTA = DV2.ID_DETALLE_VENTA
     WHERE DV2.ESTADO IN ('APROBADA', 'REEMBOLSADA')
     GROUP BY DD.ID_VENTA
) DV ON DV.ID_VENTA = V.ID_VENTA
LEFT JOIN (
    SELECT ID_VENTA, SUM(MONTO) AS PAGADO
      FROM PAGOS GROUP BY ID_VENTA
) PG ON PG.ID_VENTA = V.ID_VENTA;

/*
VISTA_VENTAS_PENDIENTES_PAGO
Cuanto le falta por cobrar cada venta, sobre el BRUTO neto de
VW_VENTA_NETA (subtotal e ITBIS menos lo reembolsado). Se excluyen las
ventas CANCELADAS y DEVUELTAS y las que ya estan saldadas. Una devolucion
parcial puede dejar el saldo en negativo (a favor del cliente): esas filas
no son deuda y no se listan aca.
*/
CREATE OR REPLACE VIEW VISTA_VENTAS_PENDIENTES_PAGO AS
SELECT
    N.ID_VENTA,
    N.ID_CLIENTE,
    N.ESTADO,
    N.SUBTOTAL_ORIGINAL AS TOTAL,
    N.PAGADO,
    N.SALDO
FROM VW_VENTA_NETA N
WHERE N.ESTADO NOT IN ('CANCELADA', 'DEVUELTA')
  AND N.SALDO > 0;

/*
VW_REPORTE_VENTAS
Resumen consolidado: UNA fila por venta con el empleado que la atendio,
el cliente, el subtotal original, lo cobrado y el saldo neto de
VW_VENTA_NETA. Para CANCELADA y DEVUELTA el saldo se muestra en 0: ya no
se les cobra. Quien solo quiera lo cobrable usa VISTA_VENTAS_PENDIENTES_PAGO.
*/
CREATE OR REPLACE VIEW VW_REPORTE_VENTAS AS
SELECT
    N.ID_VENTA,
    N.FECHA,
    N.ESTADO,
    E.NOMBRE AS EMPLEADO,
    C.NOMBRE AS CLIENTE,
    V.FACTURA,
    N.SUBTOTAL_ORIGINAL AS TOTAL,
    N.PAGADO,
    CASE WHEN N.ESTADO IN ('CANCELADA', 'DEVUELTA') THEN 0
         ELSE N.SALDO END AS SALDO
FROM VW_VENTA_NETA N
JOIN VENTAS V ON V.ID_VENTA = N.ID_VENTA
JOIN EMPLEADOS E ON E.ID_EMPLEADO = V.ID_EMPLEADO
JOIN CLIENTES  C ON C.ID_CLIENTE  = V.ID_CLIENTE;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_MONTO_PAGO ;
/*
TR_VALIDAR_MONTO_PAGO
Solo acepta pagos mientras la venta siga abierta (EN_PROCESO) y no deja
que se pague mas de lo que vale la venta. Antes de guardar, revisa el
estado y suma lo ya pagado; si algo no cuadra corta con error.
NOTA (Parte 2, 07/10/2026): es el FRENO de la cadena de cobro. Corre
dentro del MISMO INSERT que hace 24_SP_REGISTRAR_PAGO, antes de guardar:
1) la venta esta abierta (EN_PROCESO) y 2) pagado + nuevo <= TOTAL; si no
cuadra, SIGNAL y no se guarda nada. Nunca mira MONTO_RECIBIDO (el vuelto):
solo MONTO, lo que se aplica a la venta.
*/
CREATE TRIGGER TR_VALIDAR_MONTO_PAGO
BEFORE INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(10, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(10, 2);
    DECLARE V_ESTADO VARCHAR(20);
    -- (11/10/2026) Cobro por BRUTO.

    SELECT TOTAL, ESTADO INTO V_TOTAL_VENTA, V_ESTADO FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    -- (29/10/2026) BRUTO neto de devoluciones (VW_VENTA_NETA).
    SELECT BRUTO_NETO INTO V_TOTAL_VENTA
      FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;

    IF V_ESTADO <> 'EN_PROCESO' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ESTA ABIERTA PARA RECIBIR PAGOS.';
    END IF;

    IF (V_TOTAL_PAGADO + NEW.MONTO) > V_TOTAL_VENTA THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_BORRADO_PAGO ;
/*
TR_VALIDAR_BORRADO_PAGO
Un pago de una venta CANCELADA o DEVUELTA no se borra, ni con DELETE directo:
ahi la plata ya quedo resuelta y el cobro dejaria de cuadrar. Es la misma
regla que aplica SP_ANULAR_PAGO (que ademas quita el bono del 1%) ahora
hecha valer tambien cuando el borrado no pasa por el SP.
*/
CREATE TRIGGER TR_VALIDAR_BORRADO_PAGO
BEFORE DELETE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_ESTADO VARCHAR(20);

    SELECT ESTADO INTO V_ESTADO FROM VENTAS WHERE ID_VENTA = OLD.ID_VENTA;

    IF V_ESTADO IS NULL OR V_ESTADO NOT IN ('EN_PROCESO', 'REALIZADA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).';
    END IF;
END //
DELIMITER ;


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUTO_FINALIZAR_VENTA;
/*
TR_AUTO_FINALIZAR_VENTA
Cuando entra un pago, revisa si ya se cubrio el total de la venta.
Si se pago todo, marca la venta REALIZADA y ahi si crea el bono del 1%
al empleado: el bono se gana al cobrar, no al agregar productos.
NOTA (Parte 2, 07/10/2026): es el CIERRE de la cadena. Corre despues de
guardar el pago, en el mismo INSERT. El bono del 1% se calcula sobre el
TOTAL de la venta (no sobre lo pagado) y solo dispara la PRIMERA vez que
se cubre: la condicion V_ESTADO = 'EN_PROCESO' es el guardia
anti-doble-bono (un pago extra o un UPDATE ya no vuelve a crear bono).
*/
CREATE TRIGGER TR_AUTO_FINALIZAR_VENTA
AFTER INSERT ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;
    -- (11/10/2026) SUBTOTAL para el bono; el cierre es por BRUTO.
    DECLARE V_SUBTOTAL DECIMAL(12, 2);

    SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
    FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

    SET V_SUBTOTAL = V_TOTAL_VENTA;
    -- (29/10/2026) Cierre por BRUTO neto; el bono sigue sobre el SUBTOTAL.
    SELECT BRUTO_NETO INTO V_TOTAL_VENTA
      FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
    FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    -- Solo la primera vez que se cubre el total (la venta sigue EN_PROCESO)
    IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = NEW.ID_VENTA;

        INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
        VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                ROUND(V_SUBTOTAL * 0.01, 2),
                CONCAT('Comisión por venta #', NEW.ID_VENTA),
                'PENDIENTE');
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_UPDATE_PAGO ;
/*
TR_VALIDAR_UPDATE_PAGO
El pago de una venta tampoco se edita a pelo: un UPDATE directo no puede
moverlo a otra venta, no puede pasarse del total y no toca pagos de una
venta que ya esta CANCELADA o DEVUELTA (ahi la plata ya quedo resuelta).
Misma regla que TR_VALIDAR_MONTO_PAGO al insertar y que
TR_VALIDAR_BORRADO_PAGO al borrar.
*/
CREATE TRIGGER TR_VALIDAR_UPDATE_PAGO
BEFORE UPDATE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);

    -- El pago se queda en su venta
    IF NEW.ID_VENTA <> OLD.ID_VENTA THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL PAGO NO CAMBIA DE VENTA.';
    END IF;

    SELECT TOTAL, ESTADO INTO V_TOTAL_VENTA, V_ESTADO
      FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

    -- (29/10/2026) Tope por BRUTO neto (VW_VENTA_NETA).
    SELECT BRUTO_NETO INTO V_TOTAL_VENTA
      FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;

    IF V_ESTADO IS NULL OR V_ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ADMITE CAMBIOS DE PAGO (ESTA CANCELADA O DEVUELTA).';
    END IF;

    -- La suma con el cambio aplicado no puede pasarse del total
    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
      FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

    IF (V_TOTAL_PAGADO - OLD.MONTO + NEW.MONTO) > V_TOTAL_VENTA THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL MONTO DEL PAGO EXCEDE EL TOTAL DE LA VENTA.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_UPDATE ;
/*
TR_RECALCULAR_ESTADO_PAGO_UPDATE
Si alguien le cambia el monto a un pago, la venta puede quedar cobrada al
100% o dejar de estarlo: aqui se vuelve a sumar lo cobrado y se mueve el
estado (con su bono del 1% y su reapertura) igual que al insertar o al
anular, para que un UPDATE directo no deje la venta mintiendo.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_UPDATE
AFTER UPDATE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;
    -- (11/10/2026) SUBTOTAL para el bono; comparaciones por BRUTO.
    DECLARE V_SUBTOTAL DECIMAL(12, 2);

    IF NEW.MONTO <> OLD.MONTO THEN
        SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
          FROM VENTAS WHERE ID_VENTA = NEW.ID_VENTA;

        SET V_SUBTOTAL = V_TOTAL_VENTA;
        SELECT BRUTO_NETO INTO V_TOTAL_VENTA
          FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;

        SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
          FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;

        -- Quedo cobrada al 100%: se cierra y nace el bono del 1%
        IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_VENTA > 0 AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
            UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = NEW.ID_VENTA;

            INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
            VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                    ROUND(V_SUBTOTAL * 0.01, 2),
                    CONCAT('Comisión por venta #', NEW.ID_VENTA),
                    'PENDIENTE');
        END IF;

        -- Dejo de estar cobrada: se reabre y se va el bono pendiente
        IF V_ESTADO = 'REALIZADA' AND V_TOTAL_PAGADO < V_TOTAL_VENTA THEN
            UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = NEW.ID_VENTA;

            DELETE FROM BONOS_EMPLEADOS
            WHERE ID_EMPLEADO = V_ID_EMPLEADO
              AND DESCRIPCION = CONCAT('Comisión por venta #', NEW.ID_VENTA)
              AND ESTADO = 'PENDIENTE';
        END IF;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_RECALCULAR_ESTADO_PAGO_BORRADO ;
/*
TR_RECALCULAR_ESTADO_PAGO_BORRADO
Cuando un pago desaparece (DELETE directo, no por SP) la venta puede dejar
de estar cobrada: aqui se vuelve a sumar lo cobrado y se mueve el estado,
mismo trabajo que hace SP_ANULAR_PAGO pero para el borrado que no pasa por
el. Con su bono del 1% pendiente, que ya no corresponde si se fue el pago.
*/
CREATE TRIGGER TR_RECALCULAR_ESTADO_PAGO_BORRADO
AFTER DELETE ON PAGOS
FOR EACH ROW
BEGIN
    DECLARE V_TOTAL_VENTA DECIMAL(12, 2);
    DECLARE V_TOTAL_PAGADO DECIMAL(12, 2);
    DECLARE V_ESTADO VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;
    -- (11/10/2026) SUBTOTAL para el bono; comparaciones por BRUTO.
    DECLARE V_SUBTOTAL DECIMAL(12, 2);

    SELECT TOTAL, ESTADO, ID_EMPLEADO INTO V_TOTAL_VENTA, V_ESTADO, V_ID_EMPLEADO
      FROM VENTAS WHERE ID_VENTA = OLD.ID_VENTA;

    SET V_SUBTOTAL = V_TOTAL_VENTA;
    SELECT BRUTO_NETO INTO V_TOTAL_VENTA
      FROM VW_VENTA_NETA WHERE ID_VENTA = OLD.ID_VENTA;

    SELECT IFNULL(SUM(MONTO), 0) INTO V_TOTAL_PAGADO
      FROM PAGOS WHERE ID_VENTA = OLD.ID_VENTA;

    IF V_ESTADO = 'REALIZADA' AND V_TOTAL_PAGADO < V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = OLD.ID_VENTA;

        DELETE FROM BONOS_EMPLEADOS
        WHERE ID_EMPLEADO = V_ID_EMPLEADO
          AND DESCRIPCION = CONCAT('Comisión por venta #', OLD.ID_VENTA)
          AND ESTADO = 'PENDIENTE';
    END IF;

    IF V_ESTADO = 'EN_PROCESO' AND V_TOTAL_VENTA > 0 AND V_TOTAL_PAGADO >= V_TOTAL_VENTA THEN
        UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = OLD.ID_VENTA;

        INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO)
        VALUES (V_ID_EMPLEADO, CURRENT_DATE(), 'BONIFICACION',
                ROUND(V_SUBTOTAL * 0.01, 2),
                CONCAT('Comisión por venta #', OLD.ID_VENTA),
                'PENDIENTE');
    END IF;
END //
DELIMITER ;







-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 
/*
VISTA_RESUMEN_PAGOS
Muestra los pagos con el nombre de su metodo de pago, monto y fecha.
Sirve como resumen de cobros para revisar en pantalla o en reportes.
Ahora trae tambien al empleado que cobro (P8).
Ahora trae tambien el monto recibido y el VUELTO (P9).
*/
CREATE OR REPLACE VIEW VISTA_RESUMEN_PAGOS AS
SELECT 
    P.ID_PAGO,
    P.ID_VENTA,
    MP.NOMBRE AS NOMBRE_METODO, 
    E.NOMBRE AS NOMBRE_EMPLEADO,
    P.MONTO,
    P.MONTO_RECIBIDO,
    P.MONTO_RECIBIDO - P.MONTO AS VUELTO,
    P.FECHA
FROM PAGOS P
JOIN METODOS_PAGO MP ON P.ID_METODO_PAGO = MP.ID_METODO_PAGO
JOIN EMPLEADOS E ON P.ID_EMPLEADO = E.ID_EMPLEADO;
















-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[REPORTES_VENTAS: movido del 37}----------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------
/*
MOVIDO del archivo 37- REPORTES_VENTAS.sql el 12/10/2026: los reportes leen
PAGOS (cobros por metodo, saldos), asi que viven en este flujo y no en un
archivo suelto. Nombres de SP/vista intactos: la app no se toca.
CAMBIO 12/10/2026: SALDO y MONTO_REALIZADO van a BRUTO
(SUBTOTAL + ITBIS - ITBIS devuelto), porque desde el 11/10 se cobra el bruto
y con TOTAL el saldo quedaba negativo en ventas pagadas.
*/



DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTE_VENTAS ;
/*
SP_REPORTE_VENTAS
Listado de ventas por rango de fechas (ambos dias incluidos, a nivel de
dia completo). Devuelve las mismas columnas que VW_REPORTE_VENTAS pero
filtrado por el rango y ordenado del mas reciente al mas viejo. Corta con
error si el rango viene invertido.
*/
CREATE PROCEDURE SP_REPORTE_VENTAS(
    IN P_FECHA_INICIO DATE,
    IN P_FECHA_FIN    DATE
)
proc_label: BEGIN
    -- 1. El rango tiene sentido
    IF P_FECHA_INICIO > P_FECHA_FIN THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: LA FECHA INICIAL NO PUEDE SER MAYOR A LA FINAL.';
    END IF;

    -- 2. Listado (la fecha final entra completa: se suma 1 dia al tope)
    SELECT *
      FROM VW_REPORTE_VENTAS
     WHERE FECHA >= P_FECHA_INICIO
       AND FECHA <  P_FECHA_FIN + INTERVAL 1 DAY
     ORDER BY FECHA DESC, ID_VENTA DESC;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CIERRE_CAJA ;
/*
SP_CIERRE_CAJA
Cierre de caja de un dia: primero el resumen general (ventas, monto en
REALIZADAS a BRUTO y cobro real), despues las ventas agrupadas por estado
(montos a BRUTO) y por ultimo lo cobrado desglosado por metodo de pago.
Son 3 result sets seguidos. Solo lectura.
*/
CREATE PROCEDURE SP_CIERRE_CAJA(IN P_FECHA DATE)
proc_label: BEGIN
    -- 1. La fecha no puede faltar
    IF P_FECHA IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: INGRESE LA FECHA DEL CIERRE.';
    END IF;

    -- 2. Resumen general del dia
    SELECT
        P_FECHA AS FECHA,
        (SELECT COUNT(*) FROM VENTAS
          WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY)
            AS VENTAS_DEL_DIA,
        (SELECT IFNULL(SUM(BRUTO_NETO), 0) FROM VW_VENTA_NETA
          WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY
            AND ESTADO = 'REALIZADA')
            AS MONTO_REALIZADO,
        (SELECT IFNULL(SUM(MONTO), 0) FROM PAGOS
          WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY)
            AS COBRADO;

    -- 3. Las ventas del dia agrupadas por estado (montos a BRUTO neto)
    SELECT ESTADO,
           COUNT(*) AS CANTIDAD,
           IFNULL(SUM(BRUTO_NETO), 0) AS MONTO
      FROM VW_VENTA_NETA
     WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY
     GROUP BY ESTADO;

    -- 4. Lo cobrado del dia por metodo de pago
    SELECT MP.NOMBRE AS METODO,
           COUNT(*) AS OPERACIONES,
           IFNULL(SUM(P.MONTO), 0) AS COBRADO
      FROM PAGOS P
      JOIN METODOS_PAGO MP ON MP.ID_METODO_PAGO = P.ID_METODO_PAGO
     WHERE P.FECHA >= P_FECHA AND P.FECHA < P_FECHA + INTERVAL 1 DAY
     GROUP BY MP.ID_METODO_PAGO, MP.NOMBRE
     ORDER BY COBRADO DESC;
END //
DELIMITER ;

/*
SP_REPORTE_PERIODO (14/10/2026)
Reporte de ventas REALIZADAS en un rango de fechas (inclusive).
Devuelve una fila: transacciones, subtotal (base), ITBIS real y BRUTO.
BRUTO neto de devoluciones (VW_VENTA_NETA). Sin ganancia (ver 38- GANANCIAS.sql).
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REPORTE_PERIODO //
CREATE PROCEDURE SP_REPORTE_PERIODO(
    IN P_DESDE DATE,
    IN P_HASTA DATE
)
proc_label: BEGIN
    IF P_DESDE IS NULL OR P_HASTA IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE INDICAR DESDE Y HASTA.';
        LEAVE proc_label;
    END IF;

    IF P_DESDE > P_HASTA THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DESDE NO PUEDE SER MAYOR QUE HASTA.';
        LEAVE proc_label;
    END IF;

    SELECT
        COUNT(*) AS TRANSACCIONES,
        ROUND(IFNULL(SUM(SUBTOTAL_NETO), 0), 2) AS SUBTOTAL,
        ROUND(IFNULL(SUM(ITBIS_NETO), 0), 2) AS ITBIS,
        ROUND(IFNULL(SUM(BRUTO_NETO), 0), 2) AS BRUTO
      FROM VW_VENTA_NETA
     WHERE ESTADO = 'REALIZADA'
       AND DATE(FECHA) BETWEEN P_DESDE AND P_HASTA;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_ACTUALIZACION_VENTA ;
/*
TR_VALIDAR_ACTUALIZACION_VENTA
El candado de la cabecera de la venta: nadie cambia el ESTADO ni el TOTAL
con un UPDATE a pelo. El TOTAL solo lo mueve su trigger de detalle (que
levanta @VENTAS_INTERNO), REALIZADA exige cobro al 100%, CANCELADA solo
sale de SP_CANCELAR_VENTA (asi nadie se salta la reversión del stock) y
DEVUELTA solo cuando no queda ni una unidad por devolver. Una venta ya
CANCELADA o DEVUELTA no vuelve a cambiar jamas.
NOTA (Parte 3, 07/10/2026): resumen del candado - el TOTAL solo se
mueve con la bandera @VENTAS_INTERNO; -> REALIZADA exige cobro al 100%
(por eso el auto-cierre del 24 pasa SIN bandera); -> CANCELADA exige
bandera + EN_PROCESO + cero pagos; CANCELADA/DEVUELTA no salen jamas.
La bandera la levantan solo SP_CANCELAR_VENTA (21) y
TR_ACTUALIZAR_TOTAL_VENTA (23). RIESGO VIGILADO: el par SET 1/0 no
tiene EXIT HANDLER - si el UPDATE interno falla, la credencial queda
prendida en la sesion y, como las variables de usuario no se revierten
con ROLLBACK, un UPDATE a pelo posterior se colaria (demostrado en
Pruebas/test_blindaje_p3.sql). OBSERVACION: la rama 'SOLO SE REABRE
UNA VENTA REALIZADA' es inalcanzable con los 4 estados (pasar de
EN_PROCESO al mismo valor no es cambio; CANCELADA/DEVUELTA las corta
el primer if) - queda como codigo defensivo.
*/
CREATE TRIGGER TR_VALIDAR_ACTUALIZACION_VENTA
BEFORE UPDATE ON VENTAS
FOR EACH ROW
BEGIN
    DECLARE V_COBRADO DECIMAL(12, 2);
    DECLARE V_BRUTO DECIMAL(12, 2);

    -- El TOTAL solo lo toca TR_ACTUALIZAR_TOTAL_VENTA
    IF NEW.TOTAL <> OLD.TOTAL AND IFNULL(@VENTAS_INTERNO, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL TOTAL DE LA VENTA SOLO CAMBIA CON SU DETALLE.';
    END IF;

    IF NEW.ESTADO <> OLD.ESTADO THEN
        IF OLD.ESTADO IN ('CANCELADA', 'DEVUELTA') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: LA VENTA YA ESTA CANCELADA O DEVUELTA; ESE ESTADO NO CAMBIA.';
        END IF;

        IF NEW.ESTADO = 'REALIZADA' THEN
            -- Solo se marca REALIZADA una venta cobrada al 100% de su
            -- BRUTO neto (29/10/2026: descuenta las devoluciones).
            SELECT IFNULL(SUM(MONTO), 0) INTO V_COBRADO
              FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA;
            SELECT BRUTO_NETO INTO V_BRUTO
              FROM VW_VENTA_NETA WHERE ID_VENTA = NEW.ID_VENTA;
            IF OLD.ESTADO <> 'EN_PROCESO' OR V_BRUTO <= 0 OR V_COBRADO < V_BRUTO THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA REALIZADA UNA VENTA COBRADA AL 100%.';
            END IF;

        ELSEIF NEW.ESTADO = 'EN_PROCESO' THEN
            -- Reapertura: solo de una REALIZADA (se anulo un pago)
            IF OLD.ESTADO <> 'REALIZADA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE REABRE UNA VENTA REALIZADA.';
            END IF;

        ELSEIF NEW.ESTADO = 'CANCELADA' THEN
            -- La cancelacion revierte stock y bitacora: solo por el SP
            IF IFNULL(@VENTAS_INTERNO, 0) <> 1 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: USE SP_CANCELAR_VENTA; LA CANCELACION REVERSIA EL STOCK.';
            END IF;
            IF OLD.ESTADO <> 'EN_PROCESO' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE CANCELA UNA VENTA EN PROCESO.';
            END IF;
            IF EXISTS (SELECT 1 FROM PAGOS WHERE ID_VENTA = NEW.ID_VENTA) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA VENTA TIENE PAGOS; ANULELOS ANTES DE CANCELAR.';
            END IF;

        ELSEIF NEW.ESTADO = 'DEVUELTA' THEN
            -- Solo llega devuelta enterita (mismo criterio que
            -- TR_MARCAR_VENTA_DEVUELTA en el archivo 25)
            IF OLD.ESTADO <> 'REALIZADA' THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: SOLO SE MARCA DEVUELTA UNA VENTA REALIZADA.';
            END IF;
            IF EXISTS (
                SELECT 1
                FROM DETALLES_VENTA DV
                WHERE DV.ID_VENTA = NEW.ID_VENTA
                  AND DV.CANTIDAD > IFNULL(
                        (SELECT SUM(D.CANTIDAD)
                           FROM DEVOLUCIONES D
                          WHERE D.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
                            AND D.ESTADO IN ('APROBADA', 'REEMBOLSADA')), 0)
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: LA VENTA NO ESTA DEVUELTA ENTERA; QUEDAN UNIDADES.';
            END IF;

        ELSE
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: ESTADO DE VENTA DESCONOCIDO.';
        END IF;
    END IF;
END //
DELIMITER ;
