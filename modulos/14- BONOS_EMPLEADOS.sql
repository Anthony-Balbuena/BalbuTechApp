/*
DESCRIPCION DEL MODULO DE BONOS DE EMPLEADOS

Este modulo administra los bonos, horas extra y bonificaciones otorgadas a los empleados en la base de datos BALBU_TECH.

TABLA BONOS_EMPLEADOS
- ID_BONO: identificador unico, clave primaria y autoincremental.
- ID_EMPLEADO: identificador del empleado asociado, clave foranea obligatoria.
- FECHA: fecha en que se otorga o corresponde el bono, de tipo obligatorio.
- TIPO_BONO: tipo de incentivo, restringido a los valores DOBLE_SUELDO, HORAS_EXTRA o BONIFICACION.
- MONTO: cantidad monetaria del bono, de tipo obligatorio y mayor a cero.
- DESCRIPCION: detalle o motivo informativo del bono.
- FECHA_REGISTRO: fecha y hora de registro en el sistema, generada automaticamente.

RESTRICCIONES
- La clave primaria identifica cada bono de forma unica.
- La clave foranea FK_BONO_EMPLEADO asegura que el bono pertenezca a un empleado existente.
- El campo MONTO incluye una validacion para evitar cantidades menores o iguales a cero.

La tabla utiliza el motor InnoDB.
*/
CREATE TABLE BONOS_EMPLEADOS (
    ID_BONO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    FECHA DATE NOT NULL,
    TIPO_BONO ENUM(
        'DOBLE_SUELDO',
        'HORAS_EXTRA',
        'BONIFICACION'
    ) NOT NULL,
    MONTO DECIMAL(10, 2) NOT NULL CHECK (MONTO > 0),
    DESCRIPCION VARCHAR(200),
    FECHA_REGISTRO TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ESTADO ENUM('PENDIENTE', 'PAGADO', 'ANULADO') NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (ID_BONO),
    CONSTRAINT FK_BONO_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;
 

SELECT * FROM BONOS_EMPLEADOS;

ALTER TABLE BONOS_EMPLEADOS 
MODIFY COLUMN ESTADO ENUM('PENDIENTE', 'PAGADO', 'ANULADO') NOT NULL DEFAULT 'PENDIENTE';



--DESCRIPCION DE LOS INDICES DE LA TABLA BONOS_EMPLEADOS

--Este bloque describe los indices creados para que el sistema busque la informacion mas rapido en la tabla BONOS_EMPLEADOS de la base de datos BALBU_TECH.



--IX_BONO_EMPLEADO (ID_EMPLEADO): sirve para encontrar al instante todo el historial de bonos de un trabajador en especifico, sin tener que revisar todo el sistema paso a paso.
CREATE INDEX IX_BONO_EMPLEADO ON BONOS_EMPLEADOS (ID_EMPLEADO);

--IX_BONO_FECHA (FECHA): ayuda a que los reportes de contabilidad y los totales por mes o año salgan de forma inmediata.
CREATE INDEX IX_BONO_FECHA ON BONOS_EMPLEADOS (FECHA);

---IX_BONO_TIPO (TIPO_BONO): permite calcular con rapidez cuanto dinero se gasta en cada tipo de extra (como horas de mas o bonificaciones).

CREATE INDEX IX_BONO_TIPO ON BONOS_EMPLEADOS (TIPO_BONO);


CREATE INDEX IX_BONO_ESTADO ON BONOS_EMPLEADOS (ESTADO);

-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


/*
DESCRIPCION DEL PROCEDIMIENTO ALMACENADO: SP_REGISTRAR_BONO

1- Validar existencia del empleado:

Se declara una variable v_nombre_empleado de tipo VARCHAR(100) para almacenar el nombre del empleado.
Se utiliza una sentencia SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO; para obtener el nombre del empleado con el ID proporcionado.
Si v_nombre_empleado es NULL, significa que el empleado no se encuentra en la base de datos, por lo que se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO ENCONTRADO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el empleado no se encuentre.

2- Validar el monto del bono:

Se verifica si el monto P_MONTO es mayor a 100000. Si es así, se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el monto no sea válido.

3- Insertar el bono en la tabla BONOS_EMPLEADOS:

Se inserta un registro en la tabla BONOS_EMPLEADOS con los valores proporcionados (P_ID_EMPLEADO, P_FECHA, P_TIPO_BONO, P_MONTO, P_DESCRIPCION).
Se usa SELECT CONCAT('EXITO: BONO DE $', P_MONTO, ' REGISTRADO A: ', v_nombre_empleado, ' (ID: ', P_ID_EMPLEADO, ').') AS MENSAJE; para devolver un mensaje de éxito que incluye el monto del bono, el nombre del empleado y su ID.

Este procedimiento asegura que se cumplan ciertas reglas antes de insertar un bono en la base de datos, evitando posibles errores o malas prácticas. Al finalizar, el procedimiento devuelve un mensaje de éxito que confirma el registro del bono.

*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_REGISTRAR_BONO ;
CREATE PROCEDURE SP_REGISTRAR_BONO(
    IN P_ID_EMPLEADO INT,
    IN P_FECHA DATE,
    IN P_TIPO_BONO VARCHAR(20),
    IN P_MONTO DECIMAL(10,2),
    IN P_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    DECLARE v_nombre_empleado VARCHAR(100);

    -- 1. Validar existencia y obtener el nombre al mismo tiempo
    SELECT NOMBRE INTO v_nombre_empleado FROM EMPLEADOS WHERE ID_EMPLEADO = P_ID_EMPLEADO;

    IF v_nombre_empleado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EMPLEADO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar monto
    IF P_MONTO > 100000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.';
        LEAVE proc_label;
    END IF;
 
    -- 3. Insertar
    INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
    VALUES (P_ID_EMPLEADO, P_FECHA, P_TIPO_BONO, P_MONTO, P_DESCRIPCION);

    -- 4. Mensaje con ID y Nombre para confirmación total
    SELECT CONCAT('EXITO: BONO DE $', P_MONTO, ' REGISTRADO A: ', v_nombre_empleado, ' (ID: ', P_ID_EMPLEADO, ').') AS MENSAJE;
END ;
DELIMITER ;




 /* ACTUALIZAR
   
1-- Validar si el bono existe:

Se declara una variable v_bono_existente de tipo INT para almacenar el número de registros que coinciden con el ID del bono.
Se utiliza una sentencia SELECT COUNT(*) INTO v_bono_existente FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO; para contar el número de registros que coinciden con el ID del bono.
Si v_bono_existente es 0, significa que el bono no existe, por lo que se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: BONO NO ENCONTRADO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono no se encuentre.

2- Validación de monto:

Se verifica si el nuevo monto P_NUEVO_MONTO es mayor a 100000. Si es así, se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL MONTO EXCEDE EL LÍMITE PERMITIDO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el monto no sea válido.

3- Actualización del bono en la base de datos:

Se actualiza el registro del bono en la tabla BONOS_EMPLEADOS con los nuevos valores P_NUEVO_MONTO y P_NUEVA_DESCRIPCION.
Se usa SELECT 'EXITO: BONO ACTUALIZADO CORRECTAMENTE.' AS MENSAJE; para devolver un mensaje de éxito que confirma que el bono se actualizó correctamente.

Este procedimiento asegura que se cumplan ciertas reglas antes de actualizar un bono en la base de datos, evitando posibles errores o malas prácticas. Al finalizar, el procedimiento devuelve un mensaje de éxito que confirma la actualización del bono.



*/
DELIMITER //
DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_BONO //
CREATE PROCEDURE SP_ACTUALIZAR_BONO(
    IN P_ID_BONO INT,
    IN P_NUEVO_MONTO DECIMAL(10,2),
    IN P_NUEVA_DESCRIPCION VARCHAR(200)
)
proc_label: BEGIN
    -- 1. Validar si el bono existe
    IF NOT EXISTS (SELECT 1 FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: BONO NO ENCONTRADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Aplicar actualización
    UPDATE BONOS_EMPLEADOS 
    SET MONTO = P_NUEVO_MONTO,
        DESCRIPCION = P_NUEVA_DESCRIPCION
    WHERE ID_BONO = P_ID_BONO;

    SELECT 'EXITO: BONO ACTUALIZADO CORRECTAMENTE.' AS MENSAJE;
END //
DELIMITER ;

/* PAGAR BONO 
1- Verificar si el bono existe y obtener su estado actual:

Se declara una variable v_estado_actual de tipo VARCHAR(20) para almacenar el estado actual del bono.
Se utiliza una sentencia SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO; para obtener el estado actual del bono con el ID proporcionado.
Si v_estado_actual es NULL, significa que el bono no existe, por lo que se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono no se encuentre.

2- Validación de estado actual del bono:

Se verifica si el estado actual del bono es PAGADO. Si es así, se lanza un mensaje de aviso SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA HABIA SIDO PAGADO ANTERIORMENTE.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono ya se haya pagado anteriormente.

3- Validación de estado actual del bono:

Se verifica si el estado actual del bono es ANULADO. Si es así, se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE PAGAR UN BONO QUE ESTA ANULADO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono esté anulado.

4- Actualización del estado del bono a PAGADO:

Se actualiza el registro del bono en la tabla BONOS_EMPLEADOS con el nuevo estado PAGADO utilizando UPDATE BONOS_EMPLEADOS SET ESTADO = 'PAGADO' WHERE ID_BONO = P_ID_BONO;.

5- Confirmación:

Se usa SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' HA SIDO MARCADO COMO PAGADO.') AS MENSAJE; para devolver un mensaje de éxito que confirma que el bono se pagó correctamente.

Este procedimiento asegura que se cumplan ciertas reglas antes de marcar un bono como pagado, evitando posibles errores o malas prácticas. Al finalizar, el procedimiento devuelve un mensaje de éxito que confirma que el bono se pagó correctamente.
*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_PAGAR_BONO;
CREATE PROCEDURE SP_PAGAR_BONO(
    IN P_ID_BONO INT
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. Verificar si el bono existe y ver su estado actual
    SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. Validar que no esté ya pagado o anulado
    IF v_estado_actual = 'PAGADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA HABIA SIDO PAGADO ANTERIORMENTE.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'ANULADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE PAGAR UN BONO QUE ESTA ANULADO.';
        LEAVE proc_label;
    END IF;

    -- 3. Actualizar el estado a PAGADO
    UPDATE BONOS_EMPLEADOS 
    SET ESTADO = 'PAGADO' 
    WHERE ID_BONO = P_ID_BONO;

    -- 4. Confirmación
    SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' HA SIDO MARCADO COMO PAGADO.') AS MENSAJE;
END;
DELIMITER ;

/* ANULAR BONO
1- Verificar existencia y estado:

Se declara una variable v_estado_actual de tipo VARCHAR(20) para almacenar el estado actual del bono.
Se utiliza una sentencia SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO; para obtener el estado del bono con el ID proporcionado.
Si v_estado_actual es NULL, significa que el bono no existe, por lo que se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono no se encuentre.
2- Validar el estado actual del bono:

Se verifica si el estado actual del bono es 'PAGADO'. Si es así, se lanza un error SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE ANULAR UN BONO QUE YA FUE PAGADO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono ya esté pagado.

3- Verificar si el bono ya está anulado:

Si el estado actual del bono es 'ANULADO', se lanza un mensaje de aviso SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA ESTABA ANULADO.';.
Se usa LEAVE proc_label para salir del procedimiento en caso de que el bono ya esté anulado.

4- Cambiar estado a ANULADO:

Se actualiza el estado del bono a 'ANULADO' utilizando la sentencia UPDATE BONOS_EMPLEADOS SET ESTADO = 'ANULADO' WHERE ID_BONO = P_ID_BONO;.

5- Confirmación:

Se usa SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' FUE ANULADO CORRECTAMENTE.') AS MENSAJE; para devolver un mensaje de éxito que confirma que el bono se anuló correctamente.
Este procedimiento asegura que se cumplan ciertas reglas antes de anular un bono, incluyendo la validación de si el bono existe, si el bono ya está pagado o anulado, y luego cambia el estado del bono a 'ANULADO'. Al finalizar, el procedimiento devuelve un mensaje de éxito que confirma la anulación del bono.

*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_ANULAR_BONO;
CREATE PROCEDURE SP_ANULAR_BONO(
    IN P_ID_BONO INT
)
proc_label: BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    -- 1. Verificar existencia y estado
    SELECT ESTADO INTO v_estado_actual FROM BONOS_EMPLEADOS WHERE ID_BONO = P_ID_BONO;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL BONO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'PAGADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDE ANULAR UN BONO QUE YA FUE PAGADO.';
        LEAVE proc_label;
    END IF;

    IF v_estado_actual = 'ANULADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AVISO: ESTE BONO YA ESTABA ANULADO.';
        LEAVE proc_label;
    END IF;

    -- 2. Cambiar estado a ANULADO
    UPDATE BONOS_EMPLEADOS 
    SET ESTADO = 'ANULADO' 
    WHERE ID_BONO = P_ID_BONO;

    -- 3. Confirmación
    SELECT CONCAT('EXITO: EL BONO CON ID ', P_ID_BONO, ' FUE ANULADO CORRECTAMENTE.') AS MENSAJE;
END;

DELIMITER ;


/*

1- Validación del parámetro P_ESTADO:

Se verifica si P_ESTADO es NULL o si tiene un valor válido ('PENDIENTE', 'PAGADO', o 'ANULADO'). Si no cumple con esto, se lanza un error con SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: P_ESTADO NO ES VALIDO. PUEDE SER "PENDIENTE", "PAGADO", O "ANULADO".';.
Selección de los bonos con los detalles relacionados:

2- Se seleccionan los campos relevantes de las tablas BONOS_EMPLEADOS (b) y EMPLEADOS (e).

Se utiliza una consulta SELECT que incluye las columnas requeridas (ID_BONO, ID_EMPLEADO, NOMBRE_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION, ESTADO, FECHA_REGISTRO).
Se realiza una INNER JOIN entre BONOS_EMPLEADOS y EMPLEADOS para obtener los nombres de los empleados.
Se incluye una cláusula WHERE que filtra los bonos según el estado P_ESTADO si no es NULL. Si P_ESTADO es NULL, se incluyen todos los bonos.
Se ordena el resultado por la fecha de creación del bono en orden descendente.

Este procedimiento asegura que se cumplan ciertas reglas antes de seleccionar los bonos, evitando posibles errores o malas prácticas. Al finalizar, el procedimiento devuelve los bonos filtrados según el estado especificado.

*/

DELIMITER //
DROP PROCEDURE IF EXISTS SP_LISTAR_BONOS;
CREATE PROCEDURE SP_LISTAR_BONOS(
    IN P_ESTADO VARCHAR(20) -- Puedes pasarle 'PENDIENTE', 'PAGADO', 'ANULADO', o dejarlo en NULL para ver todos
)
BEGIN
    SELECT 
        b.ID_BONO,
        b.ID_EMPLEADO,
        e.NOMBRE AS NOMBRE_EMPLEADO,
        b.FECHA,
        b.TIPO_BONO,
        b.MONTO,
        b.DESCRIPCION,
        b.ESTADO,
        b.FECHA_REGISTRO
    FROM BONOS_EMPLEADOS b
    INNER JOIN EMPLEADOS e ON b.ID_EMPLEADO = e.ID_EMPLEADO
    WHERE (P_ESTADO IS NULL OR P_ESTADO = '' OR b.ESTADO = P_ESTADO)
    ORDER BY b.FECHA DESC;
END;
DELIMITER ;





----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------
DELIMITER //
CREATE TRIGGER 14_TR_VALIDAR_FECHA_BONO
BEFORE INSERT ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN 
    -- No permitir bonos con fechas de más de 30 días atrás
    IF NEW.FECHA < DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: NO SE PUEDEN REGISTRAR BONOS DE HACE MÁS DE 30 DÍAS.';
    END IF;
END //
DELIMITER ;

----BONO POR VENTA 
DELIMITER //

DROP TRIGGER IF EXISTS TR_CALCULAR_BONO_VENTA ;

CREATE TRIGGER TR_CALCULAR_BONO_VENTA
AFTER INSERT ON DETALLES_VENTA
FOR EACH ROW
BEGIN
    DECLARE V_ID_EMPLEADO INT;
    
    -- Obtenemos el empleado de la tabla VENTAS
    SELECT ID_EMPLEADO INTO V_ID_EMPLEADO 
    FROM VENTAS 
    WHERE ID_VENTA = NEW.ID_VENTA;

    -- Usamos la tabla BONOS_EMPLEADOS según tu estructura
    INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, MONTO, MOTIVO, FECHA_BONO)
    VALUES (V_ID_EMPLEADO, (NEW.SUBTOTAL * 0.01), 'Comisión por venta', CURRENT_DATE);
END ;

DELIMITER ;



-----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


CREATE OR REPLACE VIEW VISTA_TOTAL_BONOS_POR_EMPLEADO AS
SELECT 
    E.ID_EMPLEADO,
    E.NOMBRE,
    SUM(B.MONTO) AS TOTAL_BONIFICADO,
    COUNT(B.ID_BONO) AS CANTIDAD_BONOS
FROM EMPLEADOS E
LEFT JOIN BONOS_EMPLEADOS B ON E.ID_EMPLEADO = B.ID_EMPLEADO
GROUP BY E.ID_EMPLEADO;