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
