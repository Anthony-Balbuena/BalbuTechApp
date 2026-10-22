-- 44- MIGRACION_ROLES.sql
-- (22/10/2026) Cierre del rediseño de roles. Deja cualquier base existente en el
-- set final de 7 roles, sin importar de qué estado venga:
--   ADMIN, GERENTE, SUBGERENTE, RRHH, VENDEDOR, ALMACEN, CONTABILIDAD
--
-- Por que hace falta:
-- Los modulos 3 y 36 solo AGREGAN. Sobre una base vieja, EMPLEADO y CAJERO no se
-- borraban nunca: quedaban como roles vacios (sus permisos paraguas desaparecen
-- por ON DELETE CASCADE de FK_ROL_PERMISO_PERMISO) y cualquier usuario que los
-- tuviera seguia entrando a la app con un menu casi vacio.
-- En una base reconstruida desde cero este modulo no hace nada: es idempotente y
-- se puede correr las veces que haga falta.
--
-- Orden obligatorio (las dos FKs que apuntan a ROLES son RESTRICT, sin ON DELETE):
--   FK_USUARIO_ROL      -> primero mover los usuarios, despues borrar el rol.
--   FK_ROL_PERMISO_ROL  -> primero borrar los pares, despues el rol.
-- Si se invierte el orden, el DELETE falla y la migracion queda a medias.
--
-- Corre despues del 36, que es el que crea la matriz de los 7 roles.

-- 1. Los 7 roles tienen que existir antes de mover a nadie: USUARIOS.ID_ROL es
--    NOT NULL, no existe el concepto de usuario "sin rol".
INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES
    ('ADMIN'), ('GERENTE'), ('SUBGERENTE'), ('RRHH'),
    ('VENDEDOR'), ('ALMACEN'), ('CONTABILIDAD');

-- 2. Los usuarios de los roles retirados pasan a VENDEDOR, que es el que absorbe
--    el trabajo de EMPLEADO y CAJERO (ventas, clientes, asistencia, solicitudes).
UPDATE USUARIOS
   SET ID_ROL = (SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL = 'VENDEDOR')
 WHERE ID_ROL IN (SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO', 'CAJERO'));

-- 3. Pares rol-permiso de los roles retirados (FK sin ON DELETE = RESTRICT).
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE IN ('EMPLEADO', 'CAJERO');

-- 4. Los roles retirados, ya sin usuarios ni pares que los referencien.
DELETE FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO', 'CAJERO');

-- 5. Comprobacion: tiene que dar 0 y el listado tiene que tener 7 filas.
SELECT 'RESULTADO' AS ESTADO;
SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL;
SELECT CONCAT('Roles retirados que quedan: ', COUNT(*)) AS COMPROBACION
  FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO', 'CAJERO');
