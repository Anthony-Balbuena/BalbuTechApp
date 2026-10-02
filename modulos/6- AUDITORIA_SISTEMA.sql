/*
TABLA AUDITORIA_SISTEMA
Bitacora que guarda todo lo que pasa en las tablas del sistema: que tabla
fue, que registro cambio, que accion se hizo, quien la hizo y con que
valores antes y despues. Nada se borra solo; es el registro de control de
quien toca los datos.
*/
CREATE TABLE AUDITORIA_SISTEMA (
    ID_AUDITORIA INT NOT NULL AUTO_INCREMENT,
    TABLA_AFECTADA VARCHAR(50) NOT NULL,
    ID_REGISTRO_AFECTADO INT NOT NULL,
    ACCION ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    USUARIO_SISTEMA VARCHAR(50) NOT NULL, -- El usuario de la DB o del App
    FECHA_HORA TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    VALOR_ANTERIOR TEXT, -- Datos antes del cambio (en formato JSON o String)
    VALOR_NUEVO TEXT, -- Datos después del cambio
    PRIMARY KEY (ID_AUDITORIA)
) ENGINE = InnoDB;

-- Para buscar qué pasó en una fecha específica
/*
INDICE IX_AUDITORIA_FECHA
Ordena y filtra la bitacora por fecha y hora, asi los reportes y las
busquedas por periodo salen rapidos sin recorrer toda la tabla.
*/
CREATE INDEX IX_AUDITORIA_FECHA ON AUDITORIA_SISTEMA (FECHA_HORA);

-- Para rastrear todo lo que se le ha hecho a una tabla (ej: 'VENTAS')
/*
INDICE IX_AUDITORIA_TABLA
Permite rastrear rapido todo lo que le paso a una tabla en concreto
(por ejemplo VENTAS) sin revisar la bitacora completa.
*/
CREATE INDEX IX_AUDITORIA_TABLA ON AUDITORIA_SISTEMA (TABLA_AFECTADA);

----------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}------------------------------------------
----------------------------------------------------------------------------------------------------

--LISTAR
/*
6_SP_LISTAR_AUDITORIA_GENERAL
Lista la bitacora del sistema para la pantalla de auditoria.
Se puede filtrar por tabla y por un rango de fechas; si los filtros vienen
vacios trae todo, ordenado de mas reciente a mas viejo.
*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_AUDITORIA_GENERAL //
CREATE PROCEDURE 6_SP_LISTAR_AUDITORIA_GENERAL(
    IN P_TABLA VARCHAR(50),
    IN P_FECHA_INICIO DATE,
    IN P_FECHA_FIN DATE
)
BEGIN
    SELECT * FROM AUDITORIA_SISTEMA
    WHERE (P_TABLA IS NULL OR P_TABLA = '' OR TABLA_AFECTADA = P_TABLA)
      AND (DATE(FECHA_HORA) BETWEEN IFNULL(P_FECHA_INICIO, '1900-01-01') AND IFNULL(P_FECHA_FIN, CURDATE()))
    ORDER BY FECHA_HORA DESC;
END ;
DELIMITER ;

--CONSULTAR
/*
6_SP_CONSULTAR_HISTORIAL_REGISTRO
Muestra todo el historial de un registro en concreto de la bitacora.
Recibe la tabla y el ID del registro y devuelve sus cambios (accion,
usuario, fecha y valores) del mas reciente al mas antiguo.
*/

DELIMITER //

DROP PROCEDURE IF EXISTS SP_CONSULTAR_HISTORIAL_REGISTRO //
CREATE PROCEDURE 6_SP_CONSULTAR_HISTORIAL_REGISTRO(
    IN P_TABLA VARCHAR(50),
    IN P_ID_REGISTRO INT
)
BEGIN
    SELECT ID_AUDITORIA, ACCION, USUARIO_SISTEMA, FECHA_HORA, VALOR_ANTERIOR, VALOR_NUEVO
    FROM AUDITORIA_SISTEMA
    WHERE TABLA_AFECTADA = P_TABLA 
      AND ID_REGISTRO_AFECTADO = P_ID_REGISTRO
    ORDER BY FECHA_HORA DESC;
END ;
DELIMITER ;

--LIMPIAR MANTEMINIENTO 
/*
6_SP_LIMPIAR_AUDITORIA
Limpieza de mantenimiento: borra de la bitacora los registros con mas
antiguedad de los dias indicados y responde con un mensaje diciendo
cuantos registros se eliminaron.
*/

DELIMITER //

DROP PROCEDURE IF EXISTS SP_LIMPIAR_AUDITORIA //
CREATE PROCEDURE 6_SP_LIMPIAR_AUDITORIA(
    IN P_DIAS_ANTIGUEDAD INT
)
BEGIN
    DELETE FROM AUDITORIA_SISTEMA 
    WHERE FECHA_HORA < DATE_SUB(NOW(), INTERVAL P_DIAS_ANTIGUEDAD DAY);
    
    SELECT CONCAT('LIMPIEZA COMPLETADA: SE HAN ELIMINADO REGISTROS CON MÁS DE ', P_DIAS_ANTIGUEDAD, ' DÍAS.') AS MENSAJE;
END ;

DELIMITER ;



----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

DELIMITER //

-- TRIGGER PARA AUDITAR INSERT
/*
TR_AUDIT_PROVEEDORES_INSERT
Se dispara solo al insertar un proveedor y deja el registro en la bitacora
con los datos nuevos y el usuario que lo hizo. No hace falta llamarlo a
mano: trabaja en automatico.
*/
DROP TRIGGER IF EXISTS TR_AUDIT_PROVEEDORES_INSERT //
CREATE TRIGGER TR_AUDIT_PROVEEDORES_INSERT
AFTER INSERT ON PROVEEDORES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_NUEVO)
    VALUES ('PROVEEDORES', NEW.ID_PROVEEDOR, 'INSERT', USER(), 
            CONCAT('Nombre: ', NEW.NOMBRE, ', Tel: ', NEW.TELEFONO, ', Email: ', NEW.EMAIL));
END ;

-- TRIGGER PARA AUDITAR UPDATE
/*
TR_AUDIT_PROVEEDORES_UPDATE
Se dispara al actualizar un proveedor y guarda en la bitacora los valores
antes y despues del cambio junto con el usuario que lo hizo. Trabaja en
automatico, sin tener que llamarlo.
*/
DROP TRIGGER IF EXISTS TR_AUDIT_PROVEEDORES_UPDATE //
CREATE TRIGGER TR_AUDIT_PROVEEDORES_UPDATE
AFTER UPDATE ON PROVEEDORES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES ('PROVEEDORES', OLD.ID_PROVEEDOR, 'UPDATE', USER(), 
            CONCAT('Nombre: ', OLD.NOMBRE, ', Tel: ', OLD.TELEFONO, ', Email: ', OLD.EMAIL),
            CONCAT('Nombre: ', NEW.NOMBRE, ', Tel: ', NEW.TELEFONO, ', Email: ', NEW.EMAIL));
END ;

DELIMITER ;




DELIMITER //



/*
TR_AUDITORIA_PRODUCTOS_UPDATE
Se dispara al actualizar un producto, pero solo graba en la bitacora cuando
cambia el PRECIO_VENTA, anotando el precio anterior y el nuevo. Es el
control para vigilar los cambios de precio.
*/
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_PRODUCTOS_UPDATE ;
CREATE TRIGGER TR_AUDITORIA_PRODUCTOS_UPDATE
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
BEGIN
    -- Auditamos el PRECIO_VENTA
    IF OLD.PRECIO_VENTA <> NEW.PRECIO_VENTA THEN
        INSERT INTO AUDITORIA_SISTEMA (
            TABLA_AFECTADA, 
            ID_REGISTRO_AFECTADO, 
            ACCION, 
            USUARIO_SISTEMA, 
            VALOR_ANTERIOR, 
            VALOR_NUEVO
        ) VALUES (
            'PRODUCTOS', 
            NEW.ID_PRODUCTO, 
            'UPDATE', 
            USER(),
            CONCAT('Precio venta anterior: ', OLD.PRECIO_VENTA), 
            CONCAT('Precio venta nuevo: ', NEW.PRECIO_VENTA)
        );
    END IF;
END ;
DELIMITER ;