#!/usr/bin/env bash
# (07/11/2026) Pruebas de los dos cambios de esta tanda:
#   1. SP_HISTORIAL_VENTA(0) lista todas las ventas y trae la columna VENTA.
#   2. SP_VENTAS_GARANTIZABLES() lista solo ventas REALIZADA con lineas sin
#      garantia, y deja de listarlas apenas se registra la garantia.
#
# Todo corre dentro de una transaccion que se revierte al final: no deja datos.
# Nunca corre contra la base viva.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-historial-garantias-venta.sh
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

faltan=$(M -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                   WHERE ROUTINE_SCHEMA = DATABASE()
                     AND ROUTINE_NAME IN ('SP_HISTORIAL_VENTA', 'SP_VENTAS_GARANTIZABLES',
                                          'SP_LINEAS_VENTA_CON_GARANTIA', 'SP_REGISTRAR_GARANTIA');")
if [ "$faltan" != "4" ]; then
    echo "FALLO: faltan rutinas ($faltan/4). Aplica los modulos 21 y 63 en $DB_NAME." >&2
    exit 1
fi

salida=$(M -N <<'SQL'
START TRANSACTION;

SET @emp = (SELECT MIN(ID_EMPLEADO) FROM EMPLEADOS);
INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL) VALUES ('ZZHVG CLI', '0000000000', 'zzhvg@test.local');
SET @cli = LAST_INSERT_ID();
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, DIAS_GARANTIA)
VALUES ('ZZHVG PROD', 'Producto de prueba sin garantia automatica', 50.00, 25.00, 'ZZHVG-1',
        (SELECT MIN(ID_MARCA) FROM MARCAS),
        (SELECT MIN(ID_CATEGORIA) FROM CATEGORIAS),
        (SELECT MIN(ID_PROVEEDOR) FROM PROVEEDORES), NULL);
SET @prod = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION) VALUES (@prod, 5, 1, 'ZZ');
-- El total arranca en 0: TR_ACTUALIZAR_TOTAL_VENTA lo recalcula sumando el
-- SUBTOTAL generado de cada linea (si se pone 50 aca, la linea lo deja en 100).
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL)
VALUES ('EN_PROCESO', @emp, @cli, 0.00);
SET @ven = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
VALUES (@ven, @prod, 1, 50.00);
SET @det = LAST_INSERT_ID();
-- El pago dispara TR_AUTO_FINALIZAR_VENTA: la venta queda REALIZADA. El
-- producto tiene DIAS_GARANTIA NULL, asi que no se crea garantia automatica.
INSERT INTO PAGOS (ID_VENTA, ID_METODO_PAGO, ID_EMPLEADO, MONTO, MONTO_RECIBIDO)
VALUES (@ven, (SELECT MIN(ID_METODO_PAGO) FROM METODOS_PAGO), @emp, 50.00, 50.00);
INSERT INTO HISTORIAL_ESTADOS_VENTA (ID_VENTA, ESTADO_ANTERIOR, ESTADO_NUEVO, ID_EMPLEADO, MOTIVO)
VALUES (@ven, 'EN_PROCESO', 'REALIZADA', @emp, 'ZZHVG MOTIVO');
SELECT CONCAT('VENTA_ID=', @ven);
SELECT CONCAT('ESTADO=', ESTADO) FROM VENTAS WHERE ID_VENTA = @ven;

SELECT 'FASE_VENTAS_ANTES';
CALL SP_VENTAS_GARANTIZABLES();
SELECT 'FASE_LINEAS';
CALL SP_LINEAS_VENTA_CON_GARANTIA(@ven);
SELECT 'FASE_HIST_TODAS';
CALL SP_HISTORIAL_VENTA(0);
SELECT 'FASE_HIST_UNA';
CALL SP_HISTORIAL_VENTA(@ven);
SELECT 'FASE_ALTA';
CALL SP_REGISTRAR_GARANTIA(@det, 30, (SELECT MIN(ID_EMPLEADO) FROM EMPLEADOS));
SELECT 'FASE_VENTAS_DESPUES';
CALL SP_VENTAS_GARANTIZABLES();
SELECT 'FASE_FIN';

ROLLBACK;
SQL
)

seccion() {
    printf '%s\n' "$salida" | awk -v ini="$1" -v fin="$2" '
        $0 == ini { dentro = 1; next }
        $0 == fin { dentro = 0 }
        dentro
    '
}

VENTA=$(printf '%s\n' "$salida" | sed -n 's/^VENTA_ID=//p' | head -n 1)
case "$VENTA" in
    ''|*[!0-9]*)
        echo "FALLO: no se pudo crear la venta de prueba."
        printf '%s\n' "$salida" | head -n 8
        exit 1
        ;;
esac

fallos=0
fallo() { echo "FALLO: $*"; fallos=$((fallos + 1)); }
ok() { echo "OK: $*"; }

ESTADO=$(printf '%s\n' "$salida" | sed -n 's/^ESTADO=//p' | head -n 1)
if [ "$ESTADO" = "REALIZADA" ]; then
    ok "la venta de prueba quedo REALIZADA y sin garantia automatica"
else
    fallo "la venta de prueba quedo en '$ESTADO' (se esperaba REALIZADA)"
fi

# --- 1) SP_VENTAS_GARANTIZABLES lista la venta sin garantia ---------------
antes=$(seccion FASE_VENTAS_ANTES FASE_LINEAS)
if printf '%s' "$antes" | grep -q "ZZHVG CLI"; then
    ok "SP_VENTAS_GARANTIZABLES lista la venta REALIZADA sin garantia"
else
    fallo "SP_VENTAS_GARANTIZABLES no listo la venta REALIZADA sin garantia"
    printf '%s\n' "$antes" | head -n 5
fi

lineas=$(seccion FASE_LINEAS FASE_HIST_TODAS)
if printf '%s' "$lineas" | grep -q "ZZHVG PROD" && printf '%s' "$lineas" | grep -q "NO"; then
    ok "SP_LINEAS_VENTA_CON_GARANTIA marca la linea como sin garantia"
else
    fallo "SP_LINEAS_VENTA_CON_GARANTIA no marco la linea como sin garantia"
fi

# --- 2) Historial: con 0 ve todas; con el ID ve solo esa ------------------
todas=$(seccion FASE_HIST_TODAS FASE_HIST_UNA)
if printf '%s' "$todas" | grep -q "ZZHVG MOTIVO"; then
    ok "SP_HISTORIAL_VENTA(0) incluye el historial de la venta de prueba"
else
    fallo "SP_HISTORIAL_VENTA(0) no incluyo la venta de prueba"
    printf '%s\n' "$todas" | head -n 5
fi
if printf '%s' "$todas" | grep -qE "^${VENTA}[[:space:]]"; then
    ok "SP_HISTORIAL_VENTA(0) trae la columna ID_VENTA"
else
    fallo "SP_HISTORIAL_VENTA(0) no trae el ID de la venta en la primera columna"
fi

una=$(seccion FASE_HIST_UNA FASE_ALTA)
filas=$(printf '%s\n' "$una" | grep -c "ZZHVG MOTIVO")
if [ "$filas" = "1" ]; then
    ok "SP_HISTORIAL_VENTA($VENTA) devuelve solo esa venta"
else
    fallo "SP_HISTORIAL_VENTA($VENTA) devolvio $filas filas con el motivo de prueba (se esperaba 1)"
fi

# --- 3) Con la garantia registrada, deja de aparecer ----------------------
alta=$(seccion FASE_ALTA FASE_VENTAS_DESPUES)
if printf '%s' "$alta" | grep -qi "REGISTRADA"; then
    ok "SP_REGISTRAR_GARANTIA registro la garantia"
else
    fallo "SP_REGISTRAR_GARANTIA no registro la garantia"
    printf '%s\n' "$alta" | head -n 5
fi

despues=$(seccion FASE_VENTAS_DESPUES FASE_FIN)
if printf '%s' "$despues" | grep -q "ZZHVG CLI"; then
    fallo "la venta sigue apareciendo en SP_VENTAS_GARANTIZABLES con garantia"
else
    ok "la venta deja de aparecer al registrarse la garantia"
fi

# --- 4) Historial PAGINADO (15/11/2026) -----------------------------------
# SP_HISTORIAL_VENTA no tiene LIMIT: devolvia el historial completo. La pantalla
# paso a usar la variante paginada. Estas pruebas corren DESPUES del ROLLBACK,
# asi que cuentan el historial que ya tiene la base.
pag_sp="$(M -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                    WHERE ROUTINE_SCHEMA = DATABASE()
                      AND ROUTINE_NAME IN ('SP_HISTORIAL_VENTA_PAGINADO',
                                           'SP_CONTAR_HISTORIAL_VENTA');")"
if [ "$pag_sp" = "2" ]; then
    ok "los dos SP paginados del historial existen"
else
    fallo "faltan los SP paginados del historial ($pag_sp/2)"
fi

# El conteo del SP tiene que cuadrar con la tabla, con el mismo JOIN.
total_hist="$(M -N -e "SELECT COUNT(*) FROM HISTORIAL_ESTADOS_VENTA H
                         JOIN EMPLEADOS E ON E.ID_EMPLEADO = H.ID_EMPLEADO;")"
conteo_sp="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_CONTAR_HISTORIAL_VENTA(0);" \
             | awk 'NF{print $1; exit}')"
if [ "$conteo_sp" = "$total_hist" ]; then
    ok "SP_CONTAR_HISTORIAL_VENTA cuadra con la tabla ($conteo_sp)"
else
    fallo "SP_CONTAR_HISTORIAL_VENTA dijo '$conteo_sp' y la tabla tiene $total_hist"
fi

# Una pagina del tamano del total trae TODO: el LIMIT no recorta de mas.
todos_hist="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO(0, 1, 1000);" \
              | grep -c .)"
if [ "$todos_hist" = "$total_hist" ]; then
    ok "con una pagina grande devuelve el total ($todos_hist)"
else
    fallo "el paginado devolvio $todos_hist filas y la tabla tiene $total_hist"
fi

# Pagina 1 de 10 y pagina 2 de 10 cubren el total sin repetir.
p1_hist="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO(0, 1, 10);" | grep -c .)"
p2_hist="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO(0, 2, 10);" | grep -c .)"
p1_esp=$((total_hist < 10 ? total_hist : 10))
p2_esp=$((total_hist > 10 ? total_hist - 10 : 0))
if [ "$p1_hist" = "$p1_esp" ] && [ "$p2_hist" = "$p2_esp" ]; then
    ok "pagina 1 ($p1_hist) + pagina 2 ($p2_hist) cubren el total ($total_hist)"
else
    fallo "paginado: p1=$p1_hist (era $p1_esp), p2=$p2_hist (era $p2_esp), total=$total_hist"
fi

# Nulo o 0 caen a pagina 1 con 10 por pagina, igual que la pagina 1 real.
p_nula="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO(0, NULL, NULL);" | grep -c .)"
p_cero="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO(0, 0, 0);" | grep -c .)"
if [ "$p_nula" = "$p1_hist" ] && [ "$p_cero" = "$p1_hist" ]; then
    ok "pagina nula o 0 cae a la 1 con 10 por pagina"
else
    fallo "fallback de pagina: NULL=$p_nula, 0=$p_cero, esperado=$p1_hist"
fi

# Filtrar por una venta puntual acota el resultado.
venta_ref="$(M -N -e "SELECT ID_VENTA FROM HISTORIAL_ESTADOS_VENTA ORDER BY ID_HISTORIAL_ESTADO LIMIT 1;")"
if [ -n "$venta_ref" ]; then
    una_venta="$(M -N -e "SET @ID_USUARIO_ACTUAL=1; CALL SP_HISTORIAL_VENTA_PAGINADO($venta_ref, 1, 1000);" | grep -c .)"
    esperado_una="$(M -N -e "SELECT COUNT(*) FROM HISTORIAL_ESTADOS_VENTA H
                               JOIN EMPLEADOS E ON E.ID_EMPLEADO = H.ID_EMPLEADO
                              WHERE H.ID_VENTA = $venta_ref;")"
    if [ "$una_venta" = "$esperado_una" ]; then
        ok "filtrar por la venta #$venta_ref devuelve solo sus $una_venta fila(s)"
    else
        fallo "filtro por venta: devolvio $una_venta, se esperaban $esperado_una"
    fi
fi

if [ "$fallos" -eq 0 ]; then
    echo "OK historial de venta y ventas garantizables."
    exit 0
fi
echo "FALLAS: $fallos"
exit 1
