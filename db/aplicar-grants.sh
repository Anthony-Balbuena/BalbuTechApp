#!/usr/bin/env bash
# Aplica db/grant-minimos.sql a UN esquema. Va con root porque GRANT/REVOKE no
# se pueden delegar a balbu_admin (no tiene GRANT OPTION).
#
# ES IDEMPOTENTE: se puede correr las veces que haga falta sobre la misma base y
# siempre deja el mismo estado. El SQL empieza revocando todo (esquema, tablas
# con grants por columna) y despues vuelve a otorgar solo lo minimo, asi que
# correrlo dos veces no acumula ni duplica nada.
#
# Uso desde el host (con el .env cargado):
#   set -a; . ./.env; set +a
#   DB_HOST=127.0.0.1 bash db/aplicar-grants.sh BALBU_TECH
#
# Uso dentro del contenedor db (conexion por socket, DB_ROOT_PASSWORD ya esta):
#   bash db/aplicar-grants.sh BALBU_TECH
#
# Variables:
#   DB_HOST / DB_PORT   si DB_HOST esta seteado se conecta por TCP; si no, por
#                       socket. Sin esto el script solo andaba dentro del
#                       contenedor: desde el host no encontraba el socket.
#   DB_ROOT_PASSWORD    obligatoria. La trae el .env.
#   DB_APP_USER         cuenta de la app (por defecto balbu_app). Tiene que
#                       coincidir con la del .env de la app.
#
# El archivo se corre con --force y despues se validan tres cosas: que no haya
# errores distintos de "no habia grant previo" (1141/1147), que la app NO
# conserve acceso a material de claves, y que SHOW GRANTS haya respondido algo.
# Validar el resultado es mas honesto que confiar en el codigo de salida de un
# REVOKE que puede no aplicar.
#
# Sale 0 si todas las cuentas quedaron bien, 1 si alguna quedo mal o si el
# archivo de privilegios fallo, 2 si el script no pudo trabajar (sin conexion,
# sin permisos, esquema o cuentas inexistentes).
set -u

DB="${1:-}"
if [ -z "$DB" ]; then
    echo "Falta el esquema. Uso: bash $0 BALBU_TECH_TEST" >&2
    exit 1
fi

# El nombre entra en SQL y en sed: si trae comillas, barras o espacios, se
# rompe de una forma dificil de leer. Los nombres de base son [A-Za-z0-9_].
case "$DB" in
    *[!A-Za-z0-9_]*)
        echo "ERROR: nombre de esquema invalido: '$DB' (solo A-Z, a-z, 0-9, _)." >&2
        exit 2
        ;;
esac

SQL_DIR="$(dirname "$0")"
SRC="$SQL_DIR/grant-minimos.sql"
[ -f "$SRC" ] || SRC=/tmp/grant-minimos.sql
if [ ! -f "$SRC" ]; then
    echo "No encuentro grant-minimos.sql (buscado en $SQL_DIR y /tmp)." >&2
    exit 1
fi

: "${DB_ROOT_PASSWORD:?Falta DB_ROOT_PASSWORD: carga el .env o corre dentro del contenedor db}"
APP_USER="${DB_APP_USER:-balbu_app}"
# Igual que el esquema: la cuenta entra en SQL y en sed.
case "$APP_USER" in
    *[!A-Za-z0-9_.-]*)
        echo "ERROR: nombre de cuenta invalido: '$APP_USER'." >&2
        exit 2
        ;;
esac

# Si DB_HOST viene seteado, TCP. Si no, socket (contenedor).
CONN=()
if [ -n "${DB_HOST:-}" ]; then
    CONN=(-h "$DB_HOST" -P "${DB_PORT:-3306}")
fi

R() { mariadb "${CONN[@]}" -uroot -p"$DB_ROOT_PASSWORD" "$@"; }

TMP="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$TMP" "$OUT"' EXIT

# (0) Conexion: sin esto, cualquier consulta fallida se confundiria con "no hay
#     cuentas" o "no hay grants" y el script mentiria con un falso OK.
if ! respuesta=$(R -N -B -e "SELECT 1" 2>&1); then
    echo "ERROR: no hay conexion como root (DB_HOST='${DB_HOST:-socket}')." >&2
    echo "       Respuesta: $respuesta" >&2
    echo "       Desde el host: DB_HOST=127.0.0.1 bash db/aplicar-grants.sh $DB" >&2
    exit 2
fi

# (1) El esquema tiene que existir: si no, los GRANT fallan con 1146 y el
#     mensaje real queda enterrado entre decenas de lineas.
existe=$(R -N -B -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB'" 2>&1)
if [ "${existe:-x}" != "1" ]; then
    echo "ERROR: el esquema '$DB' no existe (o no se pudo consultar: '$existe')." >&2
    exit 2
fi

# (2) MariaDB identifica la cuenta por usuario@host. En el contenedor la app
#     llega como 'balbu_app'@'%'; en una base local llega como
#     'balbu_app'@'localhost' y esa cuenta es OTRA, con sus propios privilegios.
#     Endurecer solo '%' dejaba la puerta abierta en la que realmente se usa.
HOSTS=$(R -N -B -e "SELECT Host FROM mysql.user WHERE User = '$APP_USER' ORDER BY Host" 2>&1)
if printf '%s' "$HOSTS" | grep -q '^ERROR'; then
    echo "ERROR: no se pudo leer mysql.user:" >&2
    printf '%s\n' "$HOSTS" | sed 's/^/    /' >&2
    exit 2
fi
if [ -z "$HOSTS" ]; then
    echo "ERROR: no existe ninguna cuenta '$APP_USER' en el servidor." >&2
    echo "       Crear las cuentas es tarea de db/crear-usuarios.sh." >&2
    exit 2
fi

cuentas=0
fallo=0
for HOST in $HOSTS; do
    cuentas=$((cuentas + 1))
    cuenta_fallo=0
    echo "Aplicando privilegios minimos a '$DB' para '$APP_USER'@'$HOST' ..."
    sed -e "s/__DB__/$DB/g" -e "s/__HOST__/$HOST/g" \
        -e "s/'balbu_app'@/'$APP_USER'@/g" "$SRC" > "$TMP"
    R --database="$DB" --force < "$TMP" > "$OUT" 2>&1

    # 1141: no habia privilegios de esquema que revocar.
    # 1147: no habia grant por columna/tabla que revocar.
    # Los dos son normales en la primera corrida y no son fallo.
    errors=$(grep -E "^ERROR" "$OUT" | grep -vE " 114[17] " || true)
    if [ -n "$errors" ]; then
        echo "ERROR: fallaron sentencias del grant para '$HOST':" >&2
        printf '%s\n' "$errors" | sed 's/^/    /' >&2
        fallo=1
        cuenta_fallo=1
        continue
    fi

    # (3) SHOW GRANTS tiene que responder. Si devuelve vacio, todo el chequeo de
    #     abajo pasaria sin mirar nada y el script diria "verificado" mintiendo.
    if ! GRANTS=$(R -N -e "SHOW GRANTS FOR '$APP_USER'@'$HOST'" 2>&1); then
        echo "ERROR: no se pudo leer SHOW GRANTS de '$APP_USER'@'$HOST':" >&2
        printf '%s\n' "$GRANTS" | sed 's/^/    /' >&2
        fallo=1
        cuenta_fallo=1
        continue
    fi
    if [ -z "$GRANTS" ]; then
        echo "ERROR: SHOW GRANTS de '$APP_USER'@'$HOST' volvio vacio; no se puede verificar." >&2
        fallo=1
        cuenta_fallo=1
        continue
    fi

    if printf '%s\n' "$GRANTS" | grep -q "$DB\`\.\`USUARIOS\`.*CONTRASENA"; then
        echo "ERROR: $APP_USER@'$HOST' conserva acceso a USUARIOS.CONTRASENA." >&2
        fallo=1
        cuenta_fallo=1
    fi
    if printf '%s\n' "$GRANTS" | grep -q "$DB\`\.\`SECRETO_SISTEMA\`"; then
        echo "ERROR: $APP_USER@'$HOST' tiene acceso a SECRETO_SISTEMA (el pepper)." >&2
        fallo=1
        cuenta_fallo=1
    fi
    # (05/11/2026) El chequeo miraba cualquier linea de SHOW GRANTS: si quedaban
    # grants viejos sobre OTROS esquemas (BALBU_TECH_PRE, ...V92), reportaba error
    # aunque $DB estuviera bien. Ahora filtra primero las lineas de $DB.
    amplios=$(printf '%s\n' "$GRANTS" | grep -F "\`$DB\`" | grep -E "INSERT|DELETE|CREATE TEMPORARY|SHOW VIEW" || true)
    if [ -n "$amplios" ]; then
        echo "ERROR: $APP_USER@'$HOST' conserva privilegios de escritura amplios sobre $DB." >&2
        printf '%s\n' "$amplios" | sed 's/^/    /' >&2
        fallo=1
        cuenta_fallo=1
    fi

    if [ "$cuenta_fallo" -eq 0 ]; then
        echo "OK: privilegios de '$DB' recortados y verificados para '$HOST'."
        printf '%s\n' "$GRANTS" | grep -F "\`$DB\`" | sed 's/^/  /'
    fi
done

echo ""
if [ "$fallo" -eq 0 ]; then
    echo "LISTO: $cuentas cuenta(s) de '$APP_USER' con privilegios minimos sobre '$DB'."
else
    echo "FALLO: alguna cuenta de '$APP_USER' no quedo con los privilegios esperados sobre '$DB'." >&2
fi

exit "$fallo"
