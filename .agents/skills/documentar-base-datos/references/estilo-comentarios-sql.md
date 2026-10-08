# Estilo: comentarios dentro del `.sql`

Estilo **hibrido minimalista**: bloques `/* ... */` de 4 a 6 líneas, en lenguaje
coloquial, que solo expliquen la función de cada objeto.

Fuente original: `.vscode/prompts/descipcion_modulos.prompt.md` (los 5 ejemplos
de abajo se migraron de ahí sin cambios).

---

## Instrucción de análisis previo

1. Primero, leer y escanear el archivo SQL completo de principio a fin para hacer
   un inventario mental de todo lo que contiene (tablas, procedimientos
   almacenados / SP, triggers / TR, funciones / TF, vistas / VIEW).
2. Después, procesar el código aplicando las descripciones cortas **únicamente a
   los objetos que realmente estén presentes en el archivo**. Si un tipo de
   objeto no existe en el código, se salta por completo: no se inventa nada.

## Reglas estrictas

1. Bloques de comentarios cortos (`/* ... */`) de una o dos frases que expliquen
   el propósito general del objeto.
2. **ESTRICTAMENTE PROHIBIDO** enlistar columnas, campos o parámetros campo por
   campo dentro de los comentarios. La estructura del código ya habla por sí sola.
3. Ignorar y limpiar cualquier comentario viejo o basura que tenga el archivo
   original.
4. Mantener el motor InnoDB, las claves primarias, foráneas y los índices
   necesarios.

---

## Ejemplos de cómo debe quedar

### Ejemplo 1 — Tabla

```sql
/*
DESCRIPCION DEL MODULO DE MARCAS
Almacena las marcas de productos disponibles en el sistema.
*/
CREATE TABLE MARCAS (
    ID_MARCA INT NOT NULL AUTO_INCREMENT,
    NOMBRE VARCHAR(50) NOT NULL UNIQUE,
    ESTADO ENUM('ACTIVO', 'INACTIVO') NOT NULL DEFAULT 'ACTIVO',
    PRIMARY KEY (ID_MARCA)
) ENGINE = InnoDB;
```

### Ejemplo 2 — Procedimiento almacenado (SP)

```sql
/*
DESCRIPCION DEL SP INSERTAR_MARCA
Registra una nueva marca validando que el nombre no esté duplicado.
*/
DELIMITER //
CREATE PROCEDURE INSERTAR_MARCA(IN P_NOMBRE VARCHAR(50))
BEGIN
    -- Lógica...
END //
DELIMITER ;
```

### Ejemplo 3 — Trigger (TR)

```sql
/*
DESCRIPCION DEL TRIGGER TR_VALIDAR_BONO
Evita que se registren bonos con fechas de más de 60 días de antigüedad.
*/
CREATE TRIGGER TR_VALIDAR_BONO
BEFORE INSERT ON BONOS_EMPLEADOS
FOR EACH ROW
BEGIN
    -- Lógica.
END;
```

### Ejemplo 4 — Función (TF)

```sql
/*
DESCRIPCION DE LA FUNCION FN_CALCULAR_IMPUESTO
Calcula el impuesto correspondiente al subtotal de una venta.
*/
CREATE FUNCTION FN_CALCULAR_IMPUESTO(P_SUBTOTAL DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    RETURN P_SUBTOTAL * 0.18;
END;
```

### Ejemplo 5 — Vista (VIEW)

```sql
/*
DESCRIPCION DE LA VISTA VW_REPORTE_VENTAS
Muestra un resumen consolidado de las ventas realizadas por cada empleado.
*/
CREATE VIEW VW_REPORTE_VENTAS AS
SELECT ID_EMPLEADO, COUNT(*) AS TOTAL_VENTAS FROM VENTAS GROUP BY ID_EMPLEADO;
```

---

## Verificación

- Conteo: objetos `CREATE` == bloques de descripción.
- `/*` y `*/` balanceados en todo el archivo.
- `git diff` → solo líneas agregadas con `/* ... */`, cero SQL eliminado o modificado.
