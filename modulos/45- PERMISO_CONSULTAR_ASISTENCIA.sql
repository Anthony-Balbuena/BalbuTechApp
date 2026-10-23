-- ================================================================
-- BALBU_TECH - ASISTENCIA CON ITEM PROPIO
-- ================================================================
-- (23/10/2026) La asistencia sale del modulo Empleados y pasa a un item
-- propio del menu principal. Este modulo deja la matriz de permisos lista
-- para bases ya existentes (la viva y TEST).
--
-- Reglas:
--   * Fichar (REGISTRAR_ASISTENCIA): los 7 roles.
--   * Ver reportes (CONSULTAR_ASISTENCIA): ADMIN, GERENTE, SUBGERENTE y RRHH.
--     VENDEDOR queda afuera a proposito: el cajero no ve la asistencia de todos.
--   * SUBGERENTE conserva el item Empleados con EMPLEADOS_VER (solo lectura)
--     y puede justificar asistencia.
--
-- No se elimina ningun permiso existente. Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION)
VALUES ('CONSULTAR_ASISTENCIA', 'Consultar reportes de asistencia')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Fichar: los 7 roles.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO = 'REGISTRAR_ASISTENCIA'
WHERE R.NOMBRE_ROL IN (
    'ADMIN', 'GERENTE', 'SUBGERENTE', 'RRHH', 'VENDEDOR', 'ALMACEN', 'CONTABILIDAD'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Ver reportes: gestion y RRHH.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO = 'CONSULTAR_ASISTENCIA'
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'RRHH')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Subgerente: lectura de empleados para conservar el item del menu.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'SUBGERENTE', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO = 'EMPLEADOS_VER'
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Subgerente: justificar asistencia.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'SUBGERENTE', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO = 'JUSTIFICAR_ASISTENCIA'
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;
