-- Migration: Aumentar tamaño de la columna CONTRASENA para almacenar hashes PBKDF2.
-- IMPORTANTE: HAZ BACKUP ANTES DE EJECUTAR.
USE BALBU_TECH;

-- Ver estado actual (opcional):
-- SELECT COLUMN_NAME, COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS
--  WHERE TABLE_SCHEMA='BALBU_TECH' AND TABLE_NAME='USUARIOS' AND COLUMN_NAME='CONTRASENA';

ALTER TABLE `USUARIOS`
  MODIFY COLUMN `CONTRASENA` VARCHAR(512) NOT NULL;

-- Después de ejecutar esta migración, las nuevas contraseñas se almacenarán
-- en formato `pbkdf2$<iter>$<salt_b64>$<hash_b64>` generado por la aplicación.
