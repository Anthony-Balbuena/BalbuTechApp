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
-- estar desplegado antes de reimportar este modulo: los permisos finos se
-- reparten mas abajo, en la seccion MATRIZ DE PERMISOS FINOS, del mismo archivo.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_PROVEEDORES';

-- ================================================================
-- PERMISOS BASE DEL SISTEMA
-- (26/10/2026) 54 permisos: Inventario dejo de usar el paraguas
-- GESTIONAR_INVENTARIO y ahora tiene 3 permisos finos (INVENTARIO_VER,
-- INVENTARIO_AJUSTAR e INVENTARIO_COSTO), con lo que cierra la
-- Tanda B. (24/10/2026) Caja dejo de colgar de GESTIONAR_VENTAS y usa
-- CONSULTAR_CAJA, ABRIR_CAJA y CERRAR_CAJA. El modulo Usuarios usa
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
-- GESTIONAR_MARCAS, GESTIONAR_METODOS_PAGO, GESTIONAR_COMPRAS y
-- GESTIONAR_INVENTARIO. La asistencia
-- tiene sus propios permisos (REGISTRAR_ASISTENCIA, CONSULTAR_ASISTENCIA y
-- JUSTIFICAR_ASISTENCIA) desde el 23/10/2026.
-- El historial de venta usa CONSULTAR_HISTORIAL_VENTA, separado de
-- CONSULTAR_REPORTES.
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
('INVENTARIO_VER', 'Consultar movimientos de inventario'),
('INVENTARIO_AJUSTAR', 'Registrar ajustes de stock'),
('INVENTARIO_COSTO', 'Actualizar el costo de compra de productos'),
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

-- ADMIN: acceso total (los 54 permisos del sistema).
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
-- (22/10/2026) Clientes pasa a los 4 permisos finos.
-- (23/10/2026) Ya no tiene CONSULTAR_REPORTES: no ve reportes ni ganancias.
-- El historial de venta lo abre CONSULTAR_HISTORIAL_VENTA. Garantias sigue
-- dentro de GESTIONAR_VENTAS.
-- (26/10/2026) Sin CLIENTES_VER: puede crear, editar y cambiar el estado de un
-- cliente por ID, pero no buscarlo ni listarlo. De metodos de pago solo
-- conserva METODOS_PAGO_VER: consulta los existentes, no los mantiene. La
-- matriz de VENDEDOR queda en 12 permisos.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'VENDEDOR', ID_PERMISO
FROM PERMISOS
WHERE NOMBRE_PERMISO IN (
    'GESTIONAR_VENTAS',
    'CONSULTAR_CAJA',
    'ABRIR_CAJA',
    'CERRAR_CAJA',
    'CLIENTES_CREAR',
    'CLIENTES_EDITAR',
    'CLIENTES_ESTADO',
    'METODOS_PAGO_VER',
    'CONSULTAR_HISTORIAL_VENTA',
    'CONSULTAR_PRODUCTOS',
    'REGISTRAR_ASISTENCIA',
    'SOLICITAR_PERMISO'
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- (26/10/2026) La semilla ya no incluye estos cuatro. El DELETE los limpia en
-- instalaciones donde una corrida anterior del modulo los habia asignado.
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'VENDEDOR'
  AND P.NOMBRE_PERMISO IN (
      'CLIENTES_VER',
      'METODOS_PAGO_CREAR',
      'METODOS_PAGO_EDITAR',
      'METODOS_PAGO_ESTADO'
  );

-- ALMACEN: stock, compras y proveedores. Sin ventas, usuarios ni roles.
-- (22/10/2026) Suma SOLICITAR_PERMISO para que pueda pedir permisos/ausencias.
-- (26/10/2026) Conserva los 3 permisos finos de Inventario.
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
    'INVENTARIO_VER',
    'INVENTARIO_AJUSTAR',
    'INVENTARIO_COSTO',
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
    DECLARE v_rol VARCHAR(50) DEFAULT NULL;
    DECLARE v_existe INT DEFAULT 0;

    -- Rol via esquema unificado USUARIOS -> ROLES (era USUARIOS_SISTEMA, no existe).
    -- (03/11/2026, T2) Solo cuentas ACTIVO: una cuenta desactivada conservaba
    -- su rol y la funcion le seguia concediendo permisos.
    SELECT R.NOMBRE_ROL INTO v_rol
    FROM USUARIOS U
    INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    WHERE U.USUARIO = P_USERNAME
      AND U.ESTADO = 'ACTIVO'
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
      AND U.ESTADO = 'ACTIVO'
      AND P.NOMBRE_PERMISO = P_ACCION;

    RETURN v_existe > 0;
END//
DELIMITER ;

SELECT 'PERMISOS POR ROL CREADOS CORRECTAMENTE.' AS RESULTADO;

-- ================================================================
-- MATRIZ DE PERMISOS FINOS
-- ================================================================
-- (12/11/2026) Agrupado aca: la matriz y los permisos son un solo asunto y
-- este es su unico dueno. Absorbe diez modulos que hacian lo mismo en archivos
-- separados (45, 46, 47, 49, 50, 51, 52, 53, 58 y 62).
--
-- Por que viven juntos: los diez tocan las mismas dos tablas (PERMISOS y
-- ROL_PERMISO) y ninguno define tablas, rutinas, vistas ni triggers. Todos son
-- idempotentes: cada INSERT lleva ON DUPLICATE KEY y cada reemplazo borra el
-- paraguas viejo.
--
-- Va al final del modulo a proposito: primero se crean las tablas, los 54
-- permisos base y la matriz de los 7 roles, y despues se reparten los finos.
-- Asi el orden es el mismo que tenian cuando eran archivos aparte.
--
-- AVISO DE DESPLIEGUE: varias secciones borran el permiso paraguas
-- (GESTIONAR_COMPRAS, GESTIONAR_PROVEEDORES, ...). El binario tiene que estar
-- desplegado antes: el binario viejo sigue pidiendo el paraguas y el item
-- desaparece del menu hasta que se actualice. No se pierden datos.

-- ----------------------------------------------------------------
-- SECCION 1/10 · 45- PERMISO_CONSULTAR_ASISTENCIA.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 2/10 · 46- PERMISOS_PROVEEDORES.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 3/10 · 47- PERMISO_HISTORIAL_VENTA.sql
-- ----------------------------------------------------------------
-- ================================================================
-- BALBU_TECH - PERMISO DE HISTORIAL DE VENTA
-- ================================================================
-- (23/10/2026) El vendedor necesita consultar el historial de una venta, pero
-- no los reportes ni las ganancias. Se separa el historial en un permiso
-- propio (CONSULTAR_HISTORIAL_VENTA) y se le quita CONSULTAR_REPORTES a
-- VENDEDOR. Garantias no cambia: sigue con GESTIONAR_VENTAS.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo pide CONSULTAR_REPORTES para el historial; si este modulo
-- corre antes, la opcion desaparece del submenu hasta desplegar el binario
-- nuevo. No se pierden datos: solo se oculta la opcion.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('CONSULTAR_HISTORIAL_VENTA', 'Consultar el historial de una venta')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- ADMIN, GERENTE y SUBGERENTE conservan el historial; VENDEDOR lo recibe
-- aunque pierda los reportes.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON P.NOMBRE_PERMISO = 'CONSULTAR_HISTORIAL_VENTA'
WHERE R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'VENDEDOR')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- Solo VENDEDOR pierde los reportes y las ganancias: el resto de los roles
-- conserva CONSULTAR_REPORTES.
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'VENDEDOR'
  AND P.NOMBRE_PERMISO = 'CONSULTAR_REPORTES';

SELECT 'PERMISO DE HISTORIAL DE VENTA APLICADO.' AS RESULTADO;

-- ----------------------------------------------------------------
-- SECCION 4/10 · 49- PERMISOS_CATEGORIAS.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 5/10 · 50- PERMISOS_MARCAS.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 6/10 · 51- PERMISOS_METODOS_PAGO.sql
-- ----------------------------------------------------------------
-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE METODOS DE PAGO
-- ================================================================
-- (23/10/2026) Separa el modulo Metodos de pago en cuatro permisos finos, con
-- el mismo corte que Clientes, Proveedores, Categorias y Marcas:
-- METODOS_PAGO_VER, METODOS_PAGO_CREAR, METODOS_PAGO_EDITAR y
-- METODOS_PAGO_ESTADO reemplazan al paraguas GESTIONAR_METODOS_PAGO.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_METODOS_PAGO; si este modulo corre
-- antes, el item Metodos de pago desaparece del menu hasta desplegar el
-- binario nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('METODOS_PAGO_VER', 'Consultar y buscar metodos de pago'),
('METODOS_PAGO_CREAR', 'Registrar metodos de pago'),
('METODOS_PAGO_EDITAR', 'Actualizar datos de metodos de pago'),
('METODOS_PAGO_ESTADO', 'Activar o desactivar metodos de pago')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: ADMIN, GERENTE y SUBGERENTE reciben los cuatro permisos
-- finos. (26/10/2026) VENDEDOR solo METODOS_PAGO_VER: consulta los metodos
-- existentes, no los mantiene. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON (
    (R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE')
        AND P.NOMBRE_PERMISO IN (
            'METODOS_PAGO_VER', 'METODOS_PAGO_CREAR',
            'METODOS_PAGO_EDITAR', 'METODOS_PAGO_ESTADO'))
    OR (R.NOMBRE_ROL = 'VENDEDOR' AND P.NOMBRE_PERMISO = 'METODOS_PAGO_VER')
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- (26/10/2026) VENDEDOR ya no mantiene metodos de pago: si una corrida
-- anterior le asigno los tres de gestion, se los quita.
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'VENDEDOR'
  AND P.NOMBRE_PERMISO IN (
      'METODOS_PAGO_CREAR', 'METODOS_PAGO_EDITAR', 'METODOS_PAGO_ESTADO'
  );

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_METODOS_PAGO';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_METODOS_PAGO';

SELECT 'PERMISOS DE METODOS DE PAGO APLICADOS.' AS RESULTADO;

-- ----------------------------------------------------------------
-- SECCION 7/10 · 52- PERMISOS_COMPRAS.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 8/10 · 53- PERMISOS_CAJA.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 9/10 · 58- PERMISOS_INVENTARIO.sql
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- SECCION 10/10 · 62- PERMISOS_GARANTIAS.sql
-- ----------------------------------------------------------------
-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE GARANTIAS
-- ================================================================
-- (30/10/2026) Saca Garantias de GESTIONAR_VENTAS y le da cuatro permisos
-- propios, con el mismo patron que Clientes, Proveedores, Inventario y demas:
--   GARANTIAS_REGISTRAR  - registrar una garantia a mano
--   GARANTIAS_RECLAMAR   - abrir un reclamo sobre una garantia vigente
--   GARANTIAS_FINALIZAR  - cerrar un reclamo (decision de Gerencia)
--   GARANTIAS_CONSULTAR  - ver garantias y reclamos
--
-- La diferencia clave: el vendedor atiende y registra, pero NO cierra
-- reclamos. VENDEDOR conserva REGISTRAR, RECLAMAR y CONSULTAR.
--
-- ORDEN DE DESPLIEGUE:
--   1. Correr el modulo 25 completo (la seccion del ex 63 va incluida).
--   2. Desplegar el binario nuevo.
--   3. Correr este modulo.
-- El binario viejo abre Garantias con GESTIONAR_VENTAS; si este modulo corre
-- antes, el item desaparece del menu hasta desplegar el binario nuevo. No se
-- pierden datos: solo se oculta el modulo.
--
-- GESTIONAR_VENTAS NO se borra: lo siguen usando las otras nueve acciones de
-- Ventas (venta rapida, cancelar, anular pago, devolucion, cierre de caja,
-- cobrar, etc.). Solo deja de abrir Garantias.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('GARANTIAS_REGISTRAR', 'Registrar garantias de productos vendidos'),
('GARANTIAS_RECLAMAR',  'Registrar reclamos sobre garantias vigentes'),
('GARANTIAS_FINALIZAR', 'Cerrar reclamos de garantia'),
('GARANTIAS_CONSULTAR', 'Consultar garantias y reclamos')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON (
        (P.NOMBRE_PERMISO IN ('GARANTIAS_REGISTRAR', 'GARANTIAS_RECLAMAR', 'GARANTIAS_CONSULTAR')
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'VENDEDOR'))
     OR (P.NOMBRE_PERMISO = 'GARANTIAS_CONSULTAR'
         AND R.NOMBRE_ROL = 'CONTABILIDAD')
     OR (P.NOMBRE_PERMISO = 'GARANTIAS_FINALIZAR'
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE'))
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

SELECT R.NOMBRE_ROL, COUNT(*) AS PERMISOS_GARANTIA
  FROM ROL_PERMISO RP
  JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
  JOIN ROLES R ON R.NOMBRE_ROL = RP.ROL_NOMBRE
 WHERE P.NOMBRE_PERMISO LIKE 'GARANTIAS_%'
 GROUP BY R.NOMBRE_ROL
 ORDER BY R.NOMBRE_ROL;

SELECT 'PERMISOS DE GARANTIAS APLICADOS.' AS RESULTADO;

SELECT 'PERMISOS POR ROL CREADOS CORRECTAMENTE.' AS RESULTADO;


-- ================================================================
-- GARANTIAS: ASIGNACION, REPARACION Y REPUESTO (15/11/2026)
-- ================================================================
/*
SECCION GARANTIAS: ASIGNACION, REPARACION Y REPUESTO (15/11/2026)

Cablea el flujo de asignaciones de reclamos y la bitacora de reparacion con
repuestos. Fuente: odd/tasks/garantias-asignaciones-reparaciones.md.

Dos permisos nuevos, porque son dos trabajos distintos:
  GARANTIAS_ASIGNAR - decidir QUE tecnico trabaja un reclamo (gerencia)
  GARANTIAS_AVANZAR - registrar el avance de la reparacion (el tecnico)

Por que GARANTIAS_AVANZAR NO reusa GARANTIAS_FINALIZAR: la descripcion de
GARANTIAS_FINALIZAR es "Cerrar reclamos de garantia" y cierra Gerencia. Si el
avance usara ese permiso, el tecnico podria cerrar reclamos.

Rol TECNICO (nuevo): el tecnico entra con su propio usuario (USUARIOS.ID_EMPLEADO
lo permite). Lleva TRES permisos y NINGUNO de inventario:
  GARANTIAS_CONSULTAR - ver la garantia y el reclamo asignado
  GARANTIAS_AVANZAR   - registrar el avance
  CONSULTAR_PRODUCTOS - el selector de repuesto lo exige
                        (SP_CONSULTAR_PRODUCTOS_FILTRADO esta guardada por el)
El consumo de stock NO le exige INVENTARIO_AJUSTAR: el movimiento vive en
SP_MOVER_STOCK y el avance lo llama directo (ver modulo 17).

REPUESTO_VER: ver el stock de repuestos. Va aparte de INVENTARIO_VER aunque hoy
los dos conjuntos de roles coincidan, porque un permiso es una CAPACIDAD y no un
"a quien le toca hoy" - la misma razon por la que este archivo partio
GESTIONAR_INVENTARIO en INVENTARIO_VER / INVENTARIO_AJUSTAR / INVENTARIO_COSTO.
Lo tienen ADMIN, GERENTE, SUBGERENTE y ALMACEN; VENDEDOR no.

Orden: va antes de MIGRACION_ROLES, que solo retira EMPLEADO y CAJERO y no toca
roles nuevos. Idempotente: se puede correr las veces que haga falta.
*/
INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('GARANTIAS_ASIGNAR', 'Asignar un reclamo de garantia a un tecnico'),
('GARANTIAS_AVANZAR', 'Registrar el avance de una reparacion de garantia'),
('REPUESTO_VER',      'Consultar el stock de repuestos de garantia')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- El rol TECNICO. ROLES es solo ID_ROL + NOMBRE_ROL.
INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES ('TECNICO');

-- Matriz objetivo. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON (
        (P.NOMBRE_PERMISO = 'GARANTIAS_ASIGNAR'
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE'))
     OR (P.NOMBRE_PERMISO IN ('GARANTIAS_AVANZAR', 'GARANTIAS_CONSULTAR', 'CONSULTAR_PRODUCTOS')
         AND R.NOMBRE_ROL = 'TECNICO')
     OR (P.NOMBRE_PERMISO = 'REPUESTO_VER'
         AND R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE', 'ALMACEN'))
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

SELECT R.NOMBRE_ROL, P.NOMBRE_PERMISO AS PERMISO
  FROM ROL_PERMISO RP
  JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
  JOIN ROLES R ON R.NOMBRE_ROL = RP.ROL_NOMBRE
 WHERE R.NOMBRE_ROL = 'TECNICO'
 ORDER BY P.NOMBRE_PERMISO;

SELECT 'PERMISOS DE ASIGNACION, AVANCE Y REPUESTO APLICADOS.' AS RESULTADO;


-- ================================================================
-- MIGRACION_ROLES (ex modulo 44)
-- ================================================================

/*
SECCION MIGRACION_ROLES (ex modulo 44)
Cierre del rediseno de roles: deja cualquier base existente en el set final de 7 roles (ADMIN, GERENTE, SUBGERENTE, RRHH, VENDEDOR, ALMACEN, CONTABILIDAD), sin importar de que estado venga. Los modulos que arman la matriz solo AGREGAN: sobre una base vieja EMPLEADO y CAJERO no se borraban nunca, quedaban como roles vacios y sus usuarios seguian entrando a la app con un menu casi vacio. Va al FINAL del archivo a proposito: tiene que correr despues de la matriz de los 7 roles y de los diez parches finos. En una base reconstruida desde cero no hace nada: es idempotente.
*/
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
