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
    -- (12/10/2026) Precio de compra. En BD fresca nace en 0 = pendiente de
    -- cargar el real (ver Obsidian: estimados de prueba, reemplazar por factura).
    P_COMPRA DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (P_COMPRA >= 0),
    CODIGO VARCHAR(20) NOT NULL UNIQUE,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    -- (15/11/2026) Un repuesto de garantia es un producto del catalogo con su
    -- propio CODIGO que NO se vende. Este flag es la unica fuente de verdad del
    -- destino (S11) y lo que permite que un vendedor no lo vea (S12). No se usa
    -- ESTADO='INACTIVO': ESTADO es "descontinuado" y un repuesto esta activo.
    ES_REPUESTO TINYINT(1) NOT NULL DEFAULT 0,
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

-- (15/11/2026) Migracion idempotente para bases que ya existen. El DEFAULT 0
-- deja a todos los productos de hoy significando exactamente lo mismo.
ALTER TABLE PRODUCTOS
ADD COLUMN IF NOT EXISTS ES_REPUESTO TINYINT(1) NOT NULL DEFAULT 0 AFTER ESTADO;


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
    -- (14/10/2026) Precio de compra antes del precio de venta.
    IN P_COMPRA        DECIMAL(10, 2),
    IN P_PRECIO        DECIMAL(10, 2),
    IN P_CODIGO        VARCHAR(20),
    IN P_ID_MARCA      INT,
    IN P_ID_CATEGORIA  INT,
    IN P_ID_PROVEEDOR  INT,
    -- (09/10/2026) P6. La app (productos.cpp) manda la imagen como 9no
    -- parametro; sin esto el alta desde la app fallaba (nro. de args).
    IN P_IMAGEN        VARCHAR(255),
    -- (15/11/2026) 10mo. Un repuesto de garantia es un producto con su propio
    -- CODIGO que NO se vende. NULL = 0 (vendible), que es lo de siempre.
    IN P_ES_REPUESTO   TINYINT
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

    -- (14/10/2026) Precio de compra antes del precio: NULL = 0, nunca negativo.
    IF IFNULL(P_COMPRA, 0) < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRECIO DE COMPRA NO PUEDE SER NEGATIVO.';
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
    INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, IMAGEN, ES_REPUESTO)
    VALUES (v_nombre_limpio, v_desc_limpia, P_PRECIO, COALESCE(P_COMPRA, 0), v_codigo_limpio, P_ID_MARCA, P_ID_CATEGORIA, P_ID_PROVEEDOR, P_IMAGEN, IFNULL(P_ES_REPUESTO, 0));

    SELECT CONCAT('EXITO: PRODUCTO "', v_nombre_limpio, '" REGISTRADO CORRECTAMENTE.') AS MENSAJE;

END //
DELIMITER ;
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
    IN P_IMAGEN       VARCHAR(255),
    -- (12/10/2026) Costo de compra (NULL = conservar; 0 permitido).
    IN P_COSTO        DECIMAL(10, 2),
    -- (15/11/2026) NULL = conservar el flag actual.
    IN P_ES_REPUESTO  TINYINT
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
        -- (09/10/2026) P8: mismo minimo del alta (>= 10). Vacio = omitir (conserva la anterior).
        IF v_desc_limpia = '' THEN
            SET v_desc_limpia = NULL;
        ELSEIF CHAR_LENGTH(v_desc_limpia) < 10 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: DESCRIPCION DEMASIADO CORTA (MINIMO 10 CARACTERES).';
            LEAVE proc_label;
        END IF;
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

    -- (12/10/2026) El precio de compra puede ser 0 (regalo/bonificacion), nunca negativo.
    IF P_COSTO IS NOT NULL AND P_COSTO < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: EL PRECIO DE COMPRA NO PUEDE SER NEGATIVO.';
        LEAVE proc_label;
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
        -- (12/10/2026) NULL conserva el precio de compra vigente.
        P_COMPRA     = COALESCE(P_COSTO, P_COMPRA),
        CODIGO       = COALESCE(v_codigo_limpio, CODIGO),
        ID_MARCA     = COALESCE(P_ID_MARCA, ID_MARCA),
        ID_CATEGORIA = COALESCE(P_ID_CATEGORIA, ID_CATEGORIA),
        ID_PROVEEDOR = COALESCE(P_ID_PROVEEDOR, ID_PROVEEDOR),
        IMAGEN       = COALESCE(P_IMAGEN, IMAGEN),
        ES_REPUESTO  = COALESCE(P_ES_REPUESTO, ES_REPUESTO)
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
    -- 1. Variables para capturar la info actual~
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
    IN P_BUSQUEDA VARCHAR(100),
    -- (15/11/2026) Un repuesto de garantia es un producto con ES_REPUESTO = 1 que
    -- NO se vende. El modo lo decide quien llama, porque este SP lo comparten
    -- pantallas con reglas distintas:
    --   EXCLUIR -> ventas: un vendedor no ve ni puede vender un repuesto
    --   INCLUIR -> compras: hay que poder comprarlos
    --   SOLO    -> avance de reparacion: elegir QUE repuesto se consume
    -- NULL cae en INCLUIR, que es el comportamiento de antes de este cambio.
    IN P_MODO_REPUESTOS ENUM('EXCLUIR', 'INCLUIR', 'SOLO')
)
BEGIN
    SELECT 
        P.ID_PRODUCTO,
        P.CODIGO,
        P.NOMBRE,
        M.NOMBRE AS MARCA,
        C.NOMBRE AS CATEGORIA,
        P.PRECIO,
        -- (12/10/2026) Precio de compra visible para la app.
        P.P_COMPRA,
        P.ESTADO,
        -- (13/10/2026) Stock via JOIN a inventario (LEFT: sin fila igual lista).
        I.STOCK_ACTUAL AS STOCK,
        -- (13/10/2026) Proveedor para el listado de compras.
        PR.NOMBRE AS PROVEEDOR,
        -- (15/10/2026) ID del proveedor para la app.
        P.ID_PROVEEDOR
    FROM PRODUCTOS P
    INNER JOIN MARCAS M ON P.ID_MARCA = M.ID_MARCA
    INNER JOIN CATEGORIAS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
    LEFT JOIN INVENTARIO I ON I.ID_PRODUCTO = P.ID_PRODUCTO
    LEFT JOIN PROVEEDORES PR ON PR.ID_PROVEEDOR = P.ID_PROVEEDOR
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = '' 
           OR P.NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%') 
           OR P.CODIGO = P_BUSQUEDA
           -- (13/10/2026) Tambien por ID numerico.
           OR (P_BUSQUEDA REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_BUSQUEDA AS UNSIGNED)))
      AND (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'INCLUIR'
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'EXCLUIR' AND P.ES_REPUESTO = 0)
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'SOLO'    AND P.ES_REPUESTO = 1))
    ORDER BY P.ID_PRODUCTO ASC; -- <-- CAMBIADO AQUÍ (Ordena 1, 2, 3...)
END //
DELIMITER ;

-- ================================================================
-- 4.b LISTADO PAGINADO DE PRODUCTOS (08/11/2026)
-- ================================================================
-- Por que SP y no SELECT directo: balbu_app no tiene SELECT sobre PRODUCTOS
-- ni INVENTARIO (recorte de privilegios del 03/11); la lectura pasa por SPs
-- DEFINER. Estos dos son el par que usa la consola para paginar de 10 en 10:
-- uno devuelve la pagina, el otro el total para saber cuantas paginas hay.
-- El WHERE replica el de SP_CONSULTAR_PRODUCTOS_FILTRADO: si alla cambia el
-- criterio de busqueda, aca tambien.
DELIMITER //
/*
SP_CONTAR_PRODUCTOS_FILTRADOS
Cuenta los productos que devolveria la busqueda. Lo usa el paginador para
armar "Pagina 1 de N" y saber si hay una pagina mas.
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_PRODUCTOS_FILTRADOS ;
CREATE PROCEDURE SP_CONTAR_PRODUCTOS_FILTRADOS(
    IN P_BUSQUEDA VARCHAR(100),
    -- (15/11/2026) MISMO filtro que SP_CONSULTAR_PRODUCTOS_FILTRADO: si los dos
    -- no coinciden, el paginador muestra un total que no es el de la pagina.
    IN P_MODO_REPUESTOS ENUM('EXCLUIR', 'INCLUIR', 'SOLO')
)
BEGIN
    SELECT COUNT(*) AS TOTAL
      FROM PRODUCTOS P
     WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = ''
            OR P.NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%')
            OR P.CODIGO = P_BUSQUEDA
            OR (P_BUSQUEDA REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_BUSQUEDA AS UNSIGNED)))
       AND (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'INCLUIR'
            OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'EXCLUIR' AND P.ES_REPUESTO = 0)
            OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'SOLO'    AND P.ES_REPUESTO = 1));
END //
DELIMITER ;

DELIMITER //
/*
SP_CONSULTAR_PRODUCTOS_PAGINADO
Igual que SP_CONSULTAR_PRODUCTOS_FILTRADO pero devuelve una sola pagina.
P_PAGINA arranca en 1; valores nulos o fuera de rango se normalizan.
*/
DROP PROCEDURE IF EXISTS SP_CONSULTAR_PRODUCTOS_PAGINADO ;
CREATE PROCEDURE SP_CONSULTAR_PRODUCTOS_PAGINADO(
    IN P_BUSQUEDA   VARCHAR(100),
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT,
    -- (15/11/2026) Ver SP_CONSULTAR_PRODUCTOS_FILTRADO. Aca lo usa la pantalla de
    -- Productos: EXCLUIR si el rol no tiene REPUESTO_VER, INCLUIR si lo tiene.
    IN P_MODO_REPUESTOS ENUM('EXCLUIR', 'INCLUIR', 'SOLO')
)
proc_label: BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT
        P.ID_PRODUCTO,
        P.CODIGO,
        P.NOMBRE,
        M.NOMBRE AS MARCA,
        C.NOMBRE AS CATEGORIA,
        P.PRECIO,
        P.P_COMPRA,
        P.ESTADO,
        I.STOCK_ACTUAL AS STOCK,
        PR.NOMBRE AS PROVEEDOR,
        P.ID_PROVEEDOR
    FROM PRODUCTOS P
    INNER JOIN MARCAS M ON P.ID_MARCA = M.ID_MARCA
    INNER JOIN CATEGORIAS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
    LEFT JOIN INVENTARIO I ON I.ID_PRODUCTO = P.ID_PRODUCTO
    LEFT JOIN PROVEEDORES PR ON PR.ID_PROVEEDOR = P.ID_PROVEEDOR
    WHERE (P_BUSQUEDA IS NULL OR P_BUSQUEDA = ''
           OR P.NOMBRE LIKE CONCAT('%', P_BUSQUEDA, '%')
           OR P.CODIGO = P_BUSQUEDA
           OR (P_BUSQUEDA REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_BUSQUEDA AS UNSIGNED)))
      AND (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'INCLUIR'
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'EXCLUIR' AND P.ES_REPUESTO = 0)
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'SOLO'    AND P.ES_REPUESTO = 1))
    ORDER BY P.ID_PRODUCTO ASC
    LIMIT P_POR_PAGINA OFFSET v_offset;
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
    IN P_FILTRO VARCHAR(100),
    -- (15/11/2026) Ver SP_CONSULTAR_PRODUCTOS_FILTRADO: lo comparten la venta
    -- (EXCLUIR) y la compra (INCLUIR).
    IN P_MODO_REPUESTOS ENUM('EXCLUIR', 'INCLUIR', 'SOLO')
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
        -- (12/10/2026) Costo visible para la columna de compra.
        P.P_COMPRA,
        -- CONTROL DE ALERTAS CON MÚLTIPLES CONDICIONES (Else If)
        CASE 
            -- (19/10/2026) Sin fila en INVENTARIO = sin stock: antes el NULL caia en 'OK'.
            WHEN IFNULL(I.STOCK_ACTUAL, 0) = 0 THEN 'AGOTADO'
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
           OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
           -- (13/10/2026) Tambien por ID numerico (repuesto: se habia perdido).
           OR (P_FILTRO REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_FILTRO AS UNSIGNED)))
      AND P.ESTADO = 'ACTIVO'
      AND (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'INCLUIR'
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'EXCLUIR' AND P.ES_REPUESTO = 0)
           OR (IFNULL(P_MODO_REPUESTOS, 'INCLUIR') = 'SOLO'    AND P.ES_REPUESTO = 1))
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
-- SIN USO: SP_REPORTE_STOCK_CRITICO (08/11/2026)
-- Reemplazada por SP_REPORTE_STOCK_CRITICO_PAGINADO + SP_CONTAR_STOCK_CRITICO.
-- Se conserva sin uso desde 08/11/2026.
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

--PARA LA ACTUALIZACION DE LOS DATOS 
DELIMITER //
/*
PARA_ACTUALIZARDATOS
Prepara los datos del formulario de edicion de producto: devuelve el
producto junto con su categoria y su marca para popular los controles de
la pantalla.
*/
-- SIN USO: PARA_ACTUALIZARDATOS (08/11/2026)
-- Reemplazada por PARA_ACTUALIZARDATOS_PAGINADO + SP_CONTAR_PRODUCTOS.
-- Se conserva sin uso desde 08/11/2026.
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

-- ================================================================
-- 5.b LISTADOS PAGINADOS DE PRODUCTOS (08/11/2026)
-- ================================================================
-- Misma razon que el paginado de busqueda: las pantallas que piden un ID no
-- pueden traer todo. Cada par es (pagina, total); el LIMIT vive aca porque
-- balbu_app no tiene SELECT directo sobre PRODUCTOS ni INVENTARIO.
-- Permiso: el mismo que ya exige su hermana sin paginar.
DELIMITER //
/*
PARA_ACTUALIZARDATOS_PAGINADO
Una pagina del listado de edicion de producto. Permiso: GESTIONAR_PRODUCTOS.
*/
DROP PROCEDURE IF EXISTS PARA_ACTUALIZARDATOS_PAGINADO;
CREATE PROCEDURE PARA_ACTUALIZARDATOS_PAGINADO(
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT
        P.ID_PRODUCTO,
        P.NOMBRE AS PRODUCTO,
        P.PRECIO,
        C.ID_CATEGORIA,
        C.NOMBRE AS CATEGORIA,
        M.ID_MARCA,
        M.NOMBRE AS MARCA
    FROM PRODUCTOS AS P
    LEFT JOIN CATEGORIAS AS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
    LEFT JOIN MARCAS AS M ON P.ID_MARCA = M.ID_MARCA
    ORDER BY P.ID_PRODUCTO ASC
    LIMIT P_POR_PAGINA OFFSET v_offset;
END//
DELIMITER ;

DELIMITER //
/*
SP_CONTAR_PRODUCTOS
Total de productos, para el paginador de la edicion.
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_PRODUCTOS;
CREATE PROCEDURE SP_CONTAR_PRODUCTOS()
BEGIN
    SELECT COUNT(*) AS TOTAL FROM PRODUCTOS;
END//
DELIMITER ;

DELIMITER //
/*
SP_CONSULTAR_INVENTARIO_PAGINADO
Una pagina de SP_CONSULTAR_INVENTARIO. Mismo filtro y mismas columnas.
Permiso: CONSULTAR_PRODUCTOS.
*/
DROP PROCEDURE IF EXISTS SP_CONSULTAR_INVENTARIO_PAGINADO ;
CREATE PROCEDURE SP_CONSULTAR_INVENTARIO_PAGINADO(
    IN P_FILTRO     VARCHAR(100),
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT
        P.ID_PRODUCTO,
        P.CODIGO,
        P.NOMBRE,
        C.NOMBRE AS CATEGORIA,
        M.NOMBRE AS MARCA,
        I.STOCK_ACTUAL,
        I.STOCK_MINIMO,
        I.UBICACION,
        P.PRECIO,
        P.P_COMPRA,
        CASE
            WHEN IFNULL(I.STOCK_ACTUAL, 0) = 0 THEN 'AGOTADO'
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
           OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
           OR (P_FILTRO REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_FILTRO AS UNSIGNED)))
      AND P.ESTADO = 'ACTIVO'
    ORDER BY P.ID_PRODUCTO ASC
    LIMIT P_POR_PAGINA OFFSET v_offset;
END //
DELIMITER ;

DELIMITER //
/*
SP_CONTAR_INVENTARIO
Cuantos productos devuelve ese filtro, para el paginador de la consulta.
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_INVENTARIO ;
CREATE PROCEDURE SP_CONTAR_INVENTARIO(
    IN P_FILTRO VARCHAR(100)
)
BEGIN
    SELECT COUNT(*) AS TOTAL
      FROM PRODUCTOS P
      LEFT JOIN CATEGORIAS C ON P.ID_CATEGORIA = C.ID_CATEGORIA
     WHERE (P_FILTRO IS NULL OR P_FILTRO = ''
            OR P.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR P.CODIGO LIKE CONCAT('%', P_FILTRO, '%')
            OR C.NOMBRE LIKE CONCAT('%', P_FILTRO, '%')
            OR (P_FILTRO REGEXP '^[0-9]+$' AND P.ID_PRODUCTO = CAST(P_FILTRO AS UNSIGNED)))
       AND P.ESTADO = 'ACTIVO';
END //
DELIMITER ;

DELIMITER //
/*
SP_REPORTE_STOCK_CRITICO_PAGINADO
Una pagina del reporte de stock critico. Permiso: CONSULTAR_PRODUCTOS.
*/
DROP PROCEDURE IF EXISTS SP_REPORTE_STOCK_CRITICO_PAGINADO ;
CREATE PROCEDURE SP_REPORTE_STOCK_CRITICO_PAGINADO(
    IN P_PAGINA     INT,
    IN P_POR_PAGINA INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;

    IF P_PAGINA IS NULL OR P_PAGINA < 1 THEN
        SET P_PAGINA = 1;
    END IF;
    IF P_POR_PAGINA IS NULL OR P_POR_PAGINA < 1 THEN
        SET P_POR_PAGINA = 10;
    END IF;
    SET v_offset = (P_PAGINA - 1) * P_POR_PAGINA;

    SELECT
        P.NOMBRE,
        I.STOCK_ACTUAL,
        I.STOCK_MINIMO,
        (I.STOCK_MINIMO - I.STOCK_ACTUAL) AS CANTIDAD_FALTANTE
    FROM INVENTARIO I
    JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
    WHERE I.STOCK_ACTUAL <= I.STOCK_MINIMO
    ORDER BY CANTIDAD_FALTANTE DESC
    LIMIT P_POR_PAGINA OFFSET v_offset;
END //
DELIMITER ;

DELIMITER //
/*
SP_CONTAR_STOCK_CRITICO
Cuantos productos estan en o bajo su minimo, para el paginador del reporte.
*/
DROP PROCEDURE IF EXISTS SP_CONTAR_STOCK_CRITICO ;
CREATE PROCEDURE SP_CONTAR_STOCK_CRITICO()
BEGIN
    SELECT COUNT(*) AS TOTAL
      FROM INVENTARIO I
      JOIN PRODUCTOS P ON I.ID_PRODUCTO = P.ID_PRODUCTO
     WHERE I.STOCK_ACTUAL <= I.STOCK_MINIMO;
END //
DELIMITER ;
-- (08/11/2026) Se quito el CALL PARA_ACTUALIZARDATOS() suelto que habia aca:
-- se ejecutaba en CADA import y volcaba la tabla de productos como result set
-- (ruido de desarrollo). Ademas el SP ya no lo usa la app.

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

-- 6) Verificación final: listar productos y su proveedor
SELECT ID_PRODUCTO, NOMBRE, ID_PROVEEDOR FROM PRODUCTOS ORDER BY ID_PRODUCTO;

-- Verificar existencia del proveedor 1
SELECT * FROM PROVEEDORES WHERE ID_PROVEEDOR = 1;

-- 1) Añadir columna (permitir NULL temporalmente)
ALTER TABLE PRODUCTOS
ADD COLUMN IF NOT EXISTS ID_PROVEEDOR INT DEFAULT 1 AFTER ID_CATEGORIA;

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
-- Trigger TR_AUDITORIA_PRODUCTOS_UPDATE: auditoria del precio con actor.
-- (12/11/2026) El actor sale de @ID_USUARIO_ACTUAL; antes guardaba USER(),
-- que es el usuario de MySQL y no quien hizo el cambio. Si la variable no
-- esta o el usuario ya no existe, cae a USER().
-- Este trigger es el lider de la cadena de PRODUCTOS: TR_LOG_CAMBIO_ESTADO_PRODUCTO
-- (seccion HISTORIAL_ESTADOS_PRODUCTO, al final de este mismo archivo) declara
-- FOLLOWS sobre el, asi que esta definicion tiene que quedar arriba.
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
            IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER()),
            CONCAT('Precio venta anterior: ', OLD.PRECIO), 
            CONCAT('Precio venta nuevo: ', NEW.PRECIO)
        );
    END IF;
END //
DELIMITER ;




SELECT * FROM `PRODUCTOS`;

-- ================================================================
-- HISTORIAL_ESTADOS_PRODUCTO (ex modulo 18)
-- ================================================================

/*
SECCION HISTORIAL_ESTADOS_PRODUCTO (ex modulo 18)
Bitacora de los cambios ACTIVO/INACTIVO de un producto: la tabla, sus tres
indices, el SP 18_SP_CAMBIAR_ESTADO_PRODUCTO, el trigger que la alimenta y la
vista de los ultimos movimientos. El trigger es AFTER UPDATE ON PRODUCTOS y
declara FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE, que vive mas arriba en este
mismo archivo: las dos definiciones tienen que mantener ese orden.
*/
-- 1. Estructura de la Tabla
/*
TABLA HISTORIAL_ESTADOS_PRODUCTO
Guarda cada vez que un producto cambia de ACTIVO a INACTIVO o viceversa.
Anota quien hizo el cambio, el estado nuevo y el anterior, el motivo y la fecha.
Sirve como bitacora de auditoria: ningun cambio de estado queda sin rastro.
*/
CREATE TABLE HISTORIAL_ESTADOS_PRODUCTO (
    ID_HISTORIAL INT NOT NULL AUTO_INCREMENT,
    ID_PRODUCTO INT NOT NULL,
    -- (12/11/2026) NULL = "no se sabe quien". Antes era NOT NULL y el trigger
    -- caia a IFNULL(@ID_EMPLEADO_ACTUAL, 1): todo cambio sin sesion quedaba
    -- atribuido al empleado 1, que es peor que no saberlo.
    ID_EMPLEADO INT NULL,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL,
    ESTADO_ANTERIOR ENUM('ACTIVO', 'INACTIVO'),
    MOTIVO_CAMBIO VARCHAR(255),
    FECHA_CAMBIO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (ID_HISTORIAL),
    CONSTRAINT FK_HISTORIAL_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO),
    CONSTRAINT FK_HISTORIAL_EMPLEADO FOREIGN KEY (ID_EMPLEADO) REFERENCES EMPLEADOS (ID_EMPLEADO)
) ENGINE = InnoDB;

-- (12/11/2026) En una base existente la columna nacio NOT NULL. Se relaja aca
-- para que el trigger pueda guardar NULL cuando no hay sesion. Es idempotente
-- y no reescribe valores: solo cambia la definicion de la columna.
ALTER TABLE HISTORIAL_ESTADOS_PRODUCTO
    MODIFY COLUMN ID_EMPLEADO INT NULL;

-- 2. Índices para optimizar consultas de auditoría
/*
INDICE HISTORIAL_ESTADOS_PRODUCTO_FECHACAMBIO
Ordena el historial por fecha de cambio, asi los ultimos movimientos
salen primero sin recorrer toda la tabla.
*/
CREATE INDEX HISTORIAL_ESTADOS_PRODUCTO_FECHACAMBIO ON HISTORIAL_ESTADOS_PRODUCTO (FECHA_CAMBIO);
/*
INDICE IX_HISTORIAL_ESTADO_ACTUAL
Busca rapido todos los cambios que quedaron con cierto estado actual.
*/
CREATE INDEX IX_HISTORIAL_ESTADO_ACTUAL ON HISTORIAL_ESTADOS_PRODUCTO (ESTADO);
/*
INDICE IX_HISTORIAL_ESTADO_ANTERIOR
Busca rapido en que estado estaba un producto antes de cambiar,
util para auditoria y reportes de modificaciones.
*/
CREATE INDEX IX_HISTORIAL_ESTADO_ANTERIOR ON HISTORIAL_ESTADOS_PRODUCTO (ESTADO_ANTERIOR);



-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------[Store procedure}-------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------   

DELIMITER //
/* 18_SP_CAMBIAR_ESTADO_PRODUCTO (ELIMINADO 15/11/2026)
Cambiaba el estado del producto y dejaba empleado y motivo en variables de
sesion para que TR_LOG_CAMBIO_ESTADO_PRODUCTO los registrara. Nadie la
llamaba: la app cambia el estado con SP_TOGGLE_ESTADO_PRODUCTOS, que no setea
esas variables, y HISTORIAL_ESTADOS_PRODUCTO no se lee en ningun lado
(item 12.2 de PENDIENTES.md).
Item 12c: se retira la definicion y el DROP limpia las bases que ya la tenian.
*/
DROP PROCEDURE IF EXISTS 18_SP_CAMBIAR_ESTADO_PRODUCTO //
DELIMITER ;


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[TRIGERR}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
DELIMITER //
DROP TRIGGER IF EXISTS TR_LOG_CAMBIO_ESTADO_PRODUCTO //
/*
TR_LOG_CAMBIO_ESTADO_PRODUCTO
Se dispara solo cada vez que cambia el estado de un producto.
Si el estado cambio de verdad, escribe una fila en HISTORIAL_ESTADOS_PRODUCTO
con el producto, el empleado, el estado nuevo, el anterior y el motivo.

(12/11/2026) El empleado sale de @ID_EMPLEADO_ACTUAL sin fallback: si no hay
sesion queda NULL. Antes caia a IFNULL(..., 1) y todo cambio automatico
quedaba atribuido al empleado 1.
*/
CREATE TRIGGER TR_LOG_CAMBIO_ESTADO_PRODUCTO
AFTER UPDATE ON PRODUCTOS
FOR EACH ROW
-- (25/10/2026) Orden fijo: despues de la auditoria de precio del modulo 9.
FOLLOWS TR_AUDITORIA_PRODUCTOS_UPDATE
BEGIN
    -- Solo registramos si hubo un cambio real en el estado
    IF OLD.ESTADO <> NEW.ESTADO THEN
        INSERT INTO HISTORIAL_ESTADOS_PRODUCTO (
            ID_PRODUCTO, 
            ID_EMPLEADO, 
            ESTADO, 
            ESTADO_ANTERIOR,
            MOTIVO_CAMBIO
        )
        VALUES (
            NEW.ID_PRODUCTO,
            @ID_EMPLEADO_ACTUAL,
            NEW.ESTADO,
            OLD.ESTADO,
            -- Registramos el motivo enviado desde la app a través de una variable de sesión
            IFNULL(@MOTIVO_CAMBIO, 'Cambio de estado automático')
        );
    END IF;
END //
DELIMITER ;





----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------[VIEW}-------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------- 


/*
VISTA_ULTIMOS_MOVIMIENTOS
Muestra los 10 cambios de estado mas recientes, del mas nuevo al mas viejo.
Trae la fecha, el nombre del producto y el motivo del cambio.
*/
CREATE OR REPLACE VIEW VISTA_ULTIMOS_MOVIMIENTOS AS
SELECT 
    H.FECHA_CAMBIO,
    P.NOMBRE AS PRODUCTO,
    H.MOTIVO_CAMBIO
FROM HISTORIAL_ESTADOS_PRODUCTO H
JOIN PRODUCTOS P ON H.ID_PRODUCTO = P.ID_PRODUCTO
ORDER BY H.FECHA_CAMBIO DESC
LIMIT 10;





-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------[FUNTION}---------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------