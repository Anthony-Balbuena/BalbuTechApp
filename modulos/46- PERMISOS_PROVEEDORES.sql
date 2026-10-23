-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE PROVEEDORES
-- ================================================================
-- (23/10/2026) Reemplaza el permiso unico GESTIONAR_PROVEEDORES por cuatro
-- permisos finos, con el mismo corte que Clientes.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo usa GESTIONAR_PROVEEDORES; si este modulo corre antes, el
-- item Proveedores desaparece del menu hasta desplegar el binario nuevo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('PROVEEDORES_VER', 'Consultar y buscar proveedores'),
('PROVEEDORES_CREAR', 'Registrar proveedores'),
('PROVEEDORES_EDITAR', 'Actualizar datos de proveedores'),
('PROVEEDORES_ESTADO', 'Activar o desactivar proveedores')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Preserva el acceso de cualquier rol (incluidos los personalizados) que hoy
-- tenga el permiso paraguas: le da los cuatro finos antes de borrarlo.
-- Se usa una temporal para no leer y escribir ROL_PERMISO en la misma
-- sentencia (MariaDB lo rechaza).
DROP TEMPORARY TABLE IF EXISTS TMP_ROLES_PROVEEDORES;
CREATE TEMPORARY TABLE TMP_ROLES_PROVEEDORES (
    ROL_NOMBRE VARCHAR(50) NOT NULL PRIMARY KEY
);
INSERT INTO TMP_ROLES_PROVEEDORES (ROL_NOMBRE)
SELECT DISTINCT RP.ROL_NOMBRE
FROM ROL_PERMISO RP
JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_PROVEEDORES';

INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT T.ROL_NOMBRE, P.ID_PERMISO
FROM TMP_ROLES_PROVEEDORES T
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'PROVEEDORES_VER', 'PROVEEDORES_CREAR',
    'PROVEEDORES_EDITAR', 'PROVEEDORES_ESTADO'
)
ON DUPLICATE KEY UPDATE ROL_PERMISO.ROL_NOMBRE = ROL_PERMISO.ROL_NOMBRE;

DROP TEMPORARY TABLE IF EXISTS TMP_ROLES_PROVEEDORES;

-- Asegura la matriz objetivo aun si el paraguas ya no existe (base nueva o
-- reimportacion del modulo 36).
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'PROVEEDORES_VER', 'PROVEEDORES_CREAR',
    'PROVEEDORES_EDITAR', 'PROVEEDORES_ESTADO'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN')
ON DUPLICATE KEY UPDATE ROL_PERMISO.ROL_NOMBRE = ROL_PERMISO.ROL_NOMBRE;

-- Borra el paraguas viejo. Sus pares caen por ON DELETE CASCADE.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_PROVEEDORES';
