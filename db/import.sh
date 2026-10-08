#!/bin/bash
# Importa modulos/*.sql en orden numerico a la DB del contenedor.
# Uso dentro del contenedor app:  bash db/import.sh
# Uso desde Windows (host):       docker compose exec app bash db/import.sh
# Variables: DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME (ver .env),
#            MODULOS_DIR (por defecto ./modulos; util para validar otro set de SQL).
#
# Por que no usar /docker-entrypoint-initdb.d:
# - los nombres tienen espacios ("1- CATEGORIAS.sql") y no hay orden garantizado,
# - todo_modulos.sql y Mejoras_extras.sql son consolidados/experimentos y se excluyen.
set -e
cd "$(dirname "$0")/.."

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MARIADB_ROOT_PASSWORD:-linux01}}"
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
# sort -V ordena 1,2,3...10,11...36 (y 19 < 19.5 < 19.6 < 20) correctamente.
while IFS= read -r f; do
  case "$f" in
    *todo_modulos.sql|*probando*|*BALBU_TECH*) continue ;;
  esac
  count=$((count + 1))
  echo "[$count] $f"
  if ! mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
      --default-character-set=utf8mb4 --database="$DB_NAME" --force < "$f"; then
    echo "  AVISO: fallo al importar $f (sigo con --force, revisa el archivo)" >&2
    failed=$((failed + 1))
  fi
done < <(ls -1 "$MODULOS_DIR"/*.sql | sort -V)

echo "Listo: $count archivos, $failed con avisos."
echo "Tablas en $DB_NAME:"
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
  --database="$DB_NAME" -e "SHOW TABLES;"
