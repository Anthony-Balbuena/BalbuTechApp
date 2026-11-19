#!/usr/bin/env bash
# (18/11/2026) Test de la pantalla de bonos (modulo 14).
#
# POR QUE EXISTE: db/test-bonos.sh prueba los SP en SQL puro. Esto prueba lo que
# ese test no puede ver: que la pantalla llame al SP con los argumentos en el
# orden correcto (estado, pagina, porPagina), que el listado paginado funcione y
# que el alta por la interfaz llegue al SP con lo que se tipeo.
#
# Corre contra BALBU_TECH_TEST con el login DEV. Crea un rol, un empleado y un
# usuario de prueba, y los borra al salir (junto con el bono que registra).
#
# Uso dentro del contenedor app:
#   BALBU_ALLOW_DEV_LOGIN=1 BALBU_PASS=<clave del admin> \
#   DB_NAME=BALBU_TECH_TEST bash db/test-bonos-pantalla.sh
set -u
export BALBU_ALLOW_DEV_LOGIN=1

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-BALBU_TECH_TEST}"
DB_USER="${DB_ADMIN_USER:-balbu_admin}"
DB_PASSWORD="${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD (revisar .env)}"
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

ROL="PRUEBA_BONO_PANT"
USR="prueba_bono_pant"
CEDULA="TESTBP001"
DESCRIPCION="ZZ pantalla bono"
DESCRIPCION_PAGO="ZZ pantalla pagar"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bonos-pant.XXXXXX")"
borrar_filas() {
    # Orden por FKs, igual que en test-menus-por-rol.sh. Los bonos del test se
    # borran por descripcion: son los unicos que crea este script.
    Q "DELETE FROM BONOS_EMPLEADOS WHERE DESCRIPCION LIKE 'ZZ pantalla%';
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

# Limpieza por si una corrida anterior murio sin trap.
borrar_filas

mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" <<EOF
INSERT INTO ROLES (NOMBRE_ROL) VALUES ('$ROL')
    ON DUPLICATE KEY UPDATE NOMBRE_ROL = NOMBRE_ROL;
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT '$ROL', ID_PERMISO FROM PERMISOS WHERE NOMBRE_PERMISO='GESTIONAR_BONOS_EMPLEADO';
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('PRUEBA BONO PANT','$CEDULA','PRUEBA',1000,'T-BP-001','bp-001@test.local',CURDATE());
INSERT INTO USUARIOS (USUARIO, CONTRASENA, ID_EMPLEADO, ID_ROL)
SELECT '$USR', '$HASH', E.ID_EMPLEADO, R.ID_ROL
  FROM EMPLEADOS E, ROLES R
 WHERE E.CEDULA='$CEDULA' AND R.NOMBRE_ROL='$ROL';
EOF

ID_EMP=$(Q "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CEDULA'")
if [ -z "$ID_EMP" ]; then
    echo "FALLO: no se creo el empleado de prueba." >&2
    exit 1
fi
HOY=$(date +%F)

# El bono que la pantalla tiene que PAGAR se crea por SQL para conocer su ID de
# antemano: la entrada de la app se arma antes de correrla. El alta en si se
# prueba despues, pero por la interfaz.
Q "INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
   VALUES ($ID_EMP, '$HOY', 'HORAS_EXTRA', 800.00, '$DESCRIPCION_PAGO');"
ID_PAGO=$(Q "SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION='$DESCRIPCION_PAGO'")
if [ -z "$ID_PAGO" ] || [ "$ID_PAGO" = "NULL" ]; then
    echo "FALLO: no se pudo crear el bono a pagar." >&2
    exit 1
fi

# Entrada: Enter del "Presione Enter"; 1 = Empleados (unica opcion ademas de
# Cerrar sesion); 1 = Gestionar bonos; Enter = elegir en el paginador;
# 1 = Pagar bono + el ID; Enter = la pausa; Enter = elegir otra vez en el
# paginador que redibujo la lista; 3 = Registrar bono; ID del empleado;
# 3 = BONIFICACION; monto; fecha; descripcion; Enter = la pausa posterior.
# Despues de eso, EOF cierra la app.
SALIDA="$TMP/out.txt"
printf '\n1\n1\n\n1\n%s\n\n\n3\n%s\n3\n1234.50\n%s\n%s\n\n' \
        "$ID_PAGO" "$ID_EMP" "$HOY" "$DESCRIPCION" \
    | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
      timeout "$LIMITE" "$APP" >"$SALIDA" 2>&1
rc=$?

fallos=0
rojo() { echo "FALLO $1"; fallos=$((fallos + 1)); }

if ! grep -q "Acceso concedido \[DEV\]" "$SALIDA"; then
    rojo "no entro al menu (¿usuario/clave/BD?)"
elif [ "$rc" -ne 0 ]; then
    rojo "la app salio con $rc"
else
    # 1. La pantalla abrio en el estado por defecto.
    if ! grep -Fq "=== BONOS DE EMPLEADOS (PENDIENTE) ===" "$SALIDA"; then
        rojo "la pantalla no abrio filtrada por PENDIENTE"
    fi

    # 2. El listado paginado contesto: si el SP se llamara con los argumentos
    #    en otro orden, esto falla con error de SQL y no hay tabla.
    if ! grep -Fq "Pagina 1 de" "$SALIDA"; then
        rojo "el listado paginado no dibujo su pie de pagina"
    fi
    if ! grep -Eq '^ *ID *\| *EMPLEADO' "$SALIDA"; then
        rojo "el listado no dibujo la cabecera de la tabla"
    fi

    # 3. El pago por la interfaz devolvio el mensaje del SP y dejo el bono
    #    PAGADO. Es el tramo que el test de SQL no puede ver: si la pantalla
    #    llamara al SP equivocado (anular en vez de pagar), aca se nota.
    if ! grep -Fq "EXITO: EL BONO CON ID $ID_PAGO HA SIDO MARCADO COMO PAGADO." "$SALIDA"; then
        rojo "pagar el bono $ID_PAGO no devolvio el mensaje de exito del SP"
    fi
    estado_pago=$(Q "SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO=$ID_PAGO")
    if [ "$estado_pago" != "PAGADO" ]; then
        rojo "el bono pagado por la pantalla quedo en '$estado_pago', no PAGADO"
    fi

    # 4. El alta por la interfaz devolvio el mensaje del SP.
    if ! grep -Fq "EXITO: BONO DE \$1234.50 REGISTRADO A:" "$SALIDA"; then
        rojo "el alta no devolvio el mensaje de exito del SP"
    fi

    # 5. Y quedo en la base como PENDIENTE, con el tipo y el monto tipeados.
    estado=$(Q "SELECT ESTADO FROM BONOS_EMPLEADOS WHERE DESCRIPCION='$DESCRIPCION' ORDER BY ID_BONO DESC LIMIT 1")
    monto=$(Q "SELECT MONTO FROM BONOS_EMPLEADOS WHERE DESCRIPCION='$DESCRIPCION' ORDER BY ID_BONO DESC LIMIT 1")
    tipo=$(Q "SELECT TIPO_BONO FROM BONOS_EMPLEADOS WHERE DESCRIPCION='$DESCRIPCION' ORDER BY ID_BONO DESC LIMIT 1")
    if [ "$estado" != "PENDIENTE" ]; then
        rojo "el bono no quedo PENDIENTE (estado='$estado')"
    fi
    if [ "$monto" != "1234.50" ]; then
        rojo "el monto guardado no es 1234.50 (monto='$monto')"
    fi
    if [ "$tipo" != "BONIFICACION" ]; then
        rojo "el tipo guardado no es BONIFICACION (tipo='$tipo')"
    fi
fi

# ---------------------------------------------------------------------------
# Paginador con MAS de una pagina (18/11/2026).
#
# POR QUE: en TEST siempre habia <= 10 bonos PENDIENTE, asi que el paginador
# nunca dibujaba su prompt. En la viva hay 11 y el bug aparecio recien ahi:
# cualquier tecla que no fuera N o P redibujaba la tabla entera en silencio, y
# el operador que tipeaba el numero de una fila creia que la pantalla se habia
# colgado. Este bloque fuerza 2 paginas y verifica que (a) la tecla invalida
# avise, (b) la tabla se dibuje UNA sola vez, (c) se llegue al menu de acciones
# y (d) N pase a la pagina 2.
# ---------------------------------------------------------------------------
PAG_ESTADO=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ESTADO='PENDIENTE'")
FALTAN=$((11 - PAG_ESTADO))
if [ "$FALTAN" -gt 0 ]; then
    for i in $(seq 1 "$FALTAN"); do
        Q "INSERT INTO BONOS_EMPLEADOS (ID_EMPLEADO, FECHA, TIPO_BONO, MONTO, DESCRIPCION)
           VALUES ($ID_EMP, '$HOY', 'BONIFICACION', 1.00, 'ZZ pantalla pag $i');" >/dev/null
    done
fi
PAG_TOTAL=$(Q "SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ESTADO='PENDIENTE'")
if [ "$PAG_TOTAL" -lt 11 ]; then
    rojo "no se pudieron forzar 2 paginas (hay $PAG_TOTAL PENDIENTE)"
else
    # Entrada: Enter login; 1 Empleados; 1 Gestionar bonos; "1" en el paginador
    # (tecla invalida, el caso del operador); Enter para salir al menu;
    # 0 para volver al submenu; 0 para volver al principal.
    SALIDA_PAG="$TMP/out-pag.txt"
    printf '\n1\n1\n1\n\n0\n0\n' \
        | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
          timeout "$LIMITE" "$APP" >"$SALIDA_PAG" 2>&1
    if ! grep -q "Acceso concedido \[DEV\]" "$SALIDA_PAG"; then
        rojo "paginador: no entro al menu (¿usuario/clave/BD?)"
        sed 's/\x1b\[[0-9;]*m//g; s/^/        /' "$SALIDA_PAG" | head -15 >&2
    else
        if ! grep -Fq "Tecla no valida: N siguiente, P anterior, Enter para continuar." "$SALIDA_PAG"; then
            rojo "paginador: la tecla invalida no aviso nada (redibuja en silencio)"
        fi
        dibujos=$(grep -c "^Pagina 1 de" "$SALIDA_PAG")
        if [ "$dibujos" -ne 1 ]; then
            rojo "paginador: dibujo la pagina 1 $dibujos veces, se esperaba 1"
        fi
        if ! grep -Fq "1. Pagar bono" "$SALIDA_PAG"; then
            rojo "paginador: no se llego al menu de acciones"
        fi
        if grep -q "^Pagina 2 de" "$SALIDA_PAG"; then
            rojo "paginador: salto a la pagina 2 sin que se pidiera"
        fi
    fi

    # N tiene que avanzar a la pagina 2 y mostrar otros bonos.
    SALIDA_N="$TMP/out-pag-n.txt"
    printf '\n1\n1\nn\n\n0\n0\n' \
        | BALBU_USER="$USR" BALBU_PASS="$BALBU_PASS" DB_NAME="$DB_NAME" \
          timeout "$LIMITE" "$APP" >"$SALIDA_N" 2>&1
    if ! grep -q "^Pagina 2 de" "$SALIDA_N"; then
        rojo "paginador: N no paso a la pagina 2"
    fi
fi

echo
if [ "${VERBOSE:-0}" = "1" ]; then
    echo "--- salida de la app ---"
    sed 's/^/  /' "$SALIDA"
    echo
fi
if [ "$fallos" -eq 0 ]; then
    echo "TEST DE PANTALLA DE BONOS OK"
    exit 0
fi
echo "TEST DE PANTALLA DE BONOS: $fallos fallo(s)"
echo "--- salida de la app ---"
sed 's/^/  /' "$SALIDA"
exit 1
