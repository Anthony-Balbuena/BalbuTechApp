-- ============================================================
-- 2026-11-21 - PRODUCTOS: exencion de ITBIS por producto
-- ============================================================
-- Agrega el flag EXENTO_ITBIS a una base que ya existe. 0 = gravado (lo de
-- siempre), 1 = sus lineas de venta y de compra no llevan ITBIS.
--
-- Este archivo NO lo ejecuta db/import.sh (solo globbea modulos/*.sql).
-- Se aplica a mano sobre una base que ya existe:
--
--   set -a; . ./.env; set +a
--   mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" --database=BALBU_TECH \
--     < db/migraciones/2026-11-21-productos-exento-itbis.sql
--
-- Es idempotente: IF NOT EXISTS deja la columna como esta si ya existe.
--
-- AFTER DIAS_GARANTIA es obligatorio, no cosmetico: el CREATE TABLE del modulo
-- 9 pone la columna en esa posicion, y db/verificar-esquema.sh compara el orden
-- de las columnas. Si esta migracion la agregara al final de la tabla, la base
-- migrada y un import desde cero quedarian con el mismo esquema en distinto
-- orden y el verificador marcaria diferencia (fue exactamente el problema del
-- 21/11 que se cerro con db/migraciones/2026-11-21-alinear-viva-al-repo.sql).
-- ============================================================

ALTER TABLE PRODUCTOS
    ADD COLUMN IF NOT EXISTS EXENTO_ITBIS TINYINT(1) NOT NULL DEFAULT 0
        AFTER DIAS_GARANTIA;

SELECT 'PRODUCTOS.EXENTO_ITBIS disponible (0 = gravado, 1 = exento).' AS RESULTADO;
