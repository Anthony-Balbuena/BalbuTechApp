#!/usr/bin/env bash
# Test de auditoria del sistema (modulo 57) — 25/10/2026.
# Verifica que los SP de consulta no dejen versiones viejas, que los tres
# triggers de PROVEEDORES registren INSERT/UPDATE/DELETE y que guarden como
# USUARIO_SISTEMA el nombre de @ID_USUARIO_ACTUAL.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-auditoria-sistema.sh
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

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>&1; }

limpiar() {
    Q "DELETE FROM AUDITORIA_SISTEMA
        WHERE TABLA_AFECTADA = 'PROVEEDORES'
          AND (VALOR_ANTERIOR LIKE '%ZZ AUDIT 57%' OR VALOR_NUEVO LIKE '%ZZ AUDIT 57%');
       DELETE FROM PROVEEDORES WHERE NOMBRE LIKE 'ZZ AUDIT 57%';" >/dev/null 2>&1 || true
}
trap limpiar EXIT
limpiar

if ! mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
     < "modulos/57- AUDITORIA_SISTEMA_FIX.sql" >/dev/null 2>&1; then
    echo "FALLO: no se pudo aplicar modulos/57- AUDITORIA_SISTEMA_FIX.sql" >&2
    exit 1
fi

ok=0; fail=0
check() { # nombre, esperado, obtenido
    if [ "$2" = "$3" ]; then
        echo "OK   $1"
        ok=$((ok + 1))
    else
        echo "FAIL $1: esperado '$2', obtenido '$3'"
        fail=$((fail + 1))
    fi
}

U=$(Q "SELECT ID_USUARIO FROM USUARIOS ORDER BY ID_USUARIO LIMIT 1" | tr -d '[:space:]')
NOM=$(Q "SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = $U" | tr -d '[:space:]')
if [ -z "$U" ] || [ -z "$NOM" ]; then
    echo "FALLO: no hay usuario en $DB_NAME para probar el admin." >&2
    exit 1
fi

P=$(Q "SET @ID_USUARIO_ACTUAL = $U;
       INSERT INTO PROVEEDORES (NOMBRE, TELEFONO, EMAIL)
       VALUES ('ZZ AUDIT 57', '00000000057', 'zz57@test.local');
       SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
if [ -z "$P" ]; then
    echo "FALLO: no se pudo crear el proveedor de prueba." >&2
    exit 1
fi

Q "SET @ID_USUARIO_ACTUAL = $U;
   UPDATE PROVEEDORES SET NOMBRE = 'ZZ AUDIT 57 B' WHERE ID_PROVEEDOR = $P;" >/dev/null
Q "SET @ID_USUARIO_ACTUAL = $U;
   DELETE FROM PROVEEDORES WHERE ID_PROVEEDOR = $P;" >/dev/null

OUT=$(Q "
SELECT 'INSERT', (ACCION = 'INSERT' AND USUARIO_SISTEMA = '$NOM' AND VALOR_NUEVO LIKE '%ZZ AUDIT 57%')
  FROM AUDITORIA_SISTEMA WHERE TABLA_AFECTADA = 'PROVEEDORES'
   AND ID_REGISTRO_AFECTADO = $P AND ACCION = 'INSERT' LIMIT 1;
SELECT 'UPDATE', (ACCION = 'UPDATE' AND USUARIO_SISTEMA = '$NOM'
   AND VALOR_ANTERIOR LIKE '%ZZ AUDIT 57%' AND VALOR_NUEVO LIKE '%ZZ AUDIT 57 B%')
  FROM AUDITORIA_SISTEMA WHERE TABLA_AFECTADA = 'PROVEEDORES'
   AND ID_REGISTRO_AFECTADO = $P AND ACCION = 'UPDATE' LIMIT 1;
SELECT 'DELETE', (ACCION = 'DELETE' AND USUARIO_SISTEMA = '$NOM'
   AND VALOR_ANTERIOR LIKE '%ZZ AUDIT 57 B%')
  FROM AUDITORIA_SISTEMA WHERE TABLA_AFECTADA = 'PROVEEDORES'
   AND ID_REGISTRO_AFECTADO = $P AND ACCION = 'DELETE' LIMIT 1;
SELECT 'TOTAL', (COUNT(*) = 3)
  FROM AUDITORIA_SISTEMA WHERE TABLA_AFECTADA = 'PROVEEDORES'
   AND ID_REGISTRO_AFECTADO = $P;
")

while IFS=$'\t' read -r caso res; do
    [ -z "$caso" ] && continue
    check "$caso" "1" "$res"
done <<< "$OUT"

check "SP historial trae el DELETE" "1" \
    "$(Q "CALL 6_SP_CONSULTAR_HISTORIAL_REGISTRO('PROVEEDORES', $P);" | grep -c 'DELETE' || true)"

L=$(Q "CALL 6_SP_LISTAR_AUDITORIA_GENERAL('PROVEEDORES', CURDATE(), CURDATE());" | grep -c 'ZZ AUDIT 57' || true)
check "SP listar incluye hoy" "1" "$([ "$L" -ge 1 ] && echo 1 || echo 0)"

V=$(Q "SELECT COUNT(*) FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = '$DB_NAME'
          AND ROUTINE_NAME IN ('SP_LISTAR_AUDITORIA_GENERAL',
                               'SP_CONSULTAR_HISTORIAL_REGISTRO',
                               '6_SP_LIMPIAR_AUDITORIA');" | tr -d '[:space:]')
check "sin rutinas viejas sin prefijo" "0" "$V"

T=$(Q "SELECT COUNT(*) FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = '$DB_NAME'
          AND EVENT_OBJECT_TABLE = 'PROVEEDORES'
          AND TRIGGER_NAME LIKE 'TR_AUDIT_PROVEEDORES_%';" | tr -d '[:space:]')
check "tres triggers de proveedores" "3" "$T"

echo "Total: $ok OK, $fail FAIL"
[ "$fail" -eq 0 ]
