/*
TABLA HISTORIAL_LABORAL_EMPLEADO
Bitacora del historial laboral: cada vez que cambia el cargo, el salario
o el estado de un empleado, aqui quedan los valores antes y despues, el
tipo de cambio y la fecha. Si se borra el empleado se borra su historial.
*/
CREATE TABLE HISTORIAL_LABORAL_EMPLEADO (
    ID_HISTORIAL_EMPLEADO INT NOT NULL AUTO_INCREMENT,
    ID_EMPLEADO INT NOT NULL,
    -- (12/11/2026) VARCHAR(50) igual que EMPLEADOS.CARGO. Estaban en 30 y un
    -- cargo de 31 a 50 caracteres hacia fallar el INSERT del trigger, con el
    -- UPDATE del empleado entero. Ver la seccion HISTORIAL_CARGO_ANCHO al
    -- final de este archivo.
    CARGO_ANTERIOR VARCHAR(50) NOT NULL,
    CARGO_NUEVO VARCHAR(50) NOT NULL,
    SALARIO_ANTERIOR DECIMAL(10, 2) NOT NULL,
    SALARIO_NUEVO DECIMAL(10, 2) NOT NULL,
    TIPO_CAMBIO ENUM(
        'AUMENTO',
        'PROMOCION',
        'CAMBIO_PUESTO',
        -- (11/10/2026, re-aplicado: otro commit lo había pisado) Etiqueta
        -- honesta para bajas/reactivaciones (antes caían en CAMBIO_PUESTO).
        'CAMBIO_ESTADO',
        'AJUSTE'
    ) NOT NULL,
    ESTADO_ANTERIOR VARCHAR(20),
    ESTADO_NUEVO VARCHAR(20),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    OBSERVACION VARCHAR(280),
    PRIMARY KEY (ID_HISTORIAL_EMPLEADO),
    CONSTRAINT FK_HISTORIAL_EMPLEADO_REF FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO) ON DELETE CASCADE
) ENGINE = InnoDB;

-- Índices para búsquedas rápidas por empleado, fecha o tipo de cambio


/*
INDICE IX_HISTORIAL_EMPLEADO_ID
Encuentra al instante todo el historial de un empleado en especifico,
ordenado por lo que le ha pasado a lo largo del tiempo.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_ID ON HISTORIAL_LABORAL_EMPLEADO (ID_EMPLEADO);


/*
INDICE IX_HISTORIAL_EMPLEADO_FECHA
Ordena y filtra el historial por fecha de cambio, que es lo que usan los
reportes para ver que paso en un periodo.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_FECHA ON HISTORIAL_LABORAL_EMPLEADO (FECHA_CAMBIO);


/*
INDICE IX_HISTORIAL_EMPLEADO_TIPO
Agrupa y filtra el historial por tipo de cambio (AUMENTO, PROMOCION,
CAMBIO_PUESTO o AJUSTE) para los reportes.
*/
CREATE INDEX IX_HISTORIAL_EMPLEADO_TIPO ON HISTORIAL_LABORAL_EMPLEADO (TIPO_CAMBIO);

----------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}--------------------------------------------------
----------------------------------------------------------------------------------------------------

/*
TR_AUDITORIA_PERFIL_EMPLEADO
Vigila la tabla EMPLEADOS: cuando a alguien le cambia el salario, el
cargo o el estado, guarda sola una copia del antes y despues en el
historial. Trabaja en automatico.
*/


DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_PERFIL_EMPLEADO ;
CREATE TRIGGER TR_AUDITORIA_PERFIL_EMPLEADO
AFTER UPDATE ON EMPLEADOS
FOR EACH ROW
-- Orden fijo: despues de desactivar usuario post-liquidacion.
FOLLOWS TR_DESACTIVAR_USUARIO_POST_LIQUIDACION
BEGIN
    -- Comparamos si cambió el salario, el cargo o el estado del empleado
    IF OLD.SALARIO <> NEW.SALARIO OR 
       OLD.CARGO <> NEW.CARGO OR 
       OLD.ESTADO <> NEW.ESTADO THEN
       
        INSERT INTO HISTORIAL_LABORAL_EMPLEADO (
            ID_EMPLEADO, 
            CARGO_ANTERIOR, CARGO_NUEVO, 
            SALARIO_ANTERIOR, SALARIO_NUEVO, -- Corregido de SALARIO_NEW a SALARIO_NUEVO
            ESTADO_ANTERIOR, ESTADO_NUEVO,
            TIPO_CAMBIO, 
            OBSERVACION
        )
        VALUES (
            NEW.ID_EMPLEADO, 
            OLD.CARGO, NEW.CARGO, 
            OLD.SALARIO, NEW.SALARIO, 
            OLD.ESTADO, NEW.ESTADO,
            CASE 
                WHEN NEW.CARGO <> OLD.CARGO THEN 'PROMOCION'
                WHEN NEW.SALARIO > OLD.SALARIO THEN 'AUMENTO'
                -- (11/10/2026, re-aplicado) Solo-estado ya no miente CAMBIO_PUESTO.
                WHEN NEW.ESTADO <> OLD.ESTADO THEN 'CAMBIO_ESTADO'
                ELSE 'AJUSTE'
            END,
            CONCAT('Cambio automático: Cargo(', OLD.CARGO, '->', NEW.CARGO, ') Estado(', OLD.ESTADO, '->', NEW.ESTADO, ')')
        );
    END IF;
END //
DELIMITER ;


-- ================================================================
-- HISTORIAL_CARGO_ANCHO (ex modulo 68)
-- ================================================================

/*
SECCION HISTORIAL_CARGO_ANCHO (ex modulo 68)
Parche para bases viejas: el CREATE TABLE de arriba ya crea CARGO_ANTERIOR y
CARGO_NUEVO en VARCHAR(50), igual que EMPLEADOS.CARGO, pero una base creada
antes del 12/11/2026 los tenia en VARCHAR(30). Con 30, un cargo de 31 a 50
caracteres hacia fallar el INSERT del trigger TR_AUDITORIA_PERFIL_EMPLEADO con
error 1406 y, con el, se caia el UPDATE del empleado entero: no se podia
cambiar el cargo, ni dar un aumento, ni despedir a esa persona.
Este bloque consulta INFORMATION_SCHEMA y solo hace el ALTER si las columnas
todavia miden menos de 50. No crea objetos ni toca datos: ensanchar un VARCHAR
no recorta ni pierde nada, y las filas ya guardadas siguen siendo validas.
*/
-- ================================================================
-- BALBU_TECH - CARGO ANCHO EN EL HISTORIAL LABORAL
-- ================================================================
-- (12/11/2026) HISTORIAL_LABORAL_EMPLEADO.CARGO_ANTERIOR y CARGO_NUEVO eran
-- VARCHAR(30), pero EMPLEADOS.CARGO es VARCHAR(50). El trigger
-- TR_AUDITORIA_PERFIL_EMPLEADO (definido en el modulo 15 y recreado en el 55)
-- copia OLD.CARGO y NEW.CARGO ahi dentro, asi que un empleado con un cargo de
-- 31 a 50 caracteres quedaba bloqueado:
--
--   ERROR 1406 (22001): Data too long for column 'CARGO_ANTERIOR' at row 1
--
-- El que se caia era el UPDATE entero de EMPLEADOS, no solo la fila del
-- historial. En concreto no podia:
--   - cambiar de cargo (ni siquiera a un cargo corto: OLD.CARGO ya no entra),
--   - recibir un aumento (cambia SALARIO),
--   - ser despedido ni reactivado (cambia ESTADO).
-- Editar nombre, cedula, email o telefono si funcionaba: el trigger solo
-- escribe cuando cambia cargo, salario o estado.
--
-- La base viva ya estaba en VARCHAR(50) desde antes del 22/10/2026. Fue un
-- cambio hecho a mano que nunca quedo escrito en ningun modulo, asi que TEST y
-- cualquier instalacion nueva seguian en 30. Este modulo pone el cambio por
-- escrito y lo aplica donde falte.
--
-- ORDEN DE DESPLIEGUE:
--   1. Backup de la base.
--   2. Correr este modulo.
--   3. DB_NAME=BALBU_TECH_TEST bash db/test-historial-laboral.sh
--
-- Idempotente: consulta INFORMATION_SCHEMA.COLUMNS y solo hace el ALTER si la
-- columna todavia mide menos de 50. No toca datos: ensanchar un VARCHAR no
-- pierde ni recorta nada, y las filas ya guardadas siguen siendo validas.

-- 1. Filas sospechosas de truncado historico.
-- Con sql_mode estricto (el de esta instancia) no puede haber ninguna: el
-- 1406 abortaba el UPDATE antes de escribir. Si aparece algo, es que la base
-- corrio alguna vez sin modo estricto y hay que mirarlas a mano antes de
-- confiar en el historial.
SELECT COUNT(*) AS CARGOS_DE_LONGITUD_EXACTA_30
  FROM HISTORIAL_LABORAL_EMPLEADO
 WHERE CHAR_LENGTH(CARGO_ANTERIOR) = 30
    OR CHAR_LENGTH(CARGO_NUEVO) = 30;

-- 2. CARGO_ANTERIOR
SET @ancho_anterior := (SELECT CHARACTER_MAXIMUM_LENGTH
                          FROM INFORMATION_SCHEMA.COLUMNS
                         WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'HISTORIAL_LABORAL_EMPLEADO'
                           AND COLUMN_NAME = 'CARGO_ANTERIOR');

SET @sql_anterior := IF(@ancho_anterior IS NOT NULL AND @ancho_anterior < 50,
                        'ALTER TABLE HISTORIAL_LABORAL_EMPLEADO MODIFY CARGO_ANTERIOR VARCHAR(50) NOT NULL',
                        'DO 0');
PREPARE st_anterior FROM @sql_anterior;
EXECUTE st_anterior;
DEALLOCATE PREPARE st_anterior;

-- 3. CARGO_NUEVO
SET @ancho_nuevo := (SELECT CHARACTER_MAXIMUM_LENGTH
                       FROM INFORMATION_SCHEMA.COLUMNS
                      WHERE TABLE_SCHEMA = DATABASE()
                        AND TABLE_NAME = 'HISTORIAL_LABORAL_EMPLEADO'
                        AND COLUMN_NAME = 'CARGO_NUEVO');

SET @sql_nuevo := IF(@ancho_nuevo IS NOT NULL AND @ancho_nuevo < 50,
                     'ALTER TABLE HISTORIAL_LABORAL_EMPLEADO MODIFY CARGO_NUEVO VARCHAR(50) NOT NULL',
                     'DO 0');
PREPARE st_nuevo FROM @sql_nuevo;
EXECUTE st_nuevo;
DEALLOCATE PREPARE st_nuevo;

-- 4. Resultado
SELECT COLUMN_NAME, COLUMN_TYPE
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE()
   AND TABLE_NAME = 'HISTORIAL_LABORAL_EMPLEADO'
   AND COLUMN_NAME IN ('CARGO_ANTERIOR', 'CARGO_NUEVO')
 ORDER BY COLUMN_NAME;
