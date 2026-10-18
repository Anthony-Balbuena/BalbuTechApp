/*
ARCHIVO 42 - CONTRATOS (registro de contratos de empleados)
El modulo de la app genera el HTML del contrato (borrador); al FIRMAR se sube
con SP_SUBIR_CONTRATO y ahi el trigger TR_ALTA_EMPLEADO crea al empleado solo
si su cedula aun no existe en EMPLEADOS (la introduccion de un empleado es
directa: los datos se piden una vez, en el contrato).
TIPO (nombres de la UI, 17/10):
- TEMPORAL: con duracion en meses (la ley lo llama "termino fijo").
- FIJO: permanente, sin fecha fin (la ley lo llama "termino indefinido").
- NOMBRE/CEDULA/CARGO/TELEFONO/EMAIL/FECHA_INGRESO/SALARIO son un snapshot
  de lo que se firmo: no cambian despues aunque cambie el empleado.
- FECHA_FIN NULL = contrato FIJO (permanente).
- Solo un contrato ACTIVO por cedula (lo valida el SP).
- Al despedir se finaliza a mano (opcion del menu empleados).
*/
CREATE TABLE IF NOT EXISTS CONTRATOS (
    ID_CONTRATO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    TIPO ENUM('TEMPORAL', 'FIJO') NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NULL,
    SALARIO DECIMAL(10, 2) NOT NULL,
    NOMBRE VARCHAR(100) NULL,
    CEDULA VARCHAR(20) NULL,
    CARGO VARCHAR(50) NULL,
    TELEFONO VARCHAR(20) NULL,
    EMAIL VARCHAR(100) NULL,
    FECHA_INGRESO DATE NULL,
    RUTA_DOCUMENTO VARCHAR(255) NULL,
    ESTADO ENUM('ACTIVO', 'FINALIZADO') NOT NULL DEFAULT 'ACTIVO',
    FECHA_REGISTRO TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_CONTRATO),
    CONSTRAINT FK_CONTRATO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- Si la tabla ya existia sin los datos de la persona, se agregan aqui
-- (idempotente: se puede volver a correr el archivo sin romper nada).
ALTER TABLE CONTRATOS
    ADD COLUMN IF NOT EXISTS NOMBRE VARCHAR(100) NULL AFTER SALARIO,
    ADD COLUMN IF NOT EXISTS CEDULA VARCHAR(20) NULL AFTER NOMBRE,
    ADD COLUMN IF NOT EXISTS CARGO VARCHAR(50) NULL AFTER CEDULA,
    ADD COLUMN IF NOT EXISTS TELEFONO VARCHAR(20) NULL AFTER CARGO,
    ADD COLUMN IF NOT EXISTS EMAIL VARCHAR(100) NULL AFTER TELEFONO,
    ADD COLUMN IF NOT EXISTS FECHA_INGRESO DATE NULL AFTER EMAIL;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_CONTRATO //
DROP PROCEDURE IF EXISTS SP_SUBIR_CONTRATO //
/*
SP_SUBIR_CONTRATO
Sube (registra) un contrato cuando la persona firma. No pide ID: recibe los
datos de la persona que trae el borrador y, si esa cedula aun no existe en
EMPLEADOS, el trigger TR_ALTA_EMPLEADO la crea al insertar el contrato.
P_MESES: duracion en meses (solo TEMPORAL; para FIJO permanente se pasa NULL
y FECHA_FIN queda NULL). FECHA_INICIO es siempre hoy (dia de la firma).
Los datos quedan como snapshot en la fila del contrato.
Frena: datos minimos, tipo invalido, temporal sin meses, cedula con contrato
ACTIVO, empleado INACTIVO, y contacto que ya pertenezca a otro empleado
(TELEFONO/EMAIL son unicos en EMPLEADOS).
*/
CREATE PROCEDURE SP_SUBIR_CONTRATO(
    IN P_NOMBRE VARCHAR(100),
    IN P_CEDULA VARCHAR(20),
    IN P_CARGO VARCHAR(50),
    IN P_SALARIO DECIMAL(10, 2),
    IN P_TELEFONO VARCHAR(20),
    IN P_EMAIL VARCHAR(100),
    IN P_FECHA_INGRESO DATE,
    IN P_TIPO VARCHAR(10),
    IN P_MESES INT,
    IN P_RUTA VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_estado VARCHAR(10) DEFAULT NULL;

    -- 1. Datos minimos
    IF P_NOMBRE IS NULL OR TRIM(P_NOMBRE) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE ES OBLIGATORIO.';
    END IF;
    IF P_CEDULA IS NULL OR TRIM(P_CEDULA) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CEDULA ES OBLIGATORIA PARA SUBIR UN CONTRATO.';
    END IF;
    IF P_TIPO IS NULL OR P_TIPO NOT IN ('TEMPORAL', 'FIJO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TIPO DEBE SER TEMPORAL O FIJO.';
    END IF;
    IF P_TIPO = 'TEMPORAL' AND (P_MESES IS NULL OR P_MESES < 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL CONTRATO TEMPORAL NECESITA UNA DURACION EN MESES MAYOR A CERO.';
    END IF;
    IF P_SALARIO IS NULL OR P_SALARIO < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL SALARIO ES OBLIGATORIO.';
    END IF;
    IF P_FECHA_INGRESO IS NULL THEN
        SET P_FECHA_INGRESO = CURDATE();
    END IF;

    -- 2. Esa cedula, ¿ya es de alguien?
    SELECT COUNT(*) INTO v_existe FROM EMPLEADOS WHERE CEDULA = P_CEDULA;

    IF v_existe > 0 THEN
        -- Un solo contrato ACTIVO por cedula (da igual el ID)
        IF EXISTS (
            SELECT 1 FROM CONTRATOS C
            JOIN EMPLEADOS E ON E.ID_EMPLEADO = C.ID_EMPLEADO
            WHERE E.CEDULA = P_CEDULA AND C.ESTADO = 'ACTIVO'
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA CEDULA YA TIENE UN CONTRATO ACTIVO. FINALIZELLO ANTES DE REGISTRAR OTRO.';
        END IF;

        -- No se le firma contrato a un empleado inactivo
        SELECT ESTADO INTO v_estado
        FROM EMPLEADOS WHERE CEDULA = P_CEDULA
        ORDER BY (ESTADO = 'ACTIVO') DESC
        LIMIT 1;
        IF v_estado = 'INACTIVO' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA CEDULA PERTENECE A UN EMPLEADO INACTIVO. NO SE LE PUEDE REGISTRAR UN CONTRATO.';
        END IF;
    ELSE
        -- Persona nueva: necesita contacto real (lo guarda EMPLEADOS y es unico)
        IF P_TELEFONO IS NULL OR P_TELEFONO IN ('', '-') OR P_EMAIL IS NULL OR P_EMAIL IN ('', '-') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NUEVO NECESITA TELEFONO Y EMAIL REALES.';
        END IF;
        IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE TELEFONO = P_TELEFONO) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESE TELEFONO YA PERTENECE A OTRO EMPLEADO.';
        END IF;
        IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE EMAIL = P_EMAIL) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESE EMAIL YA PERTENECE A OTRO EMPLEADO.';
        END IF;
    END IF;

    -- 3. Insertamos con ID_EMPLEADO NULL: el trigger lo crea o lo vincula
    INSERT INTO CONTRATOS (
        ID_EMPLEADO, TIPO, FECHA_INICIO, FECHA_FIN, SALARIO, RUTA_DOCUMENTO,
        NOMBRE, CEDULA, CARGO, TELEFONO, EMAIL, FECHA_INGRESO
    ) VALUES (
        NULL,
        P_TIPO,
        CURDATE(),
        CASE WHEN P_TIPO = 'TEMPORAL' THEN DATE_ADD(CURDATE(), INTERVAL P_MESES MONTH) ELSE NULL END,
        P_SALARIO,
        P_RUTA,
        P_NOMBRE, P_CEDULA, P_CARGO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO
    );

    SELECT CONCAT(
        'EXITO: CONTRATO #', LAST_INSERT_ID(),
        IF(v_existe = 0, ' REGISTRADO. EMPLEADO NUEVO CREADO.', ' REGISTRADO. EMPLEADO VINCULADO.')
    ) AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_FINALIZAR_CONTRATO //
/*
SP_FINALIZAR_CONTRATO
Pasa un contrato de ACTIVO a FINALIZADO (a mano, p.ej. al despedir).
FECHA_FIN: si era NULL (indefinido) se pone hoy; si el fijo vence en el
futuro (finalizacion anticipada) se corta a hoy; si ya vencio se conserva.
*/
CREATE PROCEDURE SP_FINALIZAR_CONTRATO(
    IN P_ID_CONTRATO INT
)
proc_label: BEGIN
    DECLARE v_est_actual VARCHAR(10) DEFAULT NULL;

    IF P_ID_CONTRATO IS NULL OR P_ID_CONTRATO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: INGRESE EL ID DEL CONTRATO.';
    END IF;

    SELECT ESTADO INTO v_est_actual FROM CONTRATOS WHERE ID_CONTRATO = P_ID_CONTRATO;
    IF v_est_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO EXISTE UN CONTRATO CON ESE ID.';
    END IF;
    IF v_est_actual = 'FINALIZADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL CONTRATO YA ESTA FINALIZADO.';
    END IF;

    UPDATE CONTRATOS
    SET ESTADO = 'FINALIZADO',
        FECHA_FIN = COALESCE(LEAST(FECHA_FIN, CURDATE()), CURDATE())
    WHERE ID_CONTRATO = P_ID_CONTRATO;

    SELECT CONCAT('EXITO: CONTRATO #', P_ID_CONTRATO, ' FINALIZADO.') AS MENSAJE;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_CONTRATOS_POR_EMPLEADO //
/*
SP_CONTRATOS_POR_EMPLEADO
Historial completo de contratos de un empleado (mas reciente primero).
Frena si el empleado no existe.
*/
CREATE PROCEDURE SP_CONTRATOS_POR_EMPLEADO(
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    IF P_ID_EMPLEADO IS NULL OR P_ID_EMPLEADO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: INGRESE EL ID DEL EMPLEADO.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO EXISTE UN EMPLEADO CON ESE ID.';
    END IF;

    SELECT
        C.ID_CONTRATO,
        C.TIPO,
        C.FECHA_INICIO,
        C.FECHA_FIN,
        C.SALARIO,
        C.ESTADO,
        C.RUTA_DOCUMENTO
    FROM CONTRATOS C
    WHERE C.ID_EMPLEADO = P_ID_EMPLEADO
    ORDER BY C.ID_CONTRATO DESC;
END //
DELIMITER ;

DELIMITER //
DROP TRIGGER IF EXISTS TR_ALTA_EMPLEADO //
/*
TR_ALTA_EMPLEADO (disparador)
Se dispara SOLO antes de cada INSERT en CONTRATOS y resuelve el ID del
empleado, que es lo que permite la introduccion directa (sin Agregar Empleado):
- Si el contrato ya trae ID_EMPLEADO, no toca nada (lo valido el SP y ademas
  lo cuida la llave foranea).
- Si no trae ID (persona nueva):
  * cedula con 2 o mas empleados -> frena (ambiguo);
  * cedula con 1 empleado -> vincula ese mismo ID (no duplica);
  * cedula sin empleado -> lo CREA en EMPLEADOS con ESTADO 'ACTIVO' y le
    pone ese ID al contrato (los datos salen del snapshot del contrato).
Nota: TELEFONO/EMAIL son unicos en EMPLEADOS; los frenos de duplicidad los
hace el SP antes de llegar aqui.
*/
CREATE TRIGGER TR_ALTA_EMPLEADO
BEFORE INSERT ON CONTRATOS
FOR EACH ROW
proc_label: BEGIN
    DECLARE v_n INT DEFAULT 0;
    DECLARE v_id INT DEFAULT NULL;
    DECLARE v_estado VARCHAR(10) DEFAULT NULL;

    IF NEW.ID_EMPLEADO IS NULL THEN
        IF NEW.CEDULA IS NULL OR TRIM(NEW.CEDULA) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: FALTA LA CEDULA PARA CREAR AL EMPLEADO.';
        END IF;

        SELECT COUNT(*) INTO v_n FROM EMPLEADOS WHERE CEDULA = NEW.CEDULA;

        IF v_n > 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: HAY MAS DE UN EMPLEADO CON ESA CEDULA. REVISE LOS REGISTROS.';
        ELSEIF v_n = 1 THEN
            SELECT ID_EMPLEADO, ESTADO INTO v_id, v_estado
            FROM EMPLEADOS WHERE CEDULA = NEW.CEDULA;
            IF v_estado = 'INACTIVO' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA CEDULA PERTENECE A UN EMPLEADO INACTIVO. NO SE LE PUEDE REGISTRAR UN CONTRATO.';
            END IF;
            SET NEW.ID_EMPLEADO = v_id;
        ELSE
            INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO, ESTADO)
            VALUES (
                NEW.NOMBRE,
                NEW.CEDULA,
                NEW.CARGO,
                NEW.SALARIO,
                NEW.TELEFONO,
                NEW.EMAIL,
                COALESCE(NEW.FECHA_INGRESO, CURDATE()),
                'ACTIVO'
            );
            SET NEW.ID_EMPLEADO = LAST_INSERT_ID();
        END IF;
    END IF;
END //
DELIMITER ;
