/*
MODULO 61 - AUDITORIA CON ACTOR

Problema
--------
Quedaban tres huecos de actor despues del 56 y el 57:

  1. TR_AUDIT_CLIENTES_INSERT, TR_AUDIT_CLIENTES_UPDATE y
     TR_AUDITORIA_PRODUCTOS_UPDATE guardaban CURRENT_USER()/USER(), que
     es el usuario de MySQL (siempre balbu_app), no quien hizo el cambio.
  2. HISTORIAL_ESTADOS_PRODUCTO.ID_EMPLEADO era NOT NULL y el trigger
     TR_LOG_CAMBIO_ESTADO_PRODUCTO caia a IFNULL(@ID_EMPLEADO_ACTUAL, 1):
     todo cambio de estado quedaba atribuido al empleado 1.
  3. La app no dejaba @ID_EMPLEADO_ACTUAL en la conexion al cambiar el
     estado de un producto.

Solucion
--------
  - Los tres triggers usan @ID_USUARIO_ACTUAL, que la app deja en la
    conexion al iniciar sesion; si no esta o el usuario ya no existe,
    caen a USER() igual que el modulo 57.
  - HISTORIAL_ESTADOS_PRODUCTO.ID_EMPLEADO pasa a NULL: si no hay
    empleado en la conexion se guarda NULL, que es "no se sabe quien",
    en vez del empleado 1.
  - TR_LOG_CAMBIO_ESTADO_PRODUCTO usa @ID_EMPLEADO_ACTUAL sin fallback.

Es idempotente. No toca datos. El ALTER es seguro con filas existentes:
solo relaja la columna, no reescribe valores.
*/

DELIMITER //

-- 1. CLIENTES: INSERT
DROP TRIGGER IF EXISTS TR_AUDIT_CLIENTES_INSERT //
CREATE TRIGGER TR_AUDIT_CLIENTES_INSERT
AFTER INSERT ON CLIENTES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_NUEVO)
    VALUES ('CLIENTES', NEW.ID_CLIENTE, 'INSERT',
            IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER()),
            CONCAT('Nombre: ', NEW.NOMBRE, ', Email: ', NEW.EMAIL));
END //

-- 2. CLIENTES: UPDATE
DROP TRIGGER IF EXISTS TR_AUDIT_CLIENTES_UPDATE //
CREATE TRIGGER TR_AUDIT_CLIENTES_UPDATE
AFTER UPDATE ON CLIENTES
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_SISTEMA (TABLA_AFECTADA, ID_REGISTRO_AFECTADO, ACCION, USUARIO_SISTEMA, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES ('CLIENTES', OLD.ID_CLIENTE, 'UPDATE',
            IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER()),
            CONCAT('Nombre: ', OLD.NOMBRE, ', Email: ', OLD.EMAIL),
            CONCAT('Nombre: ', NEW.NOMBRE, ', Email: ', NEW.EMAIL));
END //

-- 3. PRODUCTOS: UPDATE (precio)
-- Se recrea antes que el historial de estado para que FOLLOWS encuentre
-- el trigger lider ya creado.
DROP TRIGGER IF EXISTS TR_AUDITORIA_PRODUCTOS_UPDATE //
CREATE TRIGGER TR_AUDITORIA_PRODUCTOS_UPDATE
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
BEGIN
    IF OLD.PRECIO <> NEW.PRECIO THEN
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
            IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER()),
            CONCAT('Precio venta anterior: ', OLD.PRECIO),
            CONCAT('Precio venta nuevo: ', NEW.PRECIO)
        );
    END IF;
END //

DELIMITER ;

-- 4. HISTORIAL_ESTADOS_PRODUCTO: el actor puede no estar
-- Idempotente: repetir el MODIFY deja la columna igual.
ALTER TABLE HISTORIAL_ESTADOS_PRODUCTO
    MODIFY COLUMN ID_EMPLEADO INT NULL;

DELIMITER //

-- 5. HISTORIAL DE ESTADO: sin fallback al empleado 1
DROP TRIGGER IF EXISTS TR_LOG_CAMBIO_ESTADO_PRODUCTO //
CREATE TRIGGER TR_LOG_CAMBIO_ESTADO_PRODUCTO
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE
BEGIN
    IF OLD.ESTADO <> NEW.ESTADO THEN
        INSERT INTO HISTORIAL_ESTADOS_PRODUCTO (
            ID_PRODUCTO,
            ID_EMPLEADO,
            ESTADO,
            ESTADO_ANTERIOR,
            MOTIVO_CAMBIO
        )
        VALUES (
            NEW.ID_PRODUCTO,
            @ID_EMPLEADO_ACTUAL,
            NEW.ESTADO,
            OLD.ESTADO,
            IFNULL(@MOTIVO_CAMBIO, 'Cambio de estado automatico')
        );
    END IF;
END //

DELIMITER ;
