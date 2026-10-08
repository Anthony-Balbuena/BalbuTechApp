/*
ARCHIVO 37 - REPORTES_VENTAS
Objetos de consulta del flujo de ventas: la vista VW_REPORTE_VENTAS
(resumen por venta con lo cobrado y el saldo), el listado por rango de
fechas (SP_REPORTE_VENTAS) y el cierre de caja del dia (SP_CIERRE_CAJA).
Todos son de SOLO LECTURA: ninguno modifica datos. Carga al final, despues
del 36.
*/

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[VIEW}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

/*
VW_REPORTE_VENTAS
Resumen consolidado: UNA fila por venta con el empleado que la atendio,
el cliente, el total, lo efectivamente cobrado (SUM sobre PAGOS) y el
saldo que falta. Es la version real del ejemplo que solo existia en la
documentacion. Ojo con CANCELADA/DEVUELTA: a esas ya no se les cobra, el
saldo se muestra tal cual (quien solo quiera lo cobrable usa
VISTA_VENTAS_PENDIENTES_PAGO, que las excluye).
*/
CREATE OR REPLACE VIEW VW_REPORTE_VENTAS AS
SELECT
    V.ID_VENTA,
    V.FECHA,
    V.ESTADO,
    E.NOMBRE AS EMPLEADO,
    C.NOMBRE AS CLIENTE,
    V.FACTURA,
    V.TOTAL,
    IFNULL(PG.PAGADO, 0) AS PAGADO,
    V.TOTAL - IFNULL(PG.PAGADO, 0) AS SALDO
FROM VENTAS V
JOIN EMPLEADOS E ON E.ID_EMPLEADO = V.ID_EMPLEADO
JOIN CLIENTES  C ON C.ID_CLIENTE  = V.ID_CLIENTE
LEFT JOIN (SELECT ID_VENTA, SUM(MONTO) AS PAGADO
             FROM PAGOS
            GROUP BY ID_VENTA) PG ON PG.ID_VENTA = V.ID_VENTA;

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

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

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure: CIERRE}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CIERRE_CAJA ;
/*
SP_CIERRE_CAJA
Cierre de caja de un dia: primero el resumen general (ventas, monto en
REALIZADAS y cobro real), despues las ventas agrupadas por estado y
por ultimo lo cobrado desglosado por metodo de pago. Son 3 result sets
seguidos. Solo lectura.
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
        (SELECT IFNULL(SUM(TOTAL), 0) FROM VENTAS
          WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY
            AND ESTADO = 'REALIZADA')
            AS MONTO_REALIZADO,
        (SELECT IFNULL(SUM(MONTO), 0) FROM PAGOS
          WHERE FECHA >= P_FECHA AND FECHA < P_FECHA + INTERVAL 1 DAY)
            AS COBRADO;

    -- 3. Las ventas del dia agrupadas por estado
    SELECT ESTADO,
           COUNT(*) AS CANTIDAD,
           IFNULL(SUM(TOTAL), 0) AS MONTO
      FROM VENTAS
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
