-- Active: 1775068811273@@127.0.0.1@3306@BALBU_TECH
CREATE TABLE CONFIGURACION (
    ID_CONFIG INT NOT NULL AUTO_INCREMENT,
    CLAVE VARCHAR(50) NOT NULL UNIQUE, -- Ej: 'PORCENTAJE_IMPUESTO', 'DIAS_GARANTIA_DEFECTO'
    VALOR VARCHAR(100) NOT NULL,
    DESCRIPCION VARCHAR(200),
    PRIMARY KEY (ID_CONFIG)
) ENGINE = InnoDB;

-- Ejemplo de datos iniciales
INSERT INTO CONFIGURACION (CLAVE, VALOR, DESCRIPCION) VALUES 
('ITBIS', '18', 'Impuesto sobre transferencia de bienes y servicios'),
('DIAS_GARANTIA', '30', 'Días de garantía por defecto en productos'),
('NOMBRE_TIENDA', 'BALBU_TECH', 'Nombre que aparecerá en los tickets');