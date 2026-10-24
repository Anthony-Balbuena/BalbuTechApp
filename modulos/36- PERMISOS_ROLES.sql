-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
-- ================================================================
-- BALBU_TECH - PERMISOS POR ROL
-- ================================================================
-- Este módulo define los permisos del sistema y los asocia a cada rol.
-- La idea es proteger el menú y las acciones con autenticación real y control por roles.
-- Set final de roles (22/10/2026): ADMIN, GERENTE, SUBGERENTE, RRHH, VENDEDOR, ALMACEN y CONTABILIDAD.

/*
TABLA PERMISOS
Lista las acciones que se pueden permitir en el sistema (gestionar usuarios,
ver reportes, etc). Cada permiso tiene un nombre unico y una descripcion.
*/
CREATE TABLE IF NOT EXISTS PERMISOS (
    ID_PERMISO INT PRIMARY KEY AUTO_INCREMENT,
    NOMBRE_PERMISO VARCHAR(80) NOT NULL UNIQUE,
    DESCRIPCION VARCHAR(200) NULL
) ENGINE = InnoDB;

/*
TABLA ROL_PERMISO
Une cada rol con los permisos que tiene. La clave compuesta evita repetir
permisos. Cualquier rol de ROLES puede tener permisos (C-3, 20/10/2026:
se elimino el CHECK que limitaba a ADMIN/RRHH/EMPLEADO).
*/
CREATE TABLE IF NOT EXISTS ROL_PERMISO (
    -- (09/10/2026) VARCHAR(50) para igualar ROLES.NOMBRE_ROL y poder atar el FK;
    -- antes VARCHAR(30) impedia la FK (los tipos deben coincidir).
    -- ROL_NOMBRE VARCHAR(30) NOT NULL,
    ROL_NOMBRE VARCHAR(50) NOT NULL,
    ID_PERMISO INT NOT NULL,
    PRIMARY KEY (ROL_NOMBRE, ID_PERMISO),
    CONSTRAINT FK_ROL_PERMISO_PERMISO FOREIGN KEY (ID_PERMISO)
        REFERENCES PERMISOS(ID_PERMISO)
        ON DELETE CASCADE,
    -- (09/10/2026) FK al rol: los nombres de aqui deben existir en ROLES.
    -- (20/10/2026) ON UPDATE CASCADE: renombrar un rol arrastra sus permisos.
    CONSTRAINT FK_ROL_PERMISO_ROL FOREIGN KEY (ROL_NOMBRE)
        REFERENCES ROLES(NOMBRE_ROL)
        ON UPDATE CASCADE
) ENGINE = InnoDB;

-- Migracion para bases ya existentes (C-3, 20/10/2026): CREATE TABLE IF NOT
-- EXISTS no toca una tabla vieja, asi que el CHECK y la FK se ajustan aparte.
-- Idempotente: los IF EXISTS permiten reimportar el modulo sin romper.
ALTER TABLE ROL_PERMISO DROP CONSTRAINT IF EXISTS CHK_ROL_NOMBRE;
ALTER TABLE ROL_PERMISO DROP FOREIGN KEY IF EXISTS FK_ROL_PERMISO_ROL;
ALTER TABLE ROL_PERMISO
    ADD CONSTRAINT FK_ROL_PERMISO_ROL FOREIGN KEY (ROL_NOMBRE)
    REFERENCES ROLES (NOMBRE_ROL) ON UPDATE CASCADE;

-- ================================================================
-- MIGRACION: PERMISOS QUE EL SET FINAL DE ROLES DEJA AFUERA
-- ================================================================
-- (20/10/2026, C-3) Las semillas de abajo solo insertan, asi que en una base
-- que ya tiene el set viejo de roles los permisos quedan pegados. Este bloque
-- borra SOLO los pares rol-permiso que el set final deja afuera.
-- Los permisos que el usuario asigno a mano desde la app se respetan.
-- Idempotente: si el par ya no existe, el DELETE no hace nada.
-- (RRHH pierde GESTIONAR_ROLES y los permisos finos de Usuarios, que son
-- exclusivos de ADMIN, y tambien los 4 permisos finos de Clientes y
-- GESTIONAR_VENTAS.)
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'RRHH'
  AND P.NOMBRE_PERMISO IN (
      'GESTIONAR_ROLES',
      'USUARIOS_VER',
      'USUARIOS_CREAR',
      'USUARIOS_EDITAR',
      'USUARIOS_ESTADO',
      'USUARIOS_CLAVE',
      'CLIENTES_VER',
      'CLIENTES_CREAR',
      'CLIENTES_EDITAR',
      'CLIENTES_ESTADO',
      'GESTIONAR_VENTAS'
  );

-- (22/10/2026) El permiso unico de Usuarios se reemplazo por los 5 permisos
-- finos USUARIOS_*. FK_ROL_PERMISO_PERMISO tiene ON DELETE CASCADE, asi que
-- los pares rol-permiso del permiso viejo se limpian solos.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_USUARIOS';

-- (22/10/2026) Mismo criterio para Empleados: el permiso unico se reemplazo
-- por 7 permisos finos (EMPLEADOS_VER/CREAR/EDITAR/BAJA, JUSTIFICAR_ASISTENCIA,
-- GESTIONAR_PERMISOS_EMPLEADO y GESTIONAR_VACACIONES_EMPLEADO).
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_EMPLEADOS';

-- (22/10/2026) Mismo criterio para Clientes: los permisos unicos de gestion y
-- consulta se reemplazaron por 4 permisos finos (CLIENTES_VER, CREAR, EDITAR y
-- ESTADO). El ON DELETE CASCADE limpia sus pares en ROL_PERMISO.
DELETE FROM PERMISOS
 WHERE NOMBRE_PERMISO IN ('GESTIONAR_CLIENTES', 'CONSULTAR_CLIENTES');

-- (23/10/2026) Proveedores: el permiso unico GESTIONAR_PROVEEDORES se
-- reemplazo por 4 permisos finos (PROVEEDORES_VER, CREAR, EDITAR y ESTADO).
-- El ON DELETE CASCADE limpia sus pares en ROL_PERMISO. El binario nuevo debe
-- estar desplegado antes de reimportar este modulo (modulo 46 hace lo mismo
-- para la base viva sin reimportar toda la matriz).
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_PROVEEDORES';

-- ================================================================
-- PERMISOS BASE DEL SISTEMA
-- (24/10/2026) 52 permisos: Caja dejo de colgar de GESTIONAR_VENTAS y usa
-- CONSULTAR_CAJA, ABRIR_CAJA y CERRAR_CAJA (modulo 53). El modulo Usuarios usa
-- 5 permisos finos
-- (USUARIOS_VER, CREAR, EDITAR, ESTADO y CLAVE), el modulo Empleados usa 7
-- (EMPLEADOS_VER, CREAR, EDITAR, BAJA, GESTIONAR_CONTRATOS,
-- GESTIONAR_PERMISOS_EMPLEADO y GESTIONAR_VACACIONES_EMPLEADO), el modulo
-- Clientes usa 4 (CLIENTES_VER, CREAR, EDITAR y ESTADO), el modulo Proveedores
-- usa 4 (PROVEEDORES_VER, CREAR, EDITAR y ESTADO), el modulo Categorias usa 4
-- (CATEGORIAS_VER, CREAR, EDITAR y ESTADO), el modulo Marcas usa 4
-- (MARCAS_VER, CREAR, EDITAR y ESTADO), el modulo Metodos de pago usa 4
-- (METODOS_PAGO_VER, CREAR, EDITAR y ESTADO) y el modulo Compras usa 6
-- (COMPRAS_VER, REGISTRAR, PAGAR, CANCELAR, DEVOLVER y REPORTES) en lugar de
-- los viejos GESTIONAR_USUARIOS, GESTIONAR_EMPLEADOS, GESTIONAR_CLIENTES,
-- CONSULTAR_CLIENTES, GESTIONAR_PROVEEDORES, GESTIONAR_CATEGORIAS,
-- GESTIONAR_MARCAS, GESTIONAR_METODOS_PAGO y GESTIONAR_COMPRAS. La asistencia
-- tiene sus propios permisos (REGISTRAR_ASISTENCIA, CONSULTAR_ASISTENCIA y
-- JUSTIFICAR_ASISTENCIA) desde el 23/10/2026 (modulo 45).
-- El historial de venta usa CONSULTAR_HISTORIAL_VENTA, separado de
-- CONSULTAR_REPORTES (modulo 47).
INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('GESTIONAR_ROLES', 'Crear, editar y consultar roles del sistema'),
('USUARIOS_VER', 'Consultar y buscar usuarios'),
('USUARIOS_CREAR', 'Registrar usuarios'),
('USUARIOS_EDITAR', 'Actualizar datos de usuarios'),
('USUARIOS_ESTADO', 'Activar o desactivar usuarios'),
('USUARIOS_CLAVE', 'Cambiar la clave de usuarios'),
('EMPLEADOS_VER', 'Consultar y buscar empleados'),
('EMPLEADOS_CREAR', 'Registrar empleados'),
('EMPLEADOS_EDITAR', 'Actualizar datos de empleados'),
('EMPLEADOS_BAJA', 'Despedir y reactivar empleados'),
('JUSTIFICAR_ASISTENCIA', 'Justificar asistencia'),
('GESTIONAR_PERMISOS_EMPLEADO', 'Aprobar o rechazar permisos de empleados'),
('GESTIONAR_VACACIONES_EMPLEADO', 'Aprobar o rechazar vacaciones'),
('CLIENTES_VER', 'Consultar y buscar clientes'),
('CLIENTES_CREAR', 'Registrar clientes'),
('CLIENTES_EDITAR', 'Actualizar datos de clientes'),
('CLIENTES_ESTADO', 'Activar o desactivar clientes'),
('PROVEEDORES_VER', 'Consultar y buscar proveedores'),
('PROVEEDORES_CREAR', 'Registrar proveedores'),
('PROVEEDORES_EDITAR', 'Actualizar datos de proveedores'),
('PROVEEDORES_ESTADO', 'Activar o desactivar proveedores'),
('CATEGORIAS_VER', 'Consultar y buscar categorias'),
('CATEGORIAS_CREAR', 'Registrar categorias'),
('CATEGORIAS_EDITAR', 'Actualizar datos de categorias'),
('CATEGORIAS_ESTADO', 'Activar o desactivar categorias'),
('MARCAS_VER', 'Consultar y buscar marcas'),
('MARCAS_CREAR', 'Registrar marcas'),
('MARCAS_EDITAR', 'Actualizar datos de marcas'),
('MARCAS_ESTADO', 'Activar o desactivar marcas'),
('GESTIONAR_PRODUCTOS', 'Gestionar productos'),
('METODOS_PAGO_VER', 'Consultar y buscar metodos de pago'),
('METODOS_PAGO_CREAR', 'Registrar metodos de pago'),
('METODOS_PAGO_EDITAR', 'Actualizar datos de metodos de pago'),
('METODOS_PAGO_ESTADO', 'Activar o desactivar metodos de pago'),
('GESTIONAR_INVENTARIO', 'Administrar inventario'),
('GESTIONAR_VENTAS', 'Gestionar ventas del sistema'),
('CONSULTAR_CAJA', 'Consultar el estado del turno de caja'),
('ABRIR_CAJA', 'Abrir el turno de caja'),
('CERRAR_CAJA', 'Cerrar el turno de caja y registrar el cuadre'),
('CONSULTAR_HISTORIAL_VENTA', 'Consultar el historial de una venta'),
('COMPRAS_VER', 'Consultar compras'),
('COMPRAS_REGISTRAR', 'Registrar compras'),
('COMPRAS_PAGAR', 'Pagar compras'),
('COMPRAS_CANCELAR', 'Cancelar compras'),
('COMPRAS_DEVOLVER', 'Registrar devoluciones de compra'),
('COMPRAS_REPORTES', 'Consultar reportes y precios de compras'),
('CONSULTAR_REPORTES', 'Consultar reportes y dashboards'),
('CONSULTAR_ASISTENCIA', 'Consultar reportes de asistencia'),
('CONSULTAR_PRODUCTOS', 'Consultar catalogo de productos'),
('REGISTRAR_ASISTENCIA', 'Registrar asistencia de empleados'),
('SOLICITAR_PERMISO', 'Solicitar permisos o ausencias'),
('GESTIONAR_CONTRATOS', 'Gestionar contratos de empleados')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- ================================================================
-- ASIGNACION DE PERMISOS POR ROL
-- ================================================================
-- (22/10/2026) Set final de roles de la tienda (7). La base es la unica
-- fuente de verdad de los permisos: esta es la matriz que queda al importar
-- el modulo y despues se puede ajustar desde la app (submenu Roles).
-- Todas las altas son idempotentes (ON DUPLICATE KEY UPDATE).

-- ADMIN: acceso total (los 49 permisos del sistema).
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'ADMIN', ID_PERMISO FROM PERMISOS
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- GERENTE: todo lo operativo, menos la administracion de roles y usuarios
-- (crear roles y usuarios es exclusivo de ADMIN). Los 7 permisos finos de
-- Empleados y los 4 de Clientes entran por este SELECT (no estan en el NOT IN).
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'GERENTE', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO NOT IN (
    'GESTIONAR_ROLES',
    'USUARIOS_VER',
    'USUARIOS_CREAR',
    'USUARIOS_EDITAR',
    'USUARIOS_ESTADO',
    'USUARIOS_CLAVE'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- SUBGERENTE: el GERENTE sin altas, bajas, contratos ni gestion de personal.
-- (22/10/2026) Conserva los 4 permisos finos de Clientes: no estan en el NOT IN.
-- (23/10/2026) Suma EMPLEADOS_VER (solo lectura) y JUSTIFICAR_ASISTENCIA:
-- conserva el item Empleados y puede justificar asistencia.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'SUBGERENTE', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO NOT IN (
    'GESTIONAR_ROLES',
    'USUARIOS_VER',
    'USUARIOS_CREAR',
    'USUARIOS_EDITAR',
    'USUARIOS_ESTADO',
    'USUARIOS_CLAVE',
    'EMPLEADOS_CREAR',
    'EMPLEADOS_EDITAR',
    'EMPLEADOS_BAJA',
    'GESTIONAR_PERMISOS_EMPLEADO',
    'GESTIONAR_VACACIONES_EMPLEADO',
    'GESTIONAR_CONTRATOS'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- RRHH: personal, contratos y reportes. Sin roles, usuarios, clientes ni ventas.
-- (22/10/2026) Suma los 7 permisos finos de Empleados; el viejo
-- GESTIONAR_EMPLEADOS ya no existe.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'RRHH', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'EMPLEADOS_VER',
    'EMPLEADOS_CREAR',
    'EMPLEADOS_EDITAR',
    'EMPLEADOS_BAJA',
    'JUSTIFICAR_ASISTENCIA',
    'GESTIONAR_PERMISOS_EMPLEADO',
    'GESTIONAR_VACACIONES_EMPLEADO',
    'GESTIONAR_CONTRATOS',
    'CONSULTAR_REPORTES',
    'CONSULTAR_ASISTENCIA',
    'REGISTRAR_ASISTENCIA',
    'SOLICITAR_PERMISO'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- VENDEDOR: atiende el mostrador. Toma los permisos de EMPLEADO y los de
-- CAJERO (que se elimina): ventas, caja, clientes, metodos de pago y consultas.
-- (22/10/2026) Clientes pasa a los 4 permisos finos: el vendedor puede ver,
-- crear, editar y cambiar el estado.
-- (23/10/2026) Ya no tiene CONSULTAR_REPORTES: no ve reportes ni ganancias.
-- El historial de venta lo abre CONSULTAR_HISTORIAL_VENTA. Garantias sigue
-- dentro de GESTIONAR_VENTAS.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'VENDEDOR', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'GESTIONAR_VENTAS',
    'CONSULTAR_CAJA',
    'ABRIR_CAJA',
    'CERRAR_CAJA',
    'CLIENTES_VER',
    'CLIENTES_CREAR',
    'CLIENTES_EDITAR',
    'CLIENTES_ESTADO',
    'METODOS_PAGO_VER',
    'METODOS_PAGO_CREAR',
    'METODOS_PAGO_EDITAR',
    'METODOS_PAGO_ESTADO',
    'CONSULTAR_HISTORIAL_VENTA',
    'CONSULTAR_PRODUCTOS',
    'REGISTRAR_ASISTENCIA',
    'SOLICITAR_PERMISO'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- ALMACEN: stock, compras y proveedores. Sin ventas, usuarios ni roles.
-- (22/10/2026) Suma SOLICITAR_PERMISO para que pueda pedir permisos/ausencias.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'ALMACEN', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'GESTIONAR_PRODUCTOS',
    'CATEGORIAS_VER',
    'CATEGORIAS_CREAR',
    'CATEGORIAS_EDITAR',
    'CATEGORIAS_ESTADO',
    'MARCAS_VER',
    'MARCAS_CREAR',
    'MARCAS_EDITAR',
    'MARCAS_ESTADO',
    'GESTIONAR_INVENTARIO',
    'COMPRAS_VER',
    'COMPRAS_REGISTRAR',
    'COMPRAS_PAGAR',
    'COMPRAS_CANCELAR',
    'COMPRAS_DEVOLVER',
    'COMPRAS_REPORTES',
    'PROVEEDORES_VER',
    'PROVEEDORES_CREAR',
    'PROVEEDORES_EDITAR',
    'PROVEEDORES_ESTADO',
    'CONSULTAR_PRODUCTOS',
    'REGISTRAR_ASISTENCIA',
    'SOLICITAR_PERMISO'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- CONTABILIDAD: solo consulta. Sin ventas, stock, personal ni permisos.
-- (22/10/2026) Clientes: solo CLIENTES_VER (antes CONSULTAR_CLIENTES).
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'CONTABILIDAD', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'CONSULTAR_REPORTES',
    'CONSULTAR_PRODUCTOS',
    'CLIENTES_VER',
    'REGISTRAR_ASISTENCIA'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- ================================================================
-- PROCEDIMIENTOS DE GESTION
-- ================================================================
-- Asigna un permiso concreto a un rol del sistema para ampliar o restringir acceso.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ASIGNAR_PERMISO_A_ROL;//
/*
SP_ASIGNAR_PERMISO_A_ROL
Da de alta un permiso concreto para un rol.
Revisa que el rol y el permiso existan; si estan bien, los une y si ya
estaba unido no duplica nada.
*/
CREATE PROCEDURE SP_ASIGNAR_PERMISO_A_ROL(
    IN P_ROL_NOMBRE VARCHAR(50),
    IN P_NOMBRE_PERMISO VARCHAR(80)
)
BEGIN
    DECLARE v_id_permiso INT;

    IF NOT EXISTS (SELECT 1 FROM ROLES WHERE NOMBRE_ROL = P_ROL_NOMBRE) THEN
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
END//
DELIMITER ;

-- Quita un permiso concreto a un rol. Si no lo tenia, avisa sin romper.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_QUITAR_PERMISO_A_ROL;//
/*
SP_QUITAR_PERMISO_A_ROL
Borra la relacion rol-permiso. Valida que el rol y el permiso existan.
Si el rol no tenia ese permiso devuelve un aviso, no un error.
*/
CREATE PROCEDURE SP_QUITAR_PERMISO_A_ROL(
    IN P_ROL_NOMBRE VARCHAR(50),
    IN P_NOMBRE_PERMISO VARCHAR(80)
)
BEGIN
    DECLARE v_id_permiso INT DEFAULT NULL;

    IF NOT EXISTS (SELECT 1 FROM ROLES WHERE NOMBRE_ROL = P_ROL_NOMBRE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL ROL NO EXISTE EN EL SISTEMA.';
    END IF;

    SELECT ID_PERMISO INTO v_id_permiso
    FROM PERMISOS
    WHERE NOMBRE_PERMISO = P_NOMBRE_PERMISO;

    IF v_id_permiso IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PERMISO NO EXISTE.';
    END IF;

    DELETE FROM ROL_PERMISO
    WHERE ROL_NOMBRE = P_ROL_NOMBRE AND ID_PERMISO = v_id_permiso;

    IF ROW_COUNT() = 0 THEN
        SELECT CONCAT('AVISO: ', P_ROL_NOMBRE, ' NO TENIA EL PERMISO ', P_NOMBRE_PERMISO, '.') AS MENSAJE;
    ELSE
        SELECT CONCAT('EXITO: PERMISO ', P_NOMBRE_PERMISO, ' QUITADO A ', P_ROL_NOMBRE, '.') AS MENSAJE;
    END IF;
END//
DELIMITER ;

-- Muestra todos los permisos asociados a un rol específico para consulta y auditoría.
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_PERMISOS_POR_ROL;//
/*
SP_LISTAR_PERMISOS_POR_ROL
Lista los permisos que tiene un rol, ordenados por nombre.
Sirve para consultar y auditar el acceso de cada rol.
*/
CREATE PROCEDURE SP_LISTAR_PERMISOS_POR_ROL(
    IN P_ROL_NOMBRE VARCHAR(50)
)
BEGIN
    SELECT P.ID_PERMISO, P.NOMBRE_PERMISO, P.DESCRIPCION
    FROM ROL_PERMISO RP
    INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
    WHERE RP.ROL_NOMBRE = P_ROL_NOMBRE
    ORDER BY P.NOMBRE_PERMISO;
END//
DELIMITER ;

-- ================================================================
-- FUNCION ESTANDAR DE VALIDACION
-- ================================================================
-- Evalúa si un usuario específico tiene acceso a una acción del sistema según su rol.
DELIMITER //
DROP FUNCTION IF EXISTS FN_TIENE_PERMISO;
/*
FN_TIENE_PERMISO
Dice si un usuario tiene permitida una accion segun su rol.
Devuelve verdadero si el rol tiene ese permiso, y falso en cualquier
otro caso (usuario inexistente o sin permiso).
*/
CREATE FUNCTION FN_TIENE_PERMISO(P_USERNAME VARCHAR(50), P_ACCION VARCHAR(80))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE v_rol VARCHAR(50);
    DECLARE v_existe INT DEFAULT 0;

    -- Rol via esquema unificado USUARIOS -> ROLES (era USUARIOS_SISTEMA, no existe).
    SELECT R.NOMBRE_ROL INTO v_rol
    FROM USUARIOS U
    INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    WHERE U.USUARIO = P_USERNAME
    LIMIT 1;

    IF v_rol IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO v_existe
    FROM USUARIOS U
    INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    INNER JOIN ROL_PERMISO RP ON RP.ROL_NOMBRE = R.NOMBRE_ROL
    INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
    WHERE U.USUARIO = P_USERNAME
      AND P.NOMBRE_PERMISO = P_ACCION;

    RETURN v_existe > 0;
END//
DELIMITER ;

SELECT 'PERMISOS POR ROL CREADOS CORRECTAMENTE.' AS RESULTADO;
