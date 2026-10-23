-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE COMPRAS
-- ================================================================
-- (23/10/2026) Separa el modulo Compras en seis permisos finos, con el mismo
-- patron que Clientes, Proveedores, Categorias, Marcas y Metodos de pago:
-- COMPRAS_VER, COMPRAS_REGISTRAR, COMPRAS_PAGAR, COMPRAS_CANCELAR,
-- COMPRAS_DEVOLVER y COMPRAS_REPORTES reemplazan al paraguas GESTIONAR_COMPRAS.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_COMPRAS; si este modulo corre
-- antes, el item Compras desaparece del menu hasta desplegar el binario nuevo.
-- No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('COMPRAS_VER', 'Consultar compras'),
('COMPRAS_REGISTRAR', 'Registrar compras'),
('COMPRAS_PAGAR', 'Pagar compras'),
('COMPRAS_CANCELAR', 'Cancelar compras'),
('COMPRAS_DEVOLVER', 'Registrar devoluciones de compra'),
('COMPRAS_REPORTES', 'Consultar reportes y precios de compras')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: los cuatro roles que hoy tienen el paraguas reciben los
-- seis permisos finos. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'COMPRAS_VER', 'COMPRAS_REGISTRAR', 'COMPRAS_PAGAR',
    'COMPRAS_CANCELAR', 'COMPRAS_DEVOLVER', 'COMPRAS_REPORTES'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_COMPRAS';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_COMPRAS';

SELECT 'PERMISOS DE COMPRAS APLICADOS.' AS RESULTADO;
