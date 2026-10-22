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
        -e "DELETE FROM USUARIOS WHERE USUARIO LIKE 'prueba_r7_%' OR USUARIO IN ('prueba_usr_ver', 'prueba_emp_ver', 'prueba_cli_ver');
            DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE IN ('PRUEBA_USR_VER', 'PRUEBA_EMP_VER', 'PRUEBA_CLI_VER');
            DELETE FROM ROLES WHERE NOMBRE_ROL IN ('PRUEBA_USR_VER', 'PRUEBA_EMP_VER', 'PRUEBA_CLI_VER');
            DELETE FROM EMPLEADOS WHERE CEDULA LIKE 'TESTR7%' OR CEDULA IN ('TESTUV001', 'TESTEV001', 'TESTCV001');" 2>/dev/null || true
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
revisar "ADMIN" "$BALBU_USER" 18 "Roles|Usuarios|Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Accesos|Ver permisos|Cerrar sesión"
revisar "GERENTE" "prueba_r7_ger" 15 "Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "SUBGERENTE" "prueba_r7_sub" 15 "Empleados|Mis permisos|Mis vacaciones|Clientes|Proveedores|Categorias|Marcas|Productos|Metodos de pago|Ventas|Compras|Inventario|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "RRHH" "prueba_r7_rrhh" 5 "Empleados|Mis permisos|Mis vacaciones|Ver permisos|Cerrar sesión"
revisar "VENDEDOR" "prueba_r7_ven" 10 "Empleados|Mis permisos|Mis vacaciones|Clientes|Productos|Metodos de pago|Ventas|Caja (turnos)|Ver permisos|Cerrar sesión"
revisar "ALMACEN" "prueba_r7_alm" 10 "Mis permisos|Mis vacaciones|Proveedores|Categorias|Marcas|Productos|Compras|Inventario|Ver permisos|Cerrar sesión"
revisar "CONTABILIDAD" "prueba_r7_con" 4 "Clientes|Productos|Ver permisos|Cerrar sesión"

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
# Entrada: Enter del "Presione Enter", 1 = Clientes (en su menu queda primero:
# Clientes, Productos, Ver permisos y Cerrar sesion), 3 = Volver.
printf '\n1\n3\n' | BALBU_USER="prueba_r7_con" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
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
# VENDEDOR en Empleados (22/10/2026): el rol tiene REGISTRAR_ASISTENCIA, asi que
# el item "Empleados" del menu principal tambien lo acepta. Sin esa condicion el
# vendedor no podia fichar: el permiso existia y era inalcanzable.
# Entrada: Enter del "Presione Enter", 1 = Empleados, 5 = Volver (son 5 opciones).
# ---------------------------------------------------------------------------
fallos_previos=$fallos
salida_ven="$TMP/out-empleados-vendedor.txt"
printf '\n1\n5\n' | BALBU_USER="prueba_r7_ven" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
    timeout "$LIMITE" "$APP" >"$salida_ven" 2>&1
rc_ven=$?

if ! grep -q "Acceso concedido \[DEV\]" "$salida_ven"; then
    echo "FALLO VENDEDOR/Empleados: no entro al menu (¿usuario/clave/BD?)"
    fail=1; fallos=$((fallos+1))
elif [ "$rc_ven" -ne 0 ]; then
    echo "FALLO VENDEDOR/Empleados: la app salio con $rc_ven"
    fail=1; fallos=$((fallos+1))
else
    submenu_ven=$(awk '/=== MODULO DE EMPLEADOS ===/{f=1} f{print} /^=============================$/ && f{exit}' "$salida_ven")
    n_sub_ven=$(printf '%s\n' "$submenu_ven" | grep -c '^[0-9]\+\. ' || true)
    if [ "$n_sub_ven" -ne 5 ]; then
        echo "FALLO VENDEDOR/Empleados: $n_sub_ven opciones en el submenu, se esperaban 5"
        fail=1; fallos=$((fallos+1))
    fi
    for label in "Marcar asistencia" "Ver asistencia" "Asistencia del dia" \
                 "Historial de asistencia" "Volver al Menu Principal"; do
        if ! printf '%s\n' "$submenu_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Empleados: falta la opcion '$label'"
            fail=1; fallos=$((fallos+1))
        fi
    done
    for label in "Agregar Empleado" "Actualizar Datos" "Despedir Empleado" \
                 "Reactivar Empleado" "Justificar asistencia" "Generar contrato" \
                 "Gestionar permisos" "Gestionar vacaciones"; do
        if printf '%s\n' "$submenu_ven" | grep -Fq "$label"; then
            echo "FALLO VENDEDOR/Empleados: el submenu muestra '$label' sin permiso"
            fail=1; fallos=$((fallos+1))
        fi
    done

    if [ "$fallos" -eq "$fallos_previos" ]; then
        echo "OK VENDEDOR/Empleados (5 opciones, puede marcar asistencia)"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "TODOS LOS TESTS DE MENUS POR ROL OK"
else
    echo "TESTS DE MENUS POR ROL: FALLAS ARRIBA"
fi
exit "$fail"
