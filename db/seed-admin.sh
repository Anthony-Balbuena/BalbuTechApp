#!/bin/bash
# Crea (o actualiza) el usuario admin para entrar a la app.
# Uso: docker compose exec app bash db/seed-admin.sh [usuario] [clave] [rol]
# La clave es OBLIGATORIA: no hay default. Pasa el segundo argumento o BALBU_PASS.
#   bash db/seed-admin.sh admin 'una-clave-larga'
#   BALBU_PASS='una-clave-larga' bash db/seed-admin.sh
# Crea un EMPLEADOS minimo + fila en USUARIOS con hash SHA256 legacy;
# login.cpp lo acepta y lo rehashea a PBKDF2 al primer login (verificarPassword).
set -e
cd "$(dirname "$0")/.."
USER="${1:-admin}"
PASS="${2:-${BALBU_PASS:-}}"
ROL="${3:-ADMIN}"
if [ -z "$PASS" ]; then
  echo "ERROR: falta la clave del usuario '$USER'." >&2
  echo "Pasa el segundo argumento o BALBU_PASS. Ya no hay clave por defecto." >&2
  exit 1
fi
if [ "${#PASS}" -lt 8 ]; then
  echo "ERROR: la clave debe tener al menos 8 caracteres." >&2
  exit 1
fi
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH}"
# (19/10/2026) Alta del admin con usuario admin dedicado; sin claves por defecto.
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

HASH=$(printf '%s' "$PASS" | sha256sum | cut -d' ' -f1)
# Roles base que el seed asegura (el resto los crean los modulos 3/36). Se crean si faltan.
for R in ADMIN RRHH VENDEDOR; do
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
