-- ================================================================
-- BALBU_TECH - PERMISOS POR ROL
-- ================================================================
-- Este módulo define los permisos del sistema y los asocia a cada rol.
-- La idea es proteger el menú y las acciones con autenticación real y control por roles.

CREATE TABLE IF NOT EXISTS PERMISOS (
    ID_PERMISO INT PRIMARY KEY AUTO_INCREMENT,
    NOMBRE_PERMISO VARCHAR(80) NOT NULL UNIQUE,
    DESCRIPCION VARCHAR(200) NULL
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS ROL_PERMISO (
    ROL_NOMBRE VARCHAR(30) NOT NULL,
    ID_PERMISO INT NOT NULL,
    PRIMARY KEY (ROL_NOMBRE, ID_PERMISO),
    CONSTRAINT FK_ROL_PERMISO_PERMISO FOREIGN KEY (ID_PERMISO)
        REFERENCES PERMISOS(ID_PERMISO)
        ON DELETE CASCADE,
    CONSTRAINT CHK_ROL_NOMBRE CHECK (
        ROL_NOMBRE IN ('ADMIN', 'RRHH', 'EMPLEADO')
    )
) ENGINE = InnoDB;

-- ================================================================
-- PERMISOS BASE DEL SISTEMA
-- ================================================================
INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('GESTIONAR_ROLES', 'Crear, editar y consultar roles del sistema'),
('GESTIONAR_USUARIOS', 'Administrar usuarios del sistema'),
('GESTIONAR_EMPLEADOS', 'Administrar empleados y personal'),
('GESTIONAR_CLIENTES', 'Gestionar clientes'),
('GESTIONAR_PROVEEDORES', 'Gestionar proveedores'),
('GESTIONAR_CATEGORIAS', 'Gestionar categorias'),
('GESTIONAR_MARCAS', 'Gestionar marcas'),
('GESTIONAR_PRODUCTOS', 'Gestionar productos'),
('GESTIONAR_INVENTARIO', 'Administrar inventario'),
('GESTIONAR_VENTAS', 'Gestionar ventas del sistema'),
('GESTIONAR_COMPRAS', 'Gestionar compras del sistema'),
('CONSULTAR_REPORTES', 'Consultar reportes y dashboards'),
('CONSULTAR_PRODUCTOS', 'Consultar catalogo de productos'),
('CONSULTAR_CLIENTES', 'Consultar clientes'),
('REGISTRAR_ASISTENCIA', 'Registrar asistencia de empleados'),
('SOLICITAR_PERMISO', 'Solicitar permisos o ausencias')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- ================================================================
-- ASIGNACION DE PERMISOS POR ROL
-- ================================================================
-- ADMIN: acceso total
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'ADMIN', ID_PERMISO FROM PERMISOS
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- RRHH: personal, usuarios, clientes y reportes
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'RRHH', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'GESTIONAR_EMPLEADOS',
    'GESTIONAR_ROLES',
    'GESTIONAR_USUARIOS',
    'GESTIONAR_CLIENTES',
    'CONSULTAR_REPORTES'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- EMPLEADO: solo consultas y permisos básicos
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'EMPLEADO', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'CONSULTAR_PRODUCTOS',
    'CONSULTAR_CLIENTES',
    'REGISTRAR_ASISTENCIA',
    'SOLICITAR_PERMISO'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- ================================================================
-- PROCEDIMIENTOS DE GESTION
-- ================================================================
-- Asigna un permiso concreto a un rol del sistema para ampliar o restringir acceso.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ASIGNAR_PERMISO_A_ROL;//
CREATE PROCEDURE SP_ASIGNAR_PERMISO_A_ROL(
    IN P_ROL_NOMBRE VARCHAR(30),
    IN P_NOMBRE_PERMISO VARCHAR(80)
)
BEGIN
    DECLARE v_id_permiso INT;

    IF NOT EXISTS (SELECT 1 FROM USUARIOS_SISTEMA WHERE ROL = P_ROL_NOMBRE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL ROL NO EXISTE EN EL SISTEMA.';
    END IF;

    SELECT ID_PERMISO INTO v_id_permiso
    FROM PERMISOS
    WHERE NOMBRE_PERMISO = P_NOMBRE_PERMISO;

    IF v_id_permiso IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PERMISO NO EXISTE.';
    END IF;

    INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
    VALUES (P_ROL_NOMBRE, v_id_permiso)
    ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

    SELECT CONCAT('EXITO: PERMISO ', P_NOMBRE_PERMISO, ' ASIGNADO A ', P_ROL_NOMBRE) AS MENSAJE;
END;//
DELIMITER ;

-- Muestra todos los permisos asociados a un rol específico para consulta y auditoría.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_PERMISOS_POR_ROL;//
CREATE PROCEDURE SP_LISTAR_PERMISOS_POR_ROL(
    IN P_ROL_NOMBRE VARCHAR(30)
)
BEGIN
    SELECT P.ID_PERMISO, P.NOMBRE_PERMISO, P.DESCRIPCION
    FROM ROL_PERMISO RP
    INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
    WHERE RP.ROL_NOMBRE = P_ROL_NOMBRE
    ORDER BY P.NOMBRE_PERMISO;
END;//
DELIMITER ;

-- ================================================================
-- FUNCION ESTANDAR DE VALIDACION
-- ================================================================
-- Evalúa si un usuario específico tiene acceso a una acción del sistema según su rol.
DELIMITER //
DROP FUNCTION IF EXISTS FN_TIENE_PERMISO;//
CREATE FUNCTION FN_TIENE_PERMISO(P_USERNAME VARCHAR(50), P_ACCION VARCHAR(20))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE v_rol VARCHAR(30);
    DECLARE v_existe INT DEFAULT 0;

    SELECT ROL INTO v_rol
    FROM USUARIOS_SISTEMA
    WHERE USERNAME = P_USERNAME
    LIMIT 1;

    IF v_rol IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO v_existe
    FROM ROL_PERMISO RP
    INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
    INNER JOIN USUARIOS_SISTEMA U ON U.ROL = RP.ROL_NOMBRE
    WHERE U.USERNAME = P_USERNAME
      AND P.NOMBRE_PERMISO = P_ACCION;

    RETURN v_existe > 0;
END;//
DELIMITER ;

SELECT 'PERMISOS POR ROL CREADOS CORRECTAMENTE.' AS RESULTADO;
