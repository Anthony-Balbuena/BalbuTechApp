-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE MARCAS
-- ================================================================
-- (23/10/2026) Separa el modulo Marcas en cuatro permisos finos, con el
-- mismo corte que Clientes, Proveedores y Categorias: MARCAS_VER,
-- MARCAS_CREAR, MARCAS_EDITAR y MARCAS_ESTADO reemplazan al paraguas
-- GESTIONAR_MARCAS.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_MARCAS; si este modulo corre
-- antes, el item Marcas desaparece del menu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('MARCAS_VER', 'Consultar y buscar marcas'),
('MARCAS_CREAR', 'Registrar marcas'),
('MARCAS_EDITAR', 'Actualizar datos de marcas'),
('MARCAS_ESTADO', 'Activar o desactivar marcas')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: los cuatro roles que hoy tienen el paraguas reciben los
-- cuatro permisos finos. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'MARCAS_VER', 'MARCAS_CREAR',
    'MARCAS_EDITAR', 'MARCAS_ESTADO'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_MARCAS';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_MARCAS';

SELECT 'PERMISOS DE MARCAS APLICADOS.' AS RESULTADO;
