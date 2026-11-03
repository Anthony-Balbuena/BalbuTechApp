#!/usr/bin/env bash
# (03/11/2026) Aplica db/grant-minimos.sql a un esquema. Va con root porque
# GRANT/REVOKE no se pueden delegar a balbu_admin (no tiene GRANT OPTION).
#
# Uso (dentro del contenedor db, que tiene DB_ROOT_PASSWORD en el entorno):
#   bash /tmp/aplicar-grants.sh BALBU_TECH_TEST
# Desde el host:
#   docker compose cp db/grant-minimos.sql db:/tmp/grant-minimos.sql
#   docker compose cp db/aplicar-grants.sh db:/tmp/aplicar-grants.sh
#   docker compose exec -T db bash /tmp/aplicar-grants.sh BALBU_TECH_TEST
#
# El archivo se corre con --force y despues se validan dos cosas: que no haya
# errores distintos de "no habia grant previo" (1141/1147) y que la app NO
# conserve acceso a material de claves. Validar el resultado es mas honesto
# que confiar en el codigo de salida de un REVOKE que puede no aplicar.
set -u

DB="${1:-}"
if [ -z "$DB" ]; then
    echo "Falta el esquema. Uso: bash $0 BALBU_TECH_TEST" >&2
    exit 1
fi

SQL_DIR="$(dirname "$0")"
SRC="$SQL_DIR/grant-minimos.sql"
[ -f "$SRC" ] || SRC=/tmp/grant-minimos.sql
if [ ! -f "$SRC" ]; then
    echo "No encuentro grant-minimos.sql (buscado en $SQL_DIR y /tmp)." >&2
    exit 1
fi

TMP="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$TMP" "$OUT"' EXIT
sed "s/__DB__/$DB/g" "$SRC" > "$TMP"

echo "Aplicando privilegios minimos a '$DB' ..."
mariadb -uroot -p"$DB_ROOT_PASSWORD" --database="$DB" --force < "$TMP" > "$OUT" 2>&1

# 1141: no habia privilegios de esquema que revocar.
# 1147: no habia grant por columna/tabla que revocar.
errors=$(grep -E "^ERROR" "$OUT" | grep -vE " 114[17] " || true)
if [ -n "$errors" ]; then
    echo "ERROR: fallaron sentencias del grant:" >&2
    printf '%s\n' "$errors" >&2
    exit 1
fi

GRANTS=$(mariadb -uroot -p"$DB_ROOT_PASSWORD" -N -e "SHOW GRANTS FOR 'balbu_app'@'%'")

if printf '%s\n' "$GRANTS" | grep -q "$DB\`\.\`USUARIOS\`.*CONTRASENA"; then
    echo "ERROR: balbu_app conserva acceso a USUARIOS.CONTRASENA." >&2
    exit 1
fi
if printf '%s\n' "$GRANTS" | grep -q "$DB\`\.\`SECRETO_SISTEMA\`"; then
    echo "ERROR: balbu_app tiene acceso a SECRETO_SISTEMA (el pepper)." >&2
    exit 1
fi
if printf '%s\n' "$GRANTS" | grep -qE "INSERT|DELETE|CREATE TEMPORARY|SHOW VIEW.*\`$DB\`"; then
    echo "ERROR: balbu_app conserva privilegios de escritura amplios sobre $DB." >&2
    printf '%s\n' "$GRANTS" | grep -E "INSERT|DELETE|CREATE TEMPORARY|SHOW VIEW" >&2
    exit 1
fi

echo "OK: privilegios de '$DB' recortados y verificados."
printf '%s\n' "$GRANTS" | grep -F "\`$DB\`" | sed 's/^/  /'
