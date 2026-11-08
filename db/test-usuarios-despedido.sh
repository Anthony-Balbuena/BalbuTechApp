#!/usr/bin/env bash
# Test de despido de empleado vs. su usuario (08/11/2026).
# Verifica que al despedir un empleado:
#   - su cuenta de usuario quede INACTIVA y sus sesiones abiertas se borren,
#   - el token deje de resolver (FN_USUARIO_SESION),
#   - no se pueda activar la cuenta mientras el empleado siga despedido,
#   - no se pueda dar de alta un usuario a un empleado despedido,
#   - el listado de alta (PARA_INSERTAR_USUARIOS) no lo ofrezca,
#   - reactivar al empleado NO reactive la cuenta sola.
# Todo corre en una transaccion que se revierte al final.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-usuarios-despedido.sh
set -u

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 1

M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK. Cada caso se verifica aparte con un SELECT.
OUT=$(M --force -N <<'SQL'
START TRANSACTION;

SET @rol = (SELECT ID_ROL FROM ROLES ORDER BY ID_ROL ASC LIMIT 1);

-- ---------------------------------------------------------------
-- Caso 1: empleado con usuario y sesion abierta
-- ---------------------------------------------------------------
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('ZZ DESP UNO', 'ZZD0001', 'ZZ', 1000.00, 'ZZT0001', 'zzdesp1@test.local', CURRENT_DATE);
SET @e1 = LAST_INSERT_ID();

INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA)
VALUES (@e1, @rol, 'zz.desp.uno', 'hash-de-prueba');
SET @u1 = LAST_INSERT_ID();

INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA)
VALUES ('ZZTOKEN-DESP-1', @u1, NOW() + INTERVAL 1 HOUR);
SET @TOKEN_SESION = 'ZZTOKEN-DESP-1';

SELECT 'SESION_ANTES', IF(FN_USUARIO_SESION() = @u1, 'OK', 'FAIL');

CALL SP_DESPEDIR_EMPLEADO(@e1, NULL);

SELECT 'EMPLEADO_INACTIVO', IF((SELECT ESTADO FROM EMPLEADOS WHERE ID_EMPLEADO = @e1) = 'INACTIVO', 'OK', 'FAIL');
SELECT 'USUARIO_INACTIVO',  IF((SELECT ESTADO FROM USUARIOS WHERE ID_USUARIO = @u1) = 'INACTIVO', 'OK', 'FAIL');
SELECT 'SESION_BORRADA',    IF((SELECT COUNT(*) FROM SESIONES WHERE ID_USUARIO = @u1) = 0, 'OK', 'FAIL');
SELECT 'SESION_INVALIDA',   IF(FN_USUARIO_SESION() IS NULL, 'OK', 'FAIL');

-- Activar la cuenta de un despedido: debe fallar.
CALL SP_TOGGLE_ESTADO_USUARIO(@u1);
SELECT 'TOGGLE_BLOQUEADO', IF((SELECT ESTADO FROM USUARIOS WHERE ID_USUARIO = @u1) = 'INACTIVO', 'OK', 'FAIL');

-- Darle otra cuenta a un despedido: debe fallar.
CALL SP_INSERTAR_USUARIO(@e1, @rol, 'zz.desp.otro', 'hash-de-prueba');
SELECT 'ALTA_RECHAZADA', IF((SELECT COUNT(*) FROM USUARIOS WHERE ID_EMPLEADO = @e1) = 1, 'OK', 'FAIL');

-- Reactivar al empleado no reactiva su cuenta.
CALL SP_REACTIVAR_EMPLEADO(@e1, NULL);
SELECT 'REACTIVA_EMPLEADO',     IF((SELECT ESTADO FROM EMPLEADOS WHERE ID_EMPLEADO = @e1) = 'ACTIVO', 'OK', 'FAIL');
SELECT 'REACTIVA_NO_TOCA_USUARIO', IF((SELECT ESTADO FROM USUARIOS WHERE ID_USUARIO = @u1) = 'INACTIVO', 'OK', 'FAIL');

-- Con el empleado activo otra vez, el toggle si funciona.
CALL SP_TOGGLE_ESTADO_USUARIO(@u1);
SELECT 'TOGGLE_PERMITE', IF((SELECT ESTADO FROM USUARIOS WHERE ID_USUARIO = @u1) = 'ACTIVO', 'OK', 'FAIL');

-- ---------------------------------------------------------------
-- Caso 2: el listado de alta no ofrece empleados despedidos
-- ---------------------------------------------------------------
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('ZZ DESP DOS', 'ZZD0002', 'ZZ', 1000.00, 'ZZT0002', 'zzdesp2@test.local', CURRENT_DATE);
SET @e2 = LAST_INSERT_ID();

INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('ZZ DESP TRES', 'ZZD0003', 'ZZ', 1000.00, 'ZZT0003', 'zzdesp3@test.local', CURRENT_DATE);
SET @e3 = LAST_INSERT_ID();

CALL SP_DESPEDIR_EMPLEADO(@e2, NULL);

SELECT 'IDS', @e2, @e3;

CALL PARA_INSERTAR_USUARIOS();

ROLLBACK;
SQL
)

ok=0; fail=0
while IFS=$'\t' read -r caso res; do
    [ -z "$caso" ] && continue
    case "$caso" in
        SESION_ANTES|EMPLEADO_INACTIVO|USUARIO_INACTIVO|SESION_BORRADA|SESION_INVALIDA|TOGGLE_BLOQUEADO|ALTA_RECHAZADA|REACTIVA_EMPLEADO|REACTIVA_NO_TOCA_USUARIO|TOGGLE_PERMITE)
            if [ "$res" = "OK" ]; then
                echo "OK   $caso"; ok=$((ok + 1))
            else
                echo "FAIL $caso: esperado OK, obtenido '$res'"; fail=$((fail + 1))
            fi
            ;;
    esac
done <<< "$OUT"

# El empleado despedido no debe aparecer en el segundo result set del listado
# (lineas "ID_EMPLEADO<TAB>NOMBRE"), pero el activo si.
IDS=$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "IDS" { print $2" "$3 }')
DESP=$(echo "$IDS" | awk '{ print $1 }')
ACTIVO=$(echo "$IDS" | awk '{ print $2 }')

if [ -z "$DESP" ] || [ -z "$ACTIVO" ]; then
    echo "FAIL LISTADO: no se pudieron leer los IDs de prueba"; fail=$((fail + 1))
else
    if printf '%s\n' "$OUT" | grep -qP "^${DESP}\t"; then
        echo "FAIL LISTADO_DESPEDIDO_FUERA: el empleado $DESP sigue en el listado"; fail=$((fail + 1))
    else
        echo "OK   LISTADO_DESPEDIDO_FUERA"; ok=$((ok + 1))
    fi
    if printf '%s\n' "$OUT" | grep -qP "^${ACTIVO}\t"; then
        echo "OK   LISTADO_ACTIVO_DENTRO"; ok=$((ok + 1))
    else
        echo "FAIL LISTADO_ACTIVO_DENTRO: el empleado activo $ACTIVO no aparece"; fail=$((fail + 1))
    fi
fi

# Mensajes: el despido avisa que la cuenta quedo inactiva y la reactivacion
# avisa que el usuario sigue inactivo.
MSGS=0
for MSG in "SU USUARIO QUEDO INACTIVO" "SU USUARIO SIGUE INACTIVO" "EL EMPLEADO ESTA INACTIVO"; do
    if printf '%s\n' "$OUT" | grep -q "$MSG"; then
        MSGS=$((MSGS + 1))
    else
        echo "FALLO: no aparecio el mensaje esperado: $MSG"
    fi
done
echo "Mensajes esperados vistos: $MSGS/3"

if [ $((ok + fail)) -eq 0 ]; then
    echo "FAIL: el test no devolvio resultados" >&2
    fail=$((fail + 1))
fi

echo "Total: $ok OK, $fail FAIL"
[ "$fail" -eq 0 ] && [ "$MSGS" -eq 3 ]
