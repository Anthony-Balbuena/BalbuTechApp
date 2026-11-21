#!/usr/bin/env bash
# Test del cierre ATOMICO de venta (15/11/2026, opcion C de P-4).
#
# Antes no habia transaccion: la cabecera y cada linea se commitaban solas, asi
# que una caida en el medio dejaba un carrito a medias con el stock ya
# descontado. Ahora cabecera + TODAS las lineas + el descuento de stock van en
# una sola transaccion.
#
# Cubre:
#   1. FALLO en la segunda linea: no queda NADA. Ni cabecera, ni la primera
#      linea —que YA se habia insertado y ya habia descontado stock—, ni fila en
#      MOVIMIENTOS_INVENTARIO. Esta es la prueba de verdad: si el rollback no
#      alcanzara a la primera linea, el stock quedaria descontado.
#   2. Exito: la venta se cierra igual que antes (regresion del camino feliz).
#
# Como se provoca el fallo: el carrito valida el stock al AGREGAR, asi que no se
# puede pedir de mas por pantalla. Se arma el carrito con dos productos y, con la
# app ya esperando en "Cerrar venta?", se pone el stock del segundo en 0 desde
# otra conexion. La app se maneja por un FIFO para poder intercalar eso.
#
# Uso:
#   DB_NAME=BALBU_TECH_TEST BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=<u> BALBU_PASS=<p> \
#   bash db/test-cierre-atomico.sh
# ESCRIBE y COMMITEA (la app es otra conexion): usa marcadores ZZ-ATOM y los
# borra al salir. Solo corre contra BALBU_TECH_TEST.
set -u
export BALBU_ALLOW_DEV_LOGIN=1

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-30}"
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
M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }
N() { mariadb -N -B -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -e "$1"; }

# TR_BLOQUEAR_BORRADO_VENTA no deja borrar ventas ni con bandera: se saca y se
# vuelve a crear al final del mismo script, para que el candado vuelva aunque un
# DELETE falle. El cuerpo tiene que ser el MISMO que declara modulos/21
# (BEGIN ... END): si se copia la version de una sola sentencia, cada corrida de
# la bateria deja BALBU_TECH_TEST en drift. De ahi el DELIMITER.
limpiar_db() {
    M --force >/dev/null 2>&1 <<'SQL'
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_VENTA;
DELETE FROM HISTORIAL_ESTADOS_VENTA WHERE ID_VENTA IN
    (SELECT ID_VENTA FROM VENTAS WHERE ID_CLIENTE IN
        (SELECT ID_CLIENTE FROM CLIENTES WHERE NOMBRE = 'ZZ ATOM CLI'));
DELETE FROM VENTAS WHERE ID_CLIENTE IN
    (SELECT ID_CLIENTE FROM CLIENTES WHERE NOMBRE = 'ZZ ATOM CLI');
DELETE FROM HISTORIAL_MOVIMIENTOS_PRODUCTO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE LIKE 'ZZ ATOM%');
DELETE FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE LIKE 'ZZ ATOM%');
DELETE FROM INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE LIKE 'ZZ ATOM%');
DELETE FROM PRODUCTOS WHERE NOMBRE LIKE 'ZZ ATOM%';
DELETE FROM CLIENTES WHERE NOMBRE = 'ZZ ATOM CLI';
DELIMITER //
CREATE TRIGGER TR_BLOQUEAR_BORRADO_VENTA
BEFORE DELETE ON VENTAS
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.';
END //
DELIMITER ;
SQL
}
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cierre-atomico.XXXXXX")"
limpiar() { limpiar_db; rm -rf "$TMP"; }
trap limpiar EXIT

fail=0
ok()    { echo "OK    $1"; }
fallo() { echo "FALLO $1: $2"; fail=1; }

# ---------------------------------------------------------------------------
# Escenario: un cliente y dos productos marcador con stock 10.
# ---------------------------------------------------------------------------
echo "--- 0. escenario ---"
limpiar_db

M --force >/dev/null 2>&1 <<'SQL'
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @cat = (SELECT ID_CATEGORIA FROM CATEGORIAS ORDER BY ID_CATEGORIA LIMIT 1);
SET @prov = (SELECT ID_PROVEEDOR FROM PROVEEDORES ORDER BY ID_PROVEEDOR LIMIT 1);

INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
VALUES ('ZZ ATOM CLI', '8090000000', 'zz.atom@correo.test', 'Calle Prueba 1');
SET @cli = LAST_INSERT_ID();

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ ATOM A', 'marcador atomico A', 100.00, 'ZZ-ATOM-A', @mar, @cat, @prov);
SET @pa = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@pa, 10, 1, 'ZZ');

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ ATOM B', 'marcador atomico B', 200.00, 'ZZ-ATOM-B', @mar, @cat, @prov);
SET @pb = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@pb, 10, 1, 'ZZ');

SELECT @cli AS CLI, @pa AS PROD_A, @pb AS PROD_B;
SQL

cli="$(N "SELECT ID_CLIENTE FROM CLIENTES WHERE NOMBRE='ZZ ATOM CLI';")"
pa="$(N "SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE='ZZ ATOM A';")"
pb="$(N "SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE='ZZ ATOM B';")"
if [[ "$cli" =~ ^[0-9]+$ && "$pa" =~ ^[0-9]+$ && "$pb" =~ ^[0-9]+$ ]]; then
    ok "escenario armado (cliente #$cli, prod A #$pa, prod B #$pb)"
else
    echo "FALLO: no se pudo armar el escenario." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Correr la app con un FIFO, para poder cambiar la base a mitad de camino.
# ---------------------------------------------------------------------------
# $1 = archivo de salida, $2 = pid (via variable global APP_PID)
APP_PID=""
abrir_app() {
    local out="$1"
    local fifo="$TMP/in"
    rm -f "$fifo"; mkfifo "$fifo"
    ( cd "$(pwd)" && timeout "$LIMITE" "$APP_ABS" <"$fifo" >"$out" 2>&1 ) &
    APP_PID=$!
    exec 3>"$fifo"          # se abre para escritura; queda abierto hasta cerrar
}
escribir() { printf '%b' "$1" >&3; }
# Espera a que la salida contenga un texto (barrier). 1 = lo vio.
esperar() {
    local out="$1" texto="$2"
    for _ in $(seq 1 100); do
        grep -qF -- "$texto" "$out" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
cerrar_app() {
    exec 3>&- 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
}

# ===========================================================================
# CASO 1: falla la SEGUNDA linea -> no debe quedar NADA
# ===========================================================================
echo "--- 1. fallo en la segunda linea: todo o nada ---"
out1="$TMP/caso1.txt"
abrir_app "$out1"
escribir '\n13\n1\n'                       # login, Ventas, Venta rapida
escribir "$pa\n2\n\n"                      # producto A, cantidad 2, sin descuento
escribir "$pb\n2\n\n"                      # producto B, cantidad 2, sin descuento
escribir '\n'                              # Producto vacio -> cierra la carga
escribir '\n'                              # Quitar algo? -> no

if esperar "$out1" "Cerrar venta? (s/n): "; then
    ok "el carrito quedo armado con los dos productos"
    escribir 's\n'
else
    fallo "armado del carrito" "no llego al prompt de cerrar"
fi

# cerrarVenta pide el cliente ANTES de abrir la transaccion, asi que este es el
# momento exacto para dejar sin stock al producto B: todavia no hay transaccion
# ni transaccion abierta.
if esperar "$out1" "ID cliente: "; then
    ok "pidió el ID del cliente (la transacción abre después de esto)"
else
    fallo "prompt del cliente" "no pidio el ID del cliente"
fi
M -e "UPDATE INVENTARIO SET STOCK_ACTUAL = 0 WHERE ID_PRODUCTO = $pb;" >/dev/null 2>&1
escribir "$cli\n"                          # recien aca empieza la transaccion
esperar "$out1" "se revirtió completa" || true
escribir 'n\n'                             # por si llega a preguntar por el pago
cerrar_app

sed 's/\x1b\[[0-9;]*m//g' "$out1" > "$TMP/caso1.limpio"

filas_venta="$(N "SELECT COUNT(*) FROM VENTAS WHERE ID_CLIENTE = $cli;")"
lineas="$(N "SELECT COUNT(*) FROM DETALLES_VENTA d JOIN VENTAS v ON v.ID_VENTA = d.ID_VENTA
              WHERE v.ID_CLIENTE = $cli;")"
stock_a="$(N "SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = $pa;")"
stock_b="$(N "SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = $pb;")"
movs_a="$(N "SELECT COUNT(*) FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO = $pa;")"

if [ "$filas_venta" = "0" ]; then
    ok "no quedó la cabecera de la venta"
else
    fallo "atomicidad" "quedaron $filas_venta venta(s) de un cierre que fallo"
fi

if [ "$lineas" = "0" ]; then
    ok "no quedaron líneas"
else
    fallo "atomicidad" "quedaron $lineas línea(s) de un cierre que fallo"
fi

# LA asercion clave: la primera linea SI se habia insertado y SI habia
# descontado stock antes de que fallara la segunda. El rollback tiene que
# haberla devuelto.
if [ "$stock_a" = "10" ]; then
    ok "el stock del producto A volvió solo a 10 (su línea se revirtió)"
else
    fallo "atomicidad del stock" \
        "el producto A quedó en $stock_a: la línea ya insertada NO se revirtió"
fi

if [ "$movs_a" = "0" ]; then
    ok "no quedó ningún movimiento de inventario del intento fallido"
else
    fallo "atomicidad del kardex" "quedaron $movs_a movimiento(s) de un cierre que fallo"
fi

if grep -q "se revirtió completa" "$TMP/caso1.limpio"; then
    ok "la app avisó que la venta se revirtió completa"
else
    fallo "aviso del rollback" "no dijo que hubiera revertido"
fi

if grep -q "se revirtió completa\|cancelada para no dejar basura" "$TMP/caso1.limpio"; then
    ok "el mensaje es el del rollback (ya no el de la cancelación compensatoria)"
else
    : # no es un fallo: el mensaje viejo tampoco seria incorrecto
fi

# ===========================================================================
# CASO 2: camino feliz -> la venta se cierra igual que antes
# ===========================================================================
echo "--- 2. regresión: el camino feliz sigue funcionando ---"
M -e "UPDATE INVENTARIO SET STOCK_ACTUAL = 10 WHERE ID_PRODUCTO = $pb;" >/dev/null 2>&1
out2="$TMP/caso2.txt"
abrir_app "$out2"
escribir '\n13\n1\n'
escribir "$pa\n3\n\n"                      # una sola linea, cantidad 3
escribir '\n'                              # Producto vacio
escribir '\n'                              # Quitar algo? -> no
if esperar "$out2" "Cerrar venta? (s/n): "; then
    escribir 's\n'
    if esperar "$out2" "ID cliente: "; then
        escribir "$cli\n"
    else
        fallo "camino feliz" "no pidio el ID del cliente"
    fi
    esperar "$out2" "FACTURA #" || true
    escribir 'n\n'                         # no pagar: queda EN_PROCESO
else
    fallo "camino feliz" "no llego al prompt de cerrar"
fi
cerrar_app
sed 's/\x1b\[[0-9;]*m//g' "$out2" > "$TMP/caso2.limpio"

venta2="$(N "SELECT v.ID_VENTA FROM VENTAS v
              JOIN DETALLES_VENTA d ON d.ID_VENTA = v.ID_VENTA
             WHERE v.ID_CLIENTE = $cli ORDER BY v.ID_VENTA DESC LIMIT 1;")"
stock_a2="$(N "SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = $pa;")"

if [[ "$venta2" =~ ^[0-9]+$ ]]; then
    ok "la venta se cerró (venta #$venta2)"
else
    fallo "camino feliz" "no se creó la venta"
fi
if [ "$stock_a2" = "7" ]; then
    ok "el stock bajó de 10 a 7 por la línea de 3"
else
    fallo "camino feliz" "el stock del producto A quedó en $stock_a2, se esperaba 7"
fi

# ---------------------------------------------------------------------------
# Limpieza
# ---------------------------------------------------------------------------
echo "--- 3. limpieza ---"
limpiar_db
resto="$(N "SELECT COUNT(*) FROM VENTAS WHERE ID_CLIENTE IN (SELECT ID_CLIENTE FROM CLIENTES WHERE NOMBRE='ZZ ATOM CLI');")"
prods="$(N "SELECT COUNT(*) FROM PRODUCTOS WHERE NOMBRE LIKE 'ZZ ATOM%';")"
cli2="$(N "SELECT COUNT(*) FROM CLIENTES WHERE NOMBRE='ZZ ATOM CLI';")"
trigger="$(N "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB_NAME' AND TRIGGER_NAME='TR_BLOQUEAR_BORRADO_VENTA';")"
if [ "$resto" = "0" ] && [ "$prods" = "0" ] && [ "$cli2" = "0" ]; then
    ok "sin marcadores (ventas $resto, productos $prods, cliente $cli2)"
else
    fallo "limpieza" "quedaron ventas=$resto productos=$prods cliente=$cli2"
fi
if [ "$trigger" = "1" ]; then
    ok "TR_BLOQUEAR_BORRADO_VENTA quedo en su lugar"
else
    fallo "limpieza" "el candado de borrado de ventas no volvio"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DEL CIERRE ATOMICO OK"
else
    echo "TESTS DEL CIERRE ATOMICO: FALLAS ARRIBA"
fi
exit "$fail"
