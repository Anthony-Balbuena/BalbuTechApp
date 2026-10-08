#!/bin/bash
# Crea (o actualiza) el usuario admin para entrar a la app.
# Uso: docker compose exec app bash db/seed-admin.sh [usuario] [clave] [rol]
# Defecto: admin / admin123 / ROLE_ADMIN.
# Crea un EMPLEADOS minimo + fila en USUARIOS con hash SHA256 legacy;
# login.cpp lo acepta y lo rehashea a PBKDF2 al primer login (verificarPassword).
set -e
cd "$(dirname "$0")/.."
USER="${1:-admin}"
PASS="${2:-admin123}"
ROL="${3:-ADMIN}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MARIADB_ROOT_PASSWORD:-linux01}}"
Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

HASH=$(printf '%s' "$PASS" | sha256sum | cut -d' ' -f1)
# Roles que la app compara tal cual (roles.cpp: ADMIN/RRHH/EMPLEADO). Se crean si faltan.
for R in ADMIN RRHH EMPLEADO; do
  mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
    -e "INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES ('$R');"
done
ID_ROL=$(Q "SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL='$ROL';")
if [ -z "$ID_ROL" ]; then echo "Rol '$ROL' no existe." >&2; exit 1; fi
ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='000-0000000-0';")
if [ -z "$ID_EMP" ]; then
  Q "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO) VALUES ('Administrador Sistema', '000-0000000-0', 'ADMIN', 25000, '000-000-0000', 'admin@balbutech.local', CURDATE());"
  ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='000-0000000-0';")
fi
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
  -e "INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA) VALUES ($ID_EMP, $ID_ROL, '$USER', '$HASH') ON DUPLICATE KEY UPDATE CONTRASENA='$HASH', ID_ROL=$ID_ROL, ESTADO='ACTIVO';"
echo "Comprobando login de '$USER':"
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
  -e "SELECT U.ID_USUARIO, U.USUARIO, U.ESTADO, R.NOMBRE_ROL FROM USUARIOS U LEFT JOIN ROLES R ON U.ID_ROL = R.ID_ROL WHERE U.USUARIO='$USER';"
