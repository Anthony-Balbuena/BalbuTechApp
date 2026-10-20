/*
ARCHIVO 42 - CONTRATOS (registro del contrato firmado)
El modulo de la app genera el HTML del contrato (borrador, opcion 12); cuando
el empleado firma, la opcion 13 lo coteja y lo registra con SP_SUBIR_CONTRATO.
CONTRATOS es el REGISTRO DEL PAPEL: no da de alta empleados.

Modelo (19/10/2026):
- La CEDULA es la llave: existe desde la oferta y no cambia.
- ID_EMPLEADO puede ser NULL: el contrato se firma ANTES del alta. Cuando el
  empleado se crea en EMPLEADOS, TR_VINCULAR_CONTRATO completa el ID solo.
- TIPO (nombres de la UI, 17/10):
  - TEMPORAL: con duracion en meses (la ley lo llama "termino fijo").
  - FIJO: permanente, sin fecha fin (la ley lo llama "termino indefinido").
- NOMBRE/CEDULA/CARGO/TELEFONO/EMAIL/FECHA_INGRESO/SALARIO son un snapshot
  de lo que se firmo: no cambian despues aunque cambie el empleado.
- FECHA_INICIO = FECHA_INGRESO del contrato (no el dia en que se sube).
- FECHA_FIN NULL = contrato FIJO (permanente).
- Solo un contrato ACTIVO por cedula (lo valida el SP).
- Al despedir se finaliza a mano (opcion del menu empleados).
- El escaneo del papel lo archiva RRHH; la app solo guarda la ruta si se la dan.
*/
CREATE TABLE IF NOT EXISTS CONTRATOS (
    ID_CONTRATO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NULL,
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

-- (19/10/2026) El contrato nace antes que el empleado: el ID puede faltar.
-- Idempotente: correrlo dos veces no cambia nada.
ALTER TABLE CONTRATOS MODIFY ID_EMPLEADO INT NULL;

-- La busqueda por cedula pasa a ser el camino normal (idempotente).
SET @hay_indice := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'CONTRATOS'
                      AND INDEX_NAME = 'IX_CONTRATOS_CEDULA');
SET @sql_indice := IF(@hay_indice = 0,
                      'CREATE INDEX IX_CONTRATOS_CEDULA ON CONTRATOS (CEDULA)',
                      'DO 0');
PREPARE st_indice FROM @sql_indice;
EXECUTE st_indice;
DEALLOCATE PREPARE st_indice;

DELIMITER //
DROP PROCEDURE IF EXISTS SP_INSERTAR_CONTRATO //
DROP PROCEDURE IF EXISTS SP_SUBIR_CONTRATO //
/*
SP_SUBIR_CONTRATO
Registra el contrato firmado. No pide ID: recibe los datos cotejados del
borrador y los guarda como snapshot.
- Si la cedula YA existe en EMPLEADOS, vincula el ID en el momento.
- Si NO existe (lo normal: el contrato se firma antes del alta), ID_EMPLEADO
  queda NULL y TR_VINCULAR_CONTRATO lo completa cuando el alta ocurra.
- Si ya hay 2+ empleados con esa cedula, frena por ambiguedad.
P_MESES: duracion en meses (solo TEMPORAL; para FIJO se pasa NULL).
FECHA_INICIO y FECHA_FIN salen de P_FECHA_INGRESO, no de CURDATE().
Frena: datos minimos, tipo invalido, temporal sin meses, cedula con contrato
ACTIVO, y empleado existente INACTIVO.
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
    DECLARE v_id INT DEFAULT NULL;
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
    IF P_SALARIO IS NULL OR P_SALARIO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL SALARIO ES OBLIGATORIO Y DEBE SER MAYOR A CERO.';
    END IF;
    IF P_FECHA_INGRESO IS NULL THEN
        SET P_FECHA_INGRESO = CURDATE();
    END IF;

    -- 2. El empleado puede no existir todavia: el contrato se firma antes
    --    del alta. Si existe, se vincula ya.
    SELECT COUNT(*) INTO v_existe FROM EMPLEADOS WHERE CEDULA = P_CEDULA;

    IF v_existe > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: HAY MAS DE UN EMPLEADO CON ESA CEDULA. REVISE LOS REGISTROS.';
    END IF;

    IF v_existe = 1 THEN
        SELECT ID_EMPLEADO, ESTADO INTO v_id, v_estado
        FROM EMPLEADOS WHERE CEDULA = P_CEDULA LIMIT 1;

        IF v_estado = 'INACTIVO' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA CEDULA PERTENECE A UN EMPLEADO INACTIVO. REACTIVELO ANTES DE REGISTRAR UN CONTRATO.';
        END IF;
    END IF;

    -- 3. Un solo contrato ACTIVO por cedula. Se mira por cedula (el ID puede
    --    ser NULL) y tambien por ID cuando ya esta vinculado.
    IF EXISTS (
        SELECT 1 FROM CONTRATOS
        WHERE ESTADO = 'ACTIVO'
          AND (CEDULA = P_CEDULA OR (v_id IS NOT NULL AND ID_EMPLEADO = v_id))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA CEDULA YA TIENE UN CONTRATO ACTIVO. CIERRE ESE CONTRATO ANTES DE REGISTRAR OTRO.';
    END IF;

    -- 4. Registro del papel
    INSERT INTO CONTRATOS (
        ID_EMPLEADO, TIPO, FECHA_INICIO, FECHA_FIN, SALARIO, RUTA_DOCUMENTO,
        NOMBRE, CEDULA, CARGO, TELEFONO, EMAIL, FECHA_INGRESO
    ) VALUES (
        v_id,
        P_TIPO,
        P_FECHA_INGRESO,
        CASE WHEN P_TIPO = 'TEMPORAL'
             THEN DATE_ADD(P_FECHA_INGRESO, INTERVAL P_MESES MONTH)
             ELSE NULL END,
        P_SALARIO,
        P_RUTA,
        P_NOMBRE, P_CEDULA, P_CARGO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO
    );

    SELECT CONCAT(
        'EXITO: CONTRATO #', LAST_INSERT_ID(), ' REGISTRADO.',
        IF(v_id IS NULL, ' EMPLEADO PENDIENTE DE ALTA.', ' EMPLEADO VINCULADO.')
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
DROP PROCEDURE IF EXISTS SP_CONTRATOS_POR_CEDULA //
/*
SP_CONTRATOS_POR_CEDULA
Historial completo de contratos de una persona (mas reciente primero).
Funciona antes y despues del alta: busca por cedula, no por ID.
No frena si no hay contratos: devuelve 0 filas.
*/
CREATE PROCEDURE SP_CONTRATOS_POR_CEDULA(
    IN P_CEDULA VARCHAR(20)
)
proc_label: BEGIN
    IF P_CEDULA IS NULL OR TRIM(P_CEDULA) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: INGRESE LA CEDULA.';
    END IF;

    SELECT
        C.ID_CONTRATO,
        C.ID_EMPLEADO,
        C.NOMBRE,
        C.CARGO,
        C.TIPO,
        C.FECHA_INICIO,
        C.FECHA_FIN,
        C.SALARIO,
        C.ESTADO,
        C.RUTA_DOCUMENTO,
        IF(C.ID_EMPLEADO IS NULL, 'PENDIENTE', 'VINCULADO') AS VINCULO
    FROM CONTRATOS C
    WHERE C.CEDULA = P_CEDULA
    ORDER BY C.ID_CONTRATO DESC;
END //
DELIMITER ;

-- (19/10/2026) Cuando se da de alta al empleado, sus contratos firmados
-- dejan de estar huerfanos. AFTER INSERT sobre EMPLEADOS: no crea nada, solo
-- completa el ID que falto al registrar el contrato.
DELIMITER //
DROP TRIGGER IF EXISTS TR_VINCULAR_CONTRATO //
CREATE TRIGGER TR_VINCULAR_CONTRATO AFTER INSERT ON EMPLEADOS
FOR EACH ROW
BEGIN
    UPDATE CONTRATOS
    SET ID_EMPLEADO = NEW.ID_EMPLEADO
    WHERE CEDULA = NEW.CEDULA AND ID_EMPLEADO IS NULL;
END //
DELIMITER ;

-- TR_ALTA_EMPLEADO ELIMINADO (18/10/2026): subir un contrato ya NO crea
-- empleados. El alta la hace RRHH desde el modulo de EMPLEADOS.
DELIMITER //
DROP TRIGGER IF EXISTS TR_ALTA_EMPLEADO //
DELIMITER ;
