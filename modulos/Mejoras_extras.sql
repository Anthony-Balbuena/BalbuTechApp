DELIMITER //

DROP PROCEDURE IF EXISTS ;
CREATE PROCEDURE sp_obtener_categorias_marcas()
BEGIN
    -- Primer conjunto de resultados: Las categorías
    SELECT id_categoria, nombre_categoria FROM categorias;

    -- Segundo conjunto de resultados: Las marcas
    SELECT id_marca, nombre_marca FROM marcas;
END;

DELIMITER //
    