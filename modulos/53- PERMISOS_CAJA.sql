-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE CAJA
-- ================================================================
-- (24/10/2026) Caja deja de colgar del paraguas GESTIONAR_VENTAS y pasa a
-- tres permisos propios: CONSULTAR_CAJA (estado del turno), ABRIR_CAJA y
-- CERRAR_CAJA (cierre con cuadre). El vendedor conserva los tres: abre su
-- turno al empezar y lo cierra al terminar. GESTIONAR_VENTAS sigue existiendo
-- y sigue mandando en el modulo Ventas.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo pide GESTIONAR_VENTAS para el item Caja; si este modulo
-- corre antes, el item Caja desaparece del menu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('CONSULTAR_CAJA', 'Consultar el estado del turno de caja'),
('ABRIR_CAJA', 'Abrir el turno de caja'),
('CERRAR_CAJA', 'Cerrar el turno de caja y registrar el cuadre')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: los cuatro roles del set que hoy ven Caja reciben los tres
-- permisos. El SELECT no lee ROL_PERMISO, asi que el ON DUPLICATE no es
-- ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'CONSULTAR_CAJA', 'ABRIR_CAJA', 'CERRAR_CAJA'
)
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'VENDEDOR')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Roles personalizados: cualquiera que hoy tenga GESTIONAR_VENTAS veia Caja.
-- Se le dan los tres permisos para que no pierda el modulo con el cambio de
-- item. No aplica a roles creados despues de correr este modulo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT DISTINCT RP.ROL_NOMBRE, P.ID_PERMISO
FROM ROL_PERMISO RP
JOIN PERMISOS PV ON PV.ID_PERMISO = RP.ID_PERMISO
                AND PV.NOMBRE_PERMISO = 'GESTIONAR_VENTAS'
JOIN PERMISOS P ON P.NOMBRE_PERMISO IN (
    'CONSULTAR_CAJA', 'ABRIR_CAJA', 'CERRAR_CAJA'
)
ON DUPLICATE KEY UPDATE ROL_PERMISO.ROL_NOMBRE = ROL_PERMISO.ROL_NOMBRE;

SELECT 'PERMISOS DE CAJA APLICADOS.' AS RESULTADO;
