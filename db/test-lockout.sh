#!/usr/bin/env bash
# (03/11/2026, T2) Regresion del bloqueo por fuerza bruta y de FN_TIENE_PERMISO.
#
# Cubre:
#   1. Cinco fallos del mismo usuario dentro de la ventana bloquean la cuenta.
#   2. Un intento bloqueado NO escribe en LOG_ACCESOS (si escribiera, cada
#      reintento correria la ventana y el bloqueo no venceria nunca).
#   3. Vencida la ventana, la clave correcta vuelve a entrar.
#   4. FN_TIENE_PERMISO devuelve 0 para una cuenta INACTIVO.
#   5. El conteo del login usa IX_LOG_ACCESOS_USUARIO_FECHA.
#
# Uso dentro del contenedor app (nunca contra la base viva):
#   BALBU_PASS=<clave del admin> bash db/test-lockout.sh
# El repo no guarda credenciales: la clave se pasa por env. DB_* y DB_ADMIN_*
# salen del .env del contenedor.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave del usuario admin)}"

USR="prueba_lock_t2"
CED="TESTLCK01"
MAX_FALLOS_ESPERADO=5

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
    echo "ERROR: no hay conexion util a $DB_HOST:$DB_PORT (base $DB_NAME, usuario $DB_USER)." >&2
    echo "       Respuesta: $pre" >&2
    exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lockout.XXXXXX")"
# limpiar_datos deja la base como estaba; limpiar agrega el borrado del
# directorio temporal. Se separan porque la preparacion del test vuelve a usar
# $TMP despues de limpiar los restos de una corrida anterior.
limpiar_datos() {
    # Orden por FKs: log de accesos, auditoria de usuarios, usuarios y
    # despues empleados. LOG_USUARIOS tiene FK sin cascada hacia USUARIOS
    # (tambien por ID_USUARIO_ADMIN), asi que sin borrarla el DELETE del
    # usuario falla con 1451 y deja el empleado huerfano con su TELEFONO
    # UNIQUE ocupado. El empleado se ubica por cedula, telefono o email
    # porque las tres columnas son UNIQUE.
    local id_usr
    id_usr=$(Q "SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = '$USR';")
    Q "DELETE FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR';" >/dev/null
    case "$id_usr" in
        ''|*[!0-9]*) : ;;
        *) Q "DELETE FROM LOG_USUARIOS WHERE ID_USUARIO = $id_usr OR ID_USUARIO_ADMIN = $id_usr;" >/dev/null ;;
    esac
    Q "DELETE FROM USUARIOS WHERE USUARIO = '$USR';" >/dev/null
    Q "DELETE FROM EMPLEADOS WHERE CEDULA = '$CED' OR TELEFONO = 'T-LCK-001' OR EMAIL = 'lock-t2@test.local';" >/dev/null
}
limpiar() {
    limpiar_datos
    rm -rf "$TMP"
}
trap limpiar EXIT

# Alta del usuario desechable: se deriva la clave de BALBU_PASS (desde el
# modulo 65 el admin puede tener CONTRASENA en NULL) y se copia su rol.
. "$(dirname "$0")/lib-clave-prueba.sh"
HASH=$(clave_pbkdf2 "$BALBU_PASS")
ID_ROL=$(Q "SELECT ID_ROL FROM USUARIOS WHERE USUARIO = '$BALBU_USER';")
if [ -z "$HASH" ] || [ -z "$ID_ROL" ]; then
    echo "No existe el usuario '$BALBU_USER' en $DB_NAME." >&2
    exit 1
fi

# Restos de una corrida anterior: el test es idempotente y los borra antes de
# arrancar (orden por FKs: log, usuarios, empleados).
limpiar_datos

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" >/dev/null <<EOF
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA LOCKOUT T2', '$CED', 'PRUEBA', 1000, 'T-LCK-001', 'lock-t2@test.local', '2026-11-03');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR', '$HASH', E.ID_EMPLEADO, $ID_ROL
  FROM EMPLEADOS E WHERE E.CEDULA = '$CED';
EOF

if [ -z "$(Q "SELECT USUARIO FROM USUARIOS WHERE USUARIO = '$USR';")" ]; then
    echo "ERROR: no se pudo crear el usuario de prueba '$USR'." >&2
    exit 1
fi
# Los fallos son por usuario, no por corrida: sin esto la prueba arrastraria
# intentos viejos y el conteo de 3 y 5 fallaria.
Q "DELETE FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR';" >/dev/null

fallos=0
fallo() { echo "FALLO: $*"; fallos=$((fallos + 1)); }
cuenta() { Q "SELECT COUNT(*) FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR';"; }
cuenta_estado() { Q "SELECT COUNT(*) FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR' AND ESTADO_INTENTO = '$1';"; }

# Corre la app por el camino interactivo: sin el atajo DEV, que saltea el login.
correr() {
    local salida="$1" entrada="$2"
    printf '%b' "$entrada" | env -u BALBU_USER -u BALBU_PASS -u BALBU_ALLOW_DEV_LOGIN \
        DB_NAME="$DB_NAME" timeout "$LIMITE" "$APP" >"$salida" 2>&1
    echo $?
}

# --- 1) Tres fallos en un solo proceso -------------------------------------
rc=$(correr "$TMP/run1.txt" "$USR\nmala\n$USR\nmala\n$USR\nmala\n")
if [ "$rc" != "0" ]; then
    fallo "run1 salio con $rc (se esperaba 0)"
fi
if [ "$(cuenta_estado FALLIDO)" != "3" ]; then
    fallo "tras 3 fallos LOG_ACCESOS tiene $(cuenta_estado FALLIDO) filas FALLIDO (se esperaban 3)"
fi
if grep -q "Cuenta bloqueada" "$TMP/run1.txt"; then
    fallo "se bloqueo con 3 fallos; el umbral es $MAX_FALLOS_ESPERADO"
fi

# --- 2) Dos fallos mas: el quinto activa el bloqueo ------------------------
rc=$(correr "$TMP/run2.txt" "$USR\nmala\n$USR\nmala\n$USR\n$BALBU_PASS\n")
if [ "$rc" != "0" ]; then
    fallo "run2 salio con $rc (se esperaba 0)"
fi
if [ "$(cuenta_estado FALLIDO)" != "5" ]; then
    fallo "tras 5 fallos LOG_ACCESOS tiene $(cuenta_estado FALLIDO) filas FALLIDO (se esperaban 5)"
fi
if ! grep -q "Cuenta bloqueada" "$TMP/run2.txt"; then
    fallo "el quinto fallo no bloqueo la cuenta (falta 'Cuenta bloqueada')"
fi
# Un chequeo de seguridad que falla en silencio se lee como "no hay bloqueo":
# si el SP o los privilegios estan mal, la app lo dice por stderr y el test
# tiene que fallar por eso, no pasar de casualidad.
if grep -q "No se pudo evaluar el bloqueo" "$TMP/run1.txt" "$TMP/run2.txt"; then
    fallo "el chequeo de bloqueo no corre (revisar SP_ESTADO_BLOQUEO_LOGIN y db/grant-minimos.sql)"
fi
if grep -q "Acceso concedido" "$TMP/run2.txt"; then
    fallo "concedio el acceso con la cuenta bloqueada"
fi

# --- 3) Bloqueada: la clave correcta no entra ni deja fila nueva ----------
antes=$(cuenta)
rc=$(correr "$TMP/run3.txt" "$USR\n$BALBU_PASS\n")
despues=$(cuenta)
if [ "$antes" != "$despues" ]; then
    fallo "un intento bloqueado escribio en LOG_ACCESOS ($antes -> $despues)"
fi
if ! grep -q "Cuenta bloqueada" "$TMP/run3.txt"; then
    fallo "la clave correcta no reporto el bloqueo"
fi
if grep -q "Acceso concedido" "$TMP/run3.txt"; then
    fallo "la clave correcta entro con la cuenta bloqueada"
fi

# --- 4) Vencida la ventana, la clave correcta vuelve a entrar -------------
if ! Q "UPDATE LOG_ACCESOS SET FECHA_ACCESO = DATE_SUB(NOW(), INTERVAL 20 MINUTE) WHERE USUARIO_INTENTADO = '$USR';" >/dev/null; then
    fallo "no se pudieron envejecer los fallos para probar el vencimiento"
fi
rc=$(correr "$TMP/run4.txt" "$USR\n$BALBU_PASS\n\n0\n")
if ! grep -q "Acceso concedido" "$TMP/run4.txt"; then
    fallo "vencida la ventana no dejo entrar con la clave correcta"
fi
if [ "$(cuenta_estado EXITOSO)" != "1" ]; then
    fallo "no quedo un unico registro EXITOSO (hay $(cuenta_estado EXITOSO))"
fi

# --- 5) FN_TIENE_PERMISO ignora cuentas INACTIVO --------------------------
activo=$(Q "SELECT FN_TIENE_PERMISO('$USR', 'GESTIONAR_VENTAS');")
Q "UPDATE USUARIOS SET ESTADO = 'INACTIVO' WHERE USUARIO = '$USR';" >/dev/null
inactivo=$(Q "SELECT FN_TIENE_PERMISO('$USR', 'GESTIONAR_VENTAS');")
Q "UPDATE USUARIOS SET ESTADO = 'ACTIVO' WHERE USUARIO = '$USR';" >/dev/null
if [ "$activo" != "1" ]; then
    fallo "FN_TIENE_PERMISO devolvio '$activo' para una cuenta ACTIVO con el permiso (se esperaba 1)"
fi
if [ "$inactivo" != "0" ]; then
    fallo "FN_TIENE_PERMISO devolvio '$inactivo' para una cuenta INACTIVO (se esperaba 0)"
fi

# --- 6) El conteo usa el indice del bloqueo -------------------------------
plan=$(Q "EXPLAIN SELECT COUNT(*) FROM LOG_ACCESOS WHERE USUARIO_INTENTADO = '$USR' AND ESTADO_INTENTO = 'FALLIDO' AND FECHA_ACCESO >= NOW() - INTERVAL 15 MINUTE;")
if ! printf '%s' "$plan" | grep -q "IX_LOG_ACCESOS_USUARIO_FECHA"; then
    fallo "EXPLAIN no usa IX_LOG_ACCESOS_USUARIO_FECHA (aplicar modulos/64- SEGURIDAD_T2.sql)"
fi

if [ "$fallos" -eq 0 ]; then
    echo "OK bloqueo por fuerza bruta (5 fallos / 15 min), sin filas al reintentar y FN_TIENE_PERMISO con ESTADO."
    exit 0
fi
echo "--- run1 ---"; head -n 20 "$TMP/run1.txt"
echo "--- run2 ---"; head -n 20 "$TMP/run2.txt"
echo "--- run3 ---"; head -n 20 "$TMP/run3.txt"
echo "--- run4 ---"; head -n 20 "$TMP/run4.txt"
exit 1
