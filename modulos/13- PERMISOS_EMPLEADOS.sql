-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH

/*
TABLA PERMISOS_EMPLEADOS
Guarda los permisos que pide cada empleado: tipo (medico, personal,
estudio, licencia o sin sueldo), rango de fechas y estado (PENDIENTE,
APROBADO o RECHAZADO). No permite fechas invertidas ni permisos que se
cruzen con otro que no este rechazado.
*/
CREATE TABLE PERMISOS_EMPLEADOS (
    ID_PERMISO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    TIPO_PERMISO ENUM(
        'MEDICO',
        'PERSONAL',
        'ESTUDIO',
        'LICENCIA',
        'SIN_SUELDO'
    ) NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    DESCRIPCION VARCHAR(200),
    ESTADO ENUM( 
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO'
    ) NOT NULL DEFAULT 'PENDIENTE',
    FECHA_SOLICITUD TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_PERMISO),
    CONSTRAINT CK_PERMISO_FECHAS CHECK (FECHA_FIN >= FECHA_INICIO),
    CONSTRAINT FK_PERMISO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    -- Acelera el historial de permisos de un empleado, que es la consulta que mas se usa
    -- para ver cuantas veces ha pedido permiso y de que tipo.
    INDEX IX_PERMISO_EMPLEADO (ID_EMPLEADO),
    -- Permite filtrar rapidamente los permisos pendientes de aprobar, que es lo que ve la
    -- pantalla del dia a dia.
    INDEX IX_PERMISO_ESTADO (ESTADO),
    -- Acelera los calendarios de ausencias, que buscan por rango de fechas para saber
    -- quien no viene en un periodo.
    INDEX IX_PERMISO_FECHAS (FECHA_INICIO, FECHA_FIN)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
SP_SOLICITAR_PERMISO
Pide un permiso nuevo para un empleado.
Valida que el empleado exista, que las fechas no sean retroactivas ni
invertidas y que no se cruce con otro permiso pendiente o aprobado; si
todo esta bien lo guarda y responde con un mensaje de exito.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_SOLICITAR_PERMISO ;
CREATE PROCEDURE SP_SOLICITAR_PERMISO(
    IN P_ID_EMPLEADO INT,
    IN P_TIPO_PERMISO ENUM('MEDICO', 'PERSONAL', 'ESTUDIO', 'LICENCIA', 'SIN_SUELDO'),
    IN P_FECHA_INICIO DATE,
    IN P_FECHA_FIN DATE,
    IN P_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE v_nombre_empleado VARCHAR(100);

    -- 1. VALIDAR EMPLEADO
    SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    IF v_nombre_empleado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN DE FECHAS
    IF P_FECHA_INICIO < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO PUEDES SOLICITAR PERMISOS RETROACTIVOS.';
        LEAVE proc_label;
    END IF;

    -- 3. VALIDACIÓN DE SOLAPAMIENTO (Solo para permisos no rechazados)
    -- (10/10/2026) 3 casos: inicio-dentro, fin-dentro y nuevo-envuelve-viejo
    -- (antes faltaba el tercero y un rango grande tragaba al chico).
    IF EXISTS (
        SELECT 1 FROM PERMISOS_EMPLEADOS 
        WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO <> 'RECHAZADO'
        AND (P_FECHA_INICIO BETWEEN FECHA_INICIO AND FECHA_FIN OR P_FECHA_FIN BETWEEN FECHA_INICIO AND FECHA_FIN
             OR FECHA_INICIO BETWEEN P_FECHA_INICIO AND P_FECHA_FIN)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA TIENES UNA SOLICITUD DE PERMISO PENDIENTE O APROBADA EN ESTAS FECHAS.';
        LEAVE proc_label;
    END IF;

    -- 4. INSERCIÓN
    INSERT INTO PERMISOS_EMPLEADOS (ID_EMPLEADO, TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, DESCRIPCION)
    VALUES (P_ID_EMPLEADO, P_TIPO_PERMISO, P_FECHA_INICIO, P_FECHA_FIN, REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' '));

    SELECT CONCAT('EXITO: SOLICITUD DE PERMISO CREADA PARA "', v_nombre_empleado, '".') AS MENSAJE;
END //
DELIMITER ;

/*
SP_LISTAR_PERMISOS_PENDIENTES
Lista las solicitudes que todavia no se resolvieron, con el nombre del
empleado, para la pantalla de gestion de RRHH. Va de la mas vieja a la
mas nueva: la primera que llego se atiende primero.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_PERMISOS_PENDIENTES //
CREATE PROCEDURE SP_LISTAR_PERMISOS_PENDIENTES()
BEGIN
    SELECT
        P.ID_PERMISO,
        P.ID_EMPLEADO,
        E.NOMBRE,
        P.TIPO_PERMISO,
        P.FECHA_INICIO,
        P.FECHA_FIN,
        IFNULL(P.DESCRIPCION, '') AS DESCRIPCION,
        P.FECHA_SOLICITUD
    FROM PERMISOS_EMPLEADOS P
    INNER JOIN EMPLEADOS E ON E.ID_EMPLEADO = P.ID_EMPLEADO
    WHERE P.ESTADO = 'PENDIENTE'
    ORDER BY P.FECHA_SOLICITUD ASC, P.ID_PERMISO ASC;
END //
DELIMITER ;

/*
SP_GESTIONAR_PERMISO
Aprueba o rechaza una solicitud pendiente. Solo se puede resolver una
vez: si el ID no existe o el permiso ya fue aprobado o rechazado, manda
un error y no toca nada. La actualizacion vuelve a exigir PENDIENTE para
que dos gestiones simultaneas no pisen el estado. Si todo esta bien
cambia el estado y confirma con un mensaje que trae el ID y el nuevo
estado.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_GESTIONAR_PERMISO ;
CREATE PROCEDURE SP_GESTIONAR_PERMISO(
    IN P_ID_PERMISO INT,
    IN P_NUEVO_ESTADO ENUM('PENDIENTE', 'APROBADO','RECHAZADO')
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. VALIDAR EXISTENCIA
    SELECT ESTADO INTO v_estado_actual
    FROM PERMISOS_EMPLEADOS
    WHERE ID_PERMISO = P_ID_PERMISO;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: PERMISO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. SOLO SE RESUELVE UNA VEZ: LA SOLICITUD DEBE ESTAR PENDIENTE
    IF v_estado_actual <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN GESTIONAR PERMISOS PENDIENTES.';
        LEAVE proc_label;
    END IF;

    -- 3. EL NUEVO ESTADO SOLO PUEDE SER APROBADO O RECHAZADO
    IF P_NUEVO_ESTADO IS NULL OR P_NUEVO_ESTADO NOT IN ('APROBADO', 'RECHAZADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTADO NO VALIDO. SOLO SE PUEDE APROBAR O RECHAZAR.';
        LEAVE proc_label;
    END IF;

    -- 4. ACTUALIZAR SOLO SI SIGUE PENDIENTE (ATOMICO)
    UPDATE PERMISOS_EMPLEADOS
    SET ESTADO = P_NUEVO_ESTADO
    WHERE ID_PERMISO = P_ID_PERMISO
      AND ESTADO = 'PENDIENTE';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN GESTIONAR PERMISOS PENDIENTES.';
        LEAVE proc_label;
    END IF;

    SELECT CONCAT('EXITO: PERMISO ID ', P_ID_PERMISO, ' ACTUALIZADO A ESTADO: ', P_NUEVO_ESTADO) AS MENSAJE;
END //
DELIMITER ;


/*
SP_HISTORIAL_PERMISOS_EMPLEADO
Lista todos los permisos de un empleado (tipo, fechas, estado y
descripcion) del mas reciente al mas antiguo, para ver su historial
completo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_HISTORIAL_PERMISOS_EMPLEADO //
CREATE PROCEDURE SP_HISTORIAL_PERMISOS_EMPLEADO(IN P_ID_EMPLEADO INT)
BEGIN
    SELECT 
        TIPO_PERMISO,
        FECHA_INICIO,
        FECHA_FIN,
        ESTADO,
        DESCRIPCION
    FROM PERMISOS_EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO
    ORDER BY FECHA_INICIO DESC;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


/*
VISTA_PERMISOS_ACTIVOS
Muestra solo los permisos aprobados que estan vigentes hoy, con el nombre
del empleado, el tipo y el rango de fechas. Sirve para pintar quienes
estan ausentes en este momento.
*/
CREATE OR REPLACE VIEW VISTA_PERMISOS_ACTIVOS AS
SELECT 
    E.NOMBRE,
    P.TIPO_PERMISO,
    P.FECHA_INICIO,
    P.FECHA_FIN,
    P.ESTADO
FROM PERMISOS_EMPLEADOS P
JOIN EMPLEADOS E ON P.ID_EMPLEADO = E.ID_EMPLEADO
WHERE CURDATE() BETWEEN P.FECHA_INICIO AND P.FECHA_FIN
AND P.ESTADO = 'APROBADO';

-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------[AUDITORIA}-------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

/*
TABLA LOG_AUDITORIA_PERMISOS
Bitacora de los permisos de empleados: que paso (ALTA, CAMBIO_ESTADO, BAJA),
el estado anterior y el nuevo, cuando paso y quien lo hizo.

(12/11/2026) Nacio guardando solo el cambio de estado y sin actor. Ahora vive
completa en este modulo, con los tres eventos y el actor. La definicion de aca
es la final para una instalacion nueva; el bloque idempotente que sigue cubre
las bases que ya tienen la tabla vieja, asi importar este modulo las actualiza.

Por que ID_EMPLEADO y TIPO_PERMISO estan aca si ya se pueden sacar del permiso:
porque ID_PERMISO es ON DELETE SET NULL a proposito (borrar un permiso no debe
destruir su bitacora) y, cuando eso pasa, estas dos columnas son lo unico que
sigue diciendo de quien era el permiso borrado.
*/
CREATE TABLE IF NOT EXISTS LOG_AUDITORIA_PERMISOS (
    ID_LOG INT AUTO_INCREMENT PRIMARY KEY,
    ID_PERMISO INT,
    ID_EMPLEADO INT,              -- dueno del permiso, sobrevive al borrado
    TIPO_PERMISO VARCHAR(20),     -- MEDICO, PERSONAL, ... idem
    ACCION VARCHAR(20) NOT NULL,  -- 'ALTA', 'CAMBIO_ESTADO', 'BAJA'
    ESTADO_ANTERIOR VARCHAR(20),
    ESTADO_NUEVO VARCHAR(20),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ID_USUARIO_ADMIN INT,         -- quien realizo el cambio
    CONSTRAINT FK_LOG_PERMISO FOREIGN KEY (ID_PERMISO)
        -- (10/10/2026) SET NULL en vez de CASCADE: borrar un permiso no debe
        -- destruir su bitacora (la columna admite NULL a proposito).
        REFERENCES PERMISOS_EMPLEADOS(ID_PERMISO) ON DELETE SET NULL,
    -- (12/11/2026) SET NULL y no CASCADE: si se borra el usuario, el registro
    -- de auditoria se queda sin nombre pero no desaparece.
    CONSTRAINT FK_LOG_PERMISO_ADMIN FOREIGN KEY (ID_USUARIO_ADMIN)
        REFERENCES USUARIOS(ID_USUARIO) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------
-- Actualizacion de una base que ya tiene la tabla vieja
-- ----------------------------------------------------------------
-- Cada paso se pregunta antes a INFORMATION_SCHEMA, asi que correr el modulo
-- dos veces no rompe nada y una instalacion nueva los saltea todos.

-- ID_EMPLEADO: dueno del permiso, sobrevive al borrado del permiso.
SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                   AND COLUMN_NAME = 'ID_EMPLEADO');
SET @sql := IF(@existe = 0,
    'ALTER TABLE LOG_AUDITORIA_PERMISOS ADD COLUMN ID_EMPLEADO INT NULL AFTER ID_PERMISO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- TIPO_PERMISO: cual era (MEDICO, PERSONAL, ...).
SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                   AND COLUMN_NAME = 'TIPO_PERMISO');
SET @sql := IF(@existe = 0,
    'ALTER TABLE LOG_AUDITORIA_PERMISOS ADD COLUMN TIPO_PERMISO VARCHAR(20) NULL AFTER ID_EMPLEADO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ACCION: se agrega NULL, se rellena lo viejo y despues pasa a NOT NULL.
-- Asi el modulo tambien sirve en una base que ya tenga filas.
SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                   AND COLUMN_NAME = 'ACCION');
SET @sql := IF(@existe = 0,
    'ALTER TABLE LOG_AUDITORIA_PERMISOS ADD COLUMN ACCION VARCHAR(20) NULL AFTER TIPO_PERMISO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Las filas anteriores solo podian venir de un UPDATE: el trigger viejo no
-- escuchaba otra cosa.
UPDATE LOG_AUDITORIA_PERMISOS SET ACCION = 'CAMBIO_ESTADO' WHERE ACCION IS NULL;

-- Relleno de las columnas denormalizadas para las filas viejas que todavia
-- tienen su permiso vivo. Las que ya perdieron el permiso (ID_PERMISO NULL) no
-- se pueden reconstruir: quedan en NULL.
UPDATE LOG_AUDITORIA_PERMISOS L
  JOIN PERMISOS_EMPLEADOS P ON P.ID_PERMISO = L.ID_PERMISO
   SET L.ID_EMPLEADO  = P.ID_EMPLEADO,
       L.TIPO_PERMISO = P.TIPO_PERMISO
 WHERE L.ID_EMPLEADO IS NULL;

SET @nullable := (SELECT IS_NULLABLE
                    FROM INFORMATION_SCHEMA.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE()
                     AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                     AND COLUMN_NAME = 'ACCION');
SET @sql := IF(@nullable = 'YES',
    'ALTER TABLE LOG_AUDITORIA_PERMISOS MODIFY ACCION VARCHAR(20) NOT NULL',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ID_USUARIO_ADMIN: el actor. SET NULL, no CASCADE: si se borra el usuario
-- el registro tiene que sobrevivir, solo se pierde el nombre.
SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                   AND COLUMN_NAME = 'ID_USUARIO_ADMIN');
SET @sql := IF(@existe = 0,
    'ALTER TABLE LOG_AUDITORIA_PERMISOS ADD COLUMN ID_USUARIO_ADMIN INT NULL AFTER FECHA_CAMBIO',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- FK del actor.
SET @existe := (SELECT COUNT(*)
                  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'LOG_AUDITORIA_PERMISOS'
                   AND CONSTRAINT_NAME = 'FK_LOG_PERMISO_ADMIN');
SET @sql := IF(@existe = 0,
    'ALTER TABLE LOG_AUDITORIA_PERMISOS ADD CONSTRAINT FK_LOG_PERMISO_ADMIN
        FOREIGN KEY (ID_USUARIO_ADMIN) REFERENCES USUARIOS (ID_USUARIO) ON DELETE SET NULL',
    'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ----------------------------------------------------------------
-- Triggers: uno por evento
-- ----------------------------------------------------------------
-- El trigger viejo (TR_LOG_GESTION_PERMISO) solo miraba UPDATE y solo
-- comparaba el estado. Se reemplaza por tres explicitos: el nombre dice que
-- evento cubre, sin tener que leer el IF de adentro.
--
-- El actor sale de @ID_USUARIO_ACTUAL, que la app deja en la conexion al
-- iniciar sesion, y se resuelve con un SELECT que devuelve NULL si no hay
-- sesion. El trigger NUNCA aborta el cambio: sin sesion (tests, SQL a mano,
-- mantenimiento) el actor queda NULL y la operacion sigue. Esa condicion no es
-- un detalle: el trigger corre DENTRO del INSERT/UPDATE/DELETE de
-- PERMISOS_EMPLEADOS, y si fallara se cae la escritura del permiso.
DROP TRIGGER IF EXISTS TR_LOG_GESTION_PERMISO;
DROP TRIGGER IF EXISTS TR_LOG_PERMISO_ALTA;
DROP TRIGGER IF EXISTS TR_LOG_PERMISO_CAMBIO_ESTADO;
DROP TRIGGER IF EXISTS TR_LOG_PERMISO_BAJA;

DELIMITER //

/*
TR_LOG_PERMISO_ALTA
Registra el alta de una solicitud. El estado anterior es NULL porque antes no
existia.
*/
CREATE TRIGGER TR_LOG_PERMISO_ALTA
AFTER INSERT ON PERMISOS_EMPLEADOS
FOR EACH ROW
BEGIN
    DECLARE v_admin INT DEFAULT NULL;

    -- (25/10/2026, patron del 29) Si el id no existe, NULL: el log no tumba el alta.
    SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL);

    INSERT INTO LOG_AUDITORIA_PERMISOS
        (ID_PERMISO, ID_EMPLEADO, TIPO_PERMISO, ACCION,
         ESTADO_ANTERIOR, ESTADO_NUEVO, ID_USUARIO_ADMIN)
    VALUES
        (NEW.ID_PERMISO, NEW.ID_EMPLEADO, NEW.TIPO_PERMISO, 'ALTA',
         NULL, NEW.ESTADO, v_admin);
END //

/*
TR_LOG_PERMISO_CAMBIO_ESTADO
Registra solo cuando cambia ESTADO. Un UPDATE que toca la descripcion o las
fechas no escribe nada: es el comportamiento que ya tenia el trigger viejo y
se mantiene a proposito.
*/
CREATE TRIGGER TR_LOG_PERMISO_CAMBIO_ESTADO
AFTER UPDATE ON PERMISOS_EMPLEADOS
FOR EACH ROW
BEGIN
    DECLARE v_admin INT DEFAULT NULL;

    IF NOT (OLD.ESTADO <=> NEW.ESTADO) THEN
        SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL);

        INSERT INTO LOG_AUDITORIA_PERMISOS
            (ID_PERMISO, ID_EMPLEADO, TIPO_PERMISO, ACCION,
             ESTADO_ANTERIOR, ESTADO_NUEVO, ID_USUARIO_ADMIN)
        VALUES
            (NEW.ID_PERMISO, NEW.ID_EMPLEADO, NEW.TIPO_PERMISO, 'CAMBIO_ESTADO',
             OLD.ESTADO, NEW.ESTADO, v_admin);
    END IF;
END //

/*
TR_LOG_PERMISO_BAJA
Registra el borrado. ID_PERMISO va NULL a proposito: la fila del permiso ya no
existe y la FK lo rechazaria (y abortaria el DELETE). La identidad queda en
ID_EMPLEADO, TIPO_PERMISO y ESTADO_ANTERIOR, que son los que sobreviven.
*/
CREATE TRIGGER TR_LOG_PERMISO_BAJA
AFTER DELETE ON PERMISOS_EMPLEADOS
FOR EACH ROW
BEGIN
    DECLARE v_admin INT DEFAULT NULL;

    SET v_admin = (SELECT ID_USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL);

    INSERT INTO LOG_AUDITORIA_PERMISOS
        (ID_PERMISO, ID_EMPLEADO, TIPO_PERMISO, ACCION,
         ESTADO_ANTERIOR, ESTADO_NUEVO, ID_USUARIO_ADMIN)
    VALUES
        (NULL, OLD.ID_EMPLEADO, OLD.TIPO_PERMISO, 'BAJA',
         OLD.ESTADO, NULL, v_admin);
END //

DELIMITER ;

-- ----------------------------------------------------------------
-- Vista de lectura
-- ----------------------------------------------------------------
/*
VIEW_HISTORIAL_PERMISOS
Traduce ids a nombres para la pantalla. LEFT JOIN en todo: el registro tiene
que seguir leyendose aunque el permiso, el empleado o el usuario ya no existan.
*/
CREATE OR REPLACE VIEW VIEW_HISTORIAL_PERMISOS AS
SELECT
    L.ID_LOG,
    L.ID_PERMISO,
    L.ID_EMPLEADO,
    E.NOMBRE AS EMPLEADO,
    L.TIPO_PERMISO,
    L.ACCION,
    L.ESTADO_ANTERIOR,
    L.ESTADO_NUEVO,
    L.FECHA_CAMBIO,
    L.ID_USUARIO_ADMIN,
    U.USUARIO AS USUARIO_ADMIN
FROM LOG_AUDITORIA_PERMISOS L
LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = L.ID_EMPLEADO
LEFT JOIN USUARIOS  U ON U.ID_USUARIO  = L.ID_USUARIO_ADMIN;

-- ----------------------------------------------------------------
-- Lectura paginada
-- ----------------------------------------------------------------
-- Patron de SP_KARDEX_PAGINADO (modulo 17): la pagina y el tamano se
-- normalizan adentro, asi la app no tiene que validarlos.
-- La guarda de permiso va escrita a mano (como en el 21 y el 63) para que la
-- rutina quede completa desde el modulo: db/injectar-guardas.py la saltea si ya
-- esta. El mapeo rutina -> permiso vive en db/mapear-permisos.sql: son
-- GESTIONAR_PERMISOS_EMPLEADO, el mismo permiso con el que se aprueban y
-- rechazan permisos (el dueno decidio no separar "aprobar" de "auditar").
DELIMITER //

/*
SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO
Una pagina del historial, de lo mas reciente a lo mas viejo.
*/
DROP PROCEDURE IF EXISTS SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO //
CREATE PROCEDURE SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO(
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    CALL SP_EXIGIR_PERMISO('SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO');

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT ID_LOG, EMPLEADO, TIPO_PERMISO, ACCION, ESTADO_ANTERIOR, ESTADO_NUEVO,
           FECHA_CAMBIO, USUARIO_ADMIN
      FROM VIEW_HISTORIAL_PERMISOS
     ORDER BY ID_LOG DESC
     LIMIT P_POR_PAGINA OFFSET v_offset;
END //

/*
SP_CONTAR_AUDITORIA_PERMISOS
Cuantos registros hay, para el "Pagina 1 de N".
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_AUDITORIA_PERMISOS //
CREATE PROCEDURE SP_CONTAR_AUDITORIA_PERMISOS()
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_CONTAR_AUDITORIA_PERMISOS');

    SELECT COUNT(*) AS TOTAL FROM LOG_AUDITORIA_PERMISOS;
END //

DELIMITER ;
