#!/usr/bin/env bash
# Test del menu principal por rol (22/10/2026).
# Crea 9 empleados/usuarios de prueba en BALBU_TECH_TEST (el ADMIN usa el
# usuario admin existente), corre la app con el atajo DEV y verifica que el
# menu muestre exactamente las opciones que da la matriz de permisos.
# Uso dentro del contenedor app:
#   BALBU_PASS=<clave del admin> bash db/test-menus-por-rol.sh
# El repo no guarda credenciales: la clave se pasa por env. DB_* y
# DB_ADMIN_* salen del .env del contenedor.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_USER="${BALBU_USER:-admin}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave del usuario admin)}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/menus-rol.XXXXXX")"
limpiar() {
    # Orden por FKs: usuarios antes que empleados, y pares del rol antes que el
    # rol (FK_ROL_PERMISO_ROL no tiene ON DELETE CASCADE). Si el rol se borrara
    # primero, el DELETE fallaria y no se limpiaria nada.
    mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" \
        -e "DELETE FROM USUARIOS WHERE USUARIO LIKE 'prueba_r7_%' OR USUARIO IN ('prueba_usr_ver', 'prueba_emp_ver', 'prueba_cli_ver', 'prueba_prod_gest', 'prueba_ven_gest', 'prueba_asi_ver', 'prueba_prov_ver', 'prueba_cat_ver', 'prueba_mar_ver', 'prueba_met_ver', 'prueba_com_ver', 'prueba_com_reg_pag', 'prueba_caja_ver', 'prueba_caja_gest');
            DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE IN ('PRUEBA_USR_VER', 'PRUEBA_EMP_VER', 'PRUEBA_CLI_VER', 'PRUEBA_PROD_GEST', 'PRUEBA_VEN_GEST', 'PRUEBA_ASI_VER', 'PRUEBA_PROV_VER', 'PRUEBA_CAT_VER', 'PRUEBA_MAR_VER', 'PRUEBA_MET_VER', 'PRUEBA_COM_VER', 'PRUEBA_COM_REG_PAG', 'PRUEBA_CAJA_VER', 'PRUEBA_CAJA_GEST');
            DELETE FROM ROLES WHERE NOMBRE_ROL IN ('PRUEBA_USR_VER', 'PRUEBA_EMP_VER', 'PRUEBA_CLI_VER', 'PRUEBA_PROD_GEST', 'PRUEBA_VEN_GEST', 'PRUEBA_ASI_VER', 'PRUEBA_PROV_VER', 'PRUEBA_CAT_VER', 'PRUEBA_MAR_VER', 'PRUEBA_MET_VER', 'PRUEBA_COM_VER', 'PRUEBA_COM_REG_PAG', 'PRUEBA_CAJA_VER', 'PRUEBA_CAJA_GEST');
            DELETE FROM EMPLEADOS WHERE CEDULA LIKE 'TESTR7%' OR CEDULA IN ('TESTUV001', 'TESTEV001', 'TESTCV001', 'TESTPG001', 'TESTVG001', 'TESTAV001', 'TESTPV001', 'TESTCA001', 'TESTMA001', 'TESTME001', 'TESTCO001', 'TESTCO002', 'TESTCJ001', 'TESTCJ002');" 2>/dev/null || true
    rm -rf "$TMP"
}
trap limpiar EXIT

HASH=$(Q "SELECT CONTRASENA FROM USUARIOS WHERE USUARIO='$BALBU_USER';")
if [ -z "$HASH" ]; then
    echo "No existe el usuario '$BALBU_USER' en $DB_NAME." >&2
    exit 1
fi

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO) VALUES
 ('PRUEBA R7 GERENTE','TESTR7001','PRUEBA',1000,'T-R7-001','r7-001@test.local','2026-10-22'),
 ('PRUEBA R7 SUBGERENTE','TESTR7002','PRUEBA',1000,'T-R7-002','r7-002@test.local','2026-10-22'),
 ('PRUEBA R7 RRHH','TESTR7003','PRUEBA',1000,'T-R7-003','r7-003@test.local','2026-10-22'),
 ('PRUEBA R7 VENDEDOR','TESTR7004','PRUEBA',1000,'T-R7-004','r7-004@test.local','2026-10-22'),
 ('PRUEBA R7 ALMACEN','TESTR7005','PRUEBA',1000,'T-R7-005','r7-005@test.local','2026-10-22'),
 ('PRUEBA R7 CONTABILIDAD','TESTR7006','PRUEBA',1000,'T-R7-006','r7-006@test.local','2026-10-22');

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_ger', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7001' AND R.NOMBRE_ROL='GERENTE';

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_sub', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7002' AND R.NOMBRE_ROL='SUBGERENTE';

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_rrhh', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7003' AND R.NOMBRE_ROL='RRHH';

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_ven', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7004' AND R.NOMBRE_ROL='VENDEDOR';

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_alm', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7005' AND R.NOMBRE_ROL='ALMACEN';

INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT 'prueba_r7_con', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTR7006' AND R.NOMBRE_ROL='CONTABILIDAD';
EOF

fail=0
fallos=0

revisar() {
    local rol="$1" usuario="$2" cant="$3" labels="$4"
    local salida="$TMP/out-$rol.txt" rc n fallos_previos=$fallos
    printf '\n0\n' | BALBU_USER="$usuario" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
        timeout "$LIMITE" "$APP" >"$salida" 2>&1
    rc=$?

    if ! grep -q "Acceso concedido \[DEV\]" "$salida"; then
        echo "FALLO $rol: no entro al menu (¿usuario/clave/BD?)"
        fail=1; fallos=$((fallos+1))
        return
    fi
    if [ "$rc" -ne 0 ]; then
        echo "FALLO $rol: la app salio con $rc"
        fail=1; fallos=$((fallos+1))
        return
    fi

    n=$(grep -c '^[0-9]\+\. ' "$salida" || true)
    if [ "$n" -ne "$cant" ]; then
        echo "FALLO $rol: $n opciones, se esperaban $cant"
        fail=1; fallos=$((fallos+1))
    fi

    local IFS='|'
    for label in $labels; do
        if ! grep -Fq "$label" "$salida"; then
            echo "FALLO $rol: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $rol ($n opciones)"
    fi
}

# Las listas usan | como separador; tienen que coincidir con itemsMenuPrincipal().
revisar "ADMIN" "$BALBU_USER" 19 "Asistencia|Roles|Usuarios|Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Accesos|Ver permisos|Cerrar sesión"
revisar "GERENTE" "prueba_r7_ger" 16 "Asistencia|Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "SUBGERENTE" "prueba_r7_sub" 16 "Asistencia|Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "RRHH" "prueba_r7_rrhh" 6 "Asistencia|Empleados|Mis permisos|Mis vacaciones|Ver permisos|Cerrar sesión"
revisar "VENDEDOR" "prueba_r7_ven" 10 "Asistencia|Mis permisos|Mis vacaciones|Clientes|Productos|Metodos de pago|Ventas|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "ALMACEN" "prueba_r7_alm" 11 "Asistencia|Mis permisos|Mis vacaciones|Proveedores|Categorias|Marcas|Productos|Compras|Inventario|Ver permisos|Cerrar sesión"
revisar "CONTABILIDAD" "prueba_r7_con" 5 "Asistencia|Clientes|Productos|Ver permisos|Cerrar sesión"

# ---------------------------------------------------------------------------
# Submenu Usuarios con permisos finos (22/10/2026): un rol con SOLO
# USUARIOS_VER ve Usuarios en el menu principal y, adentro, solo las acciones
# de consulta mas Volver.
# ---------------------------------------------------------------------------
ROL_VER="PRUEBA_USR_VER"
USR_VER="prueba_usr_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_VER';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTUV001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_VER';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_VER')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_VER', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='USUARIOS_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA USR VER','TESTUV001','PRUEBA',1000,'T-UV-001','uv-001@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_VER', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTUV001' AND R.NOMBRE_ROL='$ROL_VER';
EOF

fallos_previos=$fallos
salida_usr="$TMP/out-usuarios-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Usuarios, 3 = Volver al Menu
# Principal (el submenu filtrado solo tiene 3 opciones; el viejo 7 ya no existe).
printf '\n1\n3\n' | BALBU_USER="$USR_VER" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_usr" 2>&1
rc_usr=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_usr"; then
    echo "FALLO $ROL_VER: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_usr" -ne 0 ]; then
    echo "FALLO $ROL_VER: la app salio con $rc_usr"
    fail=1; fallos=$((fallos+1))
else
    # Solo la primera tirada del menu principal (hasta el submenu): contarlo
    # sobre toda la salida mezclaria las dos listas numeradas.
    principal=$(sed -n '1,/=== MODULO DE USUARIOS ===/p' "$salida_usr")
    n_principal=$(printf '%s\n' "$principal" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal" -ne 3 ]; then
        echo "FALLO $ROL_VER: $n_principal opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Usuarios" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal" | grep -Fq "$label"; then
            echo "FALLO $ROL_VER: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    # Solo la primera tirada del submenu (titulo -> linea de cierre).
    submenu=$(awk '/=== MODULO DE USUARIOS ===/{f=1} f{print} /^=========================$/ && f{exit}' "$salida_usr")
    n_sub=$(printf '%s\n' "$submenu" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub" -ne 3 ]; then
        echo "FALLO $ROL_VER: $n_sub opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Usuario" "Listar Usuarios" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu" | grep -Fq "$label"; then
            echo "FALLO $ROL_VER: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Usuario" "Actualizar Usuario" "Cambiar Estado" "Cambiar Clave"; do
        if printf '%s\n' "$submenu" | grep -Fq "$label"; then
            echo "FALLO $ROL_VER: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_VER (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Empleados con permisos finos (22/10/2026): un rol con SOLO
# EMPLEADOS_VER ve Empleados en el menu principal y, adentro, solo las dos
# acciones de consulta mas Volver.
# ---------------------------------------------------------------------------
ROL_EMP="PRUEBA_EMP_VER"
USR_EMP="prueba_emp_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_EMP';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTEV001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_EMP';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_EMP')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_EMP', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='EMPLEADOS_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA EMP VER','TESTEV001','PRUEBA',1000,'T-EV-001','ev-001@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_EMP', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTEV001' AND R.NOMBRE_ROL='$ROL_EMP';
EOF

fallos_previos=$fallos
salida_emp="$TMP/out-empleados-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Empleados (con este rol es la
# primera opcion visible: el menu queda Empleados, Ver permisos y Cerrar
# sesion), 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_EMP" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_emp" 2>&1
rc_emp=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_emp"; then
    echo "FALLO $ROL_EMP: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_emp" -ne 0 ]; then
    echo "FALLO $ROL_EMP: la app salio con $rc_emp"
    fail=1; fallos=$((fallos+1))
else
    # Solo la primera tirada del menu principal (hasta el submenu): contarlo
    # sobre toda la salida mezclaria las dos listas numeradas.
    principal_emp=$(sed -n '1,/=== MODULO DE EMPLEADOS ===/p' "$salida_emp")
    n_principal_emp=$(printf '%s\n' "$principal_emp" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_emp" -ne 3 ]; then
        echo "FALLO $ROL_EMP: $n_principal_emp opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Empleados" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_emp" | grep -Fq "$label"; then
            echo "FALLO $ROL_EMP: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    # Solo la primera tirada del submenu (titulo -> linea de cierre).
    submenu_emp=$(awk '/=== MODULO DE EMPLEADOS ===/{f=1} f{print} /^=============================$/ && f{exit}' "$salida_emp")
    n_sub_emp=$(printf '%s\n' "$submenu_emp" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_emp" -ne 3 ]; then
        echo "FALLO $ROL_EMP: $n_sub_emp opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Empleado" "Listar Empleados" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_emp" | grep -Fq "$label"; then
            echo "FALLO $ROL_EMP: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Empleado" "Actualizar Datos" "Despedir Empleado" \
                 "Reactivar Empleado" "Marcar asistencia" "Gestionar permisos" \
                 "Gestionar vacaciones" "Generar contrato"; do
        if printf '%s\n' "$submenu_emp" | grep -Fq "$label"; then
            echo "FALLO $ROL_EMP: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_EMP (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Clientes con permisos finos (22/10/2026): un rol con SOLO
# CLIENTES_VER ve Clientes en el menu principal y, adentro, solo las dos
# acciones de consulta mas Volver.
# ---------------------------------------------------------------------------
ROL_CLI="PRUEBA_CLI_VER"
USR_CLI="prueba_cli_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_CLI';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCV001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_CLI';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_CLI')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_CLI', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='CLIENTES_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA CLI VER','TESTCV001','PRUEBA',1000,'T-CV-001','cv-001@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_CLI', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCV001' AND R.NOMBRE_ROL='$ROL_CLI';
EOF

fallos_previos=$fallos
salida_cli="$TMP/out-clientes-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Clientes (con este rol es la
# primera opcion visible: el menu queda Clientes, Ver permisos y Cerrar
# sesion), 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_CLI" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_cli" 2>&1
rc_cli=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_cli"; then
    echo "FALLO $ROL_CLI: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_cli" -ne 0 ]; then
    echo "FALLO $ROL_CLI: la app salio con $rc_cli"
    fail=1; fallos=$((fallos+1))
else
    # Solo la primera tirada del menu principal (hasta el submenu): contarlo
    # sobre toda la salida mezclaria las dos listas numeradas.
    principal_cli=$(sed -n '1,/=== MODULO DE CLIENTES ===/p' "$salida_cli")
    n_principal_cli=$(printf '%s\n' "$principal_cli" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_cli" -ne 3 ]; then
        echo "FALLO $ROL_CLI: $n_principal_cli opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Clientes" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_cli" | grep -Fq "$label"; then
            echo "FALLO $ROL_CLI: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    # Solo la primera tirada del submenu (titulo -> linea de cierre).
    submenu_cli=$(awk '/=== MODULO DE CLIENTES ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_cli")
    n_sub_cli=$(printf '%s\n' "$submenu_cli" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_cli" -ne 3 ]; then
        echo "FALLO $ROL_CLI: $n_sub_cli opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Cliente" "Listar Clientes" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_cli" | grep -Fq "$label"; then
            echo "FALLO $ROL_CLI: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Cliente" "Actualizar Cliente" "Cambiar Estado"; do
        if printf '%s\n' "$submenu_cli" | grep -Fq "$label"; then
            echo "FALLO $ROL_CLI: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_CLI (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# CONTABILIDAD con permisos finos de Clientes (22/10/2026): reutiliza el
# usuario prueba_r7_con. Entra a Clientes y debe ver exactamente las dos
# consultas mas Volver.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_con="$TMP/out-clientes-contabilidad.txt"
# Entrada: Enter del "Presione Enter", 2 = Clientes (su menu queda Asistencia,
# Clientes, Productos, Ver permisos y Cerrar sesion), 3 = Volver.
printf '\n2\n3\n' | BALBU_USER="prueba_r7_con" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_con" 2>&1
rc_con=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_con"; then
    echo "FALLO CONTABILIDAD/Clientes: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_con" -ne 0 ]; then
    echo "FALLO CONTABILIDAD/Clientes: la app salio con $rc_con"
    fail=1; fallos=$((fallos+1))
else
    submenu_con=$(awk '/=== MODULO DE CLIENTES ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_con")
    n_sub_con=$(printf '%s\n' "$submenu_con" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_con" -ne 3 ]; then
        echo "FALLO CONTABILIDAD/Clientes: $n_sub_con opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Cliente" "Listar Clientes" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_con" | grep -Fq "$label"; then
            echo "FALLO CONTABILIDAD/Clientes: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Cliente" "Actualizar Cliente" "Cambiar Estado"; do
        if printf '%s\n' "$submenu_con" | grep -Fq "$label"; then
            echo "FALLO CONTABILIDAD/Clientes: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK CONTABILIDAD/Clientes (3 opciones en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Proveedores con permisos finos (23/10/2026): un rol con SOLO
# PROVEEDORES_VER ve Proveedores en el menu principal y, adentro, solo las dos
# consultas mas Volver.
# ---------------------------------------------------------------------------
ROL_PROV="PRUEBA_PROV_VER"
USR_PROV="prueba_prov_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_PROV';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTPV001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_PROV';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_PROV';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_PROV')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_PROV', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='PROVEEDORES_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA PROV VER','TESTPV001','PRUEBA',1000,'T-PV-001','pv-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_PROV', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTPV001' AND R.NOMBRE_ROL='$ROL_PROV';
EOF

fallos_previos=$fallos
salida_prov="$TMP/out-proveedores-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Proveedores (con este rol es la
# primera opcion visible: el menu queda Proveedores, Ver permisos y Cerrar
# sesion), 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_PROV" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_prov" 2>&1
rc_prov=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_prov"; then
    echo "FALLO $ROL_PROV: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_prov" -ne 0 ]; then
    echo "FALLO $ROL_PROV: la app salio con $rc_prov"
    fail=1; fallos=$((fallos+1))
else
    principal_prov=$(sed -n '1,/=== MODULO PROVEEDORES ===/p' "$salida_prov")
    n_principal_prov=$(printf '%s\n' "$principal_prov" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_prov" -ne 3 ]; then
        echo "FALLO $ROL_PROV: $n_principal_prov opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Proveedores" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_prov" | grep -Fq "$label"; then
            echo "FALLO $ROL_PROV: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    submenu_prov=$(awk '/=== MODULO PROVEEDORES ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_prov")
    n_sub_prov=$(printf '%s\n' "$submenu_prov" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_prov" -ne 3 ]; then
        echo "FALLO $ROL_PROV: $n_sub_prov opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar proveedor" "Listar proveedores" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_prov" | grep -Fq "$label"; then
            echo "FALLO $ROL_PROV: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar proveedor" "Actualizar proveedor" "Activar/Desactivar proveedor"; do
        if printf '%s\n' "$submenu_prov" | grep -Fq "$label"; then
            echo "FALLO $ROL_PROV: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_PROV (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# ALMACEN con los 4 permisos de Proveedores (23/10/2026): ve el submenu
# historico completo de 6 opciones.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_prov_alm="$TMP/out-proveedores-almacen.txt"
# Entrada: Enter del "Presione Enter", 4 = Proveedores (su menu queda
# Asistencia, Mis permisos, Mis vacaciones, Proveedores, ...), 6 = Volver.
printf '\n4\n6\n' | BALBU_USER="prueba_r7_alm" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_prov_alm" 2>&1
rc_prov_alm=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_prov_alm"; then
    echo "FALLO ALMACEN/Proveedores: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_prov_alm" -ne 0 ]; then
    echo "FALLO ALMACEN/Proveedores: la app salio con $rc_prov_alm"
    fail=1; fallos=$((fallos+1))
else
    submenu_prov_alm=$(awk '/=== MODULO PROVEEDORES ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_prov_alm")
    n_sub_prov_alm=$(printf '%s\n' "$submenu_prov_alm" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_prov_alm" -ne 6 ]; then
        echo "FALLO ALMACEN/Proveedores: $n_sub_prov_alm opciones en el submenu, se esperaban 6"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar proveedor" "Actualizar proveedor" "Activar/Desactivar proveedor" \
                 "Buscar proveedor" "Listar proveedores" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_prov_alm" | grep -Fq "$label"; then
            echo "FALLO ALMACEN/Proveedores: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK ALMACEN/Proveedores (6 opciones)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Categorias con permisos finos (23/10/2026): un rol con SOLO
# CATEGORIAS_VER ve Categorias en el menu principal y, adentro, solo la
# consulta mas Volver.
# ---------------------------------------------------------------------------
ROL_CAT="PRUEBA_CAT_VER"
USR_CAT="prueba_cat_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_CAT';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCA001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_CAT';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_CAT';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_CAT')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_CAT', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='CATEGORIAS_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA CAT VER','TESTCA001','PRUEBA',1000,'T-CA-001','ca-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_CAT', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCA001' AND R.NOMBRE_ROL='$ROL_CAT';
EOF

fallos_previos=$fallos
salida_cat="$TMP/out-categorias-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Categorias (con este rol es la
# primera opcion visible: el menu queda Categorias, Ver permisos y Cerrar
# sesion), 2 = Volver en un submenu de 2 opciones.
printf '\n1\n2\n' | BALBU_USER="$USR_CAT" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_cat" 2>&1
rc_cat=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_cat"; then
    echo "FALLO $ROL_CAT: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_cat" -ne 0 ]; then
    echo "FALLO $ROL_CAT: la app salio con $rc_cat"
    fail=1; fallos=$((fallos+1))
else
    principal_cat=$(sed -n '1,/=== MODULO DE CATEGORIAS ===/p' "$salida_cat")
    n_principal_cat=$(printf '%s\n' "$principal_cat" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_cat" -ne 3 ]; then
        echo "FALLO $ROL_CAT: $n_principal_cat opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Categorias" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_cat" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAT: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    submenu_cat=$(awk '/=== MODULO DE CATEGORIAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_cat")
    n_sub_cat=$(printf '%s\n' "$submenu_cat" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_cat" -ne 2 ]; then
        echo "FALLO $ROL_CAT: $n_sub_cat opciones en el submenu, se esperaban 2"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Categoria" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_cat" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAT: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Categoria" "Actualizar Categoria" "Activar/Desactivar Categoria"; do
        if printf '%s\n' "$submenu_cat" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAT: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_CAT (3 opciones en el menu principal y 2 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# ALMACEN con los 4 permisos de Categorias (23/10/2026): ve el submenu
# historico completo de 5 opciones.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_cat_alm="$TMP/out-categorias-almacen.txt"
# Entrada: Enter del "Presione Enter", 5 = Categorias (su menu queda
# Asistencia, Mis permisos, Mis vacaciones, Proveedores, Categorias, ...),
# 5 = Volver.
printf '\n5\n5\n' | BALBU_USER="prueba_r7_alm" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_cat_alm" 2>&1
rc_cat_alm=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_cat_alm"; then
    echo "FALLO ALMACEN/Categorias: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_cat_alm" -ne 0 ]; then
    echo "FALLO ALMACEN/Categorias: la app salio con $rc_cat_alm"
    fail=1; fallos=$((fallos+1))
else
    submenu_cat_alm=$(awk '/=== MODULO DE CATEGORIAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_cat_alm")
    n_sub_cat_alm=$(printf '%s\n' "$submenu_cat_alm" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_cat_alm" -ne 5 ]; then
        echo "FALLO ALMACEN/Categorias: $n_sub_cat_alm opciones en el submenu, se esperaban 5"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar Categoria" "Actualizar Categoria" \
                 "Activar/Desactivar Categoria" "Buscar Categoria" \
                 "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_cat_alm" | grep -Fq "$label"; then
            echo "FALLO ALMACEN/Categorias: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK ALMACEN/Categorias (5 opciones)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Marcas con permisos finos (23/10/2026): un rol con SOLO MARCAS_VER
# ve Marcas en el menu principal y, adentro, solo las dos consultas mas Volver.
# ---------------------------------------------------------------------------
ROL_MAR="PRUEBA_MAR_VER"
USR_MAR="prueba_mar_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_MAR';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTMA001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_MAR';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_MAR';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_MAR')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_MAR', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='MARCAS_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA MAR VER','TESTMA001','PRUEBA',1000,'T-MA-001','ma-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_MAR', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTMA001' AND R.NOMBRE_ROL='$ROL_MAR';
EOF

fallos_previos=$fallos
salida_mar="$TMP/out-marcas-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Marcas (con este rol es la primera
# opcion visible: el menu queda Marcas, Ver permisos y Cerrar sesion),
# 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_MAR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_mar" 2>&1
rc_mar=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_mar"; then
    echo "FALLO $ROL_MAR: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_mar" -ne 0 ]; then
    echo "FALLO $ROL_MAR: la app salio con $rc_mar"
    fail=1; fallos=$((fallos+1))
else
    principal_mar=$(sed -n '1,/=== MODULO DE MARCAS ===/p' "$salida_mar")
    n_principal_mar=$(printf '%s\n' "$principal_mar" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_mar" -ne 3 ]; then
        echo "FALLO $ROL_MAR: $n_principal_mar opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Marcas" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_mar" | grep -Fq "$label"; then
            echo "FALLO $ROL_MAR: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    submenu_mar=$(awk '/=== MODULO DE MARCAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_mar")
    n_sub_mar=$(printf '%s\n' "$submenu_mar" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_mar" -ne 3 ]; then
        echo "FALLO $ROL_MAR: $n_sub_mar opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Marca" "Listar Marcas" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_mar" | grep -Fq "$label"; then
            echo "FALLO $ROL_MAR: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Marca" "Actualizar Marca" "Activar/Desactivar Marca"; do
        if printf '%s\n' "$submenu_mar" | grep -Fq "$label"; then
            echo "FALLO $ROL_MAR: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_MAR (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# ALMACEN con los 4 permisos de Marcas (23/10/2026): ve el submenu historico
# completo de 6 opciones.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_mar_alm="$TMP/out-marcas-almacen.txt"
# Entrada: Enter del "Presione Enter", 6 = Marcas (su menu queda Asistencia,
# Mis permisos, Mis vacaciones, Proveedores, Categorias, Marcas, ...),
# 6 = Volver.
printf '\n6\n6\n' | BALBU_USER="prueba_r7_alm" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_mar_alm" 2>&1
rc_mar_alm=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_mar_alm"; then
    echo "FALLO ALMACEN/Marcas: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_mar_alm" -ne 0 ]; then
    echo "FALLO ALMACEN/Marcas: la app salio con $rc_mar_alm"
    fail=1; fallos=$((fallos+1))
else
    submenu_mar_alm=$(awk '/=== MODULO DE MARCAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_mar_alm")
    n_sub_mar_alm=$(printf '%s\n' "$submenu_mar_alm" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_mar_alm" -ne 6 ]; then
        echo "FALLO ALMACEN/Marcas: $n_sub_mar_alm opciones en el submenu, se esperaban 6"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar Marca" "Actualizar Marca" "Activar/Desactivar Marca" \
                 "Buscar Marca" "Listar Marcas" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_mar_alm" | grep -Fq "$label"; then
            echo "FALLO ALMACEN/Marcas: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK ALMACEN/Marcas (6 opciones)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Metodos de pago con permisos finos (23/10/2026): un rol con SOLO
# METODOS_PAGO_VER ve Metodos de pago en el menu principal y, adentro, solo las
# dos consultas mas Volver.
# ---------------------------------------------------------------------------
ROL_MET="PRUEBA_MET_VER"
USR_MET="prueba_met_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_MET';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTME001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_MET';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_MET';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_MET')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_MET', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='METODOS_PAGO_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA MET VER','TESTME001','PRUEBA',1000,'T-ME-001','me-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_MET', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTME001' AND R.NOMBRE_ROL='$ROL_MET';
EOF

fallos_previos=$fallos
salida_met="$TMP/out-metodos-pago-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Metodos de pago (con este rol es la
# primera opcion visible: el menu queda Metodos de pago, Ver permisos y Cerrar
# sesion), 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_MET" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_met" 2>&1
rc_met=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_met"; then
    echo "FALLO $ROL_MET: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_met" -ne 0 ]; then
    echo "FALLO $ROL_MET: la app salio con $rc_met"
    fail=1; fallos=$((fallos+1))
else
    principal_met=$(sed -n '1,/=== MODULO DE METODOS DE PAGO ===/p' "$salida_met")
    n_principal_met=$(printf '%s\n' "$principal_met" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_met" -ne 3 ]; then
        echo "FALLO $ROL_MET: $n_principal_met opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Metodos de pago" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_met" | grep -Fq "$label"; then
            echo "FALLO $ROL_MET: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    submenu_met=$(awk '/=== MODULO DE METODOS DE PAGO ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_met")
    n_sub_met=$(printf '%s\n' "$submenu_met" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_met" -ne 3 ]; then
        echo "FALLO $ROL_MET: $n_sub_met opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Metodo" "Listar Metodos" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_met" | grep -Fq "$label"; then
            echo "FALLO $ROL_MET: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Metodo" "Actualizar Datos" "Activar/Desactivar Metodo"; do
        if printf '%s\n' "$submenu_met" | grep -Fq "$label"; then
            echo "FALLO $ROL_MET: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_MET (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# VENDEDOR con los 4 permisos de Metodos de pago (23/10/2026): ve el submenu
# historico completo de 6 opciones.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_met_ven="$TMP/out-metodos-pago-vendedor.txt"
# Entrada: Enter del "Presione Enter", 6 = Metodos de pago (su menu queda
# Asistencia, Mis permisos, Mis vacaciones, Clientes, Productos, Metodos de
# pago, Ventas, Caja (turnos), Ver permisos y Cerrar sesion), 6 = Volver.
printf '\n6\n6\n' | BALBU_USER="prueba_r7_ven" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_met_ven" 2>&1
rc_met_ven=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_met_ven"; then
    echo "FALLO VENDEDOR/Metodos de pago: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_met_ven" -ne 0 ]; then
    echo "FALLO VENDEDOR/Metodos de pago: la app salio con $rc_met_ven"
    fail=1; fallos=$((fallos+1))
else
    submenu_met_ven=$(awk '/=== MODULO DE METODOS DE PAGO ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_met_ven")
    n_sub_met_ven=$(printf '%s\n' "$submenu_met_ven" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_met_ven" -ne 6 ]; then
        echo "FALLO VENDEDOR/Metodos de pago: $n_sub_met_ven opciones, se esperaban 6"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar Metodo" "Actualizar Datos" "Activar/Desactivar Metodo" \
                 "Buscar Metodo" "Listar Metodos" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_met_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Metodos de pago: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK VENDEDOR/Metodos de pago (6 opciones)"
    fi
fi

# ---------------------------------------------------------------------------
# VENDEDOR en Asistencia (23/10/2026): el vendedor ficha desde el item propio
# y NO ve los reportes de asistencia. Entrada: Enter del "Presione Enter",
# 1 = Asistencia, 3 = Volver (son 3 opciones).
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_ven="$TMP/out-asistencia-vendedor.txt"
printf '\n1\n3\n' | BALBU_USER="prueba_r7_ven" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_ven" 2>&1
rc_ven=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_ven"; then
    echo "FALLO VENDEDOR/Asistencia: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_ven" -ne 0 ]; then
    echo "FALLO VENDEDOR/Asistencia: la app salio con $rc_ven"
    fail=1; fallos=$((fallos+1))
else
    principal_ven=$(sed -n '1,/=== MODULO DE ASISTENCIA ===/p' "$salida_ven")
    if printf '%s\n' "$principal_ven" | grep -Fq "Empleados"; then
        echo "FALLO VENDEDOR/Asistencia: el menu principal sigue mostrando Empleados"
        fail=1; fallos=$((fallos+1))
    fi
    if ! printf '%s\n' "$principal_ven" | grep -Fq "Asistencia"; then
        echo "FALLO VENDEDOR/Asistencia: el menu principal no muestra Asistencia"
        fail=1; fallos=$((fallos+1))
    fi

    submenu_ven=$(awk '/=== MODULO DE ASISTENCIA ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_ven")
    n_sub_ven=$(printf '%s\n' "$submenu_ven" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_ven" -ne 3 ]; then
        echo "FALLO VENDEDOR/Asistencia: $n_sub_ven opciones, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Marcar entrada/salida" "Mi asistencia" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Asistencia: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Ver asistencia" "Asistencia del dia" "Historial de asistencia" "Justificar asistencia"; do
        if printf '%s\n' "$submenu_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Asistencia: muestra '$label' sin CONSULTAR_ASISTENCIA"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK VENDEDOR/Asistencia (3 opciones, sin reportes)"
    fi
fi

# ---------------------------------------------------------------------------
# SUBGERENTE en Empleados (23/10/2026): conserva el item con EMPLEADOS_VER.
# Entrada: Enter del "Presione Enter", 2 = Empleados (su menu queda Asistencia,
# Empleados, ...), 3 = Volver en un submenu de 3 opciones.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_sub_emp="$TMP/out-empleados-subgerente.txt"
printf '\n2\n3\n' | BALBU_USER="prueba_r7_sub" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_sub_emp" 2>&1
rc_sub_emp=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_sub_emp"; then
    echo "FALLO SUBGERENTE/Empleados: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_sub_emp" -ne 0 ]; then
    echo "FALLO SUBGERENTE/Empleados: la app salio con $rc_sub_emp"
    fail=1; fallos=$((fallos+1))
else
    submenu_sub_emp=$(awk '/=== MODULO DE EMPLEADOS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_sub_emp")
    n_sub_sub_emp=$(printf '%s\n' "$submenu_sub_emp" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_sub_emp" -ne 3 ]; then
        echo "FALLO SUBGERENTE/Empleados: $n_sub_sub_emp opciones, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Empleado" "Listar Empleados" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_sub_emp" | grep -Fq "$label"; then
            echo "FALLO SUBGERENTE/Empleados: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Empleado" "Actualizar Datos" "Despedir Empleado" \
                 "Reactivar Empleado" "Marcar entrada/salida" "Generar contrato"; do
        if printf '%s\n' "$submenu_sub_emp" | grep -Fq "$label"; then
            echo "FALLO SUBGERENTE/Empleados: muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK SUBGERENTE/Empleados (3 opciones, solo lectura)"
    fi
fi

# ---------------------------------------------------------------------------
# SUBGERENTE en Asistencia (23/10/2026): tiene las 7 opciones, incluida
# Justificar. Entrada: Enter, 1 = Asistencia, 7 = Volver.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_sub_asi="$TMP/out-asistencia-subgerente.txt"
printf '\n1\n7\n' | BALBU_USER="prueba_r7_sub" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_sub_asi" 2>&1
rc_sub_asi=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_sub_asi"; then
    echo "FALLO SUBGERENTE/Asistencia: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_sub_asi" -ne 0 ]; then
    echo "FALLO SUBGERENTE/Asistencia: la app salio con $rc_sub_asi"
    fail=1; fallos=$((fallos+1))
else
    submenu_sub_asi=$(awk '/=== MODULO DE ASISTENCIA ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_sub_asi")
    n_sub_sub_asi=$(printf '%s\n' "$submenu_sub_asi" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_sub_asi" -ne 7 ]; then
        echo "FALLO SUBGERENTE/Asistencia: $n_sub_sub_asi opciones, se esperaban 7"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Marcar entrada/salida" "Mi asistencia" "Ver asistencia" \
                 "Asistencia del dia" "Historial de asistencia" \
                 "Justificar asistencia" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_sub_asi" | grep -Fq "$label"; then
            echo "FALLO SUBGERENTE/Asistencia: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK SUBGERENTE/Asistencia (7 opciones, con Justificar)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Productos con permisos finos (22/10/2026): dos cortes con los dos
# permisos que ya existen. CONTABILIDAD solo tiene CONSULTAR_PRODUCTOS y antes
# veia igual el alta, la baja y la actualizacion; un rol con solo
# GESTIONAR_PRODUCTOS tiene que ver el caso inverso.
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_prod_con="$TMP/out-productos-contabilidad.txt"
# Entrada: Enter del "Presione Enter", 3 = Productos (su menu queda Asistencia,
# Clientes, Productos, Ver permisos y Cerrar sesion), 4 = Volver en un submenu de 4.
printf '\n3\n4\n' | BALBU_USER="prueba_r7_con" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_prod_con" 2>&1
rc_prod_con=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_prod_con"; then
    echo "FALLO CONTABILIDAD/Productos: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_prod_con" -ne 0 ]; then
    echo "FALLO CONTABILIDAD/Productos: la app salio con $rc_prod_con"
    fail=1; fallos=$((fallos+1))
else
    submenu_prod_con=$(awk '/=== MODULO DE PRODUCTOS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_prod_con")
    n_sub_prod_con=$(printf '%s\n' "$submenu_prod_con" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_prod_con" -ne 4 ]; then
        echo "FALLO CONTABILIDAD/Productos: $n_sub_prod_con opciones en el submenu, se esperaban 4"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Buscar Producto" "Consultar Inventario" "Reporte De Stock" "Volver Al Menu Principal"; do
        if ! printf '%s\n' "$submenu_prod_con" | grep -Fq "$label"; then
            echo "FALLO CONTABILIDAD/Productos: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Productos" "Actualizar Datos" "Activar/Desactivar Producto"; do
        if printf '%s\n' "$submenu_prod_con" | grep -Fq "$label"; then
            echo "FALLO CONTABILIDAD/Productos: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK CONTABILIDAD/Productos (4 opciones, solo consulta)"
    fi
fi

ROL_PROD="PRUEBA_PROD_GEST"
USR_PROD="prueba_prod_gest"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_PROD';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTPG001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_PROD';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_PROD')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_PROD', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='GESTIONAR_PRODUCTOS';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA PROD GEST','TESTPG001','PRUEBA',1000,'T-PG-001','pg-001@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_PROD', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTPG001' AND R.NOMBRE_ROL='$ROL_PROD';
EOF

fallos_previos=$fallos
salida_prod_gest="$TMP/out-productos-gest.txt"
# Entrada: Enter del "Presione Enter", 1 = Productos (unico modulo visible),
# 4 = Volver en un submenu de 4.
printf '\n1\n4\n' | BALBU_USER="$USR_PROD" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_prod_gest" 2>&1
rc_prod_gest=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_prod_gest"; then
    echo "FALLO $ROL_PROD: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_prod_gest" -ne 0 ]; then
    echo "FALLO $ROL_PROD: la app salio con $rc_prod_gest"
    fail=1; fallos=$((fallos+1))
else
    submenu_prod_gest=$(awk '/=== MODULO DE PRODUCTOS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_prod_gest")
    n_sub_prod_gest=$(printf '%s\n' "$submenu_prod_gest" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_prod_gest" -ne 4 ]; then
        echo "FALLO $ROL_PROD: $n_sub_prod_gest opciones en el submenu, se esperaban 4"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar Productos" "Actualizar Datos" "Activar/Desactivar Producto" "Volver Al Menu Principal"; do
        if ! printf '%s\n' "$submenu_prod_gest" | grep -Fq "$label"; then
            echo "FALLO $ROL_PROD: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Buscar Producto" "Consultar Inventario" "Reporte De Stock"; do
        if printf '%s\n' "$submenu_prod_gest" | grep -Fq "$label"; then
            echo "FALLO $ROL_PROD: el submenu muestra '$label' sin CONSULTAR_PRODUCTOS"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_PROD (4 opciones, solo gestion)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Ventas con permisos finos (22/10/2026): un rol con solo
# GESTIONAR_VENTAS ve las acciones sobre ventas pero no los reportes, que piden
# CONSULTAR_REPORTES. Hoy ningun rol real tiene uno sin el otro, por eso el caso
# usa un rol sintetico: asi el corte queda fijado igual.
# ---------------------------------------------------------------------------
ROL_VEN="PRUEBA_VEN_GEST"
USR_VEN="prueba_ven_gest"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_VEN';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTVG001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_VEN';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_VEN')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_VEN', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='GESTIONAR_VENTAS';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA VEN GEST','TESTVG001','PRUEBA',1000,'T-VG-001','vg-001@test.local','2026-10-22');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_VEN', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTVG001' AND R.NOMBRE_ROL='$ROL_VEN';
EOF

fallos_previos=$fallos
salida_ven_gest="$TMP/out-ventas-gest.txt"
# Entrada: Enter del "Presione Enter", 1 = Ventas (su menu queda Ventas,
# Ver permisos y Cerrar sesion: Caja ya no cuelga de GESTIONAR_VENTAS),
# 9 = Volver en un submenu de 9.
printf '\n1\n9\n' | BALBU_USER="$USR_VEN" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_ven_gest" 2>&1
rc_ven_gest=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_ven_gest"; then
    echo "FALLO $ROL_VEN: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_ven_gest" -ne 0 ]; then
    echo "FALLO $ROL_VEN: la app salio con $rc_ven_gest"
    fail=1; fallos=$((fallos+1))
else
    submenu_ven_gest=$(awk '/=== MODULO DE VENTAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_ven_gest")
    n_sub_ven_gest=$(printf '%s\n' "$submenu_ven_gest" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_ven_gest" -ne 9 ]; then
        echo "FALLO $ROL_VEN: $n_sub_ven_gest opciones en el submenu, se esperaban 9"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Venta rapida (carrito)" "Ver venta con IVA" "Cancelar venta" \
                 "Anular pago" "Devolucion de venta" "Cierre de caja" "Cobrar venta" \
                 "Garantias" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_ven_gest" | grep -Fq "$label"; then
            echo "FALLO $ROL_VEN: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Reporte por rango" "Ganancias" "Reporte por periodo" \
                 "Ganancias por periodo" "Historial de venta" "Exportar datos para la web"; do
        if printf '%s\n' "$submenu_ven_gest" | grep -Fq "$label"; then
            echo "FALLO $ROL_VEN: el submenu muestra '$label' sin CONSULTAR_REPORTES"
            fail=1; fallos=$((fallos+1))
        fi
    done

    # Caja ya no cuelga de GESTIONAR_VENTAS: este rol no debe ver el item.
    principal_ven_gest=$(sed -n '1,/=== MODULO DE VENTAS ===/p' "$salida_ven_gest")
    n_principal_ven_gest=$(printf '%s\n' "$principal_ven_gest" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_ven_gest" -ne 3 ]; then
        echo "FALLO $ROL_VEN: $n_principal_ven_gest opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    if printf '%s\n' "$principal_ven_gest" | grep -Fq "Caja (turnos)"; then
        echo "FALLO $ROL_VEN: ve Caja sin permisos de caja"
        fail=1; fallos=$((fallos+1))
    fi

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_VEN (9 opciones, sin reportes)"
    fi
fi

# ---------------------------------------------------------------------------
# Los dos permisos juntos (22/10/2026): el corte tiene que mostrar el submenu
# historico completo. Sin este caso, un typo en el permiso de una opcion de
# consulta la esconde para todos y los tests de arriba igual pasan (un rol que
# solo gestiona ya espera no verla).
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_prod_alm="$TMP/out-productos-almacen.txt"
# Entrada: Enter del "Presione Enter", 7 = Productos (su menu queda Asistencia,
# Mis permisos, Mis vacaciones, Proveedores, Categorias, Marcas, Productos,
# Compras, Inventario, Ver permisos y Cerrar sesion), 7 = Volver.
printf '\n7\n7\n' | BALBU_USER="prueba_r7_alm" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_prod_alm" 2>&1
rc_prod_alm=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_prod_alm"; then
    echo "FALLO ALMACEN/Productos: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_prod_alm" -ne 0 ]; then
    echo "FALLO ALMACEN/Productos: la app salio con $rc_prod_alm"
    fail=1; fallos=$((fallos+1))
else
    submenu_prod_alm=$(awk '/=== MODULO DE PRODUCTOS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_prod_alm")
    n_sub_prod_alm=$(printf '%s\n' "$submenu_prod_alm" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_prod_alm" -ne 7 ]; then
        echo "FALLO ALMACEN/Productos: $n_sub_prod_alm opciones, se esperaban 7"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Agregar Productos" "Actualizar Datos" "Activar/Desactivar Producto" \
                 "Buscar Producto" "Consultar Inventario" "Reporte De Stock" \
                 "Volver Al Menu Principal"; do
        if ! printf '%s\n' "$submenu_prod_alm" | grep -Fq "$label"; then
            echo "FALLO ALMACEN/Productos: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK ALMACEN/Productos (7 opciones, gestion y consulta)"
    fi
fi

fallos_previos=$fallos
salida_ven_ven="$TMP/out-ventas-vendedor.txt"
# (23/10/2026) VENDEDOR perdio CONSULTAR_REPORTES y gano
# CONSULTAR_HISTORIAL_VENTA: ve las 7 acciones de gestion, el historial,
# Garantias y Volver. Entrada: Enter del "Presione Enter", 7 = Ventas (su menu
# queda Asistencia, Mis permisos, Mis vacaciones, Clientes, Productos, Metodos
# de pago, Ventas, Caja (turnos), Ver permisos y Cerrar sesion), 10 = Volver en
# el submenu filtrado.
printf '\n7\n10\n' | BALBU_USER="prueba_r7_ven" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_ven_ven" 2>&1
rc_ven_ven=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_ven_ven"; then
    echo "FALLO VENDEDOR/Ventas: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_ven_ven" -ne 0 ]; then
    echo "FALLO VENDEDOR/Ventas: la app salio con $rc_ven_ven"
    fail=1; fallos=$((fallos+1))
else
    submenu_ven_ven=$(awk '/=== MODULO DE VENTAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_ven_ven")
    n_sub_ven_ven=$(printf '%s\n' "$submenu_ven_ven" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_ven_ven" -ne 10 ]; then
        echo "FALLO VENDEDOR/Ventas: $n_sub_ven_ven opciones, se esperaban 10"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Venta rapida (carrito)" "Ver venta con IVA" "Cancelar venta" \
                 "Anular pago" "Devolucion de venta" "Cierre de caja" \
                 "Cobrar venta" "Historial de venta" "Garantias" \
                 "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_ven_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Ventas: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Reporte por rango" "Ganancias" "Reporte por periodo" \
                 "Ganancias por periodo" "Exportar datos para la web"; do
        if printf '%s\n' "$submenu_ven_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Ventas: el submenu muestra '$label' sin CONSULTAR_REPORTES"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK VENDEDOR/Ventas (10 opciones, sin reportes)"
    fi
fi

# ---------------------------------------------------------------------------
# Opcion 0 (22/10/2026): tiene que caer en "Opcion no valida" como cualquier
# numero fuera de rango, igual que el menu principal. Antes el submenu volvia
# atras en silencio y parecia que la app se habia saltado un paso.
# ---------------------------------------------------------------------------
for caso in "$USR_PROD:4" "$USR_VEN:9"; do
    usuario="${caso%%:*}"
    volver="${caso##*:}"
    fallos_previos=$fallos
    salida_cero="$TMP/out-cero-$usuario.txt"
    printf '\n1\n0\n%s\n' "$volver" | BALBU_USER="$usuario" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
        timeout "$LIMITE" "$APP" >"$salida_cero" 2>&1

    if ! grep -q "Acceso concedido \[DEV\]" "$salida_cero"; then
        echo "FALLO $usuario/opcion 0: no entro al menu (¿usuario/clave/BD?)"
        fail=1; fallos=$((fallos+1))
    else
        if ! grep -q "Opcion no valida" "$salida_cero"; then
            echo "FALLO $usuario/opcion 0: no mostro 'Opcion no valida'"
            fail=1; fallos=$((fallos+1))
        fi
        # El submenu tiene que reimprimirse despues del 0 y seguir vivo.
        repeticiones=$(grep -cE '^=== MODULO DE (PRODUCTOS|VENTAS) ===$' "$salida_cero" || true)
        if [ "$repeticiones" -lt 2 ]; then
            echo "FALLO $usuario/opcion 0: el 0 corto el submenu ($repeticiones menu(s))"
            fail=1; fallos=$((fallos+1))
        fi

        if [ "$fallos" -eq "$fallos_previos" ]; then
            echo "OK $usuario/opcion 0 (avisa y sigue en el submenu)"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Asistencia como item propio (23/10/2026): un rol con SOLO
# CONSULTAR_ASISTENCIA tiene que ver el item Asistencia en el menu principal.
# Antes el item se abria solo con REGISTRAR_ASISTENCIA, asi que ese permiso
# quedaba inerte (R3-1 de la review del 23/10).
# ---------------------------------------------------------------------------
ROL_ASI="PRUEBA_ASI_VER"
USR_ASI="prueba_asi_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_ASI';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTAV001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_ASI';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_ASI';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_ASI')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_ASI', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='CONSULTAR_ASISTENCIA';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA ASI VER','TESTAV001','PRUEBA',1000,'T-AV-001','av-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_ASI', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTAV001' AND R.NOMBRE_ROL='$ROL_ASI';
EOF

fallos_previos=$fallos
salida_asi="$TMP/out-asistencia-ver.txt"
printf '\n0\n' | BALBU_USER="$USR_ASI" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_asi" 2>&1
rc_asi=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_asi"; then
    echo "FALLO $ROL_ASI: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_asi" -ne 0 ]; then
    echo "FALLO $ROL_ASI: la app salio con $rc_asi"
    fail=1; fallos=$((fallos+1))
else
    n_asi=$(grep -c '^[0-9]\+\. ' "$salida_asi" || true)
    if [ "$n_asi" -ne 3 ]; then
        echo "FALLO $ROL_ASI: $n_asi opciones, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Asistencia" "Ver permisos" "Cerrar sesión"; do
        if ! grep -Fq "$label" "$salida_asi"; then
            echo "FALLO $ROL_ASI: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    if grep -Fq "Empleados" "$salida_asi"; then
        echo "FALLO $ROL_ASI: muestra Empleados sin EMPLEADOS_VER"
        fail=1; fallos=$((fallos+1))
    fi
    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_ASI (CONSULTAR_ASISTENCIA abre Asistencia sin REGISTRAR_ASISTENCIA)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Compras con permisos finos (23/10/2026): un rol con SOLO COMPRAS_VER
# ve Compras en el menu principal y, adentro, solo "Ver compra con IVA" mas
# Volver. No debe ver ninguna accion de registro, pago, devolucion ni reporte.
# ---------------------------------------------------------------------------
ROL_COM="PRUEBA_COM_VER"
USR_COM="prueba_com_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_COM';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCO001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_COM';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_COM';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_COM')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_COM', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='COMPRAS_VER';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA COM VER','TESTCO001','PRUEBA',1000,'T-CO-001','co-001@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_COM', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCO001' AND R.NOMBRE_ROL='$ROL_COM';
EOF

fallos_previos=$fallos
salida_com="$TMP/out-compras-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Compras (con este rol es la primera
# opcion visible: el menu queda Compras, Ver permisos y Cerrar sesion),
# 2 = Volver en un submenu de 2 opciones.
printf '\n1\n2\n' | BALBU_USER="$USR_COM" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_com" 2>&1
rc_com=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_com"; then
    echo "FALLO $ROL_COM: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_com" -ne 0 ]; then
    echo "FALLO $ROL_COM: la app salio con $rc_com"
    fail=1; fallos=$((fallos+1))
else
    principal_com=$(sed -n '1,/=== MODULO DE COMPRAS ===/p' "$salida_com")
    n_principal_com=$(printf '%s\n' "$principal_com" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_com" -ne 3 ]; then
        echo "FALLO $ROL_COM: $n_principal_com opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Compras" "Ver permisos" "Cerrar sesión"; do
        if ! printf '%s\n' "$principal_com" | grep -Fq "$label"; then
            echo "FALLO $ROL_COM: el menu principal no muestra '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done

    submenu_com=$(awk '/=== MODULO DE COMPRAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_com")
    n_sub_com=$(printf '%s\n' "$submenu_com" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_com" -ne 2 ]; then
        echo "FALLO $ROL_COM: $n_sub_com opciones en el submenu, se esperaban 2"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Ver compra con IVA" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_com" | grep -Fq "$label"; then
            echo "FALLO $ROL_COM: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Compra rapida (carrito)" "Devolucion de compra" \
                 "Reporte por periodo" "Pagar compra" "Precios por suplidor" \
                 "Cancelar compra"; do
        if printf '%s\n' "$submenu_com" | grep -Fq "$label"; then
            echo "FALLO $ROL_COM: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_COM (3 opciones en el menu principal y 2 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Compras: un rol con COMPRAS_REGISTRAR y COMPRAS_PAGAR ve solo esas
# dos acciones mas Volver. Fija que registrar y pagar son permisos separados.
# ---------------------------------------------------------------------------
ROL_COM_RP="PRUEBA_COM_REG_PAG"
USR_COM_RP="prueba_com_reg_pag"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_COM_RP';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCO002';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_COM_RP';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_COM_RP';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_COM_RP')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_COM_RP', ID_PERMISO FROM PERMISOS
 WHERE NOMBRE_PERMISO IN ('COMPRAS_REGISTRAR', 'COMPRAS_PAGAR');
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA COM REG PAG','TESTCO002','PRUEBA',1000,'T-CO-002','co-002@test.local','2026-10-23');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_COM_RP', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCO002' AND R.NOMBRE_ROL='$ROL_COM_RP';
EOF

fallos_previos=$fallos
salida_com_rp="$TMP/out-compras-reg-pag.txt"
# Entrada: Enter del "Presione Enter", 1 = Compras (con este rol es la primera
# opcion visible: el menu queda Compras, Ver permisos y Cerrar sesion),
# 3 = Volver en un submenu de 3 opciones.
printf '\n1\n3\n' | BALBU_USER="$USR_COM_RP" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_com_rp" 2>&1
rc_com_rp=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_com_rp"; then
    echo "FALLO $ROL_COM_RP: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_com_rp" -ne 0 ]; then
    echo "FALLO $ROL_COM_RP: la app salio con $rc_com_rp"
    fail=1; fallos=$((fallos+1))
else
    principal_com_rp=$(sed -n '1,/=== MODULO DE COMPRAS ===/p' "$salida_com_rp")
    n_principal_com_rp=$(printf '%s\n' "$principal_com_rp" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_principal_com_rp" -ne 3 ]; then
        echo "FALLO $ROL_COM_RP: $n_principal_com_rp opciones en el menu principal, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi

    submenu_com_rp=$(awk '/=== MODULO DE COMPRAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_com_rp")
    n_sub_com_rp=$(printf '%s\n' "$submenu_com_rp" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_com_rp" -ne 3 ]; then
        echo "FALLO $ROL_COM_RP: $n_sub_com_rp opciones en el submenu, se esperaban 3"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Compra rapida (carrito)" "Pagar compra" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_com_rp" | grep -Fq "$label"; then
            echo "FALLO $ROL_COM_RP: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Ver compra con IVA" "Devolucion de compra" "Reporte por periodo" \
                 "Precios por suplidor" "Cancelar compra"; do
        if printf '%s\n' "$submenu_com_rp" | grep -Fq "$label"; then
            echo "FALLO $ROL_COM_RP: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_COM_RP (3 opciones en el menu principal y 3 en el submenu)"
    fi
fi

# ---------------------------------------------------------------------------
# ALMACEN con los 6 permisos de Compras (23/10/2026): ve el submenu historico
# completo de 8 opciones (las 7 acciones mas Volver).
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_com_alm="$TMP/out-compras-almacen.txt"
# Entrada: Enter del "Presione Enter", 8 = Compras (su menu queda Asistencia,
# Mis permisos, Mis vacaciones, Proveedores, Categorias, Marcas, Productos,
# Compras, Inventario, Ver permisos y Cerrar sesion), 8 = Volver.
printf '\n8\n8\n' | BALBU_USER="prueba_r7_alm" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_com_alm" 2>&1
rc_com_alm=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_com_alm"; then
    echo "FALLO ALMACEN/Compras: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_com_alm" -ne 0 ]; then
    echo "FALLO ALMACEN/Compras: la app salio con $rc_com_alm"
    fail=1; fallos=$((fallos+1))
else
    submenu_com_alm=$(awk '/=== MODULO DE COMPRAS ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_com_alm")
    n_sub_com_alm=$(printf '%s\n' "$submenu_com_alm" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_com_alm" -ne 8 ]; then
        echo "FALLO ALMACEN/Compras: $n_sub_com_alm opciones en el submenu, se esperaban 8"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Compra rapida (carrito)" "Ver compra con IVA" \
                 "Devolucion de compra" "Reporte por periodo" "Pagar compra" \
                 "Precios por suplidor" "Cancelar compra" \
                 "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_com_alm" | grep -Fq "$label"; then
            echo "FALLO ALMACEN/Compras: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK ALMACEN/Compras (8 opciones)"
    fi
fi

# ---------------------------------------------------------------------------
# Submenu Caja (24/10/2026): abrir, consultar y cerrar el turno tienen permisos
# separados. Un rol con solo CONSULTAR_CAJA ve el estado y nada mas.
# ---------------------------------------------------------------------------
ROL_CAJA_VER="PRUEBA_CAJA_VER"
USR_CAJA_VER="prueba_caja_ver"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_CAJA_VER';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCJ001';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_CAJA_VER';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_CAJA_VER';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_CAJA_VER')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_CAJA_VER', ID_PERMISO FROM PERMISOS
 WHERE NOMBRE_PERMISO='CONSULTAR_CAJA';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA CAJA VER','TESTCJ001','PRUEBA',1000,'T-CJ-001','cj-001@test.local','2026-10-24');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_CAJA_VER', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCJ001' AND R.NOMBRE_ROL='$ROL_CAJA_VER';
EOF

fallos_previos=$fallos
salida_caja_ver="$TMP/out-caja-ver.txt"
# Entrada: Enter del "Presione Enter", 1 = Caja (unico item del menu principal
# ademas de Ver permisos y Cerrar sesion), 2 = Volver en un submenu de 2.
printf '\n1\n2\n' | BALBU_USER="$USR_CAJA_VER" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_caja_ver" 2>&1
rc_caja_ver=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_caja_ver"; then
    echo "FALLO $ROL_CAJA_VER: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_caja_ver" -ne 0 ]; then
    echo "FALLO $ROL_CAJA_VER: la app salio con $rc_caja_ver"
    fail=1; fallos=$((fallos+1))
else
    submenu_caja_ver=$(awk '/=== MODULO DE CAJA ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_caja_ver")
    n_sub_caja_ver=$(printf '%s\n' "$submenu_caja_ver" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_caja_ver" -ne 2 ]; then
        echo "FALLO $ROL_CAJA_VER: $n_sub_caja_ver opciones en el submenu, se esperaban 2"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Estado de la caja" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_caja_ver" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAJA_VER: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Abrir caja" "Cerrar caja (cuadre)"; do
        if printf '%s\n' "$submenu_caja_ver" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAJA_VER: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_CAJA_VER (2 opciones, solo consulta)"
    fi
fi

# ---------------------------------------------------------------------------
# Los tres permisos de Caja juntos: el submenu historico completo. Sin este
# caso, un typo en ABRIR_CAJA o CERRAR_CAJA esconde la opcion para todos.
# ---------------------------------------------------------------------------
ROL_CAJA_GEST="PRUEBA_CAJA_GEST"
USR_CAJA_GEST="prueba_caja_gest"

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
DELETE FROM USUARIOS WHERE USUARIO='$USR_CAJA_GEST';
DELETE FROM EMPLEADOS WHERE CEDULA='TESTCJ002';
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL_CAJA_GEST';
DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL_CAJA_GEST';
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL_CAJA_GEST')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL_CAJA_GEST', ID_PERMISO FROM PERMISOS
 WHERE NOMBRE_PERMISO IN ('CONSULTAR_CAJA', 'ABRIR_CAJA', 'CERRAR_CAJA');
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA CAJA GEST','TESTCJ002','PRUEBA',1000,'T-CJ-002','cj-002@test.local','2026-10-24');
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR_CAJA_GEST', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='TESTCJ002' AND R.NOMBRE_ROL='$ROL_CAJA_GEST';
EOF

fallos_previos=$fallos
salida_caja_gest="$TMP/out-caja-gest.txt"
# Entrada: Enter del "Presione Enter", 1 = Caja, 4 = Volver en un submenu de 4.
printf '\n1\n4\n' | BALBU_USER="$USR_CAJA_GEST" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_caja_gest" 2>&1
rc_caja_gest=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_caja_gest"; then
    echo "FALLO $ROL_CAJA_GEST: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_caja_gest" -ne 0 ]; then
    echo "FALLO $ROL_CAJA_GEST: la app salio con $rc_caja_gest"
    fail=1; fallos=$((fallos+1))
else
    submenu_caja_gest=$(awk '/=== MODULO DE CAJA ===/{f=1} f{print} /^=+$/ && f{exit}' "$salida_caja_gest")
    n_sub_caja_gest=$(printf '%s\n' "$submenu_caja_gest" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_caja_gest" -ne 4 ]; then
        echo "FALLO $ROL_CAJA_GEST: $n_sub_caja_gest opciones en el submenu, se esperaban 4"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Abrir caja" "Estado de la caja" "Cerrar caja (cuadre)" \
                 "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_caja_gest" | grep -Fq "$label"; then
            echo "FALLO $ROL_CAJA_GEST: falta la opcion '$label' en el submenu"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK $ROL_CAJA_GEST (4 opciones, submenu completo)"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DE MENUS POR ROL OK"
else
    echo "TESTS DE MENUS POR ROL: FALLAS ARRIBA"
fi
exit "$fail"
