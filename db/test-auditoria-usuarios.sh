#!/usr/bin/env bash
# Test de auditoria de usuarios (modulo 56) — 25/10/2026.
# Verifica que TRG_AUDITORIA_USUARIOS registre rol, estado y nombre de
# usuario, y que guarde como admin el id de @ID_USUARIO_ACTUAL.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-auditoria-usuarios.sh
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

if ! M < "modulos/56- AUDITORIA_USUARIOS.sql" >/dev/null; then
    echo "FALLO: no se pudo aplicar modulos/56- AUDITORIA_USUARIOS.sql" >&2
    exit 1
fi

# Todo corre en una transaccion que se revierte: no deja datos en TEST.
OUT=$(M -N <<'SQL'
START TRANSACTION;
SET @u    = (SELECT ID_USUARIO FROM USUARIOS ORDER BY ID_USUARIO LIMIT 1);
SET @rol1 = (SELECT ID_ROL FROM USUARIOS WHERE ID_USUARIO = @u);
SET @rol2 = (SELECT ID_ROL FROM ROLES WHERE ID_ROL <> @rol1 ORDER BY ID_ROL LIMIT 1);
SET @nom1 = (SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @u);
SET @est1 = (SELECT ESTADO FROM USUARIOS WHERE ID_USUARIO = @u);
SET @est2 = IF(@est1 = 'ACTIVO', 'INACTIVO', 'ACTIVO');
SET @ID_USUARIO_ACTUAL = @u;

UPDATE USUARIOS SET ID_ROL = @rol2 WHERE ID_USUARIO = @u;
SELECT 'ROL', (ACCION = 'CAMBIO_ROL' AND VALOR_ANTERIOR = CAST(@rol1 AS CHAR)
               AND VALOR_NUEVO = CAST(@rol2 AS CHAR) AND ID_USUARIO_ADMIN = @u)
  FROM LOG_USUARIOS WHERE ID_USUARIO = @u ORDER BY ID_LOG DESC LIMIT 1;

UPDATE USUARIOS SET USUARIO = CONCAT(@nom1, '_zz') WHERE ID_USUARIO = @u;
SELECT 'USUARIO', (ACCION = 'CAMBIO_USUARIO' AND VALOR_ANTERIOR = @nom1
                   AND VALOR_NUEVO = CONCAT(@nom1, '_zz') AND ID_USUARIO_ADMIN = @u)
  FROM LOG_USUARIOS WHERE ID_USUARIO = @u ORDER BY ID_LOG DESC LIMIT 1;

UPDATE USUARIOS SET ESTADO = @est2 WHERE ID_USUARIO = @u;
SELECT 'ESTADO', (ACCION = 'CAMBIO_ESTADO' AND VALOR_ANTERIOR = @est1
                  AND VALOR_NUEVO = @est2 AND ID_USUARIO_ADMIN = @u)
  FROM LOG_USUARIOS WHERE ID_USUARIO = @u ORDER BY ID_LOG DESC LIMIT 1;

SELECT 'VISTA', (USUARIO_ADMIN = CONCAT(@nom1, '_zz'))
  FROM VIEW_HISTORIAL_CAMBIOS_USUARIOS
 WHERE ID_USUARIO_ADMIN = @u ORDER BY ID_LOG DESC LIMIT 1;

SET @ID_USUARIO_ACTUAL = NULL;
UPDATE USUARIOS SET ID_ROL = @rol1 WHERE ID_USUARIO = @u;
SELECT 'SINVAR', (ACCION = 'CAMBIO_ROL' AND ID_USUARIO_ADMIN IS NULL)
  FROM LOG_USUARIOS WHERE ID_USUARIO = @u ORDER BY ID_LOG DESC LIMIT 1;

ROLLBACK;
SQL
)

ok=0; fail=0
while IFS=$'\t' read -r caso res; do
    [ -z "$caso" ] && continue
    if [ "$res" = "1" ]; then
        echo "OK   $caso"
        ok=$((ok + 1))
    else
        echo "FAIL $caso: esperado 1, obtenido '$res'"
        fail=$((fail + 1))
    fi
done <<< "$OUT"

if [ "$ok" -eq 0 ]; then
    echo "FAIL: el test no devolvio resultados" >&2
    fail=$((fail + 1))
fi

echo "Total: $ok OK, $fail FAIL"
[ "$fail" -eq 0 ]
