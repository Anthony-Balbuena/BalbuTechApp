/*
MODULO 25 - GARANTIAS, RECLAMOS, ASIGNACIONES Y REPARACIONES

El agregado completo del posventa: la garantia (GARANTIAS), el reclamo que se
abre sobre ella (RECLAMOS_GARANTIAS), el tecnico al que se le asigna
(ASIGNACIONES_RECLAMOS), la bitacora del trabajo (DETALLE_REPARACIONES) y el
flujo que los conecta: columnas de autor y fecha, SPs de consulta y el trigger
que crea la garantia sola al confirmar la venta.

Las cinco secciones van en el orden de las FK, de la garantia hacia afuera:
GARANTIAS -> RECLAMOS_GARANTIAS -> ASIGNACIONES_RECLAMOS -> DETALLE_REPARACIONES.
El flujo va ultimo porque altera las dos primeras y redefine tres de sus SPs.

(14/11/2026) Absorbe los modulos 27, 34, 35 y 63. Estaban separados por el
orden de import (cada tabla necesita la anterior creada) y porque el 63 era un
parche correctivo posterior. Con las cinco en un archivo ese orden se cumple
solo, y las versiones viejas de los tres SPs que el 63 reemplaza quedan a la
vista en el mismo archivo, no a un import de distancia.
*/


/*
TABLA GARANTIAS
Guarda la garantia de cada producto vendido, con su fecha de inicio, fin
y estado. Solo puede haber una garantia por producto vendido y la fecha
final siempre tiene que ser despues del inicio.
*/
CREATE TABLE GARANTIAS (
    ID_GARANTIA INT NOT NULL AUTO_INCREMENT,
    ID_DETALLE_VENTA INT NOT NULL,
    FECHA_INICIO DATE NOT NULL,
    FECHA_FIN DATE NOT NULL,
    ESTADO ENUM(
        'ACTIVA',
        'VENCIDA',
        'CANCELADA'
    ) NOT NULL DEFAULT 'ACTIVA',
    -- (19/11/2026) Antes vivian como ALTER en la seccion "Flujo de garantias".
    -- Se trajeron al CREATE para que la tabla se lea completa en un solo lugar.
    ID_EMPLEADO INT NULL,
    FECHA_REGISTRO TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID_GARANTIA),
    CONSTRAINT UQ_GARANTIA_DETALLE UNIQUE (ID_DETALLE_VENTA),
    CONSTRAINT CK_GARANTIA_FECHAS CHECK (FECHA_FIN > FECHA_INICIO),
    CONSTRAINT FK_GARANTIA_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    CONSTRAINT FK_GARANTIA_DETALLE FOREIGN KEY (ID_DETALLE_VENTA) REFERENCES DETALLES_VENTA (ID_DETALLE_VENTA) ON DELETE CASCADE,
    -- Busca garantias por su fecha de inicio, util para reportes por periodo.
    INDEX IX_GARANTIA_INICIO (FECHA_INICIO),
    -- Busca garantias por su fecha de vencimiento, util para revisar cuales vencen pronto
    -- o ya vencieron.
    INDEX IX_GARANTIA_FIN (FECHA_FIN),
    -- Busca garantias por estado (ACTIVA, VENCIDA o CANCELADA), asi se filtran rapidamente
    -- las que estan vigentes.
    INDEX IX_GARANTIA_ESTADO (ESTADO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

-- (19/11/2026) ACA VIVIA una SEGUNDA definicion de SP_REGISTRAR_GARANTIA con 2
-- parametros. Estaba MUERTA: la seccion 4 de este mismo modulo la redefine con
-- 3 (P_ID_EMPLEADO) y ventas.cpp:1786 llama con 3. Se retiro la copia vieja.


DELIMITER //

DROP PROCEDURE IF EXISTS 26_SP_RECHAZAR_DEVOLUCION;

/*
26_SP_RECHAZAR_DEVOLUCION
Rechaza una devolucion que este en estado PENDIENTE.
Le agrega al motivo el motivo del rechazo; si ya fue procesada o no existe
corta con error y no cambia nada.
NOTA (Parte 5, 07/10/2026): opera sobre DEVOLUCIONES aunque vive en
el 26. El rechazo CONCATENA ' | RECHAZO: ...' al motivo original (no
lo pisa; P12: si el original es NULL se guarda solo el rechazo). Ser RECHAZADA libera la cuota (las RECHAZADAS no cuentan
en el tope del registro) y su fila SI se puede borrar
(TR_BLOQUEAR_BORRADO solo frena APROBADA/REEMBOLSADA). Es la
alternativa al paso 3 de 25_SP_PROCESAR_DEVOLUCION, que cambia el
estado sin anotar motivo.
*/
CREATE PROCEDURE 26_SP_RECHAZAR_DEVOLUCION(
    IN P_ID_DEVOLUCION INT,
    IN P_MOTIVO_RECHAZO VARCHAR(200)
)
proc_label: BEGIN
    DECLARE V_ESTADO_ACTUAL VARCHAR(20);

    -- 1. Validar que la devolución exista
    SELECT ESTADO INTO V_ESTADO_ACTUAL FROM DEVOLUCIONES WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;
    
    IF V_ESTADO_ACTUAL IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DEVOLUCIÓN NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que la devolución no esté ya procesada (solo se pueden rechazar las pendientes)
    IF V_ESTADO_ACTUAL <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN RECHAZAR DEVOLUCIONES EN ESTADO PENDIENTE.';
        LEAVE proc_label;
    END IF;

    -- 3. Aplicar el rechazo
    UPDATE DEVOLUCIONES 
    SET ESTADO = 'RECHAZADA',
        -- ANTES (P12): MOTIVO = CONCAT(MOTIVO, ' | RECHAZO: ', P_MOTIVO_RECHAZO)
        -- P12 (07/10/2026): si el motivo original es NULL no se pierde el rechazo.
        MOTIVO = CONCAT(IFNULL(CONCAT(MOTIVO, ' | '), ''), 'RECHAZO: ', P_MOTIVO_RECHAZO)
    WHERE ID_DEVOLUCION = P_ID_DEVOLUCION;
    
    -- 4. Confirmación
    SELECT 'EXITO: DEVOLUCIÓN RECHAZADA CORRECTAMENTE.' AS MENSAJE;
END//

DELIMITER ;
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_FECHAS_GARANTIA ;
/*
TR_VALIDAR_FECHAS_GARANTIA
No permite que una garantia empiece en una fecha del pasado.
Si eso pasa, le cambia el inicio a hoy antes de guardarla.
NOTA (Parte 5, 07/10/2026): a diferencia del resto de candados del
flujo (que cortan con SIGNAL), este NO da error: corrige en silencio
FECHA_INICIO a hoy. Un inicio pasado nunca llega grabado - vigilar
si se esperaba un error explicito.
*/
CREATE TRIGGER TR_VALIDAR_FECHAS_GARANTIA
BEFORE INSERT ON GARANTIAS
FOR EACH ROW
BEGIN
    IF NEW.FECHA_INICIO < CURRENT_DATE THEN
        SET NEW.FECHA_INICIO = CURRENT_DATE;
    END IF;
END //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 

/*
VISTA_DEVOLUCIONES_PENDIENTES
Muestra las devoluciones que aun estan en PENDIENTE.
Trae la venta, el producto, la cantidad y el motivo, listas para revisar.
*/
-- Vista VISTA_DEVOLUCIONES_PENDIENTES movida a 26- DEVOLUCIONES.sql.


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


-- ================================================================
-- RECLAMOS_GARANTIAS (ex modulo 27)
-- ================================================================

/*
TABLA RECLAMOS_GARANTIAS
Guarda los reclamos que se hacen sobre una garantia: que paso, cuando y
en que estado esta el reclamo (pendiente, aprobado, rechazado o cerrado).
*/
CREATE TABLE RECLAMOS_GARANTIAS (
    ID_RECLAMO_GARAN INT NOT NULL AUTO_INCREMENT,
    ID_GARANTIA INT NOT NULL,
    FECHA_RECLAMO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DESCRIPCION VARCHAR(255) NOT NULL,
    ESTADO ENUM(
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO',
        'CERRADO'
    ) NOT NULL DEFAULT 'PENDIENTE',
    -- (19/11/2026) Antes vivian como ALTER en la seccion "Flujo de garantias".
    -- Se trajeron al CREATE para que la tabla se lea completa en un solo lugar.
    ID_EMPLEADO INT NULL,
    ID_EMPLEADO_CIERRE INT NULL,
    FECHA_CIERRE TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (ID_RECLAMO_GARAN),
    CONSTRAINT FK_RECLAMO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO),
    CONSTRAINT FK_RECLAMO_EMPLEADO_CIERRE FOREIGN KEY (ID_EMPLEADO_CIERRE) REFERENCES EMPLEADOS (ID_EMPLEADO),
    CONSTRAINT FK_RECLAMO_GARANTIA FOREIGN KEY (ID_GARANTIA) REFERENCES GARANTIAS (ID_GARANTIA) ON DELETE CASCADE,
    -- Ordena los reclamos por fecha, asi los mas recientes salen primero sin recorrer toda
    -- la tabla.
    INDEX IX_RECLAMO_GARANTIA_FECHA (FECHA_RECLAMO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   
-- (19/11/2026) ACA VIVIA una SEGUNDA definicion de 27_SP_REGISTRAR_RECLAMO_GARANTIA
-- con 2 parametros. Estaba MUERTA: la seccion 4 la redefine con 3 y
-- ventas.cpp:1853 llama con 3. Se retiro la copia vieja.

-- (11/10/2026) Sin USE hardcodeado: la BD la gobierna --database del import.
-- USE BALBU_TECH;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP TRIGGER IF EXISTS TR_FINALIZAR_RECLAMO_APROBADO;
/*
TR_FINALIZAR_RECLAMO_APROBADO
Cuando un reclamo pasa de PENDIENTE a APROBADO, cancela la garantia.
Sirve para marcar que la garantia ya se uso con ese reclamo.
*/
CREATE TRIGGER TR_FINALIZAR_RECLAMO_APROBADO
AFTER UPDATE ON RECLAMOS_GARANTIAS
FOR EACH ROW
BEGIN
    -- Si el reclamo es aprobado, podemos marcar la garantía como cerrada/finalizada
    IF (NEW.ESTADO = 'APROBADO' AND OLD.ESTADO = 'PENDIENTE') THEN
        UPDATE GARANTIAS 
        SET ESTADO = 'CANCELADA' -- O el estado que prefieras para indicar "garantía agotada"
        WHERE ID_GARANTIA = NEW.ID_GARANTIA;
    END IF;
END//
DELIMITER ;

-- (15/11/2026) 27_SP_FINALIZAR_RECLAMO_TOTAL SE ELIMINO.
-- El cierre del reclamo va por SP_FINALIZAR_RECLAMO(id_asignacion), que cierra
-- la asignacion Y el reclamo juntos y escribe la auditoria. Convivir con los dos
-- dejaba reclamos CERRADO con asignaciones EN_PROCESO colgando.
-- Se deja el DROP para limpiar las bases que todavia lo tengan.
DELIMITER //
DROP PROCEDURE IF EXISTS 27_SP_FINALIZAR_RECLAMO_TOTAL //

DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[TRIGGER]------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_VALIDAR_CAMBIO_RECLAMO ;
/*
TR_VALIDAR_CAMBIO_RECLAMO (09/10/2026)
El reclamo no cambia de garantia y los estados finales no se tocan: CERRADO y
RECHAZADO son terminales y nadie reabre a PENDIENTE. Deja pasar el flujo
normal (PENDIENTE/APROBADO -> CERRADO de los SPs de finalizacion).
*/
CREATE TRIGGER TR_VALIDAR_CAMBIO_RECLAMO
BEFORE UPDATE ON RECLAMOS_GARANTIAS
FOR EACH ROW
BEGIN
    IF NEW.ID_GARANTIA <> OLD.ID_GARANTIA THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL RECLAMO NO CAMBIA DE GARANTIA.';
    END IF;

    IF OLD.ESTADO IN ('CERRADO', 'RECHAZADO') AND NEW.ESTADO <> OLD.ESTADO THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL RECLAMO YA ESTA CERRADO O RECHAZADO; ESE ESTADO NO CAMBIA.';
    END IF;

    IF NEW.ESTADO = 'PENDIENTE' AND OLD.ESTADO <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL RECLAMO NO SE REABRE.';
    END IF;
END //
DELIMITER ;

-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
/*
TR_BLOQUEAR_BORRADO_RECLAMO
Un reclamo procesado (APROBADO, RECHAZADO o CERRADO) no se borra ni con DELETE
directo: ya movio garantia/stock o cerro el caso. Solo un PENDIENTE (error de
carga) se puede eliminar. Espejo de TR_BLOQUEAR_BORRADO_DEVOLUCION.
*/
DELIMITER //
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_RECLAMO ;
CREATE TRIGGER TR_BLOQUEAR_BORRADO_RECLAMO
BEFORE DELETE ON RECLAMOS_GARANTIAS
FOR EACH ROW
BEGIN
    IF OLD.ESTADO <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: EL RECLAMO PROCESADO NO SE BORRA; USE LOS SPS DE CIERRE.';
    END IF;
END //
DELIMITER ;


-- ================================================================
-- ASIGNACIONES_RECLAMOS (ex modulo 34)
-- ================================================================

/*
TABLA ASIGNACIONES_RECLAMOS
Guarda a que tecnico se le asigno cada reclamo de garantia, con su
prioridad, estado de la asignacion y fechas. Un reclamo puede tener
varias asignaciones a lo largo del tiempo.
*/
CREATE TABLE ASIGNACIONES_RECLAMOS (
    ID_ASIGNACION INT NOT NULL AUTO_INCREMENT,
    ID_RECLAMO_GARAN INT NOT NULL,
    ID_EMPLEADO INT NOT NULL,
    FECHA_ASIGNACION TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FECHA_FINALIZACION DATETIME NULL,
    PRIORIDAD ENUM('BAJA', 'MEDIA', 'ALTA', 'URGENTE') DEFAULT 'MEDIA',
    ESTADO_ASIGNACION ENUM('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'CANCELADO') DEFAULT 'PENDIENTE',
    OBSERVACIONES VARCHAR(255),
    PRIMARY KEY (ID_ASIGNACION),
    -- (19/11/2026) Antes vivia como ALTER debajo del CREATE.
    CONSTRAINT CHK_FECHAS_VALIDAS CHECK (FECHA_FINALIZACION >= FECHA_ASIGNACION),
    -- Índices para búsqueda rápida
    INDEX IDX_EMPLEADO_FECHA (ID_EMPLEADO, FECHA_ASIGNACION),
    -- Relaciones
    CONSTRAINT FK_ASIGNACION_RECLAMO FOREIGN KEY (ID_RECLAMO_GARAN) REFERENCES RECLAMOS_GARANTIAS (ID_RECLAMO_GARAN) ON DELETE CASCADE,
    CONSTRAINT FK_ASIGNACION_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- (19/11/2026) El CHECK CHK_FECHAS_VALIDAS que antes se agregaba aca ahora se
-- declara dentro del CREATE TABLE de arriba.


/*
INDICE IDX_ASIGNACIONES_EMPLEADO_FECHA -- ELIMINADO (15/11/2026)
Era un indice DUPLICADO: el CREATE TABLE de arriba ya declara
INDEX IDX_EMPLEADO_FECHA (ID_EMPLEADO, FECHA_ASIGNACION), y este creaba un
segundo indice identico sobre las mismas dos columnas (defecto heredado del
ex modulo 34). Se deja el DROP para limpiar las bases que ya lo tenian.
*/
DROP INDEX IF EXISTS IDX_ASIGNACIONES_EMPLEADO_FECHA ON ASIGNACIONES_RECLAMOS;


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

---COMIENZA AISGNACION
DELIMITER //

DROP PROCEDURE IF EXISTS SP_ASIGNAR_TECNICO_RECLAMO; 

/*
SP_ASIGNAR_TECNICO_RECLAMO
Asigna un tecnico a un reclamo que este PENDIENTE.
Revisa que el reclamo exista y no este ya tomado, crea la asignacion en
EN_PROCESO y deja el reclamo en PENDIENTE (su enum no admite EN_PROCESO;
el avance vive en ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION).
*/
CREATE PROCEDURE SP_ASIGNAR_TECNICO_RECLAMO(
    IN P_ID_RECLAMO INT,
    IN P_ID_EMPLEADO INT,
    IN P_PRIORIDAD ENUM('BAJA', 'MEDIA', 'ALTA', 'URGENTE'),
    IN P_OBSERVACIONES VARCHAR(255)
)
proc_label: BEGIN
    DECLARE V_ESTADO_RECLAMO VARCHAR(20);

    -- 1. Validar que el reclamo exista y esté pendiente
    SELECT ESTADO INTO V_ESTADO_RECLAMO 
    FROM RECLAMOS_GARANTIAS 
    WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO;

    IF V_ESTADO_RECLAMO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: RECLAMO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_RECLAMO <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: SOLO SE PUEDEN ASIGNAR TÉCNICOS A RECLAMOS PENDIENTES.';
        LEAVE proc_label;
    END IF;

    -- 1b (09/10/2026). El tecnico debe existir (mensaje amable en vez del FK 1452).
    IF NOT EXISTS (SELECT 1 FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL EMPLEADO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 1c (09/10/2026). Sin doble asignacion en curso para el mismo reclamo.
    IF EXISTS (SELECT 1 FROM ASIGNACIONES_RECLAMOS
                WHERE ID_RECLAMO_GARAN = P_ID_RECLAMO
                  AND ESTADO_ASIGNACION IN ('PENDIENTE', 'EN_PROCESO')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL RECLAMO YA TIENE UNA ASIGNACION EN CURSO.';
        LEAVE proc_label;
    END IF;

    -- 2. Insertar la asignación con la nueva estructura
    INSERT INTO ASIGNACIONES_RECLAMOS (
        ID_RECLAMO_GARAN, 
        ID_EMPLEADO, 
        PRIORIDAD, 
        ESTADO_ASIGNACION, 
        OBSERVACIONES
    )
    VALUES (
        P_ID_RECLAMO, 
        P_ID_EMPLEADO, 
        P_PRIORIDAD, 
        'EN_PROCESO', 
        P_OBSERVACIONES
    );
    
    -- 3. El reclamo sigue PENDIENTE (su ENUM no admite EN_PROCESO; antes este
    -- UPDATE ponia 'EN_PROCESO' y fallaba con ERROR 1265. El avance del trabajo
    -- vive en ASIGNACIONES_RECLAMOS.ESTADO_ASIGNACION = 'EN_PROCESO').
    
    SELECT 'EXITO: TÉCNICO ASIGNADO CORRECTAMENTE.' AS MENSAJE;
END//

DELIMITER ;

---FINALIZAR 

DELIMITER //

DROP PROCEDURE IF EXISTS SP_FINALIZAR_RECLAMO;

/*
SP_FINALIZAR_RECLAMO
Cierra la asignacion y el reclamo al mismo tiempo.
Marca la asignacion como COMPLETADO con su fecha final, agrega la nota
final y deja el reclamo en CERRADO.
*/
CREATE PROCEDURE SP_FINALIZAR_RECLAMO(
    IN P_ID_ASIGNACION INT,
    IN P_OBSERVACIONES_FINALES VARCHAR(255)
)
proc_label: BEGIN
    -- BLINDAJE (09/10/2026, patron fase I): 2 UPDATEs atados a la misma suerte.
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_ESTADO_ASIG VARCHAR(20);
    -- (15/11/2026) Para la auditoria que se muda con el cierre (S5).
    DECLARE V_ID_RECLAMO INT;
    DECLARE V_ESTADO_ANT VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    -- 0. La asignacion debe existir y seguir en curso (antes un id malo
    -- dejaba 0 filas tocadas y mentia EXITO).
    SELECT ESTADO_ASIGNACION INTO V_ESTADO_ASIG
      FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    IF V_ESTADO_ASIG IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ASIGNACION NO ENCONTRADA.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO_ASIG = 'COMPLETADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA ASIGNACION YA FUE FINALIZADA.';
        LEAVE proc_label;
    END IF;

    -- 1. Actualizamos la asignación
    -- (15/11/2026) Si la nota viene vacia no se toca OBSERVACIONES; y si venia
    -- NULL, el CONCAT de antes la dejaba en NULL y borraba lo que hubiera.
    UPDATE ASIGNACIONES_RECLAMOS
    SET ESTADO_ASIGNACION = 'COMPLETADO',
        FECHA_FINALIZACION = NOW(),
        OBSERVACIONES = IF(IFNULL(P_OBSERVACIONES_FINALES, '') = '',
                           OBSERVACIONES,
                           CONCAT(IFNULL(OBSERVACIONES, ''), ' | Nota final: ', P_OBSERVACIONES_FINALES))
    WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    -- 2. Actualizamos el reclamo general a 'CERRADO'
    SELECT ID_RECLAMO_GARAN INTO V_ID_RECLAMO
      FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    SELECT ESTADO INTO V_ESTADO_ANT
      FROM RECLAMOS_GARANTIAS WHERE ID_RECLAMO_GARAN = V_ID_RECLAMO;

    UPDATE RECLAMOS_GARANTIAS
    SET ESTADO = 'CERRADO',
        ID_EMPLEADO_CIERRE = (SELECT ID_EMPLEADO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL),
        FECHA_CIERRE = CURRENT_TIMESTAMP
    WHERE ID_RECLAMO_GARAN = V_ID_RECLAMO;

    -- 3. Auditoria (S5): esta escritura vivia en 27_SP_FINALIZAR_RECLAMO_TOTAL y
    --    se muda con el cierre. Sin esto, cerrar por asignacion no dejaba rastro.
    --    El actor sale de la sesion: USER() es el usuario de MySQL (balbu_app
    --    para todos los roles) y no dice quien cerro.
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES ('RECLAMOS_GARANTIAS', V_ID_RECLAMO, 'UPDATE',
            IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER()),
            V_ESTADO_ANT, 'CERRADO');

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT 'EXITO: RECLAMO FINALIZADO Y CERRADO.' AS MENSAJE;
END//

DELIMITER ;


-- ================================================================
-- DETALLE_REPARACIONES (ex modulo 35)
-- ================================================================

/*
TABLA DETALLE_REPARACIONES
Guarda cada paso o avance de una reparacion: que se hizo, el repuesto
usado, el costo, el tiempo empleado, el estado y la evidencia.
Es la bitacora del trabajo tecnico sobre una asignacion.
*/
CREATE TABLE DETALLE_REPARACIONES (
    ID_REPARACION INT NOT NULL AUTO_INCREMENT,
    ID_ASIGNACION INT NOT NULL,
    ID_USUARIO INT NOT NULL,
    FECHA_ACCION TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ACCION_REALIZADA VARCHAR(255) NOT NULL,
    -- (15/11/2026) El repuesto es un producto del catalogo y consume stock real.
    -- NULL = la reparacion no uso repuesto (solo mano de obra).
    ID_PRODUCTO INT NULL,
    CANTIDAD_REPUESTO INT NULL,
    COSTO_REPUESTO DECIMAL(10,2) DEFAULT 0.00,
    TIEMPO_EMPLEADO_MIN INT DEFAULT 0,
    ESTADO_AVANCE ENUM('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'CANCELADO') NOT NULL DEFAULT 'EN_PROCESO',
    RUTA_EVIDENCIA VARCHAR(255) NULL,
    PRIMARY KEY (ID_REPARACION),
    -- (19/11/2026) Antes vivia como ALTER debajo del CREATE.
    CONSTRAINT CHK_CANTIDAD_REPUESTO CHECK (CANTIDAD_REPUESTO IS NULL OR CANTIDAD_REPUESTO > 0),
    CONSTRAINT FK_REPARACION_ASIGNACION FOREIGN KEY (ID_ASIGNACION) REFERENCES ASIGNACIONES_RECLAMOS (ID_ASIGNACION) ON DELETE CASCADE,
    CONSTRAINT FK_DETALLE_USUARIO FOREIGN KEY (ID_USUARIO) REFERENCES USUARIOS(ID_USUARIO),
    CONSTRAINT FK_REPARACION_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- (19/11/2026) Limpieza que NO se puede expresar en un CREATE TABLE: saca de las
-- bases viejas una columna que ya no existe en la definicion de arriba. En una
-- base nueva es un no-op (IF EXISTS).
-- REPUESTO_UTILIZADO era un campo de texto libre que hacia las veces de repuesto
-- y dejaba consumir stock "escribiendo el nombre" en vez de eligiendo el
-- producto, que es justo lo que este cambio vino a cerrar. Lo que haya que
-- narrar va en ACCION_REALIZADA, que ya existia para eso.
ALTER TABLE DETALLE_REPARACIONES
DROP COLUMN IF EXISTS REPUESTO_UTILIZADO;


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   


DELIMITER //

DROP PROCEDURE IF EXISTS SP_REGISTRAR_AVANCE_REPARACION;

/*
SP_REGISTRAR_AVANCE_REPARACION
Anota un avance de la reparacion con su repuesto, costo y evidencia.
Revisa que la asignacion exista y que no este completada; si esta bien,
guarda el registro del avance.
*/
CREATE PROCEDURE SP_REGISTRAR_AVANCE_REPARACION(
    IN P_ID_ASIGNACION INT,
    IN P_ID_USUARIO INT,
    IN P_ACCION VARCHAR(255),
    IN P_ID_PRODUCTO INT,
    IN P_CANTIDAD_REPUESTO INT,
    IN P_COSTO DECIMAL(10,2),
    IN P_TIEMPO INT,
    IN P_ESTADO VARCHAR(20),
    IN P_RUTA VARCHAR(255)
)
proc_label: BEGIN
    DECLARE V_ESTADO_ASIGNACION VARCHAR(20);
    DECLARE V_ID_EMPLEADO INT;
    DECLARE V_COSTO_UNITARIO DECIMAL(10,2);
    DECLARE V_COSTO DECIMAL(10,2) DEFAULT 0.00;
    -- (15/11/2026) Para la autorizacion: quien llama solo puede tocar SUS
    -- asignaciones, salvo que sea gerencia.
    DECLARE V_USUARIO_SESION VARCHAR(50);
    DECLARE V_EMPLEADO_SESION INT;
    DECLARE V_EMPLEADO_ASIGNADO INT;
    -- (15/11/2026) El avance y el consumo del repuesto van atados: si no alcanza
    -- el stock, no queda la fila del avance escrita a medias.
    DECLARE V_PROPIA_TRANSACCION INT DEFAULT 0;
    DECLARE V_SAVEPOINT INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- SAVEPOINT: si quien llama YA tiene una transaccion abierta (un test, o
        -- un flujo futuro), deshacemos SOLO lo de este SP en vez de dejarle el
        -- INSERT del avance escrito dentro de su transaccion. Sin esto, un fallo
        -- por stock insuficiente dejaba la fila del avance viva.
        IF V_SAVEPOINT = 1 THEN
            ROLLBACK TO SAVEPOINT SP_AVANCE;
        END IF;
        IF V_PROPIA_TRANSACCION = 1 THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        START TRANSACTION;
        SET V_PROPIA_TRANSACCION = 1;
    END IF;

    SAVEPOINT SP_AVANCE;
    SET V_SAVEPOINT = 1;

    -- 1. Validación de existencia de asignación
    IF NOT EXISTS (SELECT 1 FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ASIGNACIÓN NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validación de estado de reparación
    SELECT ESTADO_ASIGNACION INTO V_ESTADO_ASIGNACION 
    FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION;

    IF V_ESTADO_ASIGNACION = 'COMPLETADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: REPARACIÓN YA FINALIZADA.';
        LEAVE proc_label;
    END IF;

    -- 2a (15/11/2026) AUTORIZACION. Un tecnico solo registra avances de SUS
    -- asignaciones: sin esto, cualquier portador de GARANTIAS_AVANZAR podia
    -- consumir el stock de un repuesto en la reparacion de OTRO tecnico, y la
    -- bitacora quedaba a nombre del asignado, no del que lo hizo. Gerencia
    -- (GARANTIAS_ASIGNAR) si puede actuar en nombre de otro.
    -- Fail-closed a proposito: si falta la sesion o la asignacion, los IFNULL
    -- usan centinelas distintos (-1 y -2) para que NO puedan coincidir.
    SET V_USUARIO_SESION   = (SELECT USUARIO     FROM USUARIOS WHERE ID_USUARIO = FN_USUARIO_SESION());
    SET V_EMPLEADO_SESION  = (SELECT ID_EMPLEADO FROM USUARIOS WHERE ID_USUARIO = FN_USUARIO_SESION());
    SET V_EMPLEADO_ASIGNADO = (SELECT ID_EMPLEADO FROM ASIGNACIONES_RECLAMOS
                                WHERE ID_ASIGNACION = P_ID_ASIGNACION);

    IF IFNULL(FN_TIENE_PERMISO(V_USUARIO_SESION, 'GARANTIAS_ASIGNAR'), 0) = 0
       AND IFNULL(V_EMPLEADO_ASIGNADO, -1) <> IFNULL(V_EMPLEADO_SESION, -2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESA ASIGNACION NO ES TUYA.';
        LEAVE proc_label;
    END IF;

    -- 2b (09/10/2026). El avance usa los 4 estados del ENUM de la tabla
    -- (mensaje amable en vez del 1265 de la columna).
    IF P_ESTADO NOT IN ('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'CANCELADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTADO DE AVANCE DESCONOCIDO.';
        LEAVE proc_label;
    END IF;

    -- 2c (15/11/2026) El repuesto es un producto del catalogo marcado ES_REPUESTO.
    -- NULL = reparacion sin repuesto (solo mano de obra).
    IF P_ID_PRODUCTO IS NOT NULL THEN
        IF IFNULL(P_CANTIDAD_REPUESTO, 0) <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CANTIDAD DE REPUESTO DEBE SER MAYOR A CERO.';
            LEAVE proc_label;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO AND ES_REPUESTO = 1) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL REPUESTO NO EXISTE EN EL CATALOGO O NO ESTA MARCADO COMO REPUESTO.';
            LEAVE proc_label;
        END IF;

        -- 2d El costo se congela aca desde P_COMPRA; no lo dicta el cliente.
        SELECT P_COMPRA INTO V_COSTO_UNITARIO FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO;
        SET V_COSTO = IFNULL(V_COSTO_UNITARIO, 0) * P_CANTIDAD_REPUESTO;
    ELSE
        SET V_COSTO = IFNULL(P_COSTO, 0);
    END IF;

    -- 3. Inserción del avance
    INSERT INTO DETALLE_REPARACIONES (
        ID_ASIGNACION, ID_USUARIO, ACCION_REALIZADA, ID_PRODUCTO, CANTIDAD_REPUESTO,
        COSTO_REPUESTO, TIEMPO_EMPLEADO_MIN, ESTADO_AVANCE, RUTA_EVIDENCIA
    )
    VALUES (
        P_ID_ASIGNACION, P_ID_USUARIO, P_ACCION, P_ID_PRODUCTO, P_CANTIDAD_REPUESTO,
        V_COSTO, P_TIEMPO, P_ESTADO, P_RUTA
    );

    -- 4. Consumo de stock: la MISMA regla que el ajuste manual (SP_MOVER_STOCK),
    --    no una copia. El empleado de la bitacora es el de la asignacion, para
    --    que diga quien reparo y no quien tiene la sesion abierta.
    IF P_ID_PRODUCTO IS NOT NULL THEN
        SELECT ID_EMPLEADO INTO V_ID_EMPLEADO
        FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = P_ID_ASIGNACION;

        CALL SP_MOVER_STOCK(
            P_ID_PRODUCTO,
            V_ID_EMPLEADO,
            'SALIDA',
            P_CANTIDAD_REPUESTO,
            CONCAT('Repuesto para reparacion #', P_ID_ASIGNACION)
        );
    END IF;

    IF V_PROPIA_TRANSACCION = 1 THEN
        COMMIT;
    END IF;

    SELECT 'EXITO: AVANCE Y EVIDENCIA REGISTRADOS.' AS MENSAJE;
END//

DELIMITER ;


-- ================================================================
-- FLUJO DE GARANTIAS (ex modulo 63)
-- ================================================================

/*
SECCION FLUJO DE GARANTIAS (ex modulo 63) - AUTOR, FECHAS Y CONSULTAS

Ojo: SP_REGISTRAR_GARANTIA y 27_SP_REGISTRAR_RECLAMO_GARANTIA quedan definidos
UNA sola vez, en esta seccion. Las copias viejas de 2 parametros que vivian mas
arriba en este mismo archivo se retiraron el 19/11/2026 (eran codigo muerto: el
DROP de aca las borraba y ventas.cpp llama con 3). De
27_SP_FINALIZAR_RECLAMO_TOTAL solo queda el DROP: el cierre va por
SP_FINALIZAR_RECLAMO (15/11/2026).

Problema
--------
La garantia se abria con el paraguas GESTIONAR_VENTAS, no guardaba quien la
registro ni cuando, y el reclamo solo miraba ESTADO = 'ACTIVA': una garantia
con FECHA_FIN en el pasado seguia siendo reclamable. El estado VENCIDA estaba
en el ENUM pero ningun objeto lo escribia. La UI pedia IDs de detalle, de
garantia y de reclamo a ciegas.

Solucion
--------
  1. PRODUCTOS.DIAS_GARANTIA: dias de garantia por producto. NULL o 0 = sin
     garantia automatica.
  2. GARANTIAS: ID_EMPLEADO (quien registro) y FECHA_REGISTRO.
  3. RECLAMOS_GARANTIAS: ID_EMPLEADO, ID_EMPLEADO_CIERRE y FECHA_CIERRE.
  4. SP_REGISTRAR_GARANTIA recibe el empleado y valida los dias.
  5. 27_SP_REGISTRAR_RECLAMO_GARANTIA valida las fechas, no solo el estado.
  6. 27_SP_FINALIZAR_RECLAMO_TOTAL solo cerraba PENDIENTE o APROBADO y guardaba
     quien cerro y cuando. **Se elimino el 15/11/2026**: el cierre va por
     SP_FINALIZAR_RECLAMO, que cierra la asignacion y el reclamo juntos.
  7. SP_MARCAR_GARANTIAS_VENCIDAS escribe VENCIDA; SP_CONSULTAR_GARANTIAS lo
     invoca antes de listar para no depender de un scheduler.
  8. SP_CONSULTAR_GARANTIAS, SP_CONSULTAR_RECLAMOS y
     SP_LINEAS_VENTA_CON_GARANTIA para que la UI liste en vez de pedir IDs.
  9. TR_REGISTRAR_GARANTIA_VENTA crea la garantia sola cuando la venta pasa a
     REALIZADA, con los dias del producto y el empleado de la venta.

Orden de despliegue
-------------------
  1. Backup de la base.
  2. Correr el modulo 25 completo: esta seccion va incluida.
  3. Desplegar el binario nuevo.
El binario viejo llama a los SPs con la firma anterior y falla al registrar o
finalizar. Como GARANTIAS y RECLAMOS_GARANTIAS estan vacias y el flujo no se
usa, la ventana es de minutos y no se pierden datos.

Idempotente: los SPs y el trigger se recrean con DROP IF EXISTS + CREATE, y las
columnas y FKs de esta seccion viven dentro del CREATE TABLE de cada tabla (ver
"Consolidacion de los ALTER", abajo).
*/

-- ---------------------------------------------------------------------------
-- Consolidacion de los ALTER (19/11/2026)
-- ---------------------------------------------------------------------------
-- Esta seccion traia 5 ALTER TABLE + 5 bloques PREPARE para agregar columnas y
-- FKs sobre tablas ya creadas. Ya no: cada columna y cada restriccion quedo
-- declarada en su CREATE TABLE, que es el unico lugar donde hay que mirar.
--
--   PRODUCTOS.DIAS_GARANTIA + CK_PRODUCTO_DIAS_GARANTIA
--       -> modulos/9- PRODUCTOS.sql, CREATE TABLE PRODUCTOS.
--   GARANTIAS.ID_EMPLEADO + FECHA_REGISTRO + FK_GARANTIA_EMPLEADO
--       -> CREATE TABLE GARANTIAS, arriba en este archivo.
--   RECLAMOS_GARANTIAS.ID_EMPLEADO + ID_EMPLEADO_CIERRE + FECHA_CIERRE
--      + FK_RECLAMO_EMPLEADO + FK_RECLAMO_EMPLEADO_CIERRE
--       -> CREATE TABLE RECLAMOS_GARANTIAS, arriba en este archivo.
--
-- Consecuencia, dicha de frente: el import es para base FRESCA (ver
-- README-DOCKER.md). Una base vieja que no tenga esas columnas ya no se pone al
-- dia corriendo este modulo: hay que recrearla o migrarla a mano.

-- ---------------------------------------------------------------------------
-- 4. Registrar garantia (manual, respaldo de ventas viejas)
-- ---------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS SP_REGISTRAR_GARANTIA //
CREATE PROCEDURE SP_REGISTRAR_GARANTIA(
    IN P_ID_DETALLE_VENTA INT,
    IN P_DIAS_VALIDEZ INT,
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_EXISTE INT;
    DECLARE V_NUEVO_ID INT;

    IF NOT EXISTS (SELECT 1 FROM DETALLES_VENTA WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL DETALLE DE VENTA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_DIAS_VALIDEZ IS NULL OR P_DIAS_VALIDEZ < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LOS DIAS DE GARANTIA DEBEN SER MAYORES QUE CERO.';
        LEAVE proc_label;
    END IF;

    SELECT COUNT(*) INTO V_EXISTE FROM GARANTIAS WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA;
    IF V_EXISTE > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.';
        LEAVE proc_label;
    END IF;

    INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN, ID_EMPLEADO)
    VALUES (
        P_ID_DETALLE_VENTA,
        CURRENT_DATE,
        DATE_ADD(CURRENT_DATE, INTERVAL P_DIAS_VALIDEZ DAY),
        P_ID_EMPLEADO
    );

    SET V_NUEVO_ID = LAST_INSERT_ID();

    SELECT 'EXITO' AS ESTATUS,
           'GARANTÍA REGISTRADA CON ÉXITO.' AS MENSAJE,
           V_NUEVO_ID AS ID_GENERADO;
END //

-- ---------------------------------------------------------------------------
-- 5. Reclamar: valida fechas, no solo el estado
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS 27_SP_REGISTRAR_RECLAMO_GARANTIA //
CREATE PROCEDURE 27_SP_REGISTRAR_RECLAMO_GARANTIA(
    IN P_ID_GARANTIA INT,
    IN P_DESCRIPCION VARCHAR(255),
    IN P_ID_EMPLEADO INT
)
proc_label: BEGIN
    DECLARE V_ESTADO ENUM('ACTIVA', 'VENCIDA', 'CANCELADA');
    DECLARE V_INICIO DATE;
    DECLARE V_FIN DATE;

    SELECT ESTADO, FECHA_INICIO, FECHA_FIN
      INTO V_ESTADO, V_INICIO, V_FIN
      FROM GARANTIAS
     WHERE ID_GARANTIA = P_ID_GARANTIA;

    IF V_ESTADO IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF V_ESTADO <> 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTA GARANTÍA NO ESTÁ ACTIVA Y NO SE PUEDE RECLAMAR.';
        LEAVE proc_label;
    END IF;

    IF CURRENT_DATE < V_INICIO OR CURRENT_DATE > V_FIN THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA GARANTÍA ESTÁ VENCIDA POR FECHA Y NO SE PUEDE RECLAMAR.';
        LEAVE proc_label;
    END IF;

    IF P_DESCRIPCION IS NULL OR TRIM(P_DESCRIPCION) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA DESCRIPCIÓN DEL DAÑO ES OBLIGATORIA.';
        LEAVE proc_label;
    END IF;

    INSERT INTO RECLAMOS_GARANTIAS (ID_GARANTIA, DESCRIPCION, ID_EMPLEADO)
    VALUES (P_ID_GARANTIA, P_DESCRIPCION, P_ID_EMPLEADO);

    SELECT 'EXITO: RECLAMO REGISTRADO CORRECTAMENTE.' AS MENSAJE;
END //

-- ---------------------------------------------------------------------------
-- 6. Finalizar: SE ELIMINO (15/11/2026)
-- ---------------------------------------------------------------------------
-- El cierre va por SP_FINALIZAR_RECLAMO(id_asignacion): cierra la asignacion Y
-- el reclamo juntos. Antes eran dos caminos y se podia terminar con el reclamo
-- CERRADO y la asignacion EN_PROCESO colgando. El DROP limpia las bases viejas.
DROP PROCEDURE IF EXISTS 27_SP_FINALIZAR_RECLAMO_TOTAL //

-- ---------------------------------------------------------------------------
-- 7. Marcar vencidas: el estado que nunca se escribia
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS SP_MARCAR_GARANTIAS_VENCIDAS //
CREATE PROCEDURE SP_MARCAR_GARANTIAS_VENCIDAS()
BEGIN
    UPDATE GARANTIAS
       SET ESTADO = 'VENCIDA'
     WHERE ESTADO = 'ACTIVA'
       AND FECHA_FIN < CURRENT_DATE;
END //

-- ---------------------------------------------------------------------------
-- 8. Consulta de garantias (filtro libre + solo reclamables)
-- ---------------------------------------------------------------------------
-- Antes de listar pone al dia el estado: una ACTIVA con FECHA_FIN pasada pasa
-- a VENCIDA. Asi la app no depende de un scheduler ni muestra estados falsos.
DROP PROCEDURE IF EXISTS SP_CONSULTAR_GARANTIAS //
CREATE PROCEDURE SP_CONSULTAR_GARANTIAS(
    IN P_FILTRO VARCHAR(100),
    IN P_SOLO_RECLAMABLES INT
)
BEGIN
    CALL SP_MARCAR_GARANTIAS_VENCIDAS();

    SELECT G.ID_GARANTIA,
           V.ID_VENTA,
           IFNULL(C.NOMBRE, '') AS CLIENTE,
           P.NOMBRE AS PRODUCTO,
           G.FECHA_INICIO,
           G.FECHA_FIN,
           G.ESTADO,
           IFNULL(E.NOMBRE, '') AS REGISTRO,
           G.FECHA_REGISTRO
      FROM GARANTIAS G
      JOIN DETALLES_VENTA DV ON DV.ID_DETALLE_VENTA = G.ID_DETALLE_VENTA
      JOIN VENTAS V ON V.ID_VENTA = DV.ID_VENTA
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
      LEFT JOIN CLIENTES C ON C.ID_CLIENTE = V.ID_CLIENTE
      LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = G.ID_EMPLEADO
     WHERE (P_SOLO_RECLAMABLES = 0
            OR (G.ESTADO = 'ACTIVA' AND CURRENT_DATE BETWEEN G.FECHA_INICIO AND G.FECHA_FIN))
       AND (P_FILTRO IS NULL OR P_FILTRO = ''
            OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR P.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR CAST(V.ID_VENTA AS CHAR) = P_FILTRO
            OR G.ESTADO = P_FILTRO)
     ORDER BY G.FECHA_FIN, G.ID_GARANTIA
     LIMIT 100;
END //

-- ---------------------------------------------------------------------------
-- 9. Consulta de reclamos (por garantia + solo abiertos)
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 9c. Tecnicos disponibles para asignar (15/11/2026)
-- ---------------------------------------------------------------------------
-- "Tecnico" es un empleado ACTIVO cuyo usuario tiene el rol TECNICO: entra a la
-- app con su propio usuario, y sin usuario no podria registrar el avance. Trae
-- EN_CURSO para repartir la carga (es lo que el indice de la tabla anticipaba).
DROP PROCEDURE IF EXISTS SP_TECNICOS_DISPONIBLES //
CREATE PROCEDURE SP_TECNICOS_DISPONIBLES()
BEGIN
    SELECT E.ID_EMPLEADO,
           E.NOMBRE,
           IFNULL(E.CARGO, '') AS CARGO,
           IFNULL((SELECT COUNT(*)
                     FROM ASIGNACIONES_RECLAMOS A
                    WHERE A.ID_EMPLEADO = E.ID_EMPLEADO
                      AND A.ESTADO_ASIGNACION IN ('PENDIENTE', 'EN_PROCESO')), 0) AS EN_CURSO
      FROM EMPLEADOS E
      JOIN USUARIOS U ON U.ID_EMPLEADO = E.ID_EMPLEADO
      JOIN ROLES R ON R.ID_ROL = U.ID_ROL
     WHERE R.NOMBRE_ROL = 'TECNICO'
       AND E.ESTADO = 'ACTIVO'
       AND U.ESTADO = 'ACTIVO'
     ORDER BY EN_CURSO ASC, E.NOMBRE ASC;
END //

-- ---------------------------------------------------------------------------
-- 9b. Asignaciones: la lista que alimenta las pantallas (15/11/2026)
-- ---------------------------------------------------------------------------
-- Sin esto no hay pantalla posible: no existia NINGUN SP que listara
-- ASIGNACIONES_RECLAMOS. Las seis referencias que habia en el modulo eran
-- validaciones IF EXISTS o busquedas de una fila por ID. "Registrar avance" y
-- "Finalizar reclamo" no tenian de donde elegir: el usuario tenia que saberse
-- el ID_ASIGNACION de memoria.
-- P_ID_EMPLEADO = 0 trae todas; P_SOLO_EN_CURSO = 1 deja fuera las cerradas.
DROP PROCEDURE IF EXISTS SP_CONSULTAR_ASIGNACIONES //
CREATE PROCEDURE SP_CONSULTAR_ASIGNACIONES(
    IN P_SOLO_EN_CURSO INT,
    IN P_ID_EMPLEADO INT
)
BEGIN
    SELECT A.ID_ASIGNACION,
           A.ID_RECLAMO_GARAN,
           R.ID_GARANTIA,
           IFNULL(P.NOMBRE, '') AS PRODUCTO,
           IFNULL(E.NOMBRE, '') AS TECNICO,
           A.PRIORIDAD,
           A.ESTADO_ASIGNACION,
           A.FECHA_ASIGNACION,
           IFNULL(A.OBSERVACIONES, '') AS OBSERVACIONES,
           IFNULL(R.DESCRIPCION, '') AS RECLAMO
      FROM ASIGNACIONES_RECLAMOS A
      JOIN RECLAMOS_GARANTIAS R ON R.ID_RECLAMO_GARAN = A.ID_RECLAMO_GARAN
      LEFT JOIN GARANTIAS G ON G.ID_GARANTIA = R.ID_GARANTIA
      LEFT JOIN DETALLES_VENTA DV ON DV.ID_DETALLE_VENTA = G.ID_DETALLE_VENTA
      LEFT JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
      LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = A.ID_EMPLEADO
     WHERE (P_SOLO_EN_CURSO = 0 OR A.ESTADO_ASIGNACION IN ('PENDIENTE', 'EN_PROCESO'))
       AND (P_ID_EMPLEADO = 0 OR A.ID_EMPLEADO = P_ID_EMPLEADO)
     ORDER BY FIELD(A.PRIORIDAD, 'URGENTE', 'ALTA', 'MEDIA', 'BAJA'),
              A.FECHA_ASIGNACION ASC,
              A.ID_ASIGNACION ASC
     LIMIT 100;
END //

DROP PROCEDURE IF EXISTS SP_CONSULTAR_RECLAMOS //
CREATE PROCEDURE SP_CONSULTAR_RECLAMOS(
    IN P_ID_GARANTIA INT,
    IN P_SOLO_ABIERTOS INT
)
BEGIN
    SELECT R.ID_RECLAMO_GARAN,
           R.ID_GARANTIA,
           R.FECHA_RECLAMO,
           R.DESCRIPCION,
           R.ESTADO,
           IFNULL(E.NOMBRE, '') AS REGISTRO,
           IFNULL(EC.NOMBRE, '') AS CIERRE,
           R.FECHA_CIERRE
      FROM RECLAMOS_GARANTIAS R
      LEFT JOIN EMPLEADOS E ON E.ID_EMPLEADO = R.ID_EMPLEADO
      LEFT JOIN EMPLEADOS EC ON EC.ID_EMPLEADO = R.ID_EMPLEADO_CIERRE
     WHERE (P_ID_GARANTIA = 0 OR R.ID_GARANTIA = P_ID_GARANTIA)
       AND (P_SOLO_ABIERTOS = 0 OR R.ESTADO IN ('PENDIENTE', 'APROBADO'))
     ORDER BY R.FECHA_RECLAMO DESC, R.ID_RECLAMO_GARAN DESC
     LIMIT 100;
END //

-- ---------------------------------------------------------------------------
-- 10. Lineas de una venta para elegir el detalle a garantizar
-- ---------------------------------------------------------------------------
-- SP_VENTA_LINEAS no devuelve el ID del detalle porque alimenta la factura.
-- Este SP es solo para el alta manual: trae el ID, los dias sugeridos del
-- producto y si la linea ya tiene garantia.
DROP PROCEDURE IF EXISTS SP_LINEAS_VENTA_CON_GARANTIA //
CREATE PROCEDURE SP_LINEAS_VENTA_CON_GARANTIA(IN P_ID_VENTA INT)
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_LINEAS_VENTA_CON_GARANTIA');
    SELECT DV.ID_DETALLE_VENTA,
           P.NOMBRE AS PRODUCTO,
           DV.CANTIDAD,
           IFNULL(P.DIAS_GARANTIA, 0) AS DIAS_SUGERIDOS,
           IF(G.ID_GARANTIA IS NULL, 'NO', 'SI') AS TIENE_GARANTIA
      FROM DETALLES_VENTA DV
      JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
      LEFT JOIN GARANTIAS G ON G.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
     WHERE DV.ID_VENTA = P_ID_VENTA
     ORDER BY DV.ID_DETALLE_VENTA;
END //

-- ---------------------------------------------------------------------------
-- 10.b Ventas que todavia admiten garantia (07/11/2026)
-- ---------------------------------------------------------------------------
-- El alta manual pedia el ID de la venta a ciegas. Este SP lista las ventas
-- REALIZADA con al menos una linea sin garantia, que son las unicas sobre las
-- que tiene sentido registrar una: las que ya la tienen (por el trigger
-- automatico o por un alta anterior) no aparecen. LIMIT 50 para que la
-- pantalla no escupa historico completo.
--
-- Permiso: GARANTIAS_REGISTRAR, el mismo que abre "Registrar garantia"; todo
-- rol que llega a esa pantalla lo tiene.
DROP PROCEDURE IF EXISTS SP_VENTAS_GARANTIZABLES //
CREATE PROCEDURE SP_VENTAS_GARANTIZABLES()
BEGIN
    CALL SP_EXIGIR_PERMISO('SP_VENTAS_GARANTIZABLES');
    SELECT V.ID_VENTA,
           V.FECHA,
           C.NOMBRE AS CLIENTE,
           V.ESTADO,
           COUNT(*) AS LINEAS_SIN_GARANTIA
      FROM DETALLES_VENTA DV
      JOIN VENTAS V   ON V.ID_VENTA = DV.ID_VENTA
      JOIN CLIENTES C ON C.ID_CLIENTE = V.ID_CLIENTE
      LEFT JOIN GARANTIAS G ON G.ID_DETALLE_VENTA = DV.ID_DETALLE_VENTA
     WHERE G.ID_GARANTIA IS NULL
       AND V.ESTADO = 'REALIZADA'
     GROUP BY V.ID_VENTA, V.FECHA, C.NOMBRE, V.ESTADO
     ORDER BY V.ID_VENTA DESC
     LIMIT 50;
END //

DELIMITER ;

-- ---------------------------------------------------------------------------
-- 11. Registro automatico al confirmar la venta
-- ---------------------------------------------------------------------------
-- Va despues de TR_CAMBIO_ESTADO_VENTA para que el historial de la venta ya
-- este escrito cuando se crean las garantias. Solo actua en el pase a
-- REALIZADA y solo con productos que tengan DIAS_GARANTIA > 0. El ON DUPLICATE
-- KEY evita duplicar si el detalle ya tiene garantia (UQ_GARANTIA_DETALLE).
DELIMITER //

DROP TRIGGER IF EXISTS TR_REGISTRAR_GARANTIA_VENTA //
CREATE TRIGGER TR_REGISTRAR_GARANTIA_VENTA
AFTER UPDATE ON VENTAS
FOR EACH ROW
FOLLOWS TR_CAMBIO_ESTADO_VENTA
BEGIN
    IF NEW.ESTADO = 'REALIZADA' AND OLD.ESTADO <> 'REALIZADA' THEN
        INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN, ID_EMPLEADO)
        SELECT DV.ID_DETALLE_VENTA,
               CURRENT_DATE,
               DATE_ADD(CURRENT_DATE, INTERVAL P.DIAS_GARANTIA DAY),
               NEW.ID_EMPLEADO
          FROM DETALLES_VENTA DV
          JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO
         WHERE DV.ID_VENTA = NEW.ID_VENTA
           AND P.DIAS_GARANTIA IS NOT NULL
           AND P.DIAS_GARANTIA > 0
        ON DUPLICATE KEY UPDATE GARANTIAS.ID_GARANTIA = GARANTIAS.ID_GARANTIA;
    END IF;
END //

DELIMITER ;

SELECT 'MODULO 25 - FLUJO DE GARANTIAS APLICADO: AUTOR, FECHAS Y CONSULTAS.' AS RESULTADO;
