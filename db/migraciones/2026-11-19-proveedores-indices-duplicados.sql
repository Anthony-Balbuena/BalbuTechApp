-- ============================================================
-- 2026-11-19 - PROVEEDORES: indices unicos duplicados
-- ============================================================
-- Una base creada por los modulos viejos tiene DOS indices unicos sobre
-- TELEFONO (TELEFONO + UQ_PROVEEDOR_TELEFONO) y dos sobre EMAIL. Sobra el
-- implicito que nacia del UNIQUE inline; el CREATE TABLE del modulo 5 ya
-- declara el constraint con nombre.
--
-- Este archivo NO lo ejecuta db/import.sh (solo globbea modulos/*.sql).
-- Se aplica a mano sobre una base que ya existe:
--
--   mariadb -h 127.0.0.1 -u root -p --database=BALBU_TECH \
--     < db/migraciones/2026-11-19-proveedores-indices-duplicados.sql
--
-- Es idempotente: primero asegura el constraint con nombre y recien despues
-- dropea el indice implicito, asi nunca se queda sin la restriccion de
-- unicidad. En una base nueva no hace nada.
-- ============================================================

-- 1. Asegurar UQ_PROVEEDOR_TELEFONO (no-op si ya existe).
SET @hay_tel := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'PROVEEDORES'
                    AND INDEX_NAME = 'UQ_PROVEEDOR_TELEFONO');
SET @sql_tel := IF(@hay_tel = 0,
    'ALTER TABLE PROVEEDORES ADD UNIQUE KEY UQ_PROVEEDOR_TELEFONO (TELEFONO)',
    'DO 0');
PREPARE st FROM @sql_tel; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Asegurar UQ_PROVEEDOR_EMAIL (no-op si ya existe).
SET @hay_mail := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'PROVEEDORES'
                     AND INDEX_NAME = 'UQ_PROVEEDOR_EMAIL');
SET @sql_mail := IF(@hay_mail = 0,
    'ALTER TABLE PROVEEDORES ADD UNIQUE KEY UQ_PROVEEDOR_EMAIL (EMAIL)',
    'DO 0');
PREPARE st FROM @sql_mail; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. Dropear los indices implicitos del UNIQUE inline viejo.
ALTER TABLE PROVEEDORES
    DROP INDEX IF EXISTS TELEFONO,
    DROP INDEX IF EXISTS EMAIL;

SELECT 'PROVEEDORES: indices duplicados limpiados.' AS RESULTADO;
