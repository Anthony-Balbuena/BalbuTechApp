#!/usr/bin/env bash
# Test del barrido de borradores vacios (15/11/2026, opcion D de P-4).
#
# Regla: al entrar a la app se cancelan SOLO las ventas EN_PROCESO sin lineas
# que pasaron el plazo de cobro (48 h). No retienen stock y no se pueden cobrar.
#
# Cubre:
#   1. Un borrador vacio y viejo SE cancela.
#   2. Un borrador vacio pero RECIENTE no se toca.
#   3. Una venta VIEJA CON LINEAS no se toca. Es la asercion que importa: esa
#      puede ser un apartado legitimo y cancelarla le borraria la venta a un
#      cajero. El barrido nunca debe tocarla.
#   4. La cancelacion deja su rastro en HISTORIAL_ESTADOS_VENTA.
#
# Uso:
#   DB_NAME=BALBU_TECH_TEST BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=<u> BALBU_PASS=<p> \
#   bash db/test-borradores-barrido.sh
# Este test ESCRIBE y COMMITEA (la app es otra conexion): usa marcadores ZZ-BARR
# y los borra al salir. Solo corre contra BALBU_TECH_TEST.
set -u
export BALBU_ALLOW_DEV_LOGIN=1

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-25}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS}"
HORAS="${HORAS:-48}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 1

if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi

APP_ABS="$(pwd)/${APP#./}"
M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }
N() { mariadb -N -B -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -e "$1"; }

# TR_BLOQUEAR_BORRADO_VENTA no deja borrar ventas ni con bandera: se saca y se
# vuelve a crear. --force + CREATE ULTIMO, para que el candado vuelva aunque un
# DELETE falle. Las lineas se van por FK ON DELETE CASCADE.
limpiar_db() {
    M --force >/dev/null 2>&1 <<'SQL'
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_VENTA;
DELETE FROM HISTORIAL_ESTADOS_VENTA WHERE ID_VENTA IN
    (SELECT ID_VENTA FROM VENTAS WHERE FACTURA LIKE 'ZZ-BARR%');
DELETE FROM VENTAS WHERE FACTURA LIKE 'ZZ-BARR%';
DELETE FROM HISTORIAL_MOVIMIENTOS_PRODUCTO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ BARRIDO');
DELETE FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ BARRIDO');
DELETE FROM INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ BARRIDO');
DELETE FROM PRODUCTOS WHERE NOMBRE = 'ZZ BARRIDO';
CREATE TRIGGER TR_BLOQUEAR_BORRADO_VENTA
BEFORE DELETE ON VENTAS
FOR EACH ROW
SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.';
SQL
}
TMP="$(mktemp -d "${TMPDIR:-/tmp}/borradores-barrido.XXXXXX")"
limpiar() { limpiar_db; rm -rf "$TMP"; }
trap limpiar EXIT

fail=0
ok()    { echo "OK    $1"; }
fallo() { echo "FALLO $1: $2"; fail=1; }

# ---------------------------------------------------------------------------
# Escenario
# ---------------------------------------------------------------------------
echo "--- 0. escenario ---"
limpiar_db

M --force >/dev/null 2>&1 <<'SQL'
SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @cli = (SELECT ID_CLIENTE FROM CLIENTES ORDER BY ID_CLIENTE LIMIT 1);
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @cat = (SELECT ID_CATEGORIA FROM CATEGORIAS ORDER BY ID_CATEGORIA LIMIT 1);
SET @prov = (SELECT ID_PROVEEDOR FROM PROVEEDORES ORDER BY ID_PROVEEDOR LIMIT 1);

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ BARRIDO', 'marcador del test de barrido', 100.00, 'ZZ-BARR', @mar, @cat, @prov);
SET @prod = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@prod, 50, 1, 'ZZ');

-- (a) vacio y viejo: DEBE cancelarse
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-BARR-VACIO-VIEJO', DATE_SUB(NOW(), INTERVAL 3 DAY));
-- (b) vacio pero reciente: NO debe tocarse
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-BARR-VACIO-NUEVO', NOW());
-- (c) vieja CON LINEA: NO debe tocarse (puede ser un apartado legitimo)
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-BARR-CON-LINEA', DATE_SUB(NOW(), INTERVAL 3 DAY));
SET @vcl = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO,
                            PORCENTAJE_DESCUENTO, MONTO_ITBIS, MONTO_GANANCIA)
VALUES (@vcl, @prod, 1, 100.00, 0.00, 18.00, 0.00);
SQL

viejo="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-BARR-VACIO-VIEJO';")"
nuevo="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-BARR-VACIO-NUEVO';")"
clin="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-BARR-CON-LINEA';")"
if [[ "$viejo" =~ ^[0-9]+$ && "$nuevo" =~ ^[0-9]+$ && "$clin" =~ ^[0-9]+$ ]]; then
    ok "escenario armado (vacío viejo #$viejo, vacío nuevo #$nuevo, con línea #$clin)"
else
    echo "FALLO: no se pudieron crear las ventas marcador." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Correr la app: el barrido va al entrar, antes del menu.
# ---------------------------------------------------------------------------
echo "--- 1. entrar a la app (el barrido corre en el login) ---"
out="$TMP/login.txt"
printf '\n' | timeout "$LIMITE" "$APP_ABS" >"$out" 2>&1
sed 's/\x1b\[[0-9;]*m//g' "$out" > "$TMP/login.limpio"

if grep -q "Acceso concedido \[DEV\]" "$TMP/login.limpio"; then
    ok "el test entro a la app"
else
    fallo "login del test" "no entro (¿BALBU_USER/BALBU_PASS invalidos?)"
fi

est_viejo="$(N "SELECT ESTADO FROM VENTAS WHERE ID_VENTA=$viejo;")"
est_nuevo="$(N "SELECT ESTADO FROM VENTAS WHERE ID_VENTA=$nuevo;")"
est_clin="$(N "SELECT ESTADO FROM VENTAS WHERE ID_VENTA=$clin;")"

if [ "$est_viejo" = "CANCELADA" ]; then
    ok "el borrador vacío y viejo se canceló solo (#$viejo)"
else
    fallo "barrido" "el vacío viejo #$viejo quedo en '$est_viejo', se esperaba CANCELADA"
fi

if [ "$est_nuevo" = "EN_PROCESO" ]; then
    ok "el borrador vacío reciente no se tocó (#$nuevo)"
else
    fallo "barrido" "el vacío reciente #$nuevo quedo en '$est_nuevo', se esperaba EN_PROCESO"
fi

# LA asercion que importa.
if [ "$est_clin" = "EN_PROCESO" ]; then
    ok "la venta vieja CON LINEAS no se tocó (#$clin)"
else
    fallo "SEGURIDAD del barrido" \
        "la venta con lineas #$clin quedo en '$est_clin': el barrido cancelo una venta que no debia"
fi

# Rastro: la cancelacion tiene que quedar en el historial.
paso_hist="$(N "SELECT COUNT(*) FROM HISTORIAL_ESTADOS_VENTA
                 WHERE ID_VENTA=$viejo AND ESTADO_ANTERIOR='EN_PROCESO'
                   AND ESTADO_NUEVO='CANCELADA';")"
if [ "$paso_hist" = "1" ]; then
    ok "la cancelación dejó su rastro en HISTORIAL_ESTADOS_VENTA"
else
    fallo "historial del barrido" "no quedo el paso EN_PROCESO -> CANCELADA ($paso_hist)"
fi

# Y la pantalla lo dice.
if grep -q "EN_PROCESO sin lineas de mas de $HORAS h se cancelaron" "$TMP/login.limpio"; then
    ok "la app avisó de los borradores que canceló"
else
    fallo "aviso del barrido" "no aviso de la cancelacion"
fi

# ---------------------------------------------------------------------------
# 2. La limpieza deja la base como estaba.
# ---------------------------------------------------------------------------
echo "--- 2. limpieza ---"
limpiar_db
resto="$(N "SELECT COUNT(*) FROM VENTAS WHERE FACTURA LIKE 'ZZ-BARR%';")"
prod="$(N "SELECT COUNT(*) FROM PRODUCTOS WHERE NOMBRE='ZZ BARRIDO';")"
trigger="$(N "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB_NAME' AND TRIGGER_NAME='TR_BLOQUEAR_BORRADO_VENTA';")"
if [ "$resto" = "0" ] && [ "$prod" = "0" ]; then
    ok "sin marcadores (ventas $resto, producto $prod)"
else
    fallo "limpieza" "quedaron ventas=$resto producto=$prod"
fi
if [ "$trigger" = "1" ]; then
    ok "TR_BLOQUEAR_BORRADO_VENTA quedo en su lugar"
else
    fallo "limpieza" "el candado de borrado de ventas no volvio"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DEL BARRIDO DE BORRADORES OK"
else
    echo "TESTS DEL BARRIDO DE BORRADORES: FALLAS ARRIBA"
fi
exit "$fail"
