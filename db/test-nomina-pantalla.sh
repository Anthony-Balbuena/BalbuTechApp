#!/usr/bin/env bash
# (18/11/2026) Test de la pantalla de nomina (modulos 8 y 14).
#
# POR QUE EXISTE: db/test-nomina.sh prueba los SP en SQL puro. Esto prueba lo que
# ese test no puede ver: que la pantalla se alcance con el permiso, que el recibo
# llegue dibujado, que la confirmacion frene, y que el pago marque en la base con
# el usuario de la sesion real (el de SQL es root, que se saltea las guardas y no
# tiene token; aca la sesion la arma el login de la app).
#
# Corre contra BALBU_TECH_TEST con el login DEV. Crea un rol, un empleado y un
# usuario de prueba, y los borra al salir junto con los bonos que registra.
#
# Uso: BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=<clave del usuario de prueba> \
#      DB_NAME=BALBU_TECH_TEST bash db/test-nomina-pantalla.sh
set -u
export BALBU_ALLOW_DEV_LOGIN=1

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-8}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
BALBU_PASS="${BALBU_PASS:?Falta BALBU_PASS (clave del usuario de prueba)}"

if [ "$DB_NAME" = "BALBU_TECH" ]; then
    echo "NO correr este test contra la base viva ($DB_NAME). Usa BALBU_TECH_TEST." >&2
    exit 2
fi

if [ ! -x "$APP" ]; then
    echo "FALTA el binario $APP: corre 'bash build.sh' primero." >&2
    exit 1
fi

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1"; }

ROL="PRUEBA_NOMINA_PANT"
USR="prueba_nomina_pant"
CEDULA="TESTNP001"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nomina-pant.XXXXXX")"
borrar_filas() {
    # Orden por FKs, igual que los otros tests de pantalla. Los bonos del test se
    # borran por descripcion: son los unicos que crea este script.
    Q "DELETE FROM BONOS_EMPLEADOS WHERE DESCRIPCION LIKE 'ZZ nomina pant%';
       DELETE FROM SESIONES WHERE ID_USUARIO IN (SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO='$USR');
       DELETE FROM USUARIOS WHERE USUARIO='$USR';
       DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE='$ROL';
       DELETE FROM ROLES WHERE NOMBRE_ROL='$ROL';
       DELETE FROM EMPLEADOS WHERE CEDULA='$CEDULA';" >/dev/null 2>&1 || true
}
limpiar() {
    borrar_filas
    rm -rf "$TMP"
}
trap limpiar EXIT

. "$(dirname "$0")/lib-clave-prueba.sh"
HASH=$(clave_pbkdf2 "$BALBU_PASS")
if [ -z "$HASH" ]; then
    echo "No se pudo derivar la clave de prueba." >&2
    exit 1
fi

borrar_filas

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='GESTIONAR_NOMINA';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('ZZ NOMINA PANT','$CEDULA','PRUEBA',10000,'T-NP-001','np-001@test.local',CURDATE());
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='$CEDULA' AND R.NOMBRE_ROL='$ROL';
EOF

ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CEDULA'")
if [ -z "$ID_EMP" ] || [ "$ID_EMP" = "NULL" ]; then
    echo "FALLO: no se creo el empleado de prueba." >&2
    exit 1
fi
HOY=$(date +%F)

# Un bono del mes anterior y otro de este, para probar el arrastre por la
# pantalla: el recibo tiene que mostrar 2 y el pago tiene que marcar los 2.
Q "INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
   VALUES ($ID_EMP, DATE_SUB('$HOY', INTERVAL 45 DAY), 'BONIFICACION', 100.00, 'ZZ nomina pant viejo'),
          ($ID_EMP, '$HOY', 'HORAS_EXTRA', 50.00, 'ZZ nomina pant nuevo');"
PEND=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO=$ID_EMP AND ESTADO='PENDIENTE'")
if [ "$PEND" != "2" ]; then
    echo "FALLO: no se crearon los 2 bonos del test (hay $PEND)." >&2
    exit 1
fi

# Si hay mas de una pagina de empleados, el paginador pide una tecla ANTES de
# pedir el ID. Se arma la entrada segun cuantos empleados haya: si se asumiera
# siempre una cosa, el test se rompe el dia que la plantilla pase de 10.
EMP_CUANTOS=$(Q "SELECT COUNT(*) FROM EMPLEADOS")
PAG=""
if [ "$EMP_CUANTOS" -gt 10 ]; then PAG="
"; fi

# Entrada: Enter del login; 1 = Empleados; 1 = Nomina (el rol solo tiene esa
# opcion ademas de Volver); [Enter del paginador]; ID del empleado;
# s = confirmar el pago; Enter de la pausa; [Enter del paginador]; 0 = volver;
# 2 = Volver al Menu Principal; 2 = Cerrar sesion.
SALIDA="$TMP/out.txt"
printf '\n1\n1\n%s%s\ns\n\n%s0\n2\n2\n' "$PAG" "$ID_EMP" "$PAG" \
    | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
      timeout "$LIMITE" "$APP" >"$SALIDA" 2>&1

fallos=0
rojo() { echo "  FALLO $1"; fallos=$((fallos + 1)); }

limpiar_color() { sed 's/\x1b\[[0-9;]*m//g' "$1"; }

if ! grep -q "Acceso concedido \[DEV\]" "$SALIDA"; then
    rojo "no entro al sistema (¿usuario/clave/BD?)"
    limpiar_color "$SALIDA" | head -15 | sed 's/^/        /' >&2
else
    # El permiso nuevo tiene que abrir el item del menu principal: si no esta en
    # la lista de roles.cpp, la pantalla existe pero nadie llega.
    if ! grep -Fq "1. Empleados" <(limpiar_color "$SALIDA"); then
        rojo "el rol con GESTIONAR_NOMINA no ve el item Empleados"
    else
        echo "  OK el permiso GESTIONAR_NOMINA abre el modulo Empleados"
    fi

    if ! grep -Fq "Nomina (recibo y pago)" <(limpiar_color "$SALIDA"); then
        rojo "el submenu no muestra la opcion de nomina"
    else
        echo "  OK el submenu muestra 'Nomina (recibo y pago)'"
    fi

    # El recibo: sueldo, descuentos, bonos y total.
    if ! grep -Fq "=== RECIBO DE NOMINA" <(limpiar_color "$SALIDA"); then
        rojo "no se dibujo el recibo"
    else
        echo "  OK el recibo se dibuja"
    fi
    if ! grep -q "Bonos (2):" <(limpiar_color "$SALIDA"); then
        rojo "el recibo no muestra los 2 bonos pendientes"
    else
        echo "  OK el recibo muestra los 2 bonos (arrastre)"
    fi
    if ! grep -q 'TOTAL A PAGAR:.*9559.00' <(limpiar_color "$SALIDA"); then
        rojo "el total a pagar no es 9559.00"
    else
        echo "  OK el total a pagar suma sueldo neto y bonos (9559.00)"
    fi
    if ! grep -Fq "ZZ nomina pant viejo" <(limpiar_color "$SALIDA"); then
        rojo "el detalle no lista el bono del mes anterior"
    else
        echo "  OK el detalle lista los bonos incluidos"
    fi

    # El pago: mensaje de exito y, sobre todo, la base.
    if ! grep -q "EXITO: SE PAGARON 2 BONO" <(limpiar_color "$SALIDA"); then
        rojo "el pago no informo los 2 bonos"
    else
        echo "  OK el pago informa los 2 bonos"
    fi
fi

# La base tiene que haber quedado marcada, con fecha y con el usuario de la
# sesion (no con root: aca la sesion la armo la app).
estado=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO=$ID_EMP AND ESTADO='PAGADO'")
fecha=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO=$ID_EMP AND FECHA_PAGO=CURDATE()")
actor=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO=$ID_EMP AND PAGADO_POR='$USR'")

if [ "$estado" != "2" ]; then
    rojo "la base no quedo con los 2 bonos PAGADO (PAGADO=$estado)"
else
    echo "  OK los 2 bonos quedaron PAGADO en la base"
fi
if [ "$fecha" != "2" ]; then
    rojo "falta FECHA_PAGO en los bonos (con fecha=$fecha)"
else
    echo "  OK los 2 bonos quedaron con FECHA_PAGO de hoy"
fi
if [ "$actor" != "2" ]; then
    rojo "PAGADO_POR no es el usuario de la sesion (coinciden=$actor)"
else
    echo "  OK el actor del pago es el usuario que lo hizo ($USR)"
fi

# ---------------------------------------------------------------------------
# La confirmacion tiene que FRENAR. Se crea un tercer bono y se responde "n":
# si se pagara igual, la pantalla estaria marcando plata sin que nadie confirme,
# que es justo lo que este diseno evita.
# ---------------------------------------------------------------------------
Q "INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
   VALUES ($ID_EMP, '$HOY', 'BONIFICACION', 25.00, 'ZZ nomina pant tercero');"

SALIDA_N="$TMP/out-n.txt"
printf '\n1\n1\n%s%s\nn\n\n%s0\n2\n2\n' "$PAG" "$ID_EMP" "$PAG" \
    | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
      timeout "$LIMITE" "$APP" >"$SALIDA_N" 2>&1

no_pagado=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS
                WHERE DESCRIPCION='ZZ nomina pant tercero' AND ESTADO='PENDIENTE'
                  AND FECHA_PAGO IS NULL AND PAGADO_POR IS NULL")
if [ "$no_pagado" != "1" ]; then
    rojo "responder 'n' pago igual el bono: la confirmacion no frena"
else
    echo "  OK responder 'n' no marca nada (la confirmacion frena)"
fi

echo
if [ "${VERBOSE:-0}" = "1" ]; then
    echo "--- salida de la app ---"
    limpiar_color "$SALIDA" | sed 's/^/  /'
    echo
fi
if [ "$fallos" -eq 0 ]; then
    echo "TEST DE PANTALLA DE NOMINA OK"
    exit 0
fi
echo "TEST DE PANTALLA DE NOMINA: $fallos fallo(s)"
echo "--- salida de la app ---"
limpiar_color "$SALIDA" | sed 's/^/  /'
exit 1
