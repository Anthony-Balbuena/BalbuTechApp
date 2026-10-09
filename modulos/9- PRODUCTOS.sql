-- Active: 1786471144213@@127.0.0.1@3306@BALBU_TECH

/*
TABLA PRODUCTOS
Catalogo de productos de la tienda: nombre, descripcion, precio, codigo
unico, marca, categoria y proveedor. El precio tiene que ser mayor a cero
y el nombre no se puede repetir dentro de la misma marca. Puede traer
imagen y arranca ACTIVO.
*/

CREATE TABLE PRODUCTOS (
    ID_PRODUCTO INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(100) NOT NULL,
    DESCRIPCION VARCHAR(255) NOT NULL,
    PRECIO DECIMAL(10, 2) NOT NULL CHECK (PRECIO > 0),
    CODIGO VARCHAR(20) NOT NULL UNIQUE,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    FECHA_CREACION TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ID_MARCA INT NOT NULL,
    ID_CATEGORIA INT NOT NULL,
    ID_PROVEEDOR INT NOT NULL,
    -- (09/10/2026) P4. La columna se llama IMAGEN en la BD viva (nadie la usa);
    -- se unifica aqui para que las BD nuevas nazcan igual.
    IMAGEN VARCHAR(255),
    PRIMARY KEY (ID_PRODUCTO),
    CONSTRAINT UQ_PRODUCTO_NOMBRE_MARCA UNIQUE (NOMBRE, ID_MARCA),
    CONSTRAINT FK_PRODUCTO_MARCA FOREIGN KEY (ID_MARCA) REFERENCES MARCAS (ID_MARCA),
    CONSTRAINT FK_PRODUCTO_CATEGORIA FOREIGN KEY (ID_CATEGORIA) REFERENCES CATEGORIAS (ID_CATEGORIA),
    -- (09/10/2026) FK que faltaba: la BD viva ya lo tiene (FK_PRODUCTO_PROVEEDOR);
    -- se agrega aqui para que las BD nuevas (Docker) nazcan con el.
    CONSTRAINT FK_PRODUCTO_PROVEEDOR FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR)
) ENGINE = InnoDB;

SELECT * FROM `MARCAS`; 

SELECT * from PRODUCTOS;

/*
INDICE IX_PRODUCTOS_MARCA
Acelera los listados y filtros que cruzan productos con su marca,
evitando recorrer toda la tabla cuando se arma un reporte.
*/
CREATE INDEX IX_PRODUCTOS_MARCA ON PRODUCTOS (ID_MARCA);

/*
INDICE IX_PRODUCTOS_CATEGORIA
Acelera las busquedas por categoria y la generacion de reportes
agrupados por categoria de producto.
*/
CREATE INDEX IX_PRODUCTOS_CATEGORIA ON PRODUCTOS (ID_CATEGORIA);


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------                

DESCRIBE PRODUCTOS;

--1. INSERTAR

DELIMITER //
/*
SP_INSERTAR_PRODUCTO
Da de alta un producto nuevo validando todo antes de guardar: que el
proveedor, la marca y la categoria existan, que el codigo sea unico, que
el precio sea mayor a cero y que la descripcion tenga al menos 10
caracteres. Si algo falla no guarda nada.
*/
DROP PROCEDURE IF EXISTS SP_INSERTAR_PRODUCTO ;


CREATE PROCEDURE SP_INSERTAR_PRODUCTO(
    IN P_NOMBRE        VARCHAR(100),
    IN P_DESCRIPCION   VARCHAR(255),
    IN P_PRECIO        DECIMAL(10, 2),
    IN P_CODIGO        VARCHAR(20),
    IN P_ID_MARCA      INT,
    IN P_ID_CATEGORIA  INT,
    IN P_ID_PROVEEDOR  INT,
    -- (09/10/2026) P6. La app (productos.cpp) manda la imagen como 8vo
    -- parametro; sin esto el alta desde la app fallaba (nro. de args).
    IN P_IMAGEN        VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(100);
    DECLARE v_desc_limpia   VARCHAR(255);
    DECLARE v_codigo_limpio VARCHAR(20);

    -- 1) Limpieza
    SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
    SET v_desc_limpia   = REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' ');
    SET v_codigo_limpio = UPPER(TRIM(P_CODIGO));

    -- 2) Validaciones obligatorias
    IF P_ID_PROVEEDOR IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DEBE INDICAR ID_PROVEEDOR.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM MARCAS WHERE ID_MARCA = P_ID_MARCA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA MARCA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM CATEGORIAS WHERE ID_CATEGORIA = P_ID_CATEGORIA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CATEGORÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- Código único
    IF EXISTS (SELECT 1 FROM PRODUCTOS AS Prod WHERE Prod.CODIGO = v_codigo_limpio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL CÓDIGO YA ESTÁ REGISTRADO EN OTRO PRODUCTO.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) P1. Nombre repetido en la misma marca (amable en vez del 1062 del UNIQUE).
    IF EXISTS (SELECT 1 FROM PRODUCTOS AS Prod WHERE Prod.NOMBRE = v_nombre_limpio AND Prod.ID_MARCA = P_ID_MARCA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA EXISTE UN PRODUCTO CON ESE NOMBRE EN ESA MARCA.';
        LEAVE proc_label;
    END IF;

    -- Precio válido
    -- (09/10/2026) P2. IFNULL: el NULL pasaba el <= 0 y reventaba con 1048.
    IF IFNULL(P_PRECIO, 0) <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRECIO DEBE SER MAYOR A CERO.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) P3. Nombre vacío tras limpiar.
    IF CHAR_LENGTH(v_nombre_limpio) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.';
        LEAVE proc_label;
    END IF;

    IF LENGTH(v_desc_limpia) < 10 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DESCRIPCIÓN DEMASIADO CORTA (MÍNIMO 10 CARACTERES).';
        LEAVE proc_label;
    END IF;

    -- 3) Inserción (requiere proveedor explícito)
    INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, IMAGEN)
    VALUES (v_nombre_limpio, v_desc_limpia, P_PRECIO, v_codigo_limpio, P_ID_MARCA, P_ID_CATEGORIA, P_ID_PROVEEDOR, P_IMAGEN);

    SELECT CONCAT('EXITO: PRODUCTO "', v_nombre_limpio, '" REGISTRADO CORRECTAMENTE.') AS MENSAJE;

END //

DELIMITER ;

DESCRIBE PRODUCTOS;

--2. ACTUALIZAR

DELIMITER //
 
/*
SP_ACTUALIZAR_PRODUCTOS
Actualiza los datos que se le envien de un producto existente.
Comprueba que el producto exista, que el codigo no le pertenezca a otro,
que el precio sea positivo y que marca y categoria existan si se cambian;
lo que llegue en NULL se queda como estaba.
*/
DROP PROCEDURE IF EXISTS SP_ACTUALIZAR_PRODUCTOS ;

CREATE PROCEDURE SP_ACTUALIZAR_PRODUCTOS(
    IN P_ID_PRODUCTO  INT,
    IN P_NOMBRE       VARCHAR(100), 
    IN P_DESCRIPCION  VARCHAR(255),
    IN P_PRECIO       DECIMAL(10, 2),
    IN P_CODIGO       VARCHAR(20),
    IN P_ID_MARCA     INT,
    IN P_ID_CATEGORIA INT,
    -- (09/10/2026) P7. La app (productos.cpp) manda proveedor e imagen
    -- (9 args en total); sin estos el UPDATE desde la app fallaba.
    IN P_ID_PROVEEDOR INT,
    IN P_IMAGEN       VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_nombre_limpio VARCHAR(100); 
    DECLARE v_desc_limpia   VARCHAR(255);
    DECLARE v_codigo_limpio VARCHAR(20);

    -- 1. VALIDAR EXISTENCIA
    IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- 2. LIMPIEZA Y VALIDACIONES CONDICIONALES
    IF P_NOMBRE IS NOT NULL THEN
        SET v_nombre_limpio = REGEXP_REPLACE(TRIM(P_NOMBRE), '[[:space:]]+', ' ');
        IF v_nombre_limpio = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.';
            LEAVE proc_label;
        END IF;
    END IF;

    IF P_DESCRIPCION IS NOT NULL THEN
        SET v_desc_limpia = REGEXP_REPLACE(TRIM(P_DESCRIPCION), '[[:space:]]+', ' ');
    END IF;

    IF P_CODIGO IS NOT NULL THEN
        SET v_codigo_limpio = UPPER(TRIM(P_CODIGO));
        IF EXISTS (SELECT 1 FROM PRODUCTOS WHERE CODIGO = v_codigo_limpio AND ID_PRODUCTO <> P_ID_PRODUCTO) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: ESTE CÓDIGO YA PERTENECE A OTRO PRODUCTO.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- NUEVA VALIDACIÓN: Si mandan precio, debe ser mayor que cero
    IF P_PRECIO IS NOT NULL THEN
        IF P_PRECIO <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRECIO DEBE SER MAYOR A CERO.';
            LEAVE proc_label;
        END IF;
    END IF;

    -- Validar FKs si se intentan cambiar
    IF P_ID_MARCA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM MARCAS WHERE ID_MARCA = P_ID_MARCA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA MARCA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_ID_CATEGORIA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM CATEGORIAS WHERE ID_CATEGORIA = P_ID_CATEGORIA) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: LA CATEGORÍA NO EXISTE.';
        LEAVE proc_label;
    END IF;

    IF P_ID_PROVEEDOR IS NOT NULL AND NOT EXISTS (SELECT 1 FROM PROVEEDORES WHERE ID_PROVEEDOR = P_ID_PROVEEDOR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PROVEEDOR NO EXISTE.';
        LEAVE proc_label;
    END IF;

    -- (09/10/2026) P5. Nombre duplicado en la marca con los valores efectivos
    -- (lo que venga NULL queda como esta); se excluye la propia fila.
    IF EXISTS (SELECT 1 FROM PRODUCTOS
                WHERE NOMBRE = COALESCE(v_nombre_limpio, (SELECT NOMBRE FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO))
                  AND ID_MARCA = COALESCE(P_ID_MARCA, (SELECT ID_MARCA FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO))
                  AND ID_PRODUCTO <> P_ID_PRODUCTO) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: YA EXISTE OTRO PRODUCTO CON ESE NOMBRE EN ESA MARCA.';
        LEAVE proc_label;
    END IF;

    -- 3. ACTUALIZACIÓN DINÁMICA (Simplificada y segura)
    UPDATE PRODUCTOS 
    SET 
        NOMBRE       = COALESCE(v_nombre_limpio, NOMBRE),
        DESCRIPCION  = COALESCE(v_desc_limpia, DESCRIPCION),
        PRECIO       = COALESCE(P_PRECIO, PRECIO), -- Ya validado arriba
        CODIGO       = COALESCE(v_codigo_limpio, CODIGO),
        ID_MARCA     = COALESCE(P_ID_MARCA, ID_MARCA),
        ID_CATEGORIA = COALESCE(P_ID_CATEGORIA, ID_CATEGORIA),
        ID_PROVEEDOR = COALESCE(P_ID_PROVEEDOR, ID_PROVEEDOR),
        IMAGEN       = COALESCE(P_IMAGEN, IMAGEN)
    WHERE ID_PRODUCTO = P_ID_PRODUCTO;

    -- 4. MENSAJE DE RETORNO (Estilo BALBU_TECH)
    SET @mensaje_final = (SELECT CONCAT('EXITO: EL PRODUCTO "', 
                                        COALESCE(v_nombre_limpio, NOMBRE), 
                                        '" FUE ACTUALIZADO. (CÓDIGO: ', 
                                        COALESCE(v_codigo_limpio, CODIGO), 
                                        ')') 
                          FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO);

    SELECT @mensaje_final AS MENSAJE;

END //

DELIMITER ;


--3. Activar/Decastivar
DELIMITER //
/*
SP_TOGGLE_ESTADO_PRODUCTOS
Le da la vuelta al estado del producto: de ACTIVO a INACTIVO y viceversa.
Si el ID no existe manda un error; si existe responde con un mensaje que
dice de que estado paso al nuevo.
*/
DROP PROCEDURE IF EXISTS SP_TOGGLE_ESTADO_PRODUCTOS;
CREATE PROCEDURE SP_TOGGLE_ESTADO_PRODUCTOS(
    IN P_ID_PRODUCTO INT
)
proc_label: BEGIN
    -- 1. Variables para capturar la info actual
    DECLARE v_NOMBRE VARCHAR(100);
    DECLARE v_ESTADO_ACTUAL VARCHAR(20);
    DECLARE v_NUEVO_ESTADO VARCHAR(20);

  IF NOT EXISTS (SELECT 1 FROM PRODUCTOS WHERE ID_PRODUCTO = P_ID_PRODUCTO) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRODUCTO NO EXISTE.';
    LEAVE proc_label;
END IF;

    -- 3. Obtener el nombre y el estado actual
    SELECT `NOMBRE`, `ESTADO` INTO v_NOMBRE, v_ESTADO_ACTUAL 
    FROM `PRODUCTOS` 
    WHERE `ID_PRODUCTO` = P_ID_PRODUCTO;

    -- 4. Lógica del "Interruptor" (Toggle)
    IF v_ESTADO_ACTUAL = 'ACTIVO' THEN
        SET v_NUEVO_ESTADO = 'INACTIVO';
    ELSE
        SET v_NUEVO_ESTADO = 'ACTIVO';
    END IF;

    -- 5. Aplicar el cambio en la tabla
    UPDATE `PRODUCTOS` 
    SET `ESTADO` = v_NUEVO_ESTADO 
    WHERE `ID_PRODUCTO` = P_ID_PRODUCTO;

    -- 6. Mensaje de confirmación final
    SELECT CONCAT(
        'PRODUCTO: "', v_NOMBRE, 
        '" - CAMBIO DE: ', v_ESTADO_ACTUAL, 
        ' A: ', v_NUEVO_ESTADO
    ) AS MENSAJE;

END //
DELIMITER ;

---4. CONSULTAR PRODUCTO FILTRADO
DELIMITER //
/*
SP_CONSULTAR_PRODUCTOS_FILTRADO
Busca productos por nombre o por codigo y los devuelve con su marca,
categoria, precio y estado. Si la busqueda viene vacia o NULL trae todos,
ordenados por ID.
*/
DROP PROCEDURE IF EXISTS SP_CONSULTAR_PRODUCTOS_FILTRADO  ;


CREATE PROCEDURE SP_CONSULTAR_PRODUCTOS_FILTRADO(
    IN P_BUSQUEDA VARCHAR(100)
)
BEGIN
    SELECT 
        P.ID_PRODUCTO,
        P.CODIGO,
        P.NOMBRE,
        M.NOMBRE AS MARCA,
        C.NOMBRE AS CATEGORIA,
        P.PRECIO,
        P.ESTADO
    FROM PRODUCTOS P
    INNER JOIN MARCAS M ON P.ID_MARCA = M.ID_MARCA
    INNER JOIN CATEGORIAS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '' 
           OR P.NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%') 
           OR P.CODIGO = P_BUSQUEDA)
    ORDER BY P.ID_PRODUCTO ASC; -- <-- CAMBIADO AQUÍ (Ordena 1, 2, 3...)
END //
DELIMITER ;

--5. consultar inventario
DELIMITER //
/*
SP_CONSULTAR_INVENTARIO
Muestra el inventario de los productos activos con su stock y marca la
situacion de cada uno: AGOTADO, CRITICO, STOCK BAJO u OK segun lo que
haya contra el minimo. Se puede filtrar por nombre, codigo o categoria.
*/
DROP PROCEDURE IF EXISTS SP_CONSULTAR_INVENTARIO ;
CREATE PROCEDURE SP_CONSULTAR_INVENTARIO(
    IN P_FILTRO VARCHAR(100)
)
BEGIN
    SELECT 
        P.ID_PRODUCTO, -- Agregado para consistencia visual
        P.CODIGO,
        P.NOMBRE,
        C.NOMBRE AS CATEGORIA,
        M.NOMBRE AS MARCA,
        I.STOCK_ACTUAL,
        I.STOCK_MINIMO,
        I.UBICACION,
        P.PRECIO,
        -- CONTROL DE ALERTAS CON MÚLTIPLES CONDICIONES (Else If)
        CASE 
            WHEN I.STOCK_ACTUAL = 0 THEN 'AGOTADO'
            WHEN I.STOCK_ACTUAL <= I.STOCK_MINIMO THEN 'CRÍTICO' 
            WHEN I.STOCK_ACTUAL <= (I.STOCK_MINIMO * 2) THEN 'STOCK BAJO'
            ELSE 'OK' 
        END AS ESTATUS_STOCK
    FROM PRODUCTOS P
    LEFT JOIN INVENTARIO I ON P.ID_PRODUCTO = I.ID_PRODUCTO
    LEFT JOIN CATEGORIAS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
    LEFT JOIN MARCAS M ON P.ID_MARCA = M.ID_MARCA
    WHERE (P_FILTRO IS NULL OR P_FILTRO = '' 
           OR P.NOMBRE LIKE CONCAT('%', P_FILTRO, '%') 
           OR P.CODIGO LIKE CONCAT('%', P_FILTRO, '%')
           OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%'))
      AND P.ESTADO = 'ACTIVO'
    ORDER BY P.ID_PRODUCTO ASC; -- Ordenado numéricamente por ID de producto
END //
DELIMITER ;
--6. REPORTE STOCK 
DELIMITER //
/*
SP_REPORTE_STOCK_CRITICO
Lista los productos que estan por debajo del stock minimo con su cantidad
faltante, del mas urgente al menos, para priorizar la reposicion.
*/
DROP PROCEDURE IF EXISTS SP_REPORTE_STOCK_CRITICO ;
CREATE PROCEDURE SP_REPORTE_STOCK_CRITICO()
BEGIN
    SELECT 
        P.NOMBRE,
        I.STOCK_ACTUAL,
        I.STOCK_MINIMO,
        (I.STOCK_MINIMO - I.STOCK_ACTUAL) AS CANTIDAD_FALTANTE
    FROM INVENTARIO I
    JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
    WHERE I.STOCK_ACTUAL <= I.STOCK_MINIMO
    ORDER BY CANTIDAD_FALTANTE DESC;
END //





 
DELIMITER ;
DELIMITER //


/*
PARA_INSERTAR_PRODUCTO
Prepara los datos del formulario de alta de producto: devuelve en tres
result sets las categorias, las marcas y los proveedores, para que el
cliente llene los selects.
*/
DROP PROCEDURE IF EXISTS PARA_INSERTAR_PRODUCTO;

 /*Este procedure lo quite para mejorarlo*/

CREATE PROCEDURE PARA_INSERTAR_PRODUCTO()
BEGIN
    -- Primer conjunto de resultados: Las categorías ordenadas de forma descendente
    SELECT ID_CATEGORIA, NOMBRE 
    FROM CATEGORIAS 
    ORDER BY ID_CATEGORIA ASC;

    -- Segundo conjunto de resultados: Las marcas ordenadas de forma descendente
    SELECT ID_MARCA, NOMBRE 
    FROM MARCAS 
    ORDER BY ID_MARCA ASC; 
    
    -- Tercer conjunto de resultados: proveedores (para popular control de selección)
    SELECT ID_PROVEEDOR, NOMBRE
    FROM PROVEEDORES
    ORDER BY ID_PROVEEDOR ASC;
END//

DELIMITER ;
CALL PARA_INSERTAR_PRODUCTO();



--PARA LA ACTUALIZACION DE LOS DATOS 
DELIMITER //
/*
PARA_ACTUALIZARDATOS
Prepara los datos del formulario de edicion de producto: devuelve el
producto junto con su categoria y su marca para popular los controles de
la pantalla.
*/
DROP PROCEDURE IF EXISTS PARA_ACTUALIZARDATOS;

CREATE PROCEDURE PARA_ACTUALIZARDATOS()
BEGIN

SELECT 
    P.ID_PRODUCTO,
    P.NOMBRE AS PRODUCTO,
    P.PRECIO,
    C.ID_CATEGORIA,
    C.NOMBRE AS CATEGORIA,
    M.ID_MARCA,
    M.NOMBRE AS MARCA
FROM 
    PRODUCTOS AS P
LEFT JOIN 
    CATEGORIAS AS C 
    ON P.ID_CATEGORIA = C.ID_CATEGORIA
LEFT JOIN 
    MARCAS AS M 
    ON P.ID_MARCA = M.ID_MARCA
ORDER BY 
P.ID_PRODUCTO ASC,
    C.ID_CATEGORIA ASC, 
    M.ID_MARCA ASC;

END//

DELIMITER ;
CALL PARA_ACTUALIZARDATOS(); 


--SP PARA VER EL LA LOGICA DEL C++ el backend los para activar o desactivar 
DELIMITER //

/*
PARA_ACTIVARODESACTIVAR_PROC
Devuelve la lista simple de productos con ID, nombre y estado, que el
backend C++ usa para activar o desactivar productos en bloque.
*/
DROP PROCEDURE IF EXISTS PARA_ACTIVARODESACTIVAR_PROC;

CREATE PROCEDURE PARA_ACTIVARODESACTIVAR_PROC()
BEGIN


SELECT ID_PRODUCTO , NOMBRE ,ESTADO FROM PRODUCTOS 
ORDER BY ID_PRODUCTO ASC;
END//

DELIMITER ;

CALL PARA_ACTIVARODESACTIVAR_PROC();

SELECT * FROM PRODUCTOS; 


-- 6) Verificación final: listar productos y su proveedor
SELECT ID_PRODUCTO, NOMBRE, ID_PROVEEDOR FROM PRODUCTOS ORDER BY ID_PRODUCTO;

-- Verificar existencia del proveedor 1
SELECT * FROM PROVEEDORES WHERE ID_PROVEEDOR = 1;

-- 1) Añadir columna (permitir NULL temporalmente)
ALTER TABLE PRODUCTOS
ADD COLUMN IF NOT EXISTS ID_PROVEEDOR INT DEFAULT 1 AFTER ID_CATEGORIA;

-- 2) Asignar proveedor 1 a productos existentes que no tengan proveedor válido
UPDATE PRODUCTOS
SET ID_PROVEEDOR = 1
WHERE ID_PROVEEDOR IS NULL OR ID_PROVEEDOR = 0;

-- 3) Forzar NOT NULL y DEFAULT 1
ALTER TABLE PRODUCTOS
MODIFY COLUMN ID_PROVEEDOR INT NOT NULL DEFAULT 1;

-- 4) Añadir FK (si no existe)

-- Verificación: listar productos con su proveedor
SELECT ID_PRODUCTO, NOMBRE, ID_PROVEEDOR FROM PRODUCTOS ORDER BY ID_PRODUCTO;


SELECT * from PRODUCTOS;

ALTER TABLE PRODUCTOS 
ALTER COLUMN ID_PROVEEDOR DROP DEFAULT;

DESCRIBE PRODUCTOS;

ALTER TABLE PRODUCTOS 
MODIFY COLUMN ID_PROVEEDOR INT NOT NULL;

-----------------------------------------------------------------------------------------------------------------------
-- Trigger TR_AUDITORIA_PRODUCTOS_UPDATE movido a 9 (su tabla).
DELIMITER //
DROP TRIGGER IF EXISTS TR_AUDITORIA_PRODUCTOS_UPDATE ;
CREATE TRIGGER TR_AUDITORIA_PRODUCTOS_UPDATE
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
BEGIN
    -- Auditamos el PRECIO
    IF OLD.PRECIO <> NEW.PRECIO THEN
        INSERT INTO AUDITORIA_SISTEMA (
            TABLA_AFECTADA, 
            ID_REGISTRO_AFECTADO, 
            ACCION, 
            USUARIO_SISTEMA, 
            VALOR_ANTERIOR, 
            VALOR_NUEVO
        ) VALUES (
            'PRODUCTOS', 
            NEW.ID_PRODUCTO, 
            'UPDATE', 
            USER(),
            CONCAT('Precio venta anterior: ', OLD.PRECIO), 
            CONCAT('Precio venta nuevo: ', NEW.PRECIO)
        );
    END IF;
END //
DELIMITER ;