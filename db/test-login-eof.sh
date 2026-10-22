#!/usr/bin/env bash
# (21/10/2026) Regresion: con la entrada agotada, el login no debe girar ni
# ensuciar LOG_ACCESOS. Antes del arreglo, cada corrida con EOF (o Ctrl+D)
# gastaba los MAX_INTENTOS con usuario vacio y dejaba 3 filas
# '(vacio) / FALLIDO' en el log de accesos.
#
# Uso:  DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh
# Necesita una base ya importada (db/import.sh) y el binario compilado.
# No usa BALBU_USER/BALBU_PASS a proposito: el atajo de desarrollo saltea el
# login y este test tiene que entrar por el camino interactivo.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>&1; }

if [ ! -x "$APP" ]; then
  echo "FALTA el binario $APP: corre 'bash build.sh' primero."
  exit 1
fi

pre=$(Q "SELECT COUNT(*) FROM LOG_ACCESOS;")
case "$pre" in
  ''|*[!0-9]*)
    echo "ERROR: no hay conexion util a $DB_HOST:$DB_PORT (base $DB_NAME, usuario $DB_USER)."
    echo "       Respuesta: $pre"
    exit 1
    ;;
esac

TMP="$(mktemp -d /tmp/opencode/login-eof.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
out="$TMP/out.txt"

rc=$(env -u BALBU_USER -u BALBU_PASS timeout "$LIMITE" "$APP" </dev/null >"$out" 2>&1; echo $?)
post=$(Q "SELECT COUNT(*) FROM LOG_ACCESOS;")

fail=0

if [ "$rc" = "124" ]; then
  echo "FALLO: giro sin fin con la entrada agotada (timeout ${LIMITE}s)."
  fail=1
elif [ "$rc" != "0" ]; then
  echo "FALLO: exit $rc (se esperaba 0)."
  fail=1
fi

if [ "$post" != "$pre" ]; then
  echo "FALLO: con EOF escribio $((post - pre)) fila(s) en LOG_ACCESOS (antes $pre, despues $post)."
  fail=1
fi

if ! grep -q "Entrada agotada" "$out"; then
  echo "FALLO: no aviso 'Entrada agotada' (no corto por EOF)."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK login con entrada agotada (corta sin girar y sin ensuciar el log)"
else
  echo "--- salida de la app ---"
  head -n 20 "$out"
fi
exit $fail
