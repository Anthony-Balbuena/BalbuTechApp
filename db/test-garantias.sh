#!/usr/bin/env bash
# Test de Garantias (modulo 63) — 30/10/2026.
# Verifica el registro automatico al confirmar la venta, el alta manual con
# autor, la validacion por fecha al reclamar, el cierre con autor y fecha, y
# que SP_MARCAR_GARANTIAS_VENCIDAS escriba el estado VENCIDA.
# Todo corre en una transaccion que se revierte al final.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-garantias.sh
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

if ! M < "modulos/63- GARANTIAS_FLUJO.sql" >/dev/null; then
    echo "FALLO: no se pudo aplicar modulos/63- GARANTIAS_FLUJO.sql" >&2
    exit 1
fi

# (04/11/2026) Reimportar el modulo 63 reescribe sus SPs SIN la guarda de
# permisos. Si no se repone, check-app-sps.sh falla despues del test con
# "FALTA la guarda en 7". El inyector guarda dump de las originales antes de
# tocar nada. Como el test conecta con DB_ADMIN_USER, la guarda no bloquea
# sus llamadas (SP_EXIGIR_PERMISO exime a root/balbu_admin).
if ! python3 db/injectar-guardas.py "$DB_NAME" --aplicar >/dev/null 2>&1; then
    echo "FALLO: no se pudieron reinyectar las guardas tras importar el modulo 63" >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK. La ausencia de la fila se verifica aparte.
OUT=$(M --force <<'SQL'
START TRANSACTION;

SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @met = (SELECT ID_METODO_PAGO FROM METODOS_PAGO ORDER BY ID_METODO_PAGO LIMIT 1);

INSERT INTO CATEGORIAS (NOMBRE) VALUES ('ZZ GAR 63 CAT');
SET @cat = LAST_INSERT_ID();
INSERT INTO PROVEEDORES (NOMBRE) VALUES ('ZZ GAR 63 PROV');
SET @prov = LAST_INSERT_ID();
INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
VALUES ('ZZ GAR 63 CLI', '8090000063', 'zz63@test.local', 'x');
SET @cli = LAST_INSERT_ID();

-- Producto CON dias de garantia (30) y producto SIN dias.
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO,
                       ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, DIAS_GARANTIA)
VALUES ('ZZ GAR 63 P30', 'Producto con garantia automatica', 100.00, 0.00,
        'ZZ63-P30', 'ACTIVO', @mar, @cat, @prov, 30);
SET @prod = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@prod, 10, 1, 'ZZ');

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO,
                       ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, DIAS_GARANTIA)
VALUES ('ZZ GAR 63 P0', 'Producto sin garantia automatica', 50.00, 0.00,
        'ZZ63-P0', 'ACTIVO', @mar, @cat, @prov, NULL);
SET @prod0 = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@prod0, 5, 1, 'ZZ');

-- Venta 1: se cobra completa y el trigger TR_AUTO_FINALIZAR_VENTA la pasa a
-- REALIZADA; ahi TR_REGISTRAR_GARANTIA_VENTA crea la garantia sola.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL)
VALUES ('EN_PROCESO', @emp, @cli, 0);
SET @venta = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
VALUES (@venta, @prod, 2, 100.00, 0.00);
SET @det = LAST_INSERT_ID();
INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, ID_EMPLEADO, MONTO)
VALUES (@venta, @met, @emp, 200.00);

SELECT 'AUTO_CREADA' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS WHERE ID_DETALLE_VENTA = @det;

SELECT 'AUTO_AUTOR' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS
 WHERE ID_DETALLE_VENTA = @det
   AND ID_EMPLEADO = @emp
   AND FECHA_REGISTRO IS NOT NULL;

SELECT 'AUTO_DIAS' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS
 WHERE ID_DETALLE_VENTA = @det
   AND FECHA_FIN = DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY)
   AND ESTADO = 'ACTIVA';

SET @gar = (SELECT ID_GARANTIA FROM GARANTIAS WHERE ID_DETALLE_VENTA = @det);

-- Venta 2: producto sin DIAS_GARANTIA, queda EN_PROCESO. No debe tener
-- garantia automatica.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL)
VALUES ('EN_PROCESO', @emp, @cli, 0);
SET @venta0 = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
VALUES (@venta0, @prod0, 1, 50.00, 0.00);
SET @det0 = LAST_INSERT_ID();

SELECT 'SIN_DIAS_NO_CREA' AS CASO, IF(COUNT(*) = 0, 'OK', 'FAIL') AS RES
  FROM GARANTIAS WHERE ID_DETALLE_VENTA = @det0;

-- Alta manual (respaldo de ventas viejas): autor y dias pedidos.
CALL SP_REGISTRAR_GARANTIA(@det0, 45, @emp);

SELECT 'MANUAL_AUTOR_DIAS' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS
 WHERE ID_DETALLE_VENTA = @det0
   AND ID_EMPLEADO = @emp
   AND FECHA_FIN = DATE_ADD(CURRENT_DATE, INTERVAL 45 DAY);

-- Alta manual duplicada: debe fallar con "YA TIENE UNA GARANTIA".
CALL SP_REGISTRAR_GARANTIA(@det0, 45, @emp);

SELECT 'MANUAL_DUPLICADA_NO_INSERTA' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS WHERE ID_DETALLE_VENTA = @det0;

-- Las lineas de la venta 1: el SP marca que ya tienen garantia.
CALL SP_LINEAS_VENTA_CON_GARANTIA(@venta);

-- Reclamar dentro de fecha: funciona y guarda autor.
CALL 27_SP_REGISTRAR_RECLAMO_GARANTIA(@gar, 'ZZ reclamo dentro de fecha', @emp);

SELECT 'RECLAMO_OK' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM RECLAMOS_GARANTIAS
 WHERE ID_GARANTIA = @gar
   AND ID_EMPLEADO = @emp
   AND ESTADO = 'PENDIENTE';

SET @rec = (SELECT ID_RECLAMO_GARAN FROM RECLAMOS_GARANTIAS
             WHERE ID_GARANTIA = @gar ORDER BY ID_RECLAMO_GARAN DESC LIMIT 1);

-- Finalizar desde PENDIENTE: cierra y guarda autor y fecha de cierre.
CALL 27_SP_FINALIZAR_RECLAMO_TOTAL(@rec, @emp);

SELECT 'FINALIZAR_OK' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM RECLAMOS_GARANTIAS
 WHERE ID_RECLAMO_GARAN = @rec
   AND ESTADO = 'CERRADO'
   AND ID_EMPLEADO_CIERRE = @emp
   AND FECHA_CIERRE IS NOT NULL;

-- Finalizar un CERRADO: debe fallar.
CALL 27_SP_FINALIZAR_RECLAMO_TOTAL(@rec, @emp);

SELECT 'CERRADO_SIGUE_CERRADO' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM RECLAMOS_GARANTIAS
 WHERE ID_RECLAMO_GARAN = @rec AND ESTADO = 'CERRADO';

-- Garantia ACTIVA con fecha de fin pasada: reclamar debe fallar por fecha.
UPDATE GARANTIAS
   SET FECHA_INICIO = DATE_SUB(CURRENT_DATE, INTERVAL 10 DAY),
       FECHA_FIN = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY),
       ESTADO = 'ACTIVA'
 WHERE ID_GARANTIA = @gar;

CALL 27_SP_REGISTRAR_RECLAMO_GARANTIA(@gar, 'ZZ reclamo vencido', @emp);

SELECT 'VENCIDA_NO_RECLAMA' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM RECLAMOS_GARANTIAS WHERE ID_GARANTIA = @gar;

-- El proceso que nunca escribia VENCIDA ahora la escribe.
CALL SP_MARCAR_GARANTIAS_VENCIDAS();

SELECT 'MARCA_VENCIDA' AS CASO, IF(COUNT(*) = 1, 'OK', 'FAIL') AS RES
  FROM GARANTIAS WHERE ID_GARANTIA = @gar AND ESTADO = 'VENCIDA';

ROLLBACK;
SQL
)

echo "$OUT"

FAILS=$(printf '%s\n' "$OUT" | grep -c 'FAIL' || true)
OKS=$(printf '%s\n' "$OUT" | grep -c 'OK' || true)

# Los tres errores esperados tienen que aparecer en la salida.
ESPERADOS=0
for MSG in "YA TIENE UNA GARANT" "SOLO SE CIERRAN RECLAMOS" "VENCIDA POR FECHA"; do
    if printf '%s\n' "$OUT" | grep -q "$MSG"; then
        ESPERADOS=$((ESPERADOS + 1))
    else
        echo "FALLO: no aparecio el error esperado: $MSG"
    fi
done
echo "Errores esperados vistos: $ESPERADOS/3"

# SP_LINEAS_VENTA_CON_GARANTIA tiene que devolver la linea con TIENE = SI.
LINEAS=0
if printf '%s\n' "$OUT" | grep -q 'ZZ GAR 63 P30.*SI'; then
    LINEAS=1
else
    echo "FALLO: SP_LINEAS_VENTA_CON_GARANTIA no marco la linea como garantizada"
fi

echo "Total: $OKS OK, $FAILS FAIL"
[ "$FAILS" -eq 0 ] && [ "$ESPERADOS" -eq 3 ] && [ "$LINEAS" -eq 1 ]
