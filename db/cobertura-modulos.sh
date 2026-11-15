#!/bin/bash
# Cobertura de modulos: el inverso de db/check-app-sps.sh.
#
#   check-app-sps.sh  ->  "los SP que la app llama, existen?"
#   este script       ->  "los SP que existen, los llama alguien?"
#
# Un SP queda como hueco (sin uso) cuando nadie lo llama:
#   - ni la app C++      (*.cpp / *.h  -> CALL ...)
#   - ni otro SP         (modulos/*.sql, db/*.sql -> CALL ...)
#   - ni un CALL de importacion/seed (modulos/*.sql, db/*.sql)
#
# Es analisis estatico: no abre conexion, no necesita credenciales y no
# modifica nada.
#
# Limite conocido: igual que check-app-sps.sh, lee los CALL del texto, asi
# que un `CALL` comentado cuenta como llamada. Si un SP aparece como usado y
# sospechoso, se mira el archivo.
#
# Uso:
#   bash db/cobertura-modulos.sh
#   bash db/cobertura-modulos.sh --root /otro/repo
#
# Sale siempre con 0: es un reporte, no una validacion. Un hueco no es un
# error del script, es informacion para decidir.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { echo "ERROR: --root necesita una ruta." >&2; exit 2; }
            ROOT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Uso: bash db/cobertura-modulos.sh [--root RUTA]"
            echo ""
            echo "Lista los SP definidos en modulos/ que no llama la app,"
            echo "ni otro SP, ni un CALL de importacion."
            exit 0
            ;;
        *)
            echo "ERROR: opcion desconocida: $1" >&2
            echo "Uso: bash db/cobertura-modulos.sh [--root RUTA]" >&2
            exit 2
            ;;
    esac
done

if [ ! -d "$ROOT/modulos" ]; then
    echo "ERROR: no existe $ROOT/modulos" >&2
    exit 1
fi

# Nombres de SP a MAYUSCULAS, una por linea, ordenados y sin repetir.
normaliza() { tr '[:lower:]' '[:upper:]' | sort -u; }

# SPs que define un archivo (solo CREATE PROCEDURE, no DROP ni comentarios).
sps_de() {
    grep -oiE 'CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?PROCEDURE[[:space:]]+`?[A-Za-z0-9_]+' "$1" \
        | awk '{print $NF}' \
        | tr -d '`' \
        | normaliza
}

# SPs que llama la app C++.
llamadas_app() {
    grep -rhoiE 'CALL[[:space:]]+`?[A-Za-z0-9_]+' \
        --include=*.cpp --include=*.h "$ROOT" 2>/dev/null \
        | awk '{print $NF}' \
        | tr -d '`' \
        | normaliza
}

# SPs que llama otro objeto SQL (cuerpo de un SP o CALL de importacion).
llamadas_sql() {
    grep -rhoiE 'CALL[[:space:]]+`?[A-Za-z0-9_]+' \
        --include=*.sql "$ROOT/modulos" "$ROOT/db" 2>/dev/null \
        | awk '{print $NF}' \
        | tr -d '`' \
        | normaliza
}

en_lista() { grep -qxF "$1" <<< "$2"; }

APP="$(llamadas_app)"
SQLC="$(llamadas_sql)"

printf "Cobertura de modulos — SPs que nadie llama\n"
printf "Raiz: %s\n\n" "$ROOT"
printf "%-42s %5s %4s %4s %8s\n" "Modulo" "SPs" "App" "SQL" "Sin uso"
printf "%-42s %5s %4s %4s %8s\n" "------------------------------------------" "-----" "----" "----" "--------"

total_sp=0
total_sin=0
modulos_con_hueco=0
detalle=""
declare -A DEFINICIONES=()
declare -A VECES=()

while IFS= read -r archivo; do
    [ -z "$archivo" ] && continue
    modulo="$(basename "$archivo" .sql)"
    sps="$(sps_de "$archivo")"
    [ -z "$sps" ] && continue

    n_sp=0
    n_app=0
    n_sql=0
    huecos=()

    while IFS= read -r sp; do
        [ -z "$sp" ] && continue
        n_sp=$((n_sp + 1))
        DEFINICIONES["$sp"]="${DEFINICIONES[$sp]:-}$modulo | "
        VECES["$sp"]=$(( ${VECES[$sp]:-0} + 1 ))
        if en_lista "$sp" "$APP"; then
            n_app=$((n_app + 1))
        elif en_lista "$sp" "$SQLC"; then
            n_sql=$((n_sql + 1))
        else
            huecos+=("$sp")
        fi
    done <<< "$sps"

    total_sp=$((total_sp + n_sp))
    total_sin=$((total_sin + ${#huecos[@]}))

    printf "%-42s %5d %4d %4d %8d\n" "$modulo" "$n_sp" "$n_app" "$n_sql" "${#huecos[@]}"

    if [ ${#huecos[@]} -gt 0 ]; then
        modulos_con_hueco=$((modulos_con_hueco + 1))
        detalle+="$modulo"$'\n'
        for sp in "${huecos[@]}"; do
            detalle+="    $sp"$'\n'
        done
    fi
done < <(printf '%s\n' "$ROOT"/modulos/*.sql | sort -V)

echo ""
echo "SPs sin uso (por modulo):"
if [ -n "$detalle" ]; then
    printf "%s" "$detalle"
else
    echo "    (ninguno)"
fi

echo ""
echo "Total: $total_sin definiciones sin uso de $total_sp definiciones revisadas, en $modulos_con_hueco modulo(s)."
echo "> 'sin uso' = no lo llama la app (*.cpp), ni otro SP, ni un CALL de importacion."
echo "> Un SP que solo llama a otros pero nadie lo llama a el tambien cuenta como sin uso."

repetidas=""
for sp in "${!DEFINICIONES[@]}"; do
    if [ "${VECES[$sp]}" -gt 1 ]; then
        repetidas+="    $sp -> ${DEFINICIONES[$sp]% | }"$'\n'
    fi
done

echo ""
if [ -n "$repetidas" ]; then
    echo "Definiciones repetidas (el mismo SP en mas de un modulo):"
    printf "%s" "$repetidas" | sort
    echo "> Gana la ultima que se importe: el orden de import decide cual queda."
else
    echo "Definiciones repetidas (el mismo SP en mas de un modulo): ninguna."
fi
