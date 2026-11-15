-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH
/*
TABLA EMPLEADOS
Guarda la informacion de cada empleado: nombre, cedula, cargo, salario,
telefono, email y fechas de ingreso y despido. La cedula, el telefono y
el email son obligatorios y unicos, el salario tiene que ser mayor a cero
y todo empleado arranca ACTIVO.
*/
CREATE TABLE EMPLEADOS (
    ID_EMPLEADO INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(100) NOT NULL,
    CEDULA VARCHAR(20) NOT NULL UNIQUE,
    CARGO VARCHAR(50) NOT NULL,
    SALARIO DECIMAL(10, 2) NOT NULL CHECK (SALARIO > 0),
    TELEFONO VARCHAR(20) NOT NULL UNIQUE,
    EMAIL VARCHAR(100) NOT NULL UNIQUE,
    FECHA_INGRESO DATE NOT NULL,
    FECHA_DESPIDO DATE NULL,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_EMPLEADO),
    CONSTRAINT CK_EMPLEADO_NOMBRE CHECK (CHAR_LENGTH(TRIM(NOMBRE)) > 0)
) ENGINE = InnoDB;

--1. INSERTAR EMPLEADOS 
DELIMITER //

/*
SP_INSERTAR_EMPLEADO
Da de alta un empleado nuevo limpiando nombre, cedula, telefono y email.
Valida que nombre y cedula vengan completos, que cedula, email y telefono
no se repitan y que el salario sea mayor a cero; si todo esta bien guarda
y responde con un mensaje y el ID creado.
*/
DROP PROCEDURE IF EXISTS SP_INSERTAR_EMPLEADO ;
CREATE OR REPLACE PROCEDURE SP_INSERTAR_EMPLEADO(
    IN P_NOMBRE    VARCHAR(100),
    IN P_CEDULA    VARCHAR(15),
    IN P_CARGO     VARCHAR(50),
    IN P_SALARIO   DECIMAL(10, 2),
    IN P_TELEFONO  VARCHAR(20),
    IN P_EMAIL     VARCHAR(100),
    IN P_FECHA_INGRESO DATE
)
proc_label: BEGIN 
    DECLARE v_nombre_limpio   VARCHAR(100);
    DECLARE v_cedula_limpia   VARCHAR(15);
    DECLARE v_telefono_limpio VARCHAR(20);
    DECLARE v_email_limpio    VARCHAR(100);

    -- 0. LIMPIEZA
    SET v_nombre_limpio   = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    SET v_cedula_limpia   = REGEXP_REPLACE(P_CEDULA, '[[:space:]\-]', '');
    SET v_telefono_limpio = REGEXP_REPLACE(P_TELEFONO, '[[:space:]()\-]', '');
    SET v_email_limpio    = LOWER(REPLACE(P_EMAIL, ' ', ''));
    

    -- 1. VALIDACIÓN: DATOS OBLIGATORIOS
    IF v_nombre_limpio = '' OR v_cedula_limpia = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NOMBRE Y CÉDULA SON OBLIGATORIOS.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDACIÓN: DUPLICADOS
    IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE CEDULA = v_cedula_limpia) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA EXISTE UN EMPLEADO CON ESTA CÉDULA.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE EMAIL = v_email_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE EMAIL YA ESTÁ REGISTRADO.';
        LEAVE proc_label;
    END IF;

    IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE TELEFONO = v_telefono_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.';
        LEAVE proc_label;
    END IF;

    -- 3. VALIDACIÓN: SALARIO
    IF P_SALARIO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL SALARIO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 4. INSERCIÓN FINAL
 -- (19/10/2026) La fecha de ingreso puede venir del contrato firmado; si no
-- viene, se usa hoy.
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES (v_nombre_limpio, v_cedula_limpia, P_CARGO, P_SALARIO, v_telefono_limpio, v_email_limpio,
        COALESCE(P_FECHA_INGRESO, CURDATE()));

    SELECT CONCAT('EXITO: EMPLEADO "', v_nombre_limpio, '" INSERTADO. ID: ', LAST_INSERT_ID()) AS MENSAJE;

END//

DELIMITER ;

    


--2. ACTUALIZAR EMPLEADO 

DELIMITER //

/*
SP_ACTUALIZAR_EMPLEADO
Cambia los datos que se le envien de un empleado existente.
Comprueba que exista, limpia los valores nuevos y revisa que cedula,
telefono y email no le pertenezcan a otro; lo que llegue en NULL se queda
como estaba y el salario solo se acepta si es mayor a cero.
*/
DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_EMPLEADO ;
CREATE OR REPLACE PROCEDURE SP_ACTUALIZAR_EMPLEADO(
    IN P_ID_EMPLEADO INT,
    IN P_NOMBRE      VARCHAR(100),
    IN P_CEDULA      VARCHAR(20),
    -- (09/10/2026) C3. Orden igual al C++ (empleados.cpp): email, cargo,
    -- telefono, salario. Antes venia permutado y corrompia datos
    -- (el email caia en cargo, el cargo en salario y el salario en email).
    IN P_EMAIL       VARCHAR(100),
    IN P_CARGO       VARCHAR(50),
    IN P_TELEFONO    VARCHAR(20),
    IN P_SALARIO     DECIMAL(10, 2)
)
proc_label: BEGIN
    -- Variables para limpieza
    DECLARE v_nombre_limpio    VARCHAR(100);
    DECLARE v_cedula_limpia    VARCHAR(20);
    DECLARE v_cargo_limpio     VARCHAR(50);
    DECLARE v_telefono_limpio  VARCHAR(20);
    DECLARE v_email_limpio     VARCHAR(100);

    -- 1. VALIDAR EXISTENCIA
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. LIMPIEZA Y VALIDACIONES
    IF P_NOMBRE IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    END IF;

    -- Validación de Cédula
    IF P_CEDULA IS NOT NULL THEN
        SET v_cedula_limpia = REGEXP_REPLACE(P_CEDULA, '[[:space:]\-]', '');
        IF v_cedula_limpia = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CÉDULA NO PUEDE ESTAR VACÍA.';
            LEAVE proc_label;
        ELSEIF EXISTS (SELECT 1 FROM EMPLEADOS WHERE CEDULA = v_cedula_limpia AND ID_EMPLEADO <> P_ID_EMPLEADO) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CÉDULA YA PERTENECE A OTRO EMPLEADO.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_CARGO IS NOT NULL THEN
        SET v_cargo_limpio = REGEXP_REPLACE(TRIM(P_CARGO), '[[:space:]]+', ' ');
    END IF;

    IF P_TELEFONO IS NOT NULL THEN
        SET v_telefono_limpio = REGEXP_REPLACE(P_TELEFONO, '[[:space:]()\-]', '');
        IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE TELEFONO = v_telefono_limpio AND ID_EMPLEADO <> P_ID_EMPLEADO) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL TELÉFONO YA PERTENECE A OTRO EMPLEADO.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_EMAIL IS NOT NULL THEN
        SET v_email_limpio = LOWER(REPLACE(P_EMAIL, ' ', ''));
        IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE EMAIL = v_email_limpio AND ID_EMPLEADO <> P_ID_EMPLEADO) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMAIL YA PERTENECE A OTRO EMPLEADO.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- 3. ACTUALIZACIÓN DINÁMICA 
    UPDATE EMPLEADOS 
    SET 
        NOMBRE   = COALESCE(v_nombre_limpio, NOMBRE),
        CEDULA   = COALESCE(v_cedula_limpia, CEDULA),
        CARGO    = COALESCE(v_cargo_limpio, CARGO),
        SALARIO  = COALESCE(IF(P_SALARIO > 0, P_SALARIO, NULL), SALARIO),
        TELEFONO = COALESCE(v_telefono_limpio, TELEFONO),
        EMAIL    = COALESCE(v_email_limpio, EMAIL)
    WHERE ID_EMPLEADO = P_ID_EMPLEADO;

    -- 4. MENSAJE DE ÉXITO
    SELECT CONCAT('EXITO: EMPLEADO "', NOMBRE, '" ACTUALIZADO CON ÉXITO.') AS MENSAJE
    FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;

END //
DELIMITER ;

--3. DESPECIR EMPLEADO
DELIMITER //
/*
SP_DESPEDIR_EMPLEADO
Da de baja a un empleado: lo marca INACTIVO y le pone la fecha de despido.
No permite despedir a alguien que ya esta inactivo ni usar una fecha
futura; si no llega fecha, asume la de hoy.
*/
DROP PROCEDURE IF EXISTS SP_DESPEDIR_EMPLEADO;
CREATE PROCEDURE SP_DESPEDIR_EMPLEADO(
    IN P_ID_EMPLEADO   INT,
    IN P_FECHA_DESPIDO DATE
)
proc_label: BEGIN

    -- 1. VALIDAR QUE EL EMPLEADO EXISTE
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE EN LA BASE DE DATOS.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDAR QUE NO ESTÉ YA INACTIVO (Para evitar doble despido)
    IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO = 'INACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE EMPLEADO YA CONSTA COMO INACTIVO.';
        LEAVE proc_label;
    END IF;

    -- 3. ASIGNAR FECHA AUTOMÁTICA SI VIENE NULA
    -- Si desde tu app no mandas fecha, el sistema asume que es hoy
    IF P_FECHA_DESPIDO IS NULL THEN
        SET P_FECHA_DESPIDO = CURRENT_DATE;
    END IF;

    
IF P_FECHA_DESPIDO > CURRENT_DATE THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA FECHA DE DESPIDO NO PUEDE SER FUTURA.';
    LEAVE proc_label;
END IF;

    -- 4. ACTUALIZACIÓN DE ESTADO Y SALIDA 
    UPDATE EMPLEADOS 
    SET 
        ESTADO = 'INACTIVO',
        FECHA_DESPIDO = P_FECHA_DESPIDO
    WHERE ID_EMPLEADO = P_ID_EMPLEADO;

    -- 5. RESPUESTA
    -- El trigger TR_DESACTIVAR_USUARIO_POST_LIQUIDACION ya dejo INACTIVA la
    -- cuenta vinculada (si tenia), asi que el mensaje lo avisa.
    SELECT CONCAT('EXITO: EL EMPLEADO ID ', P_ID_EMPLEADO, ' HA SIDO DADO DE BAJA.',
                  IF(EXISTS (SELECT 1 FROM USUARIOS WHERE ID_EMPLEADO = P_ID_EMPLEADO),
                     ' SU USUARIO QUEDO INACTIVO Y SUS SESIONES CERRADAS.', '')) AS MENSAJE;

END //
DELIMITER ;

--4. REACTIVAR ENPLEADO 
DELIMITER //
/*
SP_REACTIVAR_EMPLEADO
Reactiva a un empleado que estaba inactivo: lo marca ACTIVO, borra la
fecha de despido y anota el dia de reingreso. Si se manda un nuevo
salario se aplica, pero tiene que ser mayor a cero.
*/
DROP PROCEDURE IF EXISTS  SP_REACTIVAR_EMPLEADO;
CREATE PROCEDURE SP_REACTIVAR_EMPLEADO(
    IN P_ID_EMPLEADO INT,
    IN P_NUEVO_SALARIO DECIMAL(10,2)
)
proc_label: BEGIN

    -- 1. VALIDAR QUE EL ID EXISTE
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL ID DE EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDAR QUE EL EMPLEADO ESTÉ INACTIVO
    -- No tiene sentido reactivar a alguien que ya está trabajando
    IF EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO = 'ACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: EL EMPLEADO YA SE ENCUENTRA ACTIVO.';
        LEAVE proc_label;
    END IF;

    -- 3. VALIDAR EL NUEVO SALARIO (Solo si no es NULL)
    IF P_NUEVO_SALARIO IS NOT NULL AND P_NUEVO_SALARIO <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NUEVO SALARIO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- 4. ACTUALIZACIÓN DE REINGRESO
    UPDATE EMPLEADOS 
    SET 
        ESTADO = 'ACTIVO',
        FECHA_DESPIDO = NULL,
        FECHA_INGRESO = CURRENT_DATE, -- Se actualiza a la fecha actual de reingreso
        SALARIO = COALESCE(P_NUEVO_SALARIO, SALARIO)
    WHERE ID_EMPLEADO = P_ID_EMPLEADO;
    
    -- 5. RESPUESTA
    -- La cuenta del empleado NO se reactiva sola: se avisa para que se active
    -- a mano desde Usuarios y no vuelva a operar sin que nadie lo decida.
    SELECT CONCAT('EXITO: EMPLEADO ID ', P_ID_EMPLEADO, ' REINGRESADO CORRECTAMENTE.',
                  IF(EXISTS (SELECT 1 FROM USUARIOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO = 'INACTIVO'),
                     ' SU USUARIO SIGUE INACTIVO: ACTIVELO EN EL MODULO USUARIOS.', '')) AS MENSAJE;

END //

DELIMITER ;

---4. REPORTE DE NOMINA

DELIMITER //
/*
SP_REPORTE_NOMINA_TOTAL
Resumen de la nomina de los empleados activos: total de personal, gasto
mensual, sueldos minimo, maximo y promedio, mas el desglose por cargo.
Si no hay nadie activo avisa en vez de devolver una tabla vacia.
*/
DROP PROCEDURE IF EXISTS SP_REPORTE_NOMINA_TOTAL;
CREATE PROCEDURE SP_REPORTE_NOMINA_TOTAL()
proc_label: BEGIN

    -- 1. VERIFICAR SI HAY EMPLEADOS ACTIVOS
    -- Si no hay nadie, devolvemos un mensaje claro en lugar de una tabla con NULLs
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ESTADO = 'ACTIVO') THEN
        SELECT 'AVISO: NO HAY EMPLEADOS ACTIVOS PARA GENERAR NÓMINA.' AS MENSAJE;
        LEAVE proc_label;
    END IF;

    -- 2. CONSULTA DE NÓMINA CON FORMATEO
    -- Usamos IFNULL para asegurar que los cálculos siempre devuelvan 0 en lugar de NULL
    SELECT 
        COUNT(*) AS TOTAL_EMPLEADOS,
        IFNULL(SUM(SALARIO), 0) AS GASTO_MENSUAL_NOMINA,
        IFNULL(MIN(SALARIO), 0) AS SUELDO_MINIMO,
        IFNULL(MAX(SALARIO), 0) AS SUELDO_MAXIMO,
        IFNULL(AVG(SALARIO), 0) AS SUELDO_PROMEDIO -- Añadimos el promedio para mejor reporte
    FROM EMPLEADOS
    WHERE ESTADO = 'ACTIVO';


    -- Agrega esto al final del SP o crea un nuevo SP llamado 8_SP_REPORTE_NOMINA_POR_CARGO
SELECT 
    CARGO,
    COUNT(*) AS EMPLEADOS_POR_CARGO,
    SUM(SALARIO) AS TOTAL_POR_CARGO
FROM EMPLEADOS
WHERE ESTADO = 'ACTIVO'
GROUP BY CARGO;

END //
DELIMITER ;

--5. BUSCAR ENPLEADOS DINAMICA

DELIMITER //
/*
SP_CONSULTAR_EMPLEADOS
Busqueda de empleados por ID o por nombre.
Si llega el ID prioriza ese; si no, busca por nombre con coincidencia
parcial; si ambos vienen vacios trae la lista completa.
*/
DROP PROCEDURE IF EXISTS  SP_CONSULTAR_EMPLEADOS ;
CREATE PROCEDURE SP_CONSULTAR_EMPLEADOS(
    IN P_ID_EMPLEADO   INT,
    IN P_FILTRO_NOMBRE VARCHAR(100)
)
BEGIN
    -- La lógica funciona así:
    -- 1. Si mandas el ID, prioriza la búsqueda por ese ID.
    -- 2. Si el ID es NULL, busca por nombre (coincidencia parcial).
    -- 3. Si ambos son NULL, trae la lista completa.

    SELECT 
        ID_EMPLEADO,
        CEDULA,
        NOMBRE,
        CARGO,
        SALARIO,
        TELEFONO,
        EMAIL,
        FECHA_INGRESO,
        FECHA_DESPIDO,
        ESTADO
    FROM EMPLEADOS
    WHERE 
        (P_ID_EMPLEADO IS NULL OR ID_EMPLEADO = P_ID_EMPLEADO)
        AND 
        (P_FILTRO_NOMBRE IS NULL OR TRIM(P_FILTRO_NOMBRE) = '' OR NOMBRE LIKE CONCAT('%', P_FILTRO_NOMBRE, '%'))
    ORDER BY ID_EMPLEADO DESC;

END //

DELIMITER ;


--- 6. AUMENTO POR CARGO
DELIMITER //

/*
SP_AUMENTO_POR_CARGO
Aplica un aumento por porcentaje a los empleados activos, ya sea a uno
por ID o a todos los de un cargo. Trabaja en transaccion: si no encuentra
a nadie revierte todo y avisa; si no, guarda y dice cuantos empleados se
actualizaron.
*/
DROP PROCEDURE IF EXISTS SP_AUMENTO_POR_CARGO ;
CREATE PROCEDURE SP_AUMENTO_POR_CARGO(
    IN P_ID_EMPLEADO   INT,
    IN P_CARGO         VARCHAR(50),
    IN P_PORCENTAJE    DECIMAL(5, 2)
)
proc_label: BEGIN
    DECLARE v_registros_afectados INT DEFAULT 0;

    -- 1. TRANSACCIÓN: Asegura que si algo falla, no se aplique el aumento a medias
    START TRANSACTION;

    -- 2. VALIDACIONES (Iguales a las tuyas, que están bien)
    IF (P_ID_EMPLEADO IS NULL) AND (P_CARGO IS NULL OR TRIM(P_CARGO) = '') THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESPECIFIQUE ID O CARGO.';
        LEAVE proc_label;
    END IF; 

    -- 3. CÁLCULO Y ACTUALIZACIÓN CON REDONDEO
    -- Usamos ROUND para evitar centavos infinitos o errores de precisión decimal
    UPDATE EMPLEADOS 
    SET SALARIO = ROUND(SALARIO + (SALARIO * (P_PORCENTAJE / 100)), 2)
    WHERE (P_ID_EMPLEADO IS NULL OR ID_EMPLEADO = P_ID_EMPLEADO)
      AND (P_CARGO IS NULL OR CARGO = P_CARGO)
      AND ESTADO = 'ACTIVO';
    
    SET v_registros_afectados = ROW_COUNT();

    -- 4. VALIDACIÓN DE ÉXITO
    IF v_registros_afectados = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE ENCONTRARON EMPLEADOS ACTIVOS PARA EL FILTRO DADO.';
    ELSE
        -- 5. COMMIT: Guarda los cambios permanentemente
        COMMIT;
        SELECT CONCAT('EXITO: SE APLICÓ EL AUMENTO A ', v_registros_afectados, ' EMPLEADO(S).') AS MENSAJE;
    END IF;

END //

DELIMITER ;

--- 7. ANIVERSARIO DE EMPLEADO EN LA EMPRESA 
DELIMITER //
/*
SP_ANIVERSARIOS_MES
Lista los empleados activos que cumplen aniversario de ingreso en el mes
actual, con los anos que llevan en la empresa. Si no hay empleados activos
manda error y si nadie cumple este mes avisa con un mensaje.
*/
drop PROCEDURE if EXISTS SP_ANIVERSARIOS_MES;
CREATE PROCEDURE SP_ANIVERSARIOS_MES()
proc_label: BEGIN

    -- 1. VALIDAR SI EXISTEN EMPLEADOS ACTIVOS EN GENERAL
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ESTADO = 'ACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO HAY EMPLEADOS ACTIVOS EN LA BASE DE DATOS.';
        LEAVE proc_label;
    END IF;

    -- 2. VERIFICAR SI HAY ALGUIEN DE ANIVERSARIO ESTE MES
    -- Esto evita que el DataReader en C++ se quede esperando filas que no existen
    IF NOT EXISTS (
        SELECT 1 FROM EMPLEADOS 
        WHERE MONTH(FECHA_INGRESO) = MONTH(CURRENT_DATE) 
          AND ESTADO = 'ACTIVO'
    ) THEN
        SELECT 'INFORMATIVO: NO HAY ANIVERSARIOS LABORALES EN EL MES ACTUAL.' AS MENSAJE;
        LEAVE proc_label;
    END IF;

    -- 3. CONSULTA FINAL
    SELECT 
        ID_EMPLEADO,
        NOMBRE,
        CARGO,
        FECHA_INGRESO,
        TIMESTAMPDIFF(YEAR, FECHA_INGRESO, CURRENT_DATE) AS ANOS_EN_EMPRESA
    FROM EMPLEADOS
    WHERE MONTH(FECHA_INGRESO) = MONTH(CURRENT_DATE) 
      AND ESTADO = 'ACTIVO'
    ORDER BY DAY(FECHA_INGRESO) ASC; -- Ordenados por el día que cumplen

END //

DELIMITER ;


---8. BUSCAR ENPLEADO
DELIMITER //
/*
SP_BUSQUEDA_RAPIDA_EMPLEADOS
Busqueda rapida de empleados por un solo termino: coincide con ID,
cedula, nombre o cargo. El termino es obligatorio; si no se encuentra
nada no devuelve filas y los activos salen primero.
*/
DROP PROCEDURE IF EXISTS SP_BUSQUEDA_RAPIDA_EMPLEADOS;
CREATE PROCEDURE SP_BUSQUEDA_RAPIDA_EMPLEADOS(
    IN P_TERMINO VARCHAR(100)
)
proc_label: BEGIN

    -- 1. VALIDAR QUE EL TERMINO DE BUSQUEDA NO ESTE VACIO
    IF P_TERMINO IS NULL OR TRIM(P_TERMINO) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE INGRESAR UN DATO PARA BUSCAR.';
        LEAVE proc_label;
    END IF;

    -- 2. BUSQUEDA MULTI-CRITERIO
    -- Buscamos coincidencias en ID, Cedula, Nombre o Cargo
    SELECT 
        ID_EMPLEADO,
        CEDULA,
        NOMBRE,
        CARGO,
        ESTADO
    FROM EMPLEADOS
    WHERE (
        ID_EMPLEADO = P_TERMINO -- Si es un número exacto
        OR CEDULA LIKE CONCAT('%', P_TERMINO, '%')
        OR NOMBRE LIKE CONCAT('%', P_TERMINO, '%')
        OR CARGO  LIKE CONCAT('%', P_TERMINO, '%')
    )
    ORDER BY ESTADO ASC, NOMBRE ASC; -- Muestra primero los activos y luego por orden alfabetico

    -- 3. VALIDAR SI NO SE ENCONTRARON RESULTADOS
    -- Nota: En C++, si el ResultSet está vacío, sabrás que no hubo coincidencias.

END //

DELIMITER ;


---9. VOLANTE DE PAGO
DELIMITER //
/*
SP_GENERAR_RECIBO_EMPLEADO
Genera el volante de pago de un empleado activo: sueldo bruto, los
descuentos de SFS y AFP y el sueldo neto con la fecha de emision.
Si el ID no existe o el empleado no esta activo manda un error.
*/
drop PROCEDURE IF EXISTS  SP_GENERAR_RECIBO_EMPLEADO ;
CREATE PROCEDURE SP_GENERAR_RECIBO_EMPLEADO  (
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN

    -- 1. VALIDAR QUE EL ID NO SEA NULO
    IF P_ID_EMPLEADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.';
        LEAVE proc_label;
    END IF;

    -- 2. VALIDAR QUE EL EMPLEADO EXISTA Y ESTÉ ACTIVO
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO AND ESTADO = 'ACTIVO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE O NO SE ENCUENTRA ACTIVO.';
        LEAVE proc_label;
    END IF;

    -- 3. GENERAR EL RECIBO DETALLADO
    SELECT 
        'BALBU_TECH - SOLUCIONES TECNOLÓGICAS' AS EMPRESA,
        ID_EMPLEADO,
        NOMBRE,
        CEDULA,
        CARGO,
        SALARIO AS SUELDO_BRUTO,
        -- Cálculo de Seguridad Social (SFS 3.04%, AFP 2.87% - Valores típicos en RD)
        ROUND(SALARIO * 0.0304, 2) AS DESCUENTO_SFS,
        ROUND(SALARIO * 0.0287, 2) AS DESCUENTO_AFP,
        -- Cálculo del Neto
        ROUND(SALARIO - (SALARIO * 0.0591), 2) AS SUELDO_NETO,
        DATE_FORMAT(CURRENT_DATE, '%d/%m/%Y') AS FECHA_EMISION
    FROM EMPLEADOS
    WHERE ID_EMPLEADO = P_ID_EMPLEADO;

END //

DELIMITER ;


----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------





DELIMITER //
/*
TRG_CARGO_UPPER
Se dispara antes de insertar un empleado y deja el cargo en mayusculas,
asi los nombres de cargo se guardan siempre igual. Trabaja en automatico.
*/
DROP TRIGGER IF EXISTS TRG_CARGO_UPPER;
CREATE TRIGGER TRG_CARGO_UPPER BEFORE INSERT ON EMPLEADOS
FOR EACH ROW
BEGIN
    SET NEW.CARGO = UPPER(NEW.CARGO);
END//

/*
TRG_CARGO_UPPER_UPDATE
Se dispara antes de actualizar un empleado y deja el cargo nuevo en
mayusculas, igual que en la insercion. Trabaja en automatico.
*/
DROP TRIGGER IF EXISTS TRG_CARGO_UPPER_UPDATE;
CREATE TRIGGER TRG_CARGO_UPPER_UPDATE BEFORE UPDATE ON EMPLEADOS
FOR EACH ROW
BEGIN
    SET NEW.CARGO = UPPER(NEW.CARGO);
END//

DELIMITER ;

-- ================================================================
-- EMPLEADOS_CEDULA_UNICA (ex modulo 59)
-- ================================================================

/*
SECCION EMPLEADOS_CEDULA_UNICA (ex modulo 59)
Parche para bases viejas: el CREATE TABLE de EMPLEADOS ya declara CEDULA
UNIQUE inline, pero una base creada antes de esa linea no lo tenia. Este
ALTER idempotente agrega UQ_EMPLEADOS_CEDULA. En una base nueva agrega un
segundo indice unico sobre la misma columna.
*/
-- ================================================================
-- BALBU_TECH - CEDULA UNICA EN EMPLEADOS
-- ================================================================
-- (29/10/2026) El comentario del modulo 8 decia que la cedula era
-- obligatoria y unica, pero el esquema solo tenia UNIQUE en TELEFONO y
-- EMAIL. La app confiaba en una regla que la base no hacia cumplir.
--
-- ORDEN DE DESPLIEGUE:
--   1. Backup de la base.
--   2. Correr este modulo.
--   3. Probar que rechaza una cedula repetida.
--
-- Idempotente: consulta INFORMATION_SCHEMA.STATISTICS antes de crear el
-- indice, asi correrlo dos veces no cambia nada.

-- 1. Si hay duplicados, este SELECT los lista. El ALTER de abajo falla
--    con error 1062 y no se aplica nada hasta limpiarlos.
SELECT CEDULA, COUNT(*) AS REPETIDAS
  FROM EMPLEADOS
 GROUP BY CEDULA
HAVING COUNT(*) > 1;

-- 2. El candado.
SET @hay_unico := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'EMPLEADOS'
                     AND INDEX_NAME = 'UQ_EMPLEADOS_CEDULA');
SET @sql_unico := IF(@hay_unico = 0,
                     'ALTER TABLE EMPLEADOS ADD UNIQUE KEY UQ_EMPLEADOS_CEDULA (CEDULA)',
                     'DO 0');
PREPARE st_unico FROM @sql_unico;
EXECUTE st_unico;
DEALLOCATE PREPARE st_unico;

SELECT 'CEDULA UNICA APLICADA.' AS RESULTADO;


-- ================================================================
-- CONTRATOS (ex modulo 42)
-- ================================================================

/*
SECCION CONTRATOS (ex modulo 42)
Registro del contrato firmado: la tabla CONTRATOS (FK a EMPLEADOS), sus ALTER idempotentes, el indice por cedula, los SP de subir, finalizar y consultar por cedula, y TR_VINCULAR_CONTRATO. El contrato se firma ANTES del alta, asi que ID_EMPLEADO puede ser NULL: el trigger es AFTER INSERT ON EMPLEADOS y completa el ID cuando el alta ocurre. Es el unico trigger AFTER INSERT de EMPLEADOS, asi que no hay orden que cuidar, y la tabla del ON la crea este mismo archivo, arriba.
*/
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
