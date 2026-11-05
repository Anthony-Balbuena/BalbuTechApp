#!/usr/bin/env bash
# (05/11/2026) Regresion del cambio de clave desde la app (modulo 67).
#
# Cubre:
#   1. El admin cambia la clave de otro usuario: queda en el formato del
#      servidor (SALT_LOGIN + CLAVE_SERVIDOR con pepper, CONTRASENA NULL).
#   2. La clave nueva entra por la app y la vieja ya no.
#   3. El cambio cierra las sesiones abiertas de ese usuario.
#   4. Un token de VENDEDOR no puede cambiar claves (USUARIOS_CLAVE es ADMIN).
#   5. La clave nueva se guarda con sal e iteraciones propias, no reusa las
#      viejas.
#
# Uso (nunca contra la base viva):
#   BALBU_PASS=<clave cualquiera> DB_NAME=BALBU_TECH_TEST bash db/test-cambio-clave.sh
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
APP_USER="${DB_APP_USER:-balbu_app}"
APP_PASS="${DB_APP_PASSWORD:-${DB_PASSWORD:-}}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave de prueba, no hace falta la real)}"

USR="prueba_clave_srv"
USR_ADM="prueba_clave_adm"
USR_VEN="prueba_clave_ven"
USR_ALTA="prueba_clave_alta"
CED="TESTSCC01"
CED_ADM="TESTSCC02"
CED_VEN="TESTSCC03"
CED_ALTA="TESTSCC04"
CLAVE_VIEJA="ClaveVieja123"
CLAVE_NUEVA="ClaveNueva456"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi
if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi
if [ -z "$APP_PASS" ]; then
    echo "Falta la clave de $APP_USER (DB_PASSWORD del .env) para probar la guarda." >&2
    exit 1
fi

QA() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }
QAPP() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$APP_USER" -p"$APP_PASS" --database="$DB_NAME" "$@" 2>&1; }

if ! pre=$(QA -N -e "SELECT COUNT(*) FROM USUARIOS;") || ! printf '%s' "$pre" | grep -qE '^[0-9]+$'; then
    echo "ERROR: no hay conexion util a $DB_HOST:$DB_PORT (base $DB_NAME)." >&2
    exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cambio-clave.XXXXXX")"

limpiar_datos() {
    local u id
    for u in "$USR" "$USR_ADM" "$USR_VEN" "$USR_ALTA"; do
        id=$(QA -N -e "SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = '$u';" | grep -E '^[0-9]+$' || true)
        QA -e "DELETE FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$u';" >/dev/null
        if [ -n "$id" ]; then
            QA -e "DELETE FROM SESIONES WHERE ID_USUARIO = $id;" >/dev/null
            QA -e "DELETE FROM LOG_PERMISO_SP WHERE USUARIO = '$u';" >/dev/null
            QA -e "DELETE FROM LOG_USUARIOS WHERE ID_USUARIO = $id OR ID_USUARIO_ADMIN = $id;" >/dev/null
        fi
        QA -e "DELETE FROM USUARIOS WHERE USUARIO = '$u';" >/dev/null
    done
    QA -e "DELETE FROM EMPLEADOS WHERE CEDULA IN ('$CED', '$CED_ADM', '$CED_VEN', '$CED_ALTA');" >/dev/null
}
limpiar() { limpiar_datos; rm -rf "$TMP"; }
trap limpiar EXIT
limpiar_datos

. "$(dirname "$0")/lib-clave-prueba.sh"

alta_usuario() { # <usuario> <cedula> <nombre_rol> <clave>
    local hash emp rol
    hash=$(clave_pbkdf2 "$4")
    QA -e "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
           VALUES ('PRUEBA CLAVE SRV', '$2', 'PRUEBA', 1000, 'T-$2', 'clave-$2@test.local', '2026-11-05');" >/dev/null
    emp=$(QA -N -e "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$2';" | tr -d '[:space:]')
    rol=$(QA -N -e "SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL = '$3';" | tr -d '[:space:]')
    if ! printf '%s' "$emp" | grep -qE '^[0-9]+$' || ! printf '%s' "$rol" | grep -qE '^[0-9]+$'; then
        echo "ERROR: no se pudo preparar '$1' (empleado='$emp' rol='$rol')." >&2
        exit 1
    fi
    QA -e "INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
           VALUES ('$1', '$hash', $emp, $rol);" >/dev/null
    printf '%s' "$hash" | cut -d'$' -f4   # derivado, para pedir token
}

DERIV_VIEJA=$(alta_usuario "$USR" "$CED" "VENDEDOR" "$CLAVE_VIEJA")
DERIV_ADM=$(alta_usuario "$USR_ADM" "$CED_ADM" "ADMIN" "$BALBU_PASS")
DERIV_VEN=$(alta_usuario "$USR_VEN" "$CED_VEN" "VENDEDOR" "$BALBU_PASS")

ID_USUARIO=$(QA -N -e "SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = '$USR';" | grep -E '^[0-9]+$')
if [ -z "$ID_USUARIO" ]; then
    echo "ERROR: no se creo el usuario de prueba." >&2
    exit 1
fi

fallos=0
fallo() { echo "FALLO: $*"; fallos=$((fallos + 1)); }

correr() { # <salida> <entrada> [usuario]
    local salida="$1" entrada="$2"
    printf '%b' "$entrada" | env -u BALBU_USER -u BALBU_PASS -u BALBU_ALLOW_DEV_LOGIN \
        DB_NAME="$DB_NAME" timeout "$LIMITE" "$APP" >"$salida" 2>&1
    echo $?
}

# --- 1) Primer login: migra al formato del servidor -----------------------
correr "$TMP/r1.txt" "$USR\n$CLAVE_VIEJA\n\n0\n" >/dev/null
if ! grep -q "Acceso concedido" "$TMP/r1.txt"; then
    fallo "la clave vieja (formato pbkdf2) no entro"
fi
if [ "$(QA -N -e "SELECT CLAVE_SERVIDOR IS NOT NULL FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')" != "1" ]; then
    fallo "el usuario no migro al formato del servidor antes del cambio"
fi
SALT_VIEJA=$(QA -N -e "SELECT SALT_LOGIN FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')
if [ -z "$SALT_VIEJA" ]; then
    fallo "SALT_LOGIN quedo vacia tras la migracion"
fi

# Sesion abierta a proposito: el cambio de clave tiene que cerrarla.
TOKEN_PREVIO=$(QA -N -e "CALL SP_LOGIN_AUTENTICAR('$USR', '$DERIV_VIEJA');" | tail -n 1 | cut -f9)
if [ -z "$TOKEN_PREVIO" ]; then
    fallo "no se pudo abrir una sesion de prueba antes del cambio"
fi

# --- 2) El admin cambia la clave -----------------------------------------
HASH_NUEVA=$(clave_pbkdf2 "$CLAVE_NUEVA")
resp=$(QA -N -e "CALL SP_CAMBIAR_CLAVE_USUARIO($ID_USUARIO, '$HASH_NUEVA');")
if ! printf '%s' "$resp" | grep -q "EXITO"; then
    fallo "SP_CAMBIAR_CLAVE_USUARIO no devolvio EXITO ($resp)"
fi

# --- 3) Queda en el formato del servidor ---------------------------------
if [ "$(QA -N -e "SELECT CONTRASENA IS NULL FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')" != "1" ]; then
    fallo "CONTRASENA no quedo en NULL"
fi
if [ "$(QA -N -e "SELECT CLAVE_SERVIDOR IS NOT NULL FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')" != "1" ]; then
    fallo "CLAVE_SERVIDOR quedo vacia tras el cambio"
fi
SALT_NUEVA=$(QA -N -e "SELECT SALT_LOGIN FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')
if [ -z "$SALT_NUEVA" ]; then
    fallo "SALT_LOGIN quedo vacia tras el cambio"
elif [ "$SALT_NUEVA" = "$SALT_VIEJA" ]; then
    fallo "el cambio reuso la sal vieja en vez de generar una nueva"
fi

# --- 4) El cambio cierra las sesiones del usuario ------------------------
sesiones=$(QA -N -e "SELECT COUNT(*) FROM SESIONES WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')
if [ "$sesiones" != "0" ]; then
    fallo "quedaron $sesiones sesiones abiertas despues del cambio de clave"
fi
if [ -n "$TOKEN_PREVIO" ] && [ "$(QA -N -e "SELECT COUNT(*) FROM SESIONES WHERE TOKEN = '$TOKEN_PREVIO';" | tr -d '[:space:]')" != "0" ]; then
    fallo "el token anterior sobrevivio al cambio de clave"
fi

# --- 5) La clave nueva entra y la vieja no -------------------------------
correr "$TMP/r2.txt" "$USR\n$CLAVE_NUEVA\n\n0\n" >/dev/null
if ! grep -q "Acceso concedido" "$TMP/r2.txt"; then
    fallo "la clave nueva no entra por la app"
fi
correr "$TMP/r3.txt" "$USR\n$CLAVE_VIEJA\n" >/dev/null
if grep -q "Acceso concedido" "$TMP/r3.txt"; then
    fallo "la clave vieja sigue entrando despues del cambio"
fi

# --- 6) Guarda: VENDEDOR no puede, ADMIN si ------------------------------
TOKEN_VEN=$(QA -N -e "CALL SP_LOGIN_AUTENTICAR('$USR_VEN', '$DERIV_VEN');" | tail -n 1 | cut -f9)
TOKEN_ADM=$(QA -N -e "CALL SP_LOGIN_AUTENTICAR('$USR_ADM', '$DERIV_ADM');" | tail -n 1 | cut -f9)
if [ -z "$TOKEN_VEN" ] || [ -z "$TOKEN_ADM" ]; then
    fallo "no se pudieron emitir los tokens de prueba (ven='$TOKEN_VEN' adm='$TOKEN_ADM')"
else
    HASH_OTRA=$(clave_pbkdf2 "OtraClave789")
    ven=$(QAPP -e "SET @TOKEN_SESION = '$TOKEN_VEN'; CALL SP_CAMBIAR_CLAVE_USUARIO($ID_USUARIO, '$HASH_OTRA');")
    if printf '%s' "$ven" | grep -q "EXITO\|ACTUALIZADA"; then
        fallo "un VENDEDOR pudo cambiar una clave"
    fi
    if ! printf '%s' "$ven" | grep -q "SIN PERMISO"; then
        fallo "el rechazo a VENDEDOR no fue por SIN PERMISO ($ven)"
    fi
    adm=$(QAPP -e "SET @TOKEN_SESION = '$TOKEN_ADM'; CALL SP_CAMBIAR_CLAVE_USUARIO($ID_USUARIO, '$HASH_OTRA');")
    if ! printf '%s' "$adm" | grep -q "EXITO"; then
        fallo "un ADMIN con token no pudo cambiar la clave ($adm)"
    fi
fi

# --- 6b) Formatos invalidos se rechazan sin tocar la clave ----------------
SRV_ANTES=$(QA -N -e "SELECT IFNULL(CLAVE_SERVIDOR,'') FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')
for malo in "abc123" "pbkdf2\$abc\$c2FsdA==\$ZGs=" "pbkdf2\$0\$c2FsdA==\$ZGs="; do
    r=$(QA -N -e "CALL SP_CAMBIAR_CLAVE_USUARIO($ID_USUARIO, '$malo');")
    if ! printf '%s' "$r" | grep -q "FORMATO DE CLAVE INVALIDO"; then
        fallo "el formato '$malo' no fue rechazado ($r)"
    fi
done
SRV_DESPUES=$(QA -N -e "SELECT IFNULL(CLAVE_SERVIDOR,'') FROM USUARIOS WHERE ID_USUARIO = $ID_USUARIO;" | tr -d '[:space:]')
if [ "$SRV_ANTES" != "$SRV_DESPUES" ]; then
    fallo "un formato invalido cambio CLAVE_SERVIDOR"
fi

# --- 7) El alta desde la app guarda el formato serializado ----------------
# El otro camino que escribia SHA256: un usuario creado asi queda sin sal y no
# migra nunca, porque la migracion del 65 exige CONTRASENA LIKE 'pbkdf2$%'.
QA -e "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
       VALUES ('PRUEBA CLAVE ALTA', '$CED_ALTA', 'PRUEBA', 1000, 'T-$CED_ALTA', 'clave-$CED_ALTA@test.local', '2026-11-05');" >/dev/null
ID_EMP_ALTA=$(QA -N -e "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$CED_ALTA';" | tr -d '[:space:]')
ID_ROL_VEN=$(QA -N -e "SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL = 'VENDEDOR';" | tr -d '[:space:]')
if [ -z "$ID_EMP_ALTA" ] || [ -z "$ID_ROL_VEN" ]; then
    fallo "no se pudo preparar el alta de usuario (empleado='$ID_EMP_ALTA' rol='$ID_ROL_VEN')"
else
    # Menu de ADMIN: 3 = Usuarios; adentro 1 = Agregar Usuario, 7 = Volver.
    printf '\n3\n1\n%s\n%s\n%s\n%s\n7\n' "$USR_ALTA" "ClaveAlta123" "$ID_ROL_VEN" "$ID_EMP_ALTA" \
        | env -u BALBU_USER -u BALBU_PASS BALBU_ALLOW_DEV_LOGIN=1 BALBU_USER="$USR_ADM" \
              BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" timeout "$LIMITE" "$APP" >"$TMP/alta.txt" 2>&1
    if ! grep -q "CREADO" "$TMP/alta.txt"; then
        fallo "el alta de usuario desde la app no devolvio CREADO"
    fi
    if [ "$(QA -N -e "SELECT CONTRASENA LIKE 'pbkdf2\$%' FROM USUARIOS WHERE USUARIO = '$USR_ALTA';" | tr -d '[:space:]')" != "1" ]; then
        fallo "el alta guardo la clave fuera del formato pbkdf2"
    fi
    correr "$TMP/r4.txt" "$USR_ALTA\nClaveAlta123\n\n0\n" >/dev/null
    if ! grep -q "Acceso concedido" "$TMP/r4.txt"; then
        fallo "el usuario creado desde la app no puede entrar con su clave"
    fi
fi

if [ "$fallos" -eq 0 ]; then
    echo "OK cambio de clave (formato del servidor, sal nueva, sesiones cerradas, ADMIN si y VENDEDOR no, alta en pbkdf2)."
    exit 0
fi
echo "--- r1 (clave vieja) ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/r1.txt" | head -n 8
echo "--- r2 (clave nueva) ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/r2.txt" | head -n 8
echo "--- alta (usuarios) ---"; sed -e 's/\x1b\[[0-9;]*m//g' "$TMP/alta.txt" | grep -i "EXITO\|ERROR\|CREADO\|INVALIDO" | head -n 5
exit 1
