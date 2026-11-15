#!/usr/bin/env bash
# Test de "Ver venta con IVA" paginado (15/11/2026).
#
# Cubre:
#   1. Contrato de SP_VENTAS_ULTIMAS_PAGINADO: pagina 1, pagina 2, orden por
#      ID_VENTA DESC y el fallback a 1/10 cuando la pagina o el tamano vienen
#      nulos o en 0.
#   2. SP_CONTAR_VENTAS_ULTIMAS cuadra con lo que lista el paginado.
#   3. Que SP_VENTAS_ULTIMAS (la vieja, que sigue usando cancelarVentaUI) no se
#      rompio: sigue devolviendo como maximo 20 filas con las mismas columnas.
#   4. La pantalla: entra, muestra la tabla paginada con su "Pagina X de Y" y
#      los dos pedidos por ID, y NO vuelca la factura completa de cada venta.
#
# Uso:
#   DB_NAME=BALBU_TECH_TEST BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=<u> BALBU_PASS=<p> \
#   bash db/test-ventas-ver-iva.sh
# El repo no guarda credenciales. Las ventas del punto 1 se crean DENTRO de una
# transaccion que se revierte: la base queda como estaba.
set -u
export BALBU_ALLOW_DEV_LOGIN=1

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-20}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS}"

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
# -N -B: sin encabezado ni decoracion, asi cada linea de un CALL es una fila.
M() { mariadb -N -B -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -e "$1"; }

fail=0
ok()    { echo "OK    $1"; }
fallo() { echo "FALLO $1: $2"; fail=1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ventas-ver-iva.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
correr() {   # $1 = entrada (printf), $2 = salida
    printf '%b' "$1" | timeout "$LIMITE" "$APP_ABS" >"$2" 2>&1
    echo $?
}

# ---------------------------------------------------------------------------
# 1-3. Contrato de los SP, en UNA sesion y UNA transaccion que se revierte.
# ---------------------------------------------------------------------------
echo "--- 1. contrato de los SP de paginado ---"
base="$(M "SELECT COUNT(*) FROM VISTA_VENTA_CON_IVA;")"
if ! [[ "$base" =~ ^[0-9]+$ ]]; then
    echo "FALLO: no se pudo leer el total de ventas (¿base caida?)." >&2
    exit 1
fi

# 12 ventas marcador sin lineas: no mueven stock ni ITBIS, asi el total de la
# vista sube solo por la cabecera. Se revierte al final.
res="$(M "
START TRANSACTION;
SET @ID_USUARIO_ACTUAL = 1;
SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @cli = (SELECT ID_CLIENTE FROM CLIENTES ORDER BY ID_CLIENTE LIMIT 1);
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA)
SELECT 'REALIZADA', @emp, @cli, 0.00, CONCAT('ZZ-PAG-', n)
  FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
        UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9
        UNION SELECT 10 UNION SELECT 11 UNION SELECT 12) t;

SELECT 'MK_MAX' AS K;
SELECT MAX(ID_VENTA) AS M FROM VISTA_VENTA_CON_IVA;
SELECT 'MK_TOTAL' AS K;
CALL SP_CONTAR_VENTAS_ULTIMAS();
SELECT 'MK_P1' AS K;
CALL SP_VENTAS_ULTIMAS_PAGINADO(1, 10);
SELECT 'MK_P2' AS K;
CALL SP_VENTAS_ULTIMAS_PAGINADO(2, 10);
SELECT 'MK_NULL' AS K;
CALL SP_VENTAS_ULTIMAS_PAGINADO(NULL, NULL);
SELECT 'MK_CERO' AS K;
CALL SP_VENTAS_ULTIMAS_PAGINADO(0, 0);
SELECT 'MK_VIEJO' AS K;
CALL SP_VENTAS_ULTIMAS();
SELECT 'MK_FIN' AS K;
ROLLBACK;
")"

# Solo el bloque entre dos marcadores, contando filas.
bloque() { printf '%s\n' "$res" | awk -v a="^$1\$" -v b="^MK_" \
    '$0 ~ a {on=1; next} $0 ~ b {on=0} on && NF {print}'; }
# El COUNT viene como una sola fila de un solo campo.
entre() { printf '%s\n' "$res" | awk -v a="^$1\$" -v b="^MK_" \
    '$0 ~ a {on=1; next} $0 ~ b {on=0} on && NF {print; exit}'; }

post="$(M "SELECT COUNT(*) FROM VISTA_VENTA_CON_IVA;")"
if [ "$base" = "$post" ]; then
    ok "las ventas del ensayo no quedaron (sigue en $post)"
else
    fallo "aislamiento del ensayo" "la base paso de $base a $post"
fi

esperado=$((base + 12))
contado="$(entre MK_TOTAL)"
if [ "$contado" = "$esperado" ]; then
    ok "SP_CONTAR_VENTAS_ULTIMAS cuadra ($contado = $base + 12)"
else
    fallo "SP_CONTAR_VENTAS_ULTIMAS" "dijo '$contado', se esperaba $esperado"
fi

en_p1="$(bloque MK_P1 | wc -l)"
p1_esp=$((esperado < 10 ? esperado : 10))
[ "$p1_esp" -lt 1 ] && p1_esp=1
if [ "$en_p1" = "$p1_esp" ]; then
    ok "pagina 1 trae $en_p1 fila(s) (10 por pagina)"
else
    fallo "pagina 1" "trajo $en_p1, se esperaban $p1_esp"
fi

en_p2="$(bloque MK_P2 | wc -l)"
p2_esp=$((esperado > 10 ? esperado - 10 : 0))
if [ "$en_p2" = "$p2_esp" ]; then
    ok "pagina 2 trae $en_p2 fila(s) (el resto)"
else
    fallo "pagina 2" "trajo $en_p2, se esperaban $p2_esp"
fi

# Las dos paginas juntas dan el total, sin repetir ni perder filas.
if [ "$((en_p1 + en_p2))" = "$esperado" ]; then
    ok "pagina 1 + pagina 2 cubren el total ($esperado) sin huecos"
else
    fallo "cobertura del paginado" "$en_p1 + $en_p2 != $esperado"
fi

# Orden: la primera de la pagina 1 es la venta mas nueva (dentro del ensayo).
max_id="$(entre MK_MAX)"
primera="$(bloque MK_P1 | head -1 | cut -f1)"
if [ "$primera" = "$max_id" ]; then
    ok "orden por ID_VENTA DESC (arranca en la #$max_id)"
else
    fallo "orden del paginado" "arranco en #$primera, se esperaba #$max_id"
fi

# Fallback: NULL y 0 caen a pagina 1 / 10 por pagina.
en_null="$(bloque MK_NULL | wc -l)"
en_cero="$(bloque MK_CERO | wc -l)"
if [ "$en_null" = "$en_p1" ] && [ "$en_cero" = "$en_p1" ]; then
    ok "pagina nula o 0 cae a la 1 con 10 por pagina"
else
    fallo "fallback de pagina" "NULL=$en_null, 0=$en_cero, esperado=$en_p1"
fi

# SP_VENTAS_ULTIMAS (la vieja) sigue viva para cancelarVentaUI: <=20 filas.
en_viejo="$(bloque MK_VIEJO | wc -l)"
viejo_esp=$((esperado < 20 ? esperado : 20))
if [ "$en_viejo" = "$viejo_esp" ]; then
    ok "SP_VENTAS_ULTIMAS sigue devolviendo $en_viejo fila(s) (tope 20)"
else
    fallo "SP_VENTAS_ULTIMAS" "trajo $en_viejo, se esperaban $viejo_esp"
fi

cols="$(bloque MK_P1 | head -1 | awk -F'\t' '{print NF}')"
if [ "$cols" = "7" ]; then
    ok "el paginado devuelve las 7 columnas (ID, CLIENTE, FECHA, ESTADO, SUBTOTAL, ITBIS, TOTAL)"
else
    fallo "columnas del paginado" "devolvio $cols columnas, se esperaban 7"
fi

# ---------------------------------------------------------------------------
# 4. La pantalla.
# ---------------------------------------------------------------------------
echo "--- 2. la pantalla (menu Ventas -> Ver venta con IVA) ---"
out="$TMP/pantalla.txt"
correr '\n13\n2\n\n\n' "$out" >/dev/null
limpio="$TMP/pantalla.limpio"
sed 's/\x1b\[[0-9;]*m//g' "$out" > "$limpio"

if grep -q "Acceso concedido \[DEV\]" "$limpio"; then
    ok "el test entro a la app"
else
    fallo "login del test" "no entro (¿BALBU_USER/BALBU_PASS invalidos?)"
fi

problemas=""
grep -q -- "--- VENTAS REGISTRADAS ---" "$limpio" || problemas="no abrio la pantalla"
grep -qE "Pagina 1 de [0-9]+ +\([0-9]+ registros\)" "$limpio" \
    || problemas="${problemas:+$problemas; }no mostro el encabezado de paginado"
grep -q "Ver factura completa de una venta? ID" "$limpio" \
    || problemas="${problemas:+$problemas; }no pidio el ID de la factura"
grep -q "Ver pagos de una venta? ID" "$limpio" \
    || problemas="${problemas:+$problemas; }no pidio el ID de los pagos"
grep -q "SUBTOTAL" "$limpio" || problemas="${problemas:+$problemas; }falta la columna SUBTOTAL"
grep -q "ITBIS" "$limpio" || problemas="${problemas:+$problemas; }falta la columna ITBIS"

# Regresion del bug: la pantalla volcaba la factura COMPLETA de cada venta.
# mostrarFactura imprime "ID: <n> | Cliente: ...". Al omitir el ID no debe
# aparecer ninguna.
if grep -qE "^ID: [0-9]+ \| Cliente:" "$limpio"; then
    problemas="${problemas:+$problemas; }volco la factura completa sin pedirla"
fi

if [ -z "$problemas" ]; then
    ok "pantalla paginada, con pedido por ID y sin volcar facturas"
else
    fallo "pantalla Ver venta con IVA" "$problemas"
fi

# Camino feliz del "Ver factura": pedirla por ID la abre.
idv="$(M "SELECT MAX(ID_VENTA) FROM VENTAS;")"
if [[ "$idv" =~ ^[0-9]+$ ]]; then
    out2="$TMP/factura.txt"
    correr "\\n13\\n2\\n$idv\\n\\n" "$out2" >/dev/null
    sed 's/\x1b\[[0-9;]*m//g' "$out2" > "$TMP/factura.limpio"
    if grep -qE "^ID: $idv \| Cliente:" "$TMP/factura.limpio"; then
        ok "pedir la factura por ID la abre (venta #$idv)"
    else
        fallo "factura por ID" "no mostro la venta #$idv"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DE VER VENTA CON IVA OK"
else
    echo "TESTS DE VER VENTA CON IVA: FALLAS ARRIBA"
fi
exit "$fail"
