-- ================================================================
-- BALBU_TECH - PERMISOS FINOS DE METODOS DE PAGO
-- ================================================================
-- (23/10/2026) Separa el modulo Metodos de pago en cuatro permisos finos, con
-- el mismo corte que Clientes, Proveedores, Categorias y Marcas:
-- METODOS_PAGO_VER, METODOS_PAGO_CREAR, METODOS_PAGO_EDITAR y
-- METODOS_PAGO_ESTADO reemplazan al paraguas GESTIONAR_METODOS_PAGO.
--
-- ORDEN DE DESPLIEGUE:
--   1. Compilar y desplegar el binario nuevo.
--   2. Hacer backup de la base viva.
--   3. Correr este modulo.
-- El binario viejo sigue pidiendo GESTIONAR_METODOS_PAGO; si este modulo corre
-- antes, el item Metodos de pago desaparece del menu hasta desplegar el
-- binario nuevo. No se pierden datos: solo se oculta el modulo.
--
-- Idempotente: se puede correr dos veces.

INSERT INTO PERMISOS (NOMBRE_PERMISO, DESCRIPCION) VALUES
('METODOS_PAGO_VER', 'Consultar y buscar metodos de pago'),
('METODOS_PAGO_CREAR', 'Registrar metodos de pago'),
('METODOS_PAGO_EDITAR', 'Actualizar datos de metodos de pago'),
('METODOS_PAGO_ESTADO', 'Activar o desactivar metodos de pago')
ON DUPLICATE KEY UPDATE DESCRIPCION = VALUES(DESCRIPCION);

-- Matriz objetivo: ADMIN, GERENTE y SUBGERENTE reciben los cuatro permisos
-- finos. (26/10/2026) VENDEDOR solo METODOS_PAGO_VER: consulta los metodos
-- existentes, no los mantiene. El SELECT no lee ROL_PERMISO, asi que el
-- ON DUPLICATE KEY UPDATE no es ambiguo.
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT R.NOMBRE_ROL, P.ID_PERMISO
FROM ROLES R
JOIN PERMISOS P ON (
    (R.NOMBRE_ROL IN ('ADMIN', 'GERENTE', 'SUBGERENTE')
        AND P.NOMBRE_PERMISO IN (
            'METODOS_PAGO_VER', 'METODOS_PAGO_CREAR',
            'METODOS_PAGO_EDITAR', 'METODOS_PAGO_ESTADO'))
    OR (R.NOMBRE_ROL = 'VENDEDOR' AND P.NOMBRE_PERMISO = 'METODOS_PAGO_VER')
)
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- (26/10/2026) VENDEDOR ya no mantiene metodos de pago: si una corrida
-- anterior le asigno los tres de gestion, se los quita.
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE RP.ROL_NOMBRE = 'VENDEDOR'
  AND P.NOMBRE_PERMISO IN (
      'METODOS_PAGO_CREAR', 'METODOS_PAGO_EDITAR', 'METODOS_PAGO_ESTADO'
  );

-- Borra el paraguas viejo en cualquier rol (incluidos los personalizados).
DELETE RP
FROM ROL_PERMISO RP
INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO
WHERE P.NOMBRE_PERMISO = 'GESTIONAR_METODOS_PAGO';

-- Y lo saca del catalogo. El ON DELETE CASCADE de ROL_PERMISO ya no tiene
-- pares que limpiar.
DELETE FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_METODOS_PAGO';

SELECT 'PERMISOS DE METODOS DE PAGO APLICADOS.' AS RESULTADO;
