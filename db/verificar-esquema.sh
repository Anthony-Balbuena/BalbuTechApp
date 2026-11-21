#!/bin/bash
# Verificador de esquema: compara dos bases y dice si son la MISMA base.
#
# Nace de un hueco real (20/11/2026): el diff que usabamos para cerrar P-5,
# EMPLEADOS.CEDULA y PROVEEDORES comparaba tablas, indices, FK y CHECK, pero
# NUNCA cuerpos de triggers ni de rutinas. Por eso TR_BLOQUEAR_BORRADO_VENTA
# pudo quedarse con el cuerpo viejo en TEST sin que nada lo delatara.
#
# Compara, para cada base:
#   - tablas y vistas (motor, collation)
#   - columnas (tipo, null, default, extra, collation)
#   - indices (columnas, orden, unicidad, tipo, prefijo)
#   - claves foraneas (columnas y reglas ON UPDATE / ON DELETE)
#   - CHECK constraints (clausula)
#   - triggers (tiempo, evento, tabla, ACTION_ORDER y MD5 del cuerpo)
#   - rutinas (MD5 del cuerpo y atributos fisicos)
#   - vistas (MD5 de la definicion)
#
# El ACTION_ORDER importa: es el orden real en que MariaDB ejecuta los triggers
# de un mismo grupo y es lo unico que delata una cadena de FOLLOWS rota.
#
# Uso:
#   set -a; . ./.env; set +a
#   DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH bash db/verificar-esquema.sh
#       -> crea una base temporal, importa modulos/ ahi y compara BALBU_TECH
#          contra ese import desde cero.
#
#   bash db/verificar-esquema.sh BALBU_TECH BALBU_TECH_TEST
#       -> compara dos bases que ya existen. No importa nada.
#
# Opciones:
#   --conservar   no dropea la base temporal (imprime el nombre y el comando
#                 para dropearla a mano).
#   -h, --help
#
# Sale 0 si son identicas, 1 si hay diferencias, 2 si el script no pudo
# trabajar (sin conexion, sin permisos, import fallido).
#
# Nota: crear y dropear la base temporal necesita CREATE/DROP. Con
# balbu_admin sobre produccion puede no alcanzar; ahi conviene pasar las dos
# bases ya existentes y no usar el modo fresco.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"

CONSERVAR=0
POSICIONALES=()

uso() {
    cat <<'TXT'
Uso: bash db/verificar-esquema.sh [opciones] [BASE_A [BASE_B]]

Sin BASE_B: crea una base temporal, importa modulos/ ahi y compara BASE_A
            contra ese import desde cero (BASE_A por defecto, $DB_NAME).
Con BASE_B: compara las dos bases que ya existen. No importa nada.

Opciones:
  --conservar   no dropear la base temporal
  -h, --help    esta ayuda

Variables (normalmente vienen del .env):
  DB_HOST, DB_PORT, DB_NAME, DB_ADMIN_USER, DB_ADMIN_PASSWORD

Salida: 0 identicas, 1 con diferencias, 2 error del script.
TXT
}

while [ $# -gt 0 ]; do
    case "$1" in
        --conservar)
            CONSERVAR=1
            shift
            ;;
        -h|--help)
            uso
            exit 0
            ;;
        -*)
            echo "ERROR: opcion desconocida: $1" >&2
            uso >&2
            exit 2
            ;;
        *)
            POSICIONALES+=("$1")
            shift
            ;;
    esac
done

if [ "${#POSICIONALES[@]}" -gt 2 ]; then
    echo "ERROR: se aceptan como maximo dos bases." >&2
    uso >&2
    exit 2
fi

DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

MARIADB=(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD")

# 0) Conexion: sin esto, cualquier consulta fallida se confundiria con
#    "base vacia" y el diff diria que las dos son identicas.
if ! respuesta=$("${MARIADB[@]}" -N -B -e "SELECT 1" 2>&1); then
    echo "ERROR: no hay conexion a $DB_HOST:$DB_PORT (usuario $DB_USER)." >&2
    echo "       Respuesta: $respuesta" >&2
    echo "       Local: DB_HOST=127.0.0.1 bash db/verificar-esquema.sh" >&2
    exit 2
fi

TMPDIR_V="$(mktemp -d)"
SCRATCH=""

limpiar() {
    if [ -n "$SCRATCH" ] && [ "$CONSERVAR" -eq 0 ]; then
        case "$SCRATCH" in
            verif_esquema_*)
                "${MARIADB[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH\`" >/dev/null 2>&1
                ;;
        esac
    fi
    rm -rf "$TMPDIR_V"
}
trap limpiar EXIT INT TERM

# ---------------------------------------------------------------- volcado ---
# Las definiciones de vista y de rutina pueden venir calificadas con el nombre
# de la base; se normaliza para que BALBU_TECH y BALBU_TECH_TEST no difieran
# solo por eso. CHAR(96) es la comilla invertida, para no pelear con bash.
SEC_S=""
SEC_OUT=""
SEC_TMP=""

emitir() {
    local etiqueta="$1" sql="$2"
    printf '## %s\n' "$etiqueta" >> "$SEC_OUT"
    if ! "${MARIADB[@]}" --database="$SEC_S" -N -B -e "$sql" > "$SEC_TMP" 2>&1; then
        echo "ERROR: fallo la seccion '$etiqueta' en $SEC_S:" >&2
        sed 's/^/    /' "$SEC_TMP" >&2
        return 1
    fi
    if grep -q '^ERROR' "$SEC_TMP"; then
        echo "ERROR: la seccion '$etiqueta' en $SEC_S devolvio un error:" >&2
        sed 's/^/    /' "$SEC_TMP" >&2
        return 1
    fi
    cat "$SEC_TMP" >> "$SEC_OUT"
}

# Cuerpo normalizado + hasheado. Si la definicion viene NULL es porque el
# usuario no tiene privilegio para leerla: se marca como tal en vez de hashear
# una cadena vacia, que daria el mismo MD5 en las dos bases y taparia el
# problema.
hash_normalizado() {
    printf "CASE WHEN %s IS NULL THEN '<sin-permiso>' ELSE MD5(REPLACE(%s, CONCAT(CHAR(96), DATABASE(), CHAR(96), '.'), '')) END" "$1" "$1"
}

volcar() {
    SEC_S="$1"
    SEC_OUT="$2"
    SEC_TMP="$TMPDIR_V/err.$$"
    : > "$SEC_OUT"

    emitir "TABLAS" "
        SELECT CONCAT_WS('\t', TABLE_NAME, TABLE_TYPE, IFNULL(ENGINE,'-'), IFNULL(TABLE_COLLATION,'-'))
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME" || return 1

    emitir "COLUMNAS" "
        SELECT CONCAT_WS('\t', TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, COLUMN_TYPE,
                         IS_NULLABLE, IFNULL(COLUMN_DEFAULT,'<sin-default>'), EXTRA,
                         IFNULL(COLLATION_NAME,'-'))
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME, ORDINAL_POSITION" || return 1

    emitir "INDICES" "
        SELECT CONCAT_WS('\t', TABLE_NAME, INDEX_NAME, NON_UNIQUE, SEQ_IN_INDEX,
                         IFNULL(COLUMN_NAME,'<expresion>'), INDEX_TYPE,
                         IFNULL(SUB_PART,'-'), IFNULL(COLLATION,'-'))
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX" || return 1

    emitir "FK_COLUMNAS" "
        SELECT CONCAT_WS('\t', TABLE_NAME, CONSTRAINT_NAME, ORDINAL_POSITION, COLUMN_NAME,
                         REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME)
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL
        ORDER BY TABLE_NAME, CONSTRAINT_NAME, ORDINAL_POSITION" || return 1

    emitir "FK_REGLAS" "
        SELECT CONCAT_WS('\t', TABLE_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME,
                         UPDATE_RULE, DELETE_RULE, MATCH_OPTION)
        FROM information_schema.REFERENTIAL_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME, CONSTRAINT_NAME" || return 1

    emitir "CHECKS" "
        SELECT CONCAT_WS('\t', tc.TABLE_NAME, cc.CONSTRAINT_NAME,
                         REPLACE(REPLACE(cc.CHECK_CLAUSE, CHAR(9), ' '), CHAR(10), ' '))
        FROM information_schema.CHECK_CONSTRAINTS cc
        JOIN information_schema.TABLE_CONSTRAINTS tc
          ON tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
         AND tc.CONSTRAINT_NAME   = cc.CONSTRAINT_NAME
        WHERE cc.CONSTRAINT_SCHEMA = DATABASE() AND tc.CONSTRAINT_TYPE = 'CHECK'
        ORDER BY tc.TABLE_NAME, cc.CONSTRAINT_NAME" || return 1

    # El cuerpo va hasheado: dos triggers con el mismo MD5 son el mismo trigger.
    # ACTION_ORDER es lo que delata una cadena de FOLLOWS rota.
    emitir "TRIGGERS" "
        SELECT CONCAT_WS('\t', EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION,
                         ACTION_ORDER, TRIGGER_NAME, MD5(ACTION_STATEMENT))
        FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
        ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION, ACTION_ORDER" || return 1

    emitir "RUTINAS" "
        SELECT CONCAT_WS('\t', ROUTINE_NAME, ROUTINE_TYPE,
                         $(hash_normalizado 'ROUTINE_DEFINITION'),
                         IFNULL(SQL_DATA_ACCESS,'-'), IS_DETERMINISTIC)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
        ORDER BY ROUTINE_NAME" || return 1

    emitir "VISTAS" "
        SELECT CONCAT_WS('\t', TABLE_NAME,
                         $(hash_normalizado 'VIEW_DEFINITION'),
                         IS_UPDATABLE, IFNULL(SECURITY_TYPE,'-'), IFNULL(ALGORITHM,'-'),
                         IFNULL(CHECK_OPTION,'-'))
        FROM information_schema.VIEWS
        WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME" || return 1

    rm -f "$SEC_TMP"
    return 0
}

# --------------------------------------------------------------- comparar ---
SECCIONES="TABLAS COLUMNAS INDICES FK_COLUMNAS FK_REGLAS CHECKS TRIGGERS RUTINAS VISTAS"
NUM_SECCIONES=$(echo $SECCIONES | wc -w)

extraer() {
    awk -v s="## $2" '
        $0 == s { dentro = 1; next }
        /^## /  { dentro = 0 }
        dentro  { print }
    ' "$1"
}

comparar() {
    local etq_a="$1" arch_a="$2" etq_b="$3" arch_b="$4"
    local sec c_a c_b difs=0

    for sec in $SECCIONES; do
        extraer "$arch_a" "$sec" > "$TMPDIR_V/a.$sec"
        extraer "$arch_b" "$sec" > "$TMPDIR_V/b.$sec"
        if ! diff -q "$TMPDIR_V/a.$sec" "$TMPDIR_V/b.$sec" >/dev/null 2>&1; then
            difs=$((difs+1))
            c_a=$(wc -l < "$TMPDIR_V/a.$sec")
            c_b=$(wc -l < "$TMPDIR_V/b.$sec")
            echo ""
            echo "=== DIFERENCIA EN $sec  ($etq_a: $c_a / $etq_b: $c_b) ==="
            diff -u --label "$etq_a/$sec" --label "$etq_b/$sec" \
                 "$TMPDIR_V/a.$sec" "$TMPDIR_V/b.$sec" | sed 's/^/  /'
        fi
    done

    echo ""
    if [ "$difs" -eq 0 ]; then
        echo "IDENTICAS: $etq_a y $etq_b coinciden en las $NUM_SECCIONES secciones."
        return 0
    fi
    echo "DIFERENTES: $difs de $NUM_SECCIONES secciones no coinciden."
    return 1
}

# ------------------------------------------------------------------ modo ---
if [ "${#POSICIONALES[@]}" -eq 2 ]; then
    BASE_A="${POSICIONALES[0]}"
    BASE_B="${POSICIONALES[1]}"

    echo "Comparando $BASE_A contra $BASE_B (sin importar nada)..."
    volcar "$BASE_A" "$TMPDIR_V/a.txt" || exit 2
    volcar "$BASE_B" "$TMPDIR_V/b.txt" || exit 2
    comparar "$BASE_A" "$TMPDIR_V/a.txt" "$BASE_B" "$TMPDIR_V/b.txt"
    exit $?
fi

BASE_A="${POSICIONALES[0]:-$DB_NAME}"
SCRATCH="verif_esquema_$$_$(date +%s)"

echo "Creando base temporal $SCRATCH e importando modulos/ ..."

# La base temporal tiene que nacer con el MISMO charset y collation que la de
# referencia. Si no, las tablas que no fijan COLLATE en su CREATE TABLE heredan
# el default de MariaDB (utf8mb4_uca1400_ai_ci en 11.x) y TODAS aparecen como
# distintas por un motivo que no tiene nada que ver con el esquema.
CHARSET_DEF=$("${MARIADB[@]}" -N -B -e \
    "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$BASE_A'" 2>&1)
COLL_DEF=$("${MARIADB[@]}" -N -B -e \
    "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$BASE_A'" 2>&1)

if ! printf '%s' "$CHARSET_DEF" | grep -qE '^[A-Za-z0-9_]+$' \
   || ! printf '%s' "$COLL_DEF" | grep -qE '^[A-Za-z0-9_]+$'; then
    echo "ERROR: no se pudo leer charset/collation de $BASE_A." >&2
    echo "       charset='$CHARSET_DEF' collation='$COLL_DEF'" >&2
    exit 2
fi

echo "  (charset $CHARSET_DEF, collation $COLL_DEF, igual que $BASE_A)"

if ! salida=$("${MARIADB[@]}" -e \
        "CREATE DATABASE \`$SCRATCH\` CHARACTER SET $CHARSET_DEF COLLATE $COLL_DEF" 2>&1); then
    echo "ERROR: no se pudo crear $SCRATCH:" >&2
    echo "       $salida" >&2
    echo "       Sin permiso de CREATE no hay modo fresco; pasa dos bases existentes." >&2
    exit 2
fi

if ! DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$SCRATCH" \
     DB_ADMIN_USER="$DB_USER" DB_ADMIN_PASSWORD="$DB_PASSWORD" \
     bash "$ROOT/db/import.sh" > "$TMPDIR_V/import.log" 2>&1; then
    echo "ERROR: el import a $SCRATCH fallo. Ultimas lineas:" >&2
    tail -20 "$TMPDIR_V/import.log" | sed 's/^/    /' >&2
    exit 2
fi

echo "Import: $(grep -E '^Listo:' "$TMPDIR_V/import.log" | tail -1)"
echo ""
echo "Comparando $BASE_A contra el import desde cero..."

volcar "$BASE_A" "$TMPDIR_V/a.txt" || exit 2
volcar "$SCRATCH" "$TMPDIR_V/b.txt" || exit 2

comparar "$BASE_A" "$TMPDIR_V/a.txt" "$SCRATCH (import desde cero)" "$TMPDIR_V/b.txt"
resultado=$?

if [ "$CONSERVAR" -eq 1 ]; then
    echo ""
    echo "Base temporal conservada: $SCRATCH"
    echo "Para dropearla: mariadb -h $DB_HOST -u $DB_USER -p -e \"DROP DATABASE \\\`$SCRATCH\\\`\""
fi

exit "$resultado"
