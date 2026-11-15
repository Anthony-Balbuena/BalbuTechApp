#!/bin/bash
# Prueba de db/cobertura-modulos.sh contra un repo de mentira.
# No toca la base ni el repo real: arma todo en un mktemp -d.
#
# Casos que fija:
#   - un SP que solo llama la app        -> NO es hueco
#   - un SP que solo llama otro SP       -> NO es hueco
#   - un SP que solo llama un CALL de    -> NO es hueco
#     importacion (db/*.sql)
#   - un SP que no lo llama nadie        -> ES hueco
#   - un SP que llama a otros pero nadie -> ES hueco
#     lo llama a el
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/cobertura-modulos.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fallos=0
ok()    { echo "OK    $1"; }
falla() { echo "FALLA $1"; fallos=$((fallos + 1)); }

mkdir -p "$TMP/modulos" "$TMP/db"

cat > "$TMP/modulos/1- UNO.sql" <<'SQL'
CREATE PROCEDURE SP_LLAMADA_APP()
BEGIN
    SELECT 1;
END;

CREATE PROCEDURE SP_LLAMADA_SQL()
BEGIN
    SELECT 1;
END;

CREATE PROCEDURE SP_HUERFANA()
BEGIN
    SELECT 1;
END;
SQL

cat > "$TMP/modulos/2- DOS.sql" <<'SQL'
CREATE OR REPLACE PROCEDURE SP_QUE_LLAMA()
BEGIN
    CALL SP_LLAMADA_SQL();
END;
SQL

cat > "$TMP/modulos/3- TRES.sql" <<'SQL'
CREATE PROCEDURE SP_SEMILLA()
BEGIN
    SELECT 1;
END;

-- El mismo nombre que define el modulo 1: sirve para probar el reporte de
-- definiciones repetidas.
CREATE PROCEDURE SP_LLAMADA_APP()
BEGIN
    SELECT 2;
END;
SQL

cat > "$TMP/app.cpp" <<'CPP'
std::unique_ptr<sql::PreparedStatement> p(globalCon->prepareStatement("CALL SP_LLAMADA_APP(?)"));
CPP

cat > "$TMP/db/seed.sql" <<'SQL'
CALL SP_SEMILLA();
SQL

if [ ! -f "$SCRIPT" ]; then
    falla "falta el script $SCRIPT"
    echo ""
    echo "Resultado: $fallos fallo(s)"
    exit 1
fi

salida="$(bash "$SCRIPT" --root "$TMP" 2>&1)"
codigo=$?

[ "$codigo" -eq 0 ] && ok "sale con 0" || falla "salio con $codigo"

echo "$salida" | grep -qxF "    SP_HUERFANA" \
    && ok "marca SP_HUERFANA como hueco" \
    || falla "no marco SP_HUERFANA"

echo "$salida" | grep -qxF "    SP_QUE_LLAMA" \
    && ok "marca SP_QUE_LLAMA (llama a otros pero nadie lo llama)" \
    || falla "no marco SP_QUE_LLAMA"

echo "$salida" | grep -qxF "    SP_LLAMADA_APP" \
    && falla "marco como hueco al que llama la app" \
    || ok "no marca al que llama la app"

echo "$salida" | grep -qxF "    SP_LLAMADA_SQL" \
    && falla "marco como hueco al que llama otro SP" \
    || ok "no marca al que llama otro SP"

echo "$salida" | grep -qxF "    SP_SEMILLA" \
    && falla "marco como hueco al que llama un CALL de importacion" \
    || ok "no marca al que llama un CALL de importacion"

echo "$salida" | grep -q "Total: 2 definiciones sin uso" \
    && ok "cuenta 2 huecos" \
    || falla "no conto 2 huecos"

echo "$salida" | grep -q "de 6 definiciones revisadas" \
    && ok "cuenta 6 definiciones revisadas" \
    || falla "no conto 6 definiciones revisadas"

echo "$salida" | grep -q "SP_LLAMADA_APP -> 1- UNO | 3- TRES" \
    && ok "reporta la definicion repetida" \
    || falla "no reporto la definicion repetida"

echo ""
echo "Resultado: $fallos fallo(s)"
[ "$fallos" -eq 0 ]
