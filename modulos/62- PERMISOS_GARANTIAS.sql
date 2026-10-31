-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE GARANTIAS
-- ================================================================
-- (30/10/2026) Saca Garantias de GESTIONAR_VENTAS y le da cuatro permisos
-- propios, con el mismo patron que Clientes, Proveedores, Inventario y demas:
--   GARANTIAS_REGISTRAR  - registrar una garantia a mano
--   GARANTIAS_RECLAMAR   - abrir un reclamo sobre una garantia vigente
--   GARANTIAS_FINALIZAR  - cerrar un reclamo (decision de Gerencia)
--   GARANTIAS_CONSULTAR  - ver garantias y reclamos
--
-- La diferencia clave: el vendedor atiende y registra, pero NO cierra
-- reclamos. VENDEDOR conserva REGISTRAR, RECLAMAR y CONSULTAR.
--
-- ORDEN DE DESPLIEGUE:
--   1. Correr 63- GARANTIAS_FLUJO.sql.
--   2. Desplegar el binario nuevo.
--   3. Correr este modulo.
-- El binario viejo abre Garantias con GESTIONAR_VENTAS; si este modulo corre
-- antes, el item desaparece del menu hasta desplegar el binario nuevo. No se
-- pierden datos: solo se oculta el modulo.
--
-- GESTIONAR_VENTAS NO se borra: lo siguen usando las otras nueve acciones de
-- Ventas (venta rapida, cancelar, anular pago, devolucion, cierre de caja,
-- cobrar, etc.). Solo deja de abrir Garantias.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('GARANTIAS_REGISTRAR', 'Registrar garantias de productos vendidos'),
('GARANTIAS_RECLAMAR',  'Registrar reclamos sobre garantias vigentes'),
('GARANTIAS_FINALIZAR', 'Cerrar reclamos de garantia'),
('GARANTIAS_CONSULTAR', 'Consultar garantias y reclamos')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON (
        (P.NOMBRE_PERMISO IN ('GARANTIAS_REGISTRAR', 'GARANTIAS_RECLAMAR', 'GARANTIAS_CONSULTAR')
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'VENDEDOR'))
     OR (P.NOMBRE_PERMISO = 'GARANTIAS_CONSULTAR'
         AND R.NOMBRE_ROL = 'CONTABILIDAD')
     OR (P.NOMBRE_PERMISO = 'GARANTIAS_FINALIZAR'
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE'))
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

SELECT R.NOMBRE_ROL, COUNT(*) AS PERMISOS_GARANTIA
  FROM ROL_PERMISO RP
  JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
  JOIN ROLES R ON R.NOMBRE_ROL = RP.ROL_NOMBRE
 WHERE P.NOMBRE_PERMISO LIKE 'GARANTIAS_%'
 GROUP BY R.NOMBRE_ROL
 ORDER BY R.NOMBRE_ROL;

SELECT 'PERMISOS DE GARANTIAS APLICADOS.' AS RESULTADO;
