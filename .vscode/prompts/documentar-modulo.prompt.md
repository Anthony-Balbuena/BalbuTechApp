---
description: Genera comentarios con guiones (--) detallando uso, descripción numerada y parámetros encima de cada objeto SQL.
---

Tu tarea es analizar el archivo SQL activo e INSERTAR COMENTARIOS DE LÍNEA (`--`) justo encima de CADA objeto (Procedimientos Almacenados, Triggers, Funciones, Tablas e Índices).

Manten el código SQL intacto y aplica estrictamente estas plantillas de comentarios:

1. Encima de PROCEDIMIENTOS ALMACENADOS (`CREATE PROCEDURE`):
-- uso de [Propósito en lenguaje natural, ej: agregar un usuario]
-- Descripción:
--   [Explicación concisa de lo que realiza el procedimiento]
--   1) [Primera validación o comprobación inicial]
--   2) [Segunda validación o regla de negocio]
--   3) [Paso de limpieza, transformación o normalización de datos]
--   4) [Verificación de duplicados o disponibilidad]
--   5) [Operación principal: INSERT / UPDATE / DELETE]
--   6) [Respuesta esperada o manejo de excepciones con SIGNAL]
-- Parámetros:
--   [Lista de parámetros con sus tipos, ej: P_ID_EMPLEADO INT, P_USUARIO VARCHAR(50)]

2. Encima de TRIGGERS (`CREATE TRIGGER`):
-- uso de [Disparador automático al realizar X acción]
-- Descripción:
--   Se ejecuta [BEFORE/AFTER] de un [INSERT/UPDATE/DELETE] en la tabla [NOMBRE_TABLA]:
--   1) [Comprobación automática que realiza]
--   2) [Cálculo o actualización secundaria en otra tabla]
--   3) [Validación final o lanzamiento de error SIGNAL si no cumple la regla]

3. Encima de TABLAS (`CREATE TABLE`):
-- uso de [Propósito de la tabla, ej: Almacenar la asistencia diaria de los empleados]
-- Descripción:
--   Almacena los registros de [Nombre Entidad] en el sistema.
--   Campos principales:
--     - [COLUMNA_1]: [Para qué sirve]
--     - [COLUMNA_2]: [Para qué sirve]
--   Reglas y Restricciones:
--     - Clave primaria ([PRIMARY KEY])
--     - Llave foránea hacia [TABLA_PADRE]
--     - [Validación UNIQUE / CHECK de la tabla]

4. Encima de ÍNDICES Y FUNCIONES (`CREATE INDEX` / `CREATE FUNCTION`):
-- uso de [Optimizar búsquedas por X campo / Función para calcular Y]
-- Descripción:
--   1) [Propósito y detalle de la operación o aceleración en la base de datos]
-- Parámetros / Retorno:
--   [Detalle de entrada/salida si aplica]

Devuelve el código SQL completo preservando todas las sentencias originales e insertando los comentarios `--` arriba de cada objeto.
