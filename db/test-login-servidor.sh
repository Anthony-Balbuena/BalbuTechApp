#!/usr/bin/env bash
# (03/11/2026) Regresion del login con verificacion en el servidor (modulo 65).
#
# Cubre:
#   1. Login con el formato viejo (pbkdf2 en CONTRASENA) y migracion automatica:
#      al entrar, CONTRASENA queda NULL y CLAVE_SERVIDOR con el valor nuevo.
#   2. Segundo login con el formato del servidor (SALT_LOGIN + CLAVE_SERVIDOR).
#   3. Clave incorrecta rechazada, sin dejar el usuario migrado a medias.
#   4. balbu_app NO puede leer CONTRASENA ni SECRETO_SISTEMA.
#
# Uso (nunca contra la base viva):
#   BALBU_PASS=<clave del admin> DB_NAME=BALBU_TECH_TEST bash db/test-login-servidor.sh
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
# DB_PASSWORD del entorno es la clave de la app (balbu_app, ver .env); se
# guarda antes de pisarla con la del admin, que es la que usa el test para
# preparar datos.
APP_USER="${DB_APP_USER:-balbu_app}"
APP_PASS="${DB_APP_PASSWORD:-${DB_PASSWORD:-}}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave del usuario admin)}"

if [ -z "$APP_PASS" ]; then
    echo "Falta la clave de $APP_USER (DB_PASSWORD en .env) para probar los grants." >&2
    exit 1
fi

USR="prueba_login_srv"
CED="TESTLSV01"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>&1; }

if ! pre=$(Q "SELECT COUNT(*) FROM LOG_ACCESOS;") || ! printf '%s' "$pre" | grep -qE '^[0-9]+$'; then
    echo "ERROR: no hay conexion util a $DB_HOST:$DB_PORT (base $DB_NAME)." >&2
    echo "       Respuesta: $pre" >&2
    exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/login-srv.XXXXXX")"
limpiar_datos() {
    local id
    id=$(Q "SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = '$USR';")
    Q "DELETE FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR';" >/dev/null
    case "$id" in
        ''|*[!0-9]*) : ;;
        *) Q "DELETE FROM LOG_USUARIOS WHERE ID_USUARIO = $id OR ID_USUARIO_ADMIN = $id;" >/dev/null ;;
    esac
    Q "DELETE FROM USUARIOS WHERE USUARIO = '$USR';" >/dev/null
    Q "DELETE FROM EMPLEADOS WHERE CEDULA = '$CED';" >/dev/null
}
limpiar() { limpiar_datos; rm -rf "$TMP"; }
trap limpiar EXIT

limpiar_datos

# (03/11/2026) El usuario nace en el formato viejo (pbkdf2 en CONTRASENA) para
# probar la migracion automatica. Se deriva de BALBU_PASS: copiar el hash del
# admin ya no sirve porque desde el modulo 65 puede estar en NULL.
. "$(dirname "$0")/lib-clave-prueba.sh"
HASH=$(clave_pbkdf2 "$BALBU_PASS")
ID_ROL=$(Q "SELECT ID_ROL FROM USUARIOS WHERE USUARIO = '$BALBU_USER';")
if [ -z "$HASH" ] || [ -z "$ID_ROL" ]; then
    echo "No se pudo preparar el usuario de prueba en $DB_NAME." >&2
    exit 1
fi

Q "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
   VALUES ('PRUEBA LOGIN SRV', '$CED', 'PRUEBA', 1000, 'T-LSV-001', 'login-srv@test.local', '2026-11-03');"
EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$CED';")
printf "INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL) VALUES ('%s', '%s', %s, %s);\n" \
    "$USR" "$HASH" "$EMP" "$ID_ROL" > "$TMP/alta.sql"
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" < "$TMP/alta.sql"

if [ -z "$(Q "SELECT USUARIO FROM USUARIOS WHERE USUARIO = '$USR';")" ]; then
    echo "ERROR: no se pudo crear el usuario de prueba '$USR'." >&2
    exit 1
fi

fallos=0
fallo() { echo "FALLO: $*"; fallos=$((fallos + 1)); }

correr() {
    local salida="$1" entrada="$2"
    printf '%b' "$entrada" | env -u BALBU_USER -u BALBU_PASS -u BALBU_ALLOW_DEV_LOGIN \
        DB_NAME="$DB_NAME" timeout "$LIMITE" "$APP" >"$salida" 2>&1
    echo $?
}

# --- 1) Primer login: formato viejo y migracion ---------------------------
rc=$(correr "$TMP/r1.txt" "$USR\n$BALBU_PASS\n\n0\n")
if ! grep -q "Acceso concedido" "$TMP/r1.txt"; then
    fallo "el primer login (formato pbkdf2) no entro"
fi
if [ "$(Q "SELECT CONTRASENA IS NULL FROM USUARIOS WHERE USUARIO = '$USR';")" != "1" ]; then
    fallo "CONTRASENA no quedo en NULL tras la migracion"
fi
if [ "$(Q "SELECT CLAVE_SERVIDOR IS NOT NULL FROM USUARIOS WHERE USUARIO = '$USR';")" != "1" ]; then
    fallo "CLAVE_SERVIDOR quedo vacia tras la migracion"
fi
if [ "$(Q "SELECT SALT_LOGIN IS NOT NULL FROM USUARIOS WHERE USUARIO = '$USR';")" != "1" ]; then
    fallo "SALT_LOGIN quedo vacia tras la migracion"
fi

# --- 2) Segundo login: formato del servidor -------------------------------
rc=$(correr "$TMP/r2.txt" "$USR\n$BALBU_PASS\n\n0\n")
if ! grep -q "Acceso concedido" "$TMP/r2.txt"; then
    fallo "el segundo login (formato servidor) no entro"
fi
if grep -q "No se pudo derivar" "$TMP/r2.txt"; then
    fallo "la derivacion fallo en el formato del servidor"
fi

# --- 3) Clave incorrecta --------------------------------------------------
rc=$(correr "$TMP/r3.txt" "$USR\nclave_que_no_es\n")
if grep -q "Acceso concedido" "$TMP/r3.txt"; then
    fallo "acepto una clave incorrecta"
fi
if ! grep -q "Credenciales inválidas" "$TMP/r3.txt"; then
    fallo "no reporto credenciales invalidas con clave incorrecta"
fi

# --- 4) La app no puede leer el material de claves ------------------------
lectura=$(printf "SELECT CONTRASENA FROM USUARIOS LIMIT 1;\n" | \
    mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$APP_USER" -p"$APP_PASS" \
            --database="$DB_NAME" 2>&1)
if ! printf '%s' "$lectura" | grep -q "denied"; then
    fallo "balbu_app todavia puede leer USUARIOS.CONTRASENA"
fi
pepper=$(printf "SELECT VALOR FROM SECRETO_SISTEMA;\n" | \
    mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$APP_USER" -p"$APP_PASS" \
            --database="$DB_NAME" 2>&1)
if ! printf '%s' "$pepper" | grep -q "denied"; then
    fallo "balbu_app puede leer el pepper de SECRETO_SISTEMA"
fi

if [ "$fallos" -eq 0 ]; then
    echo "OK login en servidor (migracion automatica, segundo login, clave mala y hash inaccesible)."
    exit 0
fi
echo "--- r1 ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/r1.txt" | head -n 12
echo "--- r2 ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/r2.txt" | head -n 12
echo "--- r3 ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/r3.txt" | head -n 12
exit 1
