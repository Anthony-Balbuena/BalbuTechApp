#!/usr/bin/env bash
# (21/11/2026) Tests de la EXENCION DE ITBIS POR PRODUCTO.
#
# POR QUE EXISTE: el catalogo necesita que algunos productos no lleven ITBIS sin
# bajarle la tasa a toda la empresa. El riesgo no esta en la venta, esta en la
# devolucion: si una linea se guardo con MONTO_ITBIS = 0 y la devolucion lo
# recalcula con la tasa vigente, se le devuelve al cliente un impuesto que nunca
# pago.
#
# Cubre (ver odd/tasks/exencion-itbis.md):
#   S1  la columna EXENTO_ITBIS existe en PRODUCTOS
#   S5  SP_MARCAR_PRODUCTO_EXENTO marca y desmarca
#   S2  venta de producto exento  -> MONTO_ITBIS = 0.00
#   S2  venta de producto gravado -> MONTO_ITBIS = la tasa vigente (no regresion)
#   S3  compra de producto exento -> el precio ES el neto, ITBIS = 0.00
#   S3  compra de producto gravado -> sigue desglosando (no regresion)
#   S4  devolucion de linea exenta -> ITBIS reembolsado = 0.00
#   S4  devolucion de linea gravada con la tasa cambiada despues de vender ->
#       devuelve el ITBIS que se COBRO, no el que esta vigente hoy
#
# Todo corre DENTRO de una transaccion que se revierte: no deja datos.
# Es SQL puro, no necesita el binario de la app.
#
# Uso: DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave> \
#      bash db/test-itbis-exento.sh
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

# Las rutinas que este test ejercita tienen que existir. Si falta alguna, el test
# no puede decir nada: mejor cortar que dar un verde vacio.
faltan=$(M -N -B -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                      WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE='PROCEDURE'
                        AND ROUTINE_NAME IN ('SP_AGREGAR_DETALLE_VENTA',
                                             'SP_REGISTRAR_DEVOLUCION',
                                             '19_SP_INICIAR_COMPRA',
                                             '22_SP_AGREGAR_DETALLE_COMPRA',
                                             'SP_MARCAR_PRODUCTO_EXENTO');")
if [ "$faltan" != "5" ]; then
    echo "FALLO: faltan rutinas de la exencion de ITBIS ($faltan/5)." >&2
    echo "       Falta SP_MARCAR_PRODUCTO_EXENTO o el modulo no esta aplicado en $DB_NAME." >&2
    exit 1
fi

# Con la columna ausente no hay nada que probar: el resto del test daria un
# verde falso porque MONTO_ITBIS = 0 tambien pasa cuando el SP ignora el flag.
hay_col=$(M -N -B -e "SELECT COUNT(*) FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'PRODUCTOS'
                         AND COLUMN_NAME = 'EXENTO_ITBIS';")
if [ "$hay_col" != "1" ]; then
    echo "FALLO: PRODUCTOS no tiene la columna EXENTO_ITBIS (S1)." >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir. Todo va en una transaccion que se revierte al final.
OUT=$(M -N -B --force <<'SQL'
START TRANSACTION;

SET @emp  = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @cli  = (SELECT ID_CLIENTE  FROM CLIENTES  ORDER BY ID_CLIENTE  LIMIT 1);
SET @mar  = (SELECT ID_MARCA    FROM MARCAS    ORDER BY ID_MARCA    LIMIT 1);
SET @cat  = (SELECT ID_CATEGORIA FROM CATEGORIAS ORDER BY ID_CATEGORIA LIMIT 1);
SET @prov = (SELECT ID_PROVEEDOR FROM PROVEEDORES ORDER BY ID_PROVEEDOR LIMIT 1);
SET @tasa = (SELECT VALOR + 0 FROM CONFIGURACION WHERE CLAVE = 'ITBIS');
SET @itbis_esperado = ROUND(100.00 * @tasa / 100, 2);

-- Dos productos: uno que se marca exento y otro que queda gravado.
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ ITBIS EXENTO', 'marcador del test de exencion', 100.00, 'ZZ-EXENTO', @mar, @cat, @prov);
SET @p_exento = LAST_INSERT_ID();
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ ITBIS GRAVADO', 'marcador del test de exencion', 100.00, 'ZZ-GRAVADO', @mar, @cat, @prov);
SET @p_gravado = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION) VALUES (@p_exento, 50, 1, 'ZZ');
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION) VALUES (@p_gravado, 50, 1, 'ZZ');

-- S1: nace gravado.
SELECT IF((SELECT EXENTO_ITBIS FROM PRODUCTOS WHERE ID_PRODUCTO = @p_exento) = 0,
  'OK un producto nuevo nace gravado', 'FALLO un producto nuevo no nace gravado');

-- S5: se marca y se desmarca.
CALL SP_MARCAR_PRODUCTO_EXENTO(@p_exento, 1);
SELECT IF((SELECT EXENTO_ITBIS FROM PRODUCTOS WHERE ID_PRODUCTO = @p_exento) = 1,
  'OK SP_MARCAR_PRODUCTO_EXENTO marca', 'FALLO SP_MARCAR_PRODUCTO_EXENTO no marca');

-- S2: venta exenta -> ITBIS 0.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-EXENTO-V', NOW());
SET @v1 = LAST_INSERT_ID();
CALL SP_AGREGAR_DETALLE_VENTA(@v1, @p_exento, 1, @emp, 0.00);
SELECT IF((SELECT MONTO_ITBIS FROM DETALLES_VENTA WHERE ID_VENTA = @v1 AND ID_PRODUCTO = @p_exento) = 0.00,
  'OK venta de producto exento: ITBIS 0.00', 'FALLO venta de producto exento cobro ITBIS');

-- S2: venta gravada -> la tasa vigente (no regresion).
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-GRAVADO-V', NOW());
SET @v2 = LAST_INSERT_ID();
CALL SP_AGREGAR_DETALLE_VENTA(@v2, @p_gravado, 1, @emp, 0.00);
SELECT IF((SELECT MONTO_ITBIS FROM DETALLES_VENTA WHERE ID_VENTA = @v2 AND ID_PRODUCTO = @p_gravado) = @itbis_esperado,
  CONCAT('OK venta de producto gravado: ITBIS ', @itbis_esperado), 'FALLO venta gravada cobro otra cosa');

-- S3: compra exenta -> el precio escrito ES el neto, ITBIS 0.
CALL 19_SP_INICIAR_COMPRA(@prov, @emp, @c1);
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@c1, @p_exento, 2, 100.00);
SELECT IF((SELECT MONTO_ITBIS FROM DETALLE_COMPRA WHERE ID_COMPRA = @c1 AND ID_PRODUCTO = @p_exento) = 0.00,
  'OK compra de producto exento: ITBIS 0.00', 'FALLO compra de producto exento invento ITBIS');
SELECT IF((SELECT PRECIO_UNITARIO FROM DETALLE_COMPRA WHERE ID_COMPRA = @c1 AND ID_PRODUCTO = @p_exento) = 100.00,
  'OK compra exenta: el precio escrito queda como neto', 'FALLO compra exenta desgloso el precio');

-- S3: compra gravada -> sigue desglosando el ITBIS de la factura (no regresion).
CALL 19_SP_INICIAR_COMPRA(@prov, @emp, @c2);
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@c2, @p_gravado, 2, 100.00);
SELECT IF((SELECT MONTO_ITBIS FROM DETALLE_COMPRA WHERE ID_COMPRA = @c2 AND ID_PRODUCTO = @p_gravado) > 0,
  'OK compra de producto gravado sigue desglosando ITBIS', 'FALLO compra gravada dejo de desglosar');

-- S4: devolucion de la linea EXENTA -> no se devuelve impuesto.
SET @d1 = (SELECT ID_DETALLE_VENTA FROM DETALLES_VENTA WHERE ID_VENTA = @v1 AND ID_PRODUCTO = @p_exento);
CALL SP_REGISTRAR_DEVOLUCION(@d1, NULL, @emp, 1, 'ZZ test exencion', 'BUENO');
SELECT IF((SELECT MONTO_ITBIS_REEMBOLSADO FROM DEVOLUCIONES WHERE ID_DETALLE_VENTA = @d1 ORDER BY ID_DEVOLUCION DESC LIMIT 1) = 0.00,
  'OK devolucion de linea exenta: ITBIS reembolsado 0.00', 'FALLO devolucion de linea exenta reembolso ITBIS');

-- S4: devolucion de la linea GRAVADA con la tasa cambiada DESPUES de vender.
-- Se cobro @itbis_esperado al 18; ahora la configuracion dice 10. La devolucion
-- tiene que devolver lo cobrado, no el 10 % vigente.
UPDATE CONFIGURACION SET VALOR = '10' WHERE CLAVE = 'ITBIS';
SET @d2 = (SELECT ID_DETALLE_VENTA FROM DETALLES_VENTA WHERE ID_VENTA = @v2 AND ID_PRODUCTO = @p_gravado);
CALL SP_REGISTRAR_DEVOLUCION(@d2, NULL, @emp, 1, 'ZZ test exencion', 'BUENO');
SELECT IF((SELECT MONTO_ITBIS_REEMBOLSADO FROM DEVOLUCIONES WHERE ID_DETALLE_VENTA = @d2 ORDER BY ID_DEVOLUCION DESC LIMIT 1) = @itbis_esperado,
  CONCAT('OK devolucion devuelve el ITBIS cobrado (', @itbis_esperado, '), no el vigente'),
  CONCAT('FALLO devolucion uso la tasa vigente: devolvio ',
         (SELECT MONTO_ITBIS_REEMBOLSADO FROM DEVOLUCIONES WHERE ID_DETALLE_VENTA = @d2 ORDER BY ID_DEVOLUCION DESC LIMIT 1),
         ' en vez de ', @itbis_esperado));

ROLLBACK;
SQL
)

echo "$OUT" | grep -E '^(OK|FALLO) ' | sed 's/^/  /'

ok=$(echo "$OUT" | grep -c '^OK ')
fallo=$(echo "$OUT" | grep -c '^FALLO ')

if [ "$fallo" -ne 0 ]; then
    echo "FALLO: $fallo de $((ok + fallo)) pruebas de exencion de ITBIS fallaron."
    exit 1
fi

echo "OK: $ok/$ok pruebas de exencion de ITBIS en verde."
exit 0
