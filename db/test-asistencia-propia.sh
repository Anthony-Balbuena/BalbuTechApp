#!/usr/bin/env bash
# Test de autoservicio de asistencia (23/10/2026).
# Crea un empleado y un usuario de prueba con SOLO REGISTRAR_ASISTENCIA,
# entra a Asistencia -> Marcar y verifica que la fila quede con SU ID_EMPLEADO,
# sin pedir el ID a mano.
# Uso local:
#   DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root \
#   DB_ADMIN_PASSWORD=linux01 BALBU_PASS=admin123 bash db/test-asistencia-propia.sh
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

ROL="PRUEBA_ASIS"
USR="prueba_asis"
CED="TESTAS001"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/asistencia-propia.XXXXXX")"

limpiar() {
    mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
        -e "DELETE A FROM ASISTENCIA_EMPLEADOS A
              JOIN EMPLEADOS E ON E.ID_EMPLEADO = A.ID_EMPLEADO
             WHERE E.CEDULA = '$CED';
            DELETE FROM USUARIOS WHERE USUARIO = '$USR';
            DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE = '$ROL';
            DELETE FROM ROLES WHERE NOMBRE_ROL = '$ROL';
            DELETE FROM EMPLEADOS WHERE CEDULA = '$CED';" 2>/dev/null || true
    rm -rf "$TMP"
}
trap limpiar EXIT

HASH=$(Q "SELECT CONTRASENA FROM USUARIOS WHERE USUARIO='$BALBU_USER';")
if [ -z "$HASH" ]; then
    echo "No existe el usuario '$BALBU_USER' en $DB_NAME." >&2
    exit 1
fi

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE A FROM ASISTENCIA_EMPLEADOS A
  JOIN EMPLEADOS E ON E.ID_EMPLEADO = A.ID_EMPLEADO
 WHERE E.CEDULA = '$CED';
DELETE FROM USUARIOS WHERE USUARIO = '$USR';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE = '$ROL';
DELETE FROM ROLES WHERE NOMBRE_ROL = '$ROL';
DELETE FROM EMPLEADOS WHERE CEDULA = '$CED';

INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO = 'REGISTRAR_ASISTENCIA';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA ASISTENCIA', '$CED', 'PRUEBA', 1000, 'T-AS-001', 'as-001@test.local', CURDATE());
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA = '$CED' AND R.NOMBRE_ROL = '$ROL';
EOF

ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CED';")
if [ -z "$ID_EMP" ]; then
    echo "FALLO: no se pudo crear el empleado de prueba." >&2
    exit 1
fi

SALIDA="$TMP/salida.txt"
# Secuencia tolerante al horario:
#   Enter del login, 1 = Asistencia, 1 = Marcar.
#   Si la hora es >= 12:00 el SP pide confirmar ENTRADA con 's'.
#   Si es < 12:00, la 's' la consume el "Presione Enter" y el Enter siguiente
#   sale del submenu. En ambos casos termina con 3 = Volver / 3 = Cerrar.
printf '\n1\n1\ns\n\n3\n3\n' | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$SALIDA" 2>&1
RC=$?

fail=0

if ! grep -q "Acceso concedido \[DEV\]" "$SALIDA"; then
    echo "FALLO: no entro al menu (¿usuario/clave/BD?)"
    fail=1
fi
if [ "$RC" -ne 0 ]; then
    echo "FALLO: la app salio con $RC"
    fail=1
fi
if grep -q "ID empleado:" "$SALIDA"; then
    echo "FALLO: Marcar asistencia todavia pide el ID a mano"
    fail=1
fi
if ! grep -q "MARCAR ASISTENCIA" "$SALIDA"; then
    echo "FALLO: no entro a Marcar asistencia"
    fail=1
fi

FILAS=$(Q "SELECT COUNT(*) FROM ASISTENCIA_EMPLEADOS
            WHERE ID_EMPLEADO = $ID_EMP AND FECHA = CURDATE();")
if [ "$FILAS" -ne 1 ]; then
    echo "FALLO: se esperaba 1 fila de asistencia para el empleado $ID_EMP, hay $FILAS"
    fail=1
fi

ENTRADA=$(Q "SELECT HORA_ENTRADA IS NOT NULL FROM ASISTENCIA_EMPLEADOS
              WHERE ID_EMPLEADO = $ID_EMP AND FECHA = CURDATE();")
if [ "$ENTRADA" != "1" ]; then
    echo "FALLO: la fila quedo sin HORA_ENTRADA"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK ASISTENCIA PROPIA (empleado $ID_EMP, sin pedir ID)"
else
    echo "TEST ASISTENCIA PROPIA: FALLAS ARRIBA"
    echo "--- salida ---"
    sed -n '1,80p' "$SALIDA"
fi

exit "$fail"
