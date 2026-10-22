#!/usr/bin/env bash
# Test de la migracion de roles (modulo 44) — 22/10/2026.
# Simula una base vieja: crea EMPLEADO y CAJERO con un usuario cada uno, corre el
# modulo 44 dos veces y verifica que los roles se retiren y los usuarios pasen a
# VENDEDOR sin perder la matriz.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-migracion-roles.sh
set -u

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
SQL="modulos/44- MIGRACION_ROLES.sql"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

if [ ! -f "$SQL" ]; then
    echo "FALTA $SQL: correr desde la raiz del repo." >&2
    exit 1
fi

cd "$(dirname "$0")/.." || exit 1

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>/dev/null; }

limpiar() {
    # Orden por FKs: los logs apuntan a USUARIOS (FK_LOG_USUARIOS_USUARIO) y el
    # UPDATE de la migracion dispara el trigger que escribe LOG_USUARIOS; sin
    # borrar esos hijos primero, el DELETE de USUARIOS falla con ERROR 1451.
    # Despues: usuarios antes que empleados (FK_USUARIO_EMPLEADO), y el par antes
    # que el rol (FK_ROL_PERMISO_ROL es RESTRICT).
    Q "DELETE FROM LOG_USUARIOS WHERE ID_USUARIO IN
         (SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO IN ('prueba_mig_emp', 'prueba_mig_caj'));
       DELETE FROM LOG_ACCESOS WHERE ID_USUARIO IN
         (SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO IN ('prueba_mig_emp', 'prueba_mig_caj'));
       DELETE FROM USUARIOS WHERE USUARIO IN ('prueba_mig_emp', 'prueba_mig_caj');
       DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE IN ('EMPLEADO', 'CAJERO', 'PRUEBA_ALCANCE');
       DELETE FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO', 'CAJERO', 'PRUEBA_ALCANCE');
       DELETE FROM EMPLEADOS WHERE CEDULA IN ('TESTMIG001', 'TESTMIG002');" >/dev/null 2>&1 || true
}
trap limpiar EXIT

fail=0
comprobar() {
    local descripcion="$1" obtenido="$2" esperado="$3"
    if [ "$obtenido" = "$esperado" ]; then
        echo "OK    $descripcion ($obtenido)"
    else
        echo "FALLO $descripcion: $obtenido (se esperaba $esperado)"
        fail=1
    fi
}

# ---------------------------------------------------------------------------
# 1. Escenario "base vieja": los dos roles retirados, cada uno con un permiso y
#    un usuario propio.
# ---------------------------------------------------------------------------
limpiar
mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" >/dev/null 2>&1 <<'SQL'
INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES ('EMPLEADO'), ('CAJERO');
INSERT IGNORE INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
 SELECT 'EMPLEADO', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_VENTAS';
INSERT IGNORE INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
 SELECT 'CAJERO', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_VENTAS';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO) VALUES
 ('PRUEBA MIG EMPLEADO','TESTMIG001','PRUEBA',1000,'T-MG-001','mig-001@test.local','2026-10-22'),
 ('PRUEBA MIG CAJERO','TESTMIG002','PRUEBA',1000,'T-MG-002','mig-002@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
 SELECT 'prueba_mig_emp', 'x', E.ID_EMPLEADO, R.ID_ROL
   FROM EMPLEADOS E, ROLES R
  WHERE E.CEDULA='TESTMIG001' AND R.NOMBRE_ROL='EMPLEADO';
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
 SELECT 'prueba_mig_caj', 'x', E.ID_EMPLEADO, R.ID_ROL
   FROM EMPLEADOS E, ROLES R
  WHERE E.CEDULA='TESTMIG002' AND R.NOMBRE_ROL='CAJERO';
SQL

comprobar "roles retirados antes de migrar" \
    "$(Q "SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO','CAJERO')")" "2"
comprobar "usuarios en roles retirados antes de migrar" \
    "$(Q "SELECT COUNT(*) FROM USUARIOS U JOIN ROLES R ON R.ID_ROL=U.ID_ROL
          WHERE U.USUARIO IN ('prueba_mig_emp','prueba_mig_caj')")" "2"

# ---------------------------------------------------------------------------
# 2. Primera pasada: tiene que retirar los roles y mover los usuarios.
# ---------------------------------------------------------------------------
errores=$(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
    --database="$DB_NAME" --force < "$SQL" 2>&1 | grep -c "^ERROR" || true)
comprobar "errores SQL en la primera pasada" "$errores" "0"

comprobar "roles retirados despues de migrar" \
    "$(Q "SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO','CAJERO')")" "0"
comprobar "usuarios que quedaron en un rol retirado" \
    "$(Q "SELECT COUNT(*) FROM USUARIOS U JOIN ROLES R ON R.ID_ROL=U.ID_ROL
          WHERE U.USUARIO IN ('prueba_mig_emp','prueba_mig_caj')
            AND R.NOMBRE_ROL IN ('EMPLEADO','CAJERO')")" "0"
comprobar "usuarios movidos a VENDEDOR" \
    "$(Q "SELECT COUNT(*) FROM USUARIOS U JOIN ROLES R ON R.ID_ROL=U.ID_ROL
          WHERE U.USUARIO IN ('prueba_mig_emp','prueba_mig_caj')
            AND R.NOMBRE_ROL = 'VENDEDOR'")" "2"
comprobar "los 7 roles del set final" \
    "$(Q "SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL IN
          ('ADMIN','GERENTE','SUBGERENTE','RRHH','VENDEDOR','ALMACEN','CONTABILIDAD')")" "7"
comprobar "permisos de VENDEDOR intactos" \
    "$(Q "SELECT COUNT(*) FROM ROL_PERMISO WHERE ROL_NOMBRE='VENDEDOR'")" "10"

# ---------------------------------------------------------------------------
# 3. Segunda pasada: idempotente, sin errores y sin cambiar nada.
# ---------------------------------------------------------------------------
roles_antes=$(Q "SELECT COUNT(*) FROM ROLES")
matriz_antes=$(Q "SELECT COUNT(*) FROM ROL_PERMISO")
errores=$(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
    --database="$DB_NAME" --force < "$SQL" 2>&1 | grep -c "^ERROR" || true)
comprobar "errores SQL en la segunda pasada" "$errores" "0"
comprobar "roles sin cambios en la segunda pasada" "$(Q "SELECT COUNT(*) FROM ROLES")" "$roles_antes"
comprobar "matriz sin cambios en la segunda pasada" "$(Q "SELECT COUNT(*) FROM ROL_PERMISO")" "$matriz_antes"

# ---------------------------------------------------------------------------
# 4. Alcance: un rol personalizado y sus pares no se tocan, y nadie queda
#    apuntando a un ID_ROL inexistente.
# ---------------------------------------------------------------------------
Q "INSERT INTO ROLES (NOMBRE_ROL) VALUES ('PRUEBA_ALCANCE')
     ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
   INSERT IGNORE INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
     SELECT 'PRUEBA_ALCANCE', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO = 'GESTIONAR_VENTAS';"
errores=$(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
    --database="$DB_NAME" --force < "$SQL" 2>&1 | grep -c "^ERROR" || true)
comprobar "errores SQL con un rol personalizado presente" "$errores" "0"
comprobar "rol personalizado que sobrevivio" \
    "$(Q "SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL='PRUEBA_ALCANCE'")" "1"
comprobar "pares del rol personalizado que sobrevivieron" \
    "$(Q "SELECT COUNT(*) FROM ROL_PERMISO WHERE ROL_NOMBRE='PRUEBA_ALCANCE'")" "1"
comprobar "usuarios con un ID_ROL inexistente" \
    "$(Q "SELECT COUNT(*) FROM USUARIOS U LEFT JOIN ROLES R ON R.ID_ROL=U.ID_ROL WHERE R.ID_ROL IS NULL")" "0"

if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DE MIGRACION DE ROLES OK"
else
    echo "TESTS DE MIGRACION DE ROLES: FALLAS ARRIBA"
fi
exit "$fail"
