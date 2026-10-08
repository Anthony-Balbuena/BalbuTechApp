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
    PRIMARY KEY (ID_GARANTIA),
    CONSTRAINT UQ_GARANTIA_DETALLE UNIQUE (ID_DETALLE_VENTA),
    CONSTRAINT CK_GARANTIA_FECHAS CHECK (FECHA_FIN > FECHA_INICIO),
    CONSTRAINT FK_GARANTIA_DETALLE FOREIGN KEY (ID_DETALLE_VENTA) REFERENCES DETALLES_VENTA (ID_DETALLE_VENTA) ON DELETE CASCADE
) ENGINE = InnoDB;

/*
INDICE IX_GARANTIA_INICIO
Busca garantias por su fecha de inicio, util para reportes por periodo.
*/
CREATE INDEX IX_GARANTIA_INICIO ON GARANTIAS (FECHA_INICIO);

/*
INDICE IX_GARANTIA_FIN
Busca garantias por su fecha de vencimiento, util para revisar cuales
vencen pronto o ya vencieron.
*/
CREATE INDEX IX_GARANTIA_FIN ON GARANTIAS (FECHA_FIN);


/*
INDICE IX_GARANTIA_ESTADO
Busca garantias por estado (ACTIVA, VENCIDA o CANCELADA),
asi se filtran rapidamente las que estan vigentes.
*/
CREATE INDEX IX_GARANTIA_ESTADO ON GARANTIAS (ESTADO);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_GARANTIA;
/*
SP_REGISTRAR_GARANTIA
Crea la garantia de un producto vendido contando desde hoy.
Revisa que ese producto no tenga ya una garantia; si la tiene corta con
error, y si no, guarda las fechas y devuelve el ID nuevo.
NOTA (Parte 5, 07/10/2026): el UNIQUE UQ_GARANTIA_DETALLE es el
respaldo del paso 1 - si dos sesiones registran a la vez, el conteo
pasa a ambas pero el UNIQUE corta a la segunda. Fechas: CHECK
CK_GARANTIA_FECHAS (FIN > INICIO) y TR_VALIDAR_FECHAS_GARANTIA
autocorrige un inicio en el pasado (silencioso, no senala).
*/
CREATE PROCEDURE SP_REGISTRAR_GARANTIA(
    IN P_ID_DETALLE_VENTA INT,
    IN P_DIAS_VALIDEZ INT
)
proc_label: BEGIN
    DECLARE V_EXISTE INT;
    DECLARE V_NUEVO_ID INT;

    -- 1. Verificar si ya existe una garantía
    SELECT COUNT(*) INTO V_EXISTE FROM GARANTIAS WHERE ID_DETALLE_VENTA = P_ID_DETALLE_VENTA;
    
    IF V_EXISTE > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE PRODUCTO YA TIENE UNA GARANTÍA ASIGNADA.';
        LEAVE proc_label;
    END IF;

    -- 2. Insertar el registro
    INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN)
    VALUES (
        P_ID_DETALLE_VENTA, 
        CURRENT_DATE, 
        DATE_ADD(CURRENT_DATE, INTERVAL P_DIAS_VALIDEZ DAY)
        
    );

    -- 3. Capturar el ID recién generado
    SET V_NUEVO_ID = LAST_INSERT_ID();

    -- 4. Devolver mensaje y el ID para tu interfaz C#
    SELECT 
        'EXITO' AS ESTATUS,
        'GARANTÍA REGISTRADA CON ÉXITO.' AS MENSAJE,
        V_NUEVO_ID AS ID_GENERADO;
END //
DELIMITER ;




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