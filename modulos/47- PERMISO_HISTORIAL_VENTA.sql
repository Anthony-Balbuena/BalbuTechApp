-- ================================================================
-- BALBU_TECH - PERMISO DE HISTORIAL DE VENTA
-- ================================================================
-- (23/10/2026) El vendedor necesita consultar el historial de una venta, pero
-- no los reportes ni las ganancias. Se separa el historial en un permiso
-- propio (CONSULTAR_HISTORIAL_VENTA) y se le quita CONSULTAR_REPORTES a
-- VENDEDOR. Garantias no cambia: sigue con GESTIONAR_VENTAS.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo pide CONSULTAR_REPORTES para el historial; si este modulo
-- corre antes, la opcion desaparece del submenu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta la opcion.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('CONSULTAR_HISTORIAL_VENTA', 'Consultar el historial de una venta')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- ADMIN, GERENTE y SUBGERENTE conservan el historial; VENDEDOR lo recibe
-- aunque pierda los reportes.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO = 'CONSULTAR_HISTORIAL_VENTA'
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'VENDEDOR')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Solo VENDEDOR pierde los reportes y las ganancias: el resto de los roles
-- conserva CONSULTAR_REPORTES.
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'VENDEDOR'
  AND P.NOMBRE_PERMISO = 'CONSULTAR_REPORTES';

SELECT 'PERMISO DE HISTORIAL DE VENTA APLICADO.' AS RESULTADO;
