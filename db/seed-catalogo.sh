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
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MARIADB_ROOT_PASSWORD:-linux01}}"
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
