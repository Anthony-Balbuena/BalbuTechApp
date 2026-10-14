-- Active: 1775068811273@@127.0.0.1@3306@BALBU_TECH
/*
TABLA CONFIGURACION
Guarda los ajustes del sistema como pares de clave y valor: porcentaje de
impuesto, dias de garantia, nombre de la tienda, etc.
Asi se cambian los ajustes sin tocar el codigo.
*/
CREATE TABLE CONFIGURACION (
    ID_CONFIG INT NOT NULL AUTO_INCREMENT,
    CLAVE VARCHAR(50) NOT NULL UNIQUE, -- Ej: 'PORCENTAJE_IMPUESTO', 'DIAS_GARANTIA_DEFECTO'
    VALOR VARCHAR(100) NOT NULL,
    DESCRIPCION VARCHAR(200),
    PRIMARY KEY (ID_CONFIG)
) ENGINE = InnoDB;

-- Ejemplo de datos iniciales
INSERT IGNORE INTO CONFIGURACION (CLAVE, VALOR, DESCRIPCION) VALUES 
('ITBIS', '18', 'Impuesto sobre transferencia de bienes y servicios'),
('DIAS_GARANTIA', '30', 'Días de garantía por defecto en productos'),
('NOMBRE_TIENDA', 'BALBU_TECH', 'Nombre que aparecerá en los tickets');
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNCION TASA ITBIS}------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP FUNCTION IF EXISTS FN_TASA_ITBIS ;
/*
FN_TASA_ITBIS (13/10/2026)
Tasa vigente para mostrar precios con impuesto en la app. Si falta o es
invalida, devuelve 18. Solo lectura.
*/
CREATE FUNCTION FN_TASA_ITBIS()
RETURNS DECIMAL(5, 2)
READS SQL DATA
BEGIN
    DECLARE V_TASA DECIMAL(5, 2) DEFAULT 18.00;
    DECLARE V_TXT VARCHAR(100);
    SELECT VALOR INTO V_TXT FROM CONFIGURACION WHERE CLAVE = 'ITBIS' LIMIT 1;
    IF V_TXT IS NOT NULL AND V_TXT + 0 > 0 THEN
        SET V_TASA = V_TXT + 0;
    END IF;
    RETURN V_TASA;
END //
DELIMITER ;
