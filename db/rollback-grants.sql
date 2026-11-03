-- ROLLBACK de db/grant-minimos.sql (03/11/2026)
-- Privilegios de balbu_app ANTES del recorte, por esquema. Correr con root.
REVOKE ALL PRIVILEGES ON `__DB__`.* FROM 'balbu_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES, EXECUTE, SHOW VIEW
  ON `__DB__`.* TO 'balbu_app'@'%';
FLUSH PRIVILEGES;
