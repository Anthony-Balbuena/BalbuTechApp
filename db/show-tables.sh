#!/usr/bin/env bash
# (19/10/2026) Muestra las tablas de BALBU_TECH (task "Docker: ver tablas").
# Uso: docker compose exec app bash db/show-tables.sh
# Usa el usuario admin de mantenimiento (DB_ADMIN_USER/DB_ADMIN_PASSWORD del .env).
set -u

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -e "SHOW TABLES;"
