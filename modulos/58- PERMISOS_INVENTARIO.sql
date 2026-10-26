-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE INVENTARIO
-- ================================================================
-- (26/10/2026) Separa el modulo Inventario en tres permisos finos, con el mismo
-- patron que Clientes, Proveedores, Categorias, Marcas, Metodos de pago y
-- Compras: INVENTARIO_VER (Movimientos), INVENTARIO_AJUSTAR (Ajuste de stock) e
-- INVENTARIO_COSTO (Ajustar p.compra) reemplazan al paraguas
-- GESTIONAR_INVENTARIO. Es el ultimo modulo con permiso paraguas de la Tanda B.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_INVENTARIO; si este modulo corre
-- antes, el item Inventario desaparece del menu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('INVENTARIO_VER', 'Consultar movimientos de inventario'),
('INVENTARIO_AJUSTAR', 'Registrar ajustes de stock'),
('INVENTARIO_COSTO', 'Actualizar el costo de compra de productos')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: los cuatro roles que hoy tienen el paraguas reciben los
-- tres permisos finos. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'INVENTARIO_VER', 'INVENTARIO_AJUSTAR', 'INVENTARIO_COSTO'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_INVENTARIO';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_INVENTARIO';

SELECT 'PERMISOS DE INVENTARIO APLICADOS.' AS RESULTADO;
