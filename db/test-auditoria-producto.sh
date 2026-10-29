#!/usr/bin/env bash
# Test de auditoria con actor (modulo 61) — 29/10/2026.
# Verifica que clientes y productos guarden el usuario de la sesion, y que
# el historial de estado de producto guarde el empleado de la sesion o NULL
# si no hay empleado. Todo corre en una transaccion que se revierte.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-auditoria-producto.sh
set -u

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 1

M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }

if ! M < "modulos/61- AUDITORIA_ACTOR.sql" >/dev/null; then
    echo "FALLO: no se pudo aplicar modulos/61- AUDITORIA_ACTOR.sql" >&2
    exit 1
fi

OUT=$(M -N <<'SQL'
START TRANSACTION;

SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @uid = (SELECT ID_USUARIO FROM USUARIOS ORDER BY ID_USUARIO LIMIT 1);
SET @usr = (SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @uid);
SET @ID_USUARIO_ACTUAL = @uid;

-- Producto de prueba con su cadena de referencias. Todo se revierte al final
-- para que TEST quede igual, aunque no tenga productos propios.
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
INSERT INTO CATEGORIAS (NOMBRE) VALUES ('ZZ AUDIT 61 CAT');
SET @cat = LAST_INSERT_ID();
INSERT INTO PROVEEDORES (NOMBRE) VALUES ('ZZ AUDIT 61 PROV');
SET @prov = LAST_INSERT_ID();
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ AUDIT 61 P', 'Producto de prueba de auditoria', 100.00, 0.00, 'ZZ61-P', 'ACTIVO', @mar, @cat, @prov);
SET @prod = LAST_INSERT_ID();
SET @estado = 'ACTIVO';
SET @precio = 100.00;

-- 1. Con empleado y usuario en la conexion.
SET @ID_EMPLEADO_ACTUAL = @emp;
SET @MOTIVO_CAMBIO = 'ZZ AUDIT 61';
UPDATE PRODUCTOS
   SET ESTADO = IF(@estado = 'ACTIVO', 'INACTIVO', 'ACTIVO'),
       PRECIO = @precio + 1
 WHERE ID_PRODUCTO = @prod;

SELECT 'EMPLEADO_HIST' AS CASO,
       IF(COUNT(*) >= 1, 'OK', 'FAIL') AS RES
  FROM HISTORIAL_ESTADOS_PRODUCTO
 WHERE ID_PRODUCTO = @prod
   AND ID_EMPLEADO = @emp
   AND MOTIVO_CAMBIO = 'ZZ AUDIT 61';

SELECT 'PRODUCTO_AUDIT' AS CASO,
       IF(COUNT(*) >= 1, 'OK', 'FAIL') AS RES
  FROM AUDITORIA_SISTEMA
 WHERE TABLA_AFECTADA = 'PRODUCTOS'
   AND ID_REGISTRO_AFECTADO = @prod
   AND ACCION = 'UPDATE'
   AND USUARIO_SISTEMA = @usr
   AND VALOR_NUEVO LIKE 'Precio venta nuevo:%';

-- 2. Sin empleado: el historial debe quedar en NULL, no en el empleado 1.
SET @ID_EMPLEADO_ACTUAL = NULL;
SET @MOTIVO_CAMBIO = 'ZZ AUDIT 62';
UPDATE PRODUCTOS
   SET ESTADO = @estado,
       PRECIO = @precio
 WHERE ID_PRODUCTO = @prod;

SELECT 'SIN_EMPLEADO_NULL' AS CASO,
       IF(COUNT(*) >= 1, 'OK', 'FAIL') AS RES
  FROM HISTORIAL_ESTADOS_PRODUCTO
 WHERE ID_PRODUCTO = @prod
   AND ID_EMPLEADO IS NULL
   AND MOTIVO_CAMBIO = 'ZZ AUDIT 62';

-- 3. Clientes: INSERT y UPDATE con el usuario de la sesion.
INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
VALUES ('ZZ AUDIT 61', '8090000061', 'zz61@test.local', 'x');
SET @cli = LAST_INSERT_ID();
UPDATE CLIENTES SET NOMBRE = 'ZZ AUDIT 61 B' WHERE ID_CLIENTE = @cli;

SELECT 'CLIENTE_INSERT' AS CASO,
       IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM AUDITORIA_SISTEMA
 WHERE TABLA_AFECTADA = 'CLIENTES'
   AND ID_REGISTRO_AFECTADO = @cli
   AND ACCION = 'INSERT'
   AND USUARIO_SISTEMA = @usr;

SELECT 'CLIENTE_UPDATE' AS CASO,
       IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM AUDITORIA_SISTEMA
 WHERE TABLA_AFECTADA = 'CLIENTES'
   AND ID_REGISTRO_AFECTADO = @cli
   AND ACCION = 'UPDATE'
   AND USUARIO_SISTEMA = @usr;

ROLLBACK;
SQL
)

echo "$OUT"
FAILS=$(printf '%s\n' "$OUT" | grep -c 'FAIL' || true)
OKS=$(printf '%s\n' "$OUT" | grep -c 'OK' || true)
echo "Total: $OKS OK, $FAILS FAIL"
[ "$FAILS" -eq 0 ]
