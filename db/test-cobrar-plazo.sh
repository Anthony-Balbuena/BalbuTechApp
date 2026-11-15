#!/usr/bin/env bash
# Test del plazo de cobro de ventas (15/11/2026).
#
# Regla: una venta EN_PROCESO que pasa las 48 h sin cobrarse se marca en rojo en
# «Cobrar venta en proceso» y avisa que retiene stock. Los borradores vacios
# (EN_PROCESO sin lineas) son un caso aparte: no tienen saldo, la vista de
# pendientes los descarta, asi que salen por SP_VENTAS_BORRADOR_VIEJO.
#
# Cubre:
#   1. SP_VENTAS_PENDIENTES_PAGINADO trae FECHA y HORAS_ABIERTA, e incluye las
#      vencidas (>= 48 h) y las recientes.
#   2. SP_CONTAR_VENTAS_PENDIENTES cuadra con esa lista.
#   3. SP_VENTAS_BORRADOR_VIEJO lista SOLO las vacias y viejas, y respeta el
#      umbral que recibe.
#   4. La pantalla: la vencida sale en rojo, la reciente no, y el aviso de
#      borradores nombra la vacia.
#
# Uso:
#   DB_NAME=BALBU_TECH_TEST BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER=<u> BALBU_PASS=<p> \
#   bash db/test-cobrar-plazo.sh
# Este test ESCRIBE y COMMITEA (la app es otra conexion y no veria una
# transaccion sin confirmar): usa marcadores ZZ-PLAZO y los borra al salir.
# Solo corre contra BALBU_TECH_TEST.
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

# ---------------------------------------------------------------------------
# Limpieza. Se corre SIEMPRE (trap). TR_BLOQUEAR_BORRADO_VENTA no deja borrar
# ventas ni con bandera, asi que hay que sacarlo y volver a crearlo. Se usa
# --force y el CREATE va ULTIMO, para que corra aunque un DELETE falle: si el
# script muriera entre el DROP y el CREATE, la base quedaria sin el candado.
# Las lineas se van solas: la FK FK_DETALLE_VENTA es ON DELETE CASCADE.
# ---------------------------------------------------------------------------
limpiar_db() {
    M --force >/dev/null 2>&1 <<'SQL'
DROP TRIGGER IF EXISTS TR_BLOQUEAR_BORRADO_VENTA;
DELETE FROM HISTORIAL_ESTADOS_VENTA WHERE ID_VENTA IN
    (SELECT ID_VENTA FROM VENTAS WHERE FACTURA LIKE 'ZZ-PLAZO%');
DELETE FROM VENTAS WHERE FACTURA LIKE 'ZZ-PLAZO%';
DELETE FROM HISTORIAL_MOVIMIENTOS_PRODUCTO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ PLAZO COBRO');
DELETE FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ PLAZO COBRO');
DELETE FROM INVENTARIO WHERE ID_PRODUCTO IN
    (SELECT ID_PRODUCTO FROM PRODUCTOS WHERE NOMBRE = 'ZZ PLAZO COBRO');
DELETE FROM PRODUCTOS WHERE NOMBRE = 'ZZ PLAZO COBRO';
CREATE TRIGGER TR_BLOQUEAR_BORRADO_VENTA
BEFORE DELETE ON VENTAS
FOR EACH ROW
SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'ERROR: LA VENTA NO SE PUEDE BORRAR; USE SP_CANCELAR_VENTA PARA ANULARLA.';
SQL
}
limpiar() { limpiar_db; rm -rf "$TMP"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cobrar-plazo.XXXXXX")"
trap limpiar EXIT

fail=0
ok()    { echo "OK    $1"; }
fallo() { echo "FALLO $1: $2"; fail=1; }

# ---------------------------------------------------------------------------
# Escenario. Tres ventas: una vencida, una vacia y vieja, y una reciente.
# ---------------------------------------------------------------------------
echo "--- 0. escenario ---"
limpiar_db >/dev/null 2>&1   # arranca de cero aunque una corrida previa haya quedado a medias

base="$(N "SELECT COUNT(*) FROM VISTA_VENTAS_PENDIENTES_PAGO;")"
if ! [[ "$base" =~ ^[0-9]+$ ]]; then
    echo "FALLO: no se pudo leer el total de pendientes (¿base caida?)." >&2
    exit 1
fi

M --force >/dev/null 2>&1 <<'SQL'
SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @cli = (SELECT ID_CLIENTE FROM CLIENTES ORDER BY ID_CLIENTE LIMIT 1);
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @cat = (SELECT ID_CATEGORIA FROM CATEGORIAS ORDER BY ID_CATEGORIA LIMIT 1);
SET @prov = (SELECT ID_PROVEEDOR FROM PROVEEDORES ORDER BY ID_PROVEEDOR LIMIT 1);

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ PLAZO COBRO', 'marcador del test de plazo', 100.00, 'ZZ-PLAZO', @mar, @cat, @prov);
SET @prod = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@prod, 50, 1, 'ZZ');

-- Vencida: con linea, 3 dias de abierta.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-PLAZO-VENCIDA', DATE_SUB(NOW(), INTERVAL 3 DAY));
SET @venc = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO,
                            PORCENTAJE_DESCUENTO, MONTO_ITBIS, MONTO_GANANCIA)
VALUES (@venc, @prod, 1, 100.00, 0.00, 18.00, 0.00);

-- Vacia: sin lineas, 3 dias de abierta. Su saldo es 0, la vista la descarta.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-PLAZO-VACIA', DATE_SUB(NOW(), INTERVAL 3 DAY));
SET @vacia = LAST_INSERT_ID();

-- Reciente: con linea, recien abierta.
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL, FACTURA, FECHA)
VALUES ('EN_PROCESO', @emp, @cli, 0.00, 'ZZ-PLAZO-NUEVA', NOW());
SET @nueva = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO,
                            PORCENTAJE_DESCUENTO, MONTO_ITBIS, MONTO_GANANCIA)
VALUES (@nueva, @prod, 1, 50.00, 0.00, 9.00, 0.00);

SELECT @venc AS VENCIDA, @vacia AS VACIA, @nueva AS NUEVA;
SQL

venc="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-PLAZO-VENCIDA';")"
vacia="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-PLAZO-VACIA';")"
nueva="$(N "SELECT ID_VENTA FROM VENTAS WHERE FACTURA='ZZ-PLAZO-NUEVA';")"
if [[ "$venc" =~ ^[0-9]+$ && "$vacia" =~ ^[0-9]+$ && "$nueva" =~ ^[0-9]+$ ]]; then
    ok "escenario armado (vencida #$venc, vacia #$vacia, reciente #$nueva)"
else
    echo "FALLO: no se pudieron crear las ventas marcador." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1-3. Contrato de los SP.
# ---------------------------------------------------------------------------
echo "--- 1. SP_VENTAS_PENDIENTES_PAGINADO con antiguedad ---"
horas_venc="$(N "SELECT HORAS_ABIERTA FROM VISTA_VENTAS_PENDIENTES_PAGO WHERE ID_VENTA=$venc;")"
horas_nueva="$(N "SELECT HORAS_ABIERTA FROM VISTA_VENTAS_PENDIENTES_PAGO WHERE ID_VENTA=$nueva;")"
aparece_vacia="$(N "SELECT COUNT(*) FROM VISTA_VENTAS_PENDIENTES_PAGO WHERE ID_VENTA=$vacia;")"

if [[ "$horas_venc" =~ ^[0-9]+$ ]] && [ "$horas_venc" -ge "$HORAS" ]; then
    ok "la vencida expone su antiguedad ($horas_venc h >= $HORAS)"
else
    fallo "antiguedad de la vencida" "dijo '$horas_venc', se esperaban >= $HORAS"
fi

if [[ "$horas_nueva" =~ ^[0-9]+$ ]] && [ "$horas_nueva" -lt "$HORAS" ]; then
    ok "la reciente queda por debajo del plazo ($horas_nueva h < $HORAS)"
else
    fallo "antiguedad de la reciente" "dijo '$horas_nueva', se esperaba < $HORAS"
fi

if [ "$aparece_vacia" = "0" ]; then
    ok "la vacia NO aparece en la vista de pendientes (saldo 0)"
else
    fallo "vista de pendientes" "la vacia #$vacia aparecio y no deberia (saldo 0)"
fi

contado="$(N "SELECT COUNT(*) FROM VISTA_VENTAS_PENDIENTES_PAGO;")"
if [ "$contado" = "$((base + 2))" ]; then
    ok "SP_CONTAR_VENTAS_PENDIENTES cuadra ($contado = $base + 2)"
else
    fallo "conteo de pendientes" "dijo '$contado', se esperaba $((base + 2))"
fi

# El SP, no solo la vista: la pantalla lee HORAS_ABIERTA de aca.
cols_sp="$(N "SET @ID_USUARIO_ACTUAL=1; CALL SP_VENTAS_PENDIENTES_PAGINADO(1, 10);" \
    | sed -n '1p' | awk -F'\t' '{print NF}')"
if [ "$cols_sp" = "8" ]; then
    ok "SP_VENTAS_PENDIENTES_PAGINADO devuelve 8 columnas (con FECHA y HORAS_ABIERTA)"
else
    fallo "columnas del SP" "devolvio $cols_sp, se esperaban 8"
fi

# Y el SP tiene que traer la vencida, no solo la vista.
en_sp="$(N "SET @ID_USUARIO_ACTUAL=1; CALL SP_VENTAS_PENDIENTES_PAGINADO(1, 10);" \
    | awk -F'\t' -v id="$venc" '$1 == id {print $8}')"
if [ "$en_sp" = "$horas_venc" ]; then
    ok "el SP trae la vencida con su antiguedad ($en_sp h)"
else
    fallo "el SP y la vencida" "la fila #$venc trajo '$en_sp', se esperaba '$horas_venc'"
fi

echo "--- 2. SP_VENTAS_BORRADOR_VIEJO ---"
b48="$(N "SET @ID_USUARIO_ACTUAL=1; CALL SP_VENTAS_BORRADOR_VIEJO($HORAS);" | awk 'NF{print $1}' | tr '\n' ' ')"
b_null="$(N "SET @ID_USUARIO_ACTUAL=1; CALL SP_VENTAS_BORRADOR_VIEJO(NULL);" | awk 'NF{print $1}' | tr '\n' ' ')"

if printf '%s' "$b48" | grep -qw "$vacia"; then
    ok "el borrador vacio y viejo aparece (#$vacia)"
else
    fallo "borrador viejo" "no listo la vacia #$vacia (dijo: ${b48:-nada})"
fi
if printf '%s' "$b48" | grep -qw "$venc"; then
    fallo "borrador viejo" "listo la vencida #$venc, que tiene lineas"
else
    ok "la vencida NO se cuenta como borrador (tiene lineas)"
fi
if printf '%s' "$b48" | grep -qw "$nueva"; then
    fallo "borrador viejo" "listo la reciente #$nueva, que no paso el plazo"
else
    ok "la reciente no aparece como borrador viejo"
fi
if [ "$b_null" = "$b48" ]; then
    ok "sin umbral cae al default ($HORAS h)"
else
    fallo "default del umbral" "NULL dio '$b_null' y $HORAS dio '$b48'"
fi

# ---------------------------------------------------------------------------
# 4. La pantalla.
# ---------------------------------------------------------------------------
echo "--- 3. la pantalla (menu Ventas -> Cobrar venta) ---"
out="$TMP/cobrar.txt"
printf '\n13\n9\n' | timeout "$LIMITE" "$APP_ABS" >"$out" 2>&1
crudo="$out"
limpio="$TMP/cobrar.limpio"
sed 's/\x1b\[[0-9;]*m//g' "$out" > "$limpio"

problemas=""
grep -q -- "--- COBRAR VENTA EN PROCESO ---" "$limpio" || problemas="no abrio la pantalla"
grep -q "ABIERTA" "$limpio" || problemas="${problemas:+$problemas; }falta la columna ABIERTA"
grep -q "llevan mas de $HORAS h sin cobrarse" "$limpio" \
    || problemas="${problemas:+$problemas; }no aviso de las vencidas"
grep -q "EN_PROCESO sin lineas hace mas de $HORAS h" "$limpio" \
    || problemas="${problemas:+$problemas; }no aviso de los borradores vacios"
grep -q "#$vacia" "$limpio" \
    || problemas="${problemas:+$problemas; }el aviso no nombra la vacia #$vacia"

# El color va en la salida CRUDA: la vencida con \e[31m y la reciente sin el.
if grep -qE "$venc .*\[31m" "$crudo"; then
    :
else
    problemas="${problemas:+$problemas; }la vencida #$venc no salio en rojo"
fi
fila_nueva="$(grep -aE "^$nueva " "$crudo" | head -1)"
if [ -n "$fila_nueva" ] && ! printf '%s' "$fila_nueva" | grep -q "\[31m"; then
    :
else
    problemas="${problemas:+$problemas; }la reciente #$nueva salio en rojo"
fi

if [ -z "$problemas" ]; then
    ok "vencida en rojo, reciente normal, y los dos avisos con su ID"
else
    fallo "pantalla Cobrar venta" "$problemas"
fi

# ---------------------------------------------------------------------------
# 5. La limpieza deja la base como estaba.
# ---------------------------------------------------------------------------
echo "--- 4. limpieza ---"
limpiar >/dev/null 2>&1
resto="$(N "SELECT COUNT(*) FROM VENTAS WHERE FACTURA LIKE 'ZZ-PLAZO%';")"
prod="$(N "SELECT COUNT(*) FROM PRODUCTOS WHERE NOMBRE='ZZ PLAZO COBRO';")"
trigger="$(N "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB_NAME' AND TRIGGER_NAME='TR_BLOQUEAR_BORRADO_VENTA';")"
ahora="$(N "SELECT COUNT(*) FROM VISTA_VENTAS_PENDIENTES_PAGO;")"

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
if [ "$ahora" = "$base" ]; then
    ok "la base quedo como estaba ($ahora pendientes, era $base)"
else
    fallo "limpieza" "quedaron $ahora pendientes, eran $base"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DE PLAZO DE COBRO OK"
else
    echo "TESTS DE PLAZO DE COBRO: FALLAS ARRIBA"
fi
exit "$fail"
