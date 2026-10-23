-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE CATEGORIAS
-- ================================================================
-- (23/10/2026) Separa el modulo Categorias en cuatro permisos finos, con el
-- mismo corte que Clientes y Proveedores: CATEGORIAS_VER, CATEGORIAS_CREAR,
-- CATEGORIAS_EDITAR y CATEGORIAS_ESTADO reemplazan al paraguas
-- GESTIONAR_CATEGORIAS.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_CATEGORIAS; si este modulo corre
-- antes, el item Categorias desaparece del menu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('CATEGORIAS_VER', 'Consultar y buscar categorias'),
('CATEGORIAS_CREAR', 'Registrar categorias'),
('CATEGORIAS_EDITAR', 'Actualizar datos de categorias'),
('CATEGORIAS_ESTADO', 'Activar o desactivar categorias')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: los cuatro roles que hoy tienen el paraguas reciben los
-- cuatro permisos finos. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'CATEGORIAS_VER', 'CATEGORIAS_CREAR',
    'CATEGORIAS_EDITAR', 'CATEGORIAS_ESTADO'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_CATEGORIAS';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_CATEGORIAS';

SELECT 'PERMISOS DE CATEGORIAS APLICADOS.' AS RESULTADO;
