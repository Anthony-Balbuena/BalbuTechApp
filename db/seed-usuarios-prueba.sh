#!/bin/bash
# Crea un usuario de prueba por rol (los seis que no son ADMIN) en la base TEST.
# Sirve para validar el mapeo PERMISO_POR_RUTINA entrando con cada rol real.
#
# Uso: bash db/seed-usuarios-prueba.sh '<clave>' [DB_NAME]
#   bash db/seed-usuarios-prueba.sh 'Prueba1234'
#   DB_NAME=BALBU_TECH_TEST bash db/seed-usuarios-prueba.sh 'Prueba1234'
#
# Seguridad: el script se niega a correr si el DB_NAME resuelto no contiene
# "TEST". El .env se carga PRIMERO y despues se resuelve el nombre de la base,
# para que el DB_NAME del .env (la viva) nunca pise el valor pedido.
# La clave se guarda en el formato legacy (pbkdf2$...), igual que seed-admin.sh:
# SP_LOGIN_AUTENTICAR la migra al formato del servidor en el primer login.
set -e
cd "$(dirname "$0")/.."

PASS="${1:-${BALBU_PASS_PRUEBA:-}}"
DB_NAME_ARG="$2"

if [ -z "$PASS" ]; then
  echo "ERROR: falta la clave." >&2
  echo "Uso: bash db/seed-usuarios-prueba.sh '<clave>'" >&2
  exit 1
fi
if [ "${#PASS}" -lt 8 ]; then
  echo "ERROR: la clave debe tener al menos 8 caracteres." >&2
  exit 1
fi

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

# Resolucion del nombre de la base, en este orden:
#   1) segundo argumento
#   2) DB_NAME del entorno, solo si ya es de prueba
#   3) BALBU_TECH_TEST por defecto
if [ -n "$DB_NAME_ARG" ]; then
  DB_NAME="$DB_NAME_ARG"
elif [ -n "$DB_NAME" ] && case "$DB_NAME" in *TEST*) true ;; *) false ;; esac; then
  : # ya es de prueba
else
  DB_NAME="BALBU_TECH_TEST"
fi

case "$DB_NAME" in
  *TEST*) ;;
  *)
    echo "ERROR: DB_NAME='$DB_NAME' no parece una base de prueba." >&2
    echo "Este script solo escribe en bases cuyo nombre contenga TEST." >&2
    exit 1
    ;;
esac

# Dentro del contenedor el servicio se llama "db"; fuera, el MariaDB local.
if getent hosts db >/dev/null 2>&1; then
  DB_HOST=db
else
  DB_HOST="${DB_HOST_TARGET:-127.0.0.1}"
fi
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: falta python3 para generar el hash PBKDF2." >&2
  exit 1
fi

HASH=$(printf '%s' "$PASS" | python3 -c '
import base64, hashlib, os, sys
password = sys.stdin.buffer.read()
iteraciones = 100000
sal = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha256", password, sal, iteraciones, 32)
print("pbkdf2${}${}${}".format(
    iteraciones,
    base64.b64encode(sal).decode(),
    base64.b64encode(dk).decode(),
))
')
SIN_MIGRAR="SALT_LOGIN = NULL, ITER_LOGIN = NULL, CLAVE_SERVIDOR = NULL"

# < /dev/null: sin esto el cliente se come las lineas del while que lo invoca.
Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
        --database="$DB_NAME" -N -e "$1" < /dev/null; }
EXEC() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
        --database="$DB_NAME" -e "$1" < /dev/null; }

# usuario|rol|cedula|nombre|cargo
USUARIOS_PRUEBA='
prueba.sys|ADMIN|000-0000000-7|Admin de Prueba|ADMIN
prueba.gerente|GERENTE|000-0000000-1|Gerente de Prueba|GERENTE
prueba.subgerente|SUBGERENTE|000-0000000-2|Subgerente de Prueba|SUBGERENTE
prueba.rrhh|RRHH|000-0000000-3|RRHH de Prueba|RRHH
prueba.vendedor|VENDEDOR|000-0000000-4|Vendedor de Prueba|VENDEDOR
prueba.almacen|ALMACEN|000-0000000-5|Almacen de Prueba|ALMACEN
prueba.contabilidad|CONTABILIDAD|000-0000000-6|Contabilidad de Prueba|CONTABILIDAD
'

echo "Base destino: $DB_NAME ($DB_HOST:$DB_PORT)"
echo

echo "$USUARIOS_PRUEBA" | while IFS='|' read -r USR ROL CED NOMBRE CARGO; do
  if [ -z "$USR" ]; then continue; fi

  ID_ROL=$(Q "SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL='$ROL';")
  if [ -z "$ID_ROL" ]; then
    echo "[!] $USR: el rol '$ROL' no existe en $DB_NAME" >&2
    continue
  fi

  ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CED';")
  if [ -z "$ID_EMP" ]; then
    # El email, la cedula y el telefono son unicos: uno por usuario.
    EXEC "INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
          VALUES ('$NOMBRE', '$CED', '$CARGO', 20000,
                  CONCAT('000-000-000', RIGHT('$CED', 1)),
                  '$USR@balbutech.local', CURDATE());"
    ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CED';")
  fi

  EXEC "INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA)
        VALUES ($ID_EMP, $ID_ROL, '$USR', '$HASH')
        ON DUPLICATE KEY UPDATE CONTRASENA='$HASH', ID_ROL=$ID_ROL, ID_EMPLEADO=$ID_EMP,
                                ESTADO='ACTIVO', $SIN_MIGRAR;"

  echo "  OK  $USR ($ROL)"
done

echo
echo "Usuarios de prueba en $DB_NAME:"
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
  --database="$DB_NAME" -e \
  "SELECT U.USUARIO, R.NOMBRE_ROL, U.ESTADO
     FROM USUARIOS U JOIN ROLES R ON R.ID_ROL = U.ID_ROL
    WHERE U.USUARIO LIKE 'prueba.%'
    ORDER BY R.NOMBRE_ROL;" < /dev/null
