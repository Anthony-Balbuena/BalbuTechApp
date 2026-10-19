#!/bin/bash
# Carga el catalogo base demo (categorias, marcas, metodos de pago).
# Uso: docker compose exec app bash db/seed-catalogo.sh
# Idempotente (INSERT IGNORE): se puede correr cuantas veces sea.
# Los .sql importan las tablas vacias a proposito; estos datos son opt-in
# para desarrollo/pruebas (la app los necesita para registrar productos).
set -e
cd "$(dirname "$0")/.."
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
# (19/10/2026) Seed de catalogo con usuario admin dedicado; sin claves por defecto.
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

Q "INSERT IGNORE INTO CATEGORIAS (NOMBRE, DESCRIPCION, ICONO_URL) VALUES
  ('COMPUTADORAS PORTATILES O LAPTOPS', 'EQUIPOS DE COMPUTO MOVILES', 'ICON-LAPTOP'),
  ('TARJETA DE VIDEO', 'COMPONENTE DE PROCESAMIENDO GRAFICO', 'ICON-GPU'),
  ('RAM', 'MEMORIA DE ACCESO ALEATORIO', 'ICON-RAM'),
  ('CPU', 'UNIDAD DE PROCESAMIENTO', 'ICON CPU');"
Q "INSERT IGNORE INTO MARCAS (NOMBRE) VALUES
  ('ASUS'), ('MSI'), ('LOGITECH'), ('RAZER'), ('HP'),
  ('WESTERN DIGITAL'), ('IPHONE'), ('XIAOMI'), ('JBL'), ('RED MAGIC');"
Q "INSERT IGNORE INTO METODOS_PAGO (NOMBRE) VALUES
  ('EFECTIVO'), ('TARJETA'), ('TRANSFERENCIA'), ('DEPOSITO');"
echo "Catalogo:"
Q "SELECT COUNT(*) AS categorias FROM CATEGORIAS;"
Q "SELECT COUNT(*) AS marcas FROM MARCAS;"
Q "SELECT COUNT(*) AS metodos FROM METODOS_PAGO;"
