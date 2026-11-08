#!/bin/bash
# Importa modulos/*.sql en orden numerico a la DB del contenedor.
# Uso dentro del contenedor app:  bash db/import.sh
# Uso desde Windows (host):       docker compose exec app bash db/import.sh
# Variables: DB_HOST/DB_PORT/DB_ADMIN_USER/DB_ADMIN_PASSWORD/DB_NAME (ver .env),
#            MODULOS_DIR (por defecto ./modulos; util para validar otro set de SQL).
#
# Por que no usar /docker-entrypoint-initdb.d:
# - los nombres tienen espacios ("1- CATEGORIAS.sql") y no hay orden garantizado,
# - todo_modulos.sql y Mejoras_extras.sql son consolidados/experimentos y se excluyen.
#
# (08/11/2026) Que significa "funciono":
# - Reimportar sobre una base existente es NORMAL y termina en 0. Los errores de
#   idempotencia (1050 tabla existe, 1061 indice/columna duplicada, 1265 truncation
#   al re-aplicar un ALTER que ya estaba) se reportan como AVISOS, no como fallo.
# - Cualquier otro ^ERROR es un error real y el script sale con 1.
# - Las guardas de permiso se inyectan SIEMPRE, antes de cualquier exit 1: una
#   base con SPs sin guarda es un agujero de permisos, no un detalle de reporte.
set -e
cd "$(dirname "$0")/.."

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
# (19/10/2026) Mantenimiento con usuario admin dedicado; sin claves por defecto.
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
MODULOS_DIR="${MODULOS_DIR:-modulos}"

if [ ! -d "$MODULOS_DIR" ]; then
  echo "No existe $MODULOS_DIR" >&2
  exit 1
fi

# Espera a que MariaDB acepte conexiones (hasta 60s).
echo "Esperando a MariaDB en $DB_HOST:$DB_PORT ..."
for i in $(seq 1 60); do
  if mariadb-admin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --silent 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "MariaDB no responde en $DB_HOST:$DB_PORT" >&2
    exit 1
  fi
  sleep 1
done

echo "Importando $MODULOS_DIR a base $DB_NAME ..."
count=0
failed=0
avisos=0
# (14/10/2026) --force sale 0 aunque haya errores de sentencia adentro:
# se cuentan las lineas ^ERROR por archivo para no mentir con "0 avisos".
# (08/11/2026) Se separan dos clases de error:
#   - AVISO de idempotencia (1050 tabla existe, 1061 indice/columna duplicada,
#     1265 truncation al re-aplicar un ALTER que ya estaba): son el resultado
#     normal de reimportar sobre una base existente. NO fallan el import.
#   - ERROR real: cualquier otro. Ese si falla.
# Antes cualquier 1050 contaba como fallo, asi que reimportar siempre "fallaba"
# y el script moria ANTES de inyectar las guardas: la base quedaba con SPs sin
# control de permisos y en silencio (paso dos veces en BALBU_TECH).
# sort -V ordena 1,2,3...10,11...36 (y 19 < 19.5 < 19.6 < 20) correctamente.
while IFS= read -r f; do
  case "$f" in
    *todo_modulos.sql|*probando*|*BALBU_TECH*) continue ;;
  esac
  count=$((count + 1))
  echo "[$count] $f"
  log=$(mktemp)
  mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
      --default-character-set=utf8mb4 --database="$DB_NAME" --force < "$f" >"$log" 2>&1
  n_avisos=$(grep "^ERROR" "$log" | grep -cE "^ERROR (1050|1061|1265) " || true)
  n_reales=$(grep "^ERROR" "$log" | grep -vE "^ERROR (1050|1061|1265) " | wc -l || true)
  if [ "$n_avisos" -gt 0 ]; then
    avisos=$((avisos + n_avisos))
  fi
  if [ "$n_reales" -gt 0 ]; then
    echo "  ERROR: $n_reales sentencia(s) con error real en $f:" >&2
    grep "^ERROR" "$log" | grep -vE "^ERROR (1050|1061|1265) " | head -n 5 >&2
    failed=$((failed + 1))
  fi
  rm -f "$log"
done < <(ls -1 "$MODULOS_DIR"/*.sql | sort -V)

echo "Listo: $count archivos, $avisos aviso(s) de idempotencia, $failed con errores reales."

# (03/11/2026) Los CREATE PROCEDURE de los modulos no traen la guarda de
# permisos: se inyecta despues de importar.
# (08/11/2026) Esto corre SIEMPRE, antes de cualquier exit 1: una base con SPs
# sin guarda es un agujero de permisos, no un detalle de reporte.
guardas_ok=0
if [ -f db/injectar-guardas.py ]; then
  echo "Inyectando guardas de permiso en $DB_NAME ..."
  if python3 db/injectar-guardas.py "$DB_NAME" --aplicar; then
    guardas_ok=1
  else
    echo "ERROR: no se pudieron inyectar las guardas de permiso." >&2
    failed=$((failed + 1))
  fi
fi

if [ "$failed" -gt 0 ]; then
  echo "Import con errores: $failed archivo(s)/paso(s). Revisar los ERROR de arriba." >&2
  exit 1
fi
if [ "$guardas_ok" = "1" ]; then
  echo "Verifica cobertura con: DB_NAME=$DB_NAME bash db/check-app-sps.sh"
fi
echo "Tablas en $DB_NAME:"
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
  --database="$DB_NAME" -e "SHOW TABLES;"
