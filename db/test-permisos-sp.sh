#!/usr/bin/env bash
# (03/11/2026) Prueba de la guarda de permisos dentro de los SPs (modulo 66).
#
# Cubre:
#   1. Sin token, un SP guardado rechaza la llamada.
#   2. Con token de VENDEDOR, un SP de consulta de metodos de pago pasa.
#   3. Con el mismo token, un SP que exige CATEGORIAS_VER se rechaza.
#   4. El rechazo queda registrado en LOG_PERMISO_SP.
#
# Uso (nunca contra la base viva):
#   BALBU_PASS=<clave del admin> DB_NAME=BALBU_TECH_TEST bash db/test-permisos-sp.sh
set -u

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
# DB_PASSWORD del entorno es la clave de la app (balbu_app, ver .env); se
# guarda antes de pisarla con la del admin.
APP_USER="${DB_APP_USER:-balbu_app}"
APP_PASS="${DB_APP_PASSWORD:-${DB_PASSWORD:-}}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave del usuario admin)}"

USR="prueba_perm_sp"
CED="TESTPMSP1"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi
if [ -z "$APP_PASS" ]; then
    echo "Falta la clave de $APP_USER (DB_PASSWORD del .env) para probar como app." >&2
    exit 1
fi

QA() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@"; }
# Conexion como la app: es la unica que el control tiene que frenar.
QAPP() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$APP_USER" -p"$APP_PASS" --database="$DB_NAME" "$@"; }

exigiendo=$(QA -N -e "SELECT COUNT(*) FROM PERMISO_POR_RUTINA WHERE EXIGIR = 1" 2>&1)
case "$exigiendo" in
    ''|*[!0-9]*)
        echo "ERROR: no hay conexion util a $DB_HOST:$DB_PORT ($exigiendo)." >&2
        exit 1
        ;;
    0)
        echo "AVISO: ninguna rutina tiene EXIGIR = 1; el test no probaria nada." >&2
        exit 1
        ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/perm-sp.XXXXXX")"
limpiar_datos() {
    local id
    id=$(QA -N -e "SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = '$USR';")
    QA -e "DELETE FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR';" >/dev/null 2>&1
    case "$id" in
        ''|*[!0-9]*) : ;;
        *)
            QA -e "DELETE FROM SESIONES WHERE ID_USUARIO = $id;" >/dev/null 2>&1
            QA -e "DELETE FROM LOG_USUARIOS WHERE ID_USUARIO = $id OR ID_USUARIO_ADMIN = $id;" >/dev/null 2>&1
            ;;
    esac
    QA -e "DELETE FROM USUARIOS WHERE USUARIO = '$USR';" >/dev/null 2>&1
    QA -e "DELETE FROM EMPLEADOS WHERE CEDULA = '$CED';" >/dev/null 2>&1
}
limpiar() { limpiar_datos; rm -rf "$TMP"; }
trap limpiar EXIT
limpiar_datos

. "$(dirname "$0")/lib-clave-prueba.sh"
HASH=$(clave_pbkdf2 "$BALBU_PASS")
# El derivado es el ultimo campo de pbkdf2$iter$sal$hash.
DERIV="${HASH##*\$}"

QA -e "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
       VALUES ('PRUEBA PERM SP', '$CED', 'PRUEBA', 1000, 'T-PMSP-1', 'perm-sp@test.local', '2026-11-03');"
EMP=$(QA -N -e "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$CED';")
ID_ROL=$(QA -N -e "SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL = 'VENDEDOR';")
if [ -z "$EMP" ] || [ -z "$ID_ROL" ]; then
    echo "ERROR: falta el rol VENDEDOR o no se creo el empleado de prueba." >&2
    exit 1
fi
QA -e "INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
       VALUES ('$USR', '$HASH', $EMP, $ID_ROL);"

# Token real, emitido por el servidor con la clave correcta.
LOGIN=$(QA -N -e "CALL SP_LOGIN_AUTENTICAR('$USR', '$DERIV');" 2>&1 | tail -n 1)
RESULTADO=$(printf '%s' "$LOGIN" | cut -f1)
TOKEN=$(printf '%s' "$LOGIN" | cut -f9)
if [ "$RESULTADO" != "OK" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: no se pudo obtener token de prueba (resultado='$RESULTADO')." >&2
    exit 1
fi

fallos=0
fallo() { echo "FALLO: $*"; fallos=$((fallos + 1)); }

# --- 1) Sin token ---------------------------------------------------------
sin_token=$(QAPP -e "CALL SP_LISTAR_METODOS_PAGO();" 2>&1)
if ! printf '%s' "$sin_token" | grep -q "SESION INVALIDA"; then
    fallo "sin token, SP_LISTAR_METODOS_PAGO no fue rechazado"
fi

# --- 2) Con token de VENDEDOR, lo permitido pasa --------------------------
permitido=$(QAPP -e "SET @TOKEN_SESION = '$TOKEN'; CALL SP_LISTAR_METODOS_PAGO();" 2>&1)
if printf '%s' "$permitido" | grep -q "SIN PERMISO\|SESION INVALIDA"; then
    fallo "VENDEDOR no pudo consultar metodos de pago (deberia poder)"
fi

# --- 3) Con el mismo token, lo prohibido se corta -------------------------
prohibido=$(QAPP -e "SET @TOKEN_SESION = '$TOKEN'; CALL SP_LISTAR_CATEGORIAS();" 2>&1)
if ! printf '%s' "$prohibido" | grep -q "SIN PERMISO"; then
    fallo "VENDEDOR pudo llamar SP_LISTAR_CATEGORIAS (exige CATEGORIAS_VER)"
fi

# --- 4) Queda registrado --------------------------------------------------
rechazos=$(QA -N -e "SELECT COUNT(*) FROM LOG_PERMISO_SP
                      WHERE RUTINA = 'SP_LISTAR_CATEGORIAS'
                        AND USUARIO = '$USR' AND RESULTADO = 'SIN_PERMISO';")
case "$rechazos" in
    ''|*[!0-9]*) fallo "no se pudo leer LOG_PERMISO_SP" ;;
    0) fallo "el rechazo no quedo registrado en LOG_PERMISO_SP" ;;
esac

if [ "$fallos" -eq 0 ]; then
    echo "OK guarda de permisos en SPs (sin token, permitido, prohibido y registro)."
    exit 0
fi
echo "--- sin token ---"; printf '%s\n' "$sin_token" | head -n 3
echo "--- permitido ---"; printf '%s\n' "$permitido" | head -n 3
echo "--- prohibido ---"; printf '%s\n' "$prohibido" | head -n 3
exit 1
