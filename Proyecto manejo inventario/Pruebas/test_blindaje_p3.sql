-- =============================================================================
-- test_blindaje_p3.sql — Recreación de los suites viejos de la Parte 3
-- (test_blindaje, smoke_fase1, test_fase_h, test_paquetito_j/k; se perdieron
--  en la limpieza de /tmp). Cubre los checks de candados (B*) y historial (H*)
--  descritos en "contexto tabla ventas.txt" sección 13.
-- Uso:  mariadb --force -h 127.0.0.1 -uroot -pXXX BALBU_TECH < test_blindaje_p3.sql
--       (--force = continuar tras los SIGNAL esperados de cada candado;
--        sin él el cliente se detiene en el primer ERROR)
-- Cada bloque va en SU PROPIA sesión con START TRANSACTION ... ROLLBACK:
-- los candados lanzan SIGNAL y el cliente se detiene; al desconectar la
-- transacción revierte sola. Residuo esperado: 0 en todas las tablas.
-- Fecha: 07/10/2026 (Parte 3 — Blindajes)
-- =============================================================================

-- --- B1: el TOTAL a pelo no pasa ------------------------------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b1);
UPDATE VENTAS SET TOTAL = 999 WHERE ID_VENTA = @b1;
-- Esperado: ERROR: EL TOTAL DE LA VENTA SOLO CAMBIA CON SU DETALLE.
ROLLBACK;

-- --- B2: REALIZADA sin cobro no pasa --------------------------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b2);
UPDATE VENTAS SET ESTADO = 'REALIZADA' WHERE ID_VENTA = @b2;
-- Esperado: ERROR: SOLO SE MARCA REALIZADA UNA VENTA COBRADA AL 100%.
ROLLBACK;

-- --- B3: CANCELADA a pelo no pasa (hay que usar el SP) ---------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b3);
UPDATE VENTAS SET ESTADO = 'CANCELADA' WHERE ID_VENTA = @b3;
-- Esperado: ERROR: USE SP_CANCELAR_VENTA; LA CANCELACION REVERSIA EL STOCK.
ROLLBACK;

-- --- B4: EN_PROCESO sobre EN_PROCESO no es cambio (no dispara el candado) -------
-- (y la rama "SOLO SE REABRE UNA VENTA REALIZADA" queda como inalcanzable
--  con los 4 estados: código defensivo — ver nota en 21- VENTAS.sql)
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b4);
UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = @b4;
-- Esperado: pasa sin error (no hay cambio de estado)
ROLLBACK;

-- --- B4b: reabrir una REALIZADA sí es legítimo -----------------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b4b);
CALL SP_AGREGAR_DETALLE_VENTA(@b4b, 20, 1, 7);
CALL 24_SP_REGISTRAR_PAGO(@b4b, 1, 100.00, 7);   -- auto-cierre -> REALIZADA
UPDATE VENTAS SET ESTADO = 'EN_PROCESO' WHERE ID_VENTA = @b4b;
-- Esperado: pasa; la venta queda EN_PROCESO (se anuló un pago)
ROLLBACK;

-- --- B5: DELETE a pelo de la venta no pasa ---------------------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @b5);
DELETE FROM VENTAS WHERE ID_VENTA = @b5;
-- Esperado: ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.
ROLLBACK;

-- --- H: cancelación legítima deja 2 filas de historial ---------------------------
START TRANSACTION;
CALL 21_SP_INICIAR_VENTA(7, 1, @h);
CALL SP_AGREGAR_DETALLE_VENTA(@h, 20, 1, 7);
CALL SP_CANCELAR_VENTA(@h, 7);
SELECT ESTADO_ANTERIOR, ESTADO_NUEVO, MOTIVO
  FROM HISTORIAL_ESTADOS_VENTA WHERE ID_VENTA = @h
 ORDER BY ID_HISTORIAL_ESTADO;
-- Esperado: (NULL, EN_PROCESO, 'Venta iniciada') y
--           (EN_PROCESO, CANCELADA, 'Estado: EN_PROCESO -> CANCELADA')
ROLLBACK;

-- --- FLAG: la bandera @VENTAS_INTERNO sobrevive al ROLLBACK (riesgo) -------------
START TRANSACTION;
SET @VENTAS_INTERNO = 1;          -- simulando un UPDATE interno que falló y no la apagó
ROLLBACK;
SELECT IF(IFNULL(@VENTAS_INTERNO, 0) = 1,
          'RIESGO: la bandera SOBREVIVE al ROLLBACK', 'ok') AS DEMO1;
SET @VENTAS_INTERNO = 0;          -- limpiar la sesión

-- --- FLAG: con la bandera prendida, el candado de TOTAL se colaría ---------------
START TRANSACTION;
SET @VENTAS_INTERNO = 1;          -- credencial "interna" prendida en esta sesión
CALL 21_SP_INICIAR_VENTA(7, 1, @bf);
UPDATE VENTAS SET TOTAL = 99999 WHERE ID_VENTA = @bf;
SELECT CONCAT('BYPASS: TOTAL paso a ', TOTAL) AS DEMO2 FROM VENTAS WHERE ID_VENTA = @bf;
ROLLBACK;
SET @VENTAS_INTERNO = 0;          -- limpiar la sesión

-- --- LÍNEA BASE FINAL (debe volver a 0 / 8) --------------------------------------
SELECT COUNT(*) AS VENTAS      FROM VENTAS;                 -- 0
SELECT COUNT(*) AS DETALLES    FROM DETALLES_VENTA;          -- 0
SELECT COUNT(*) AS HIST_ESTADOS FROM HISTORIAL_ESTADOS_VENTA; -- 0
SELECT STOCK_ACTUAL AS STOCK_20 FROM INVENTARIO WHERE ID_PRODUCTO = 20; -- 8
