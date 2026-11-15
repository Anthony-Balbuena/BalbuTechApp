#!/usr/bin/env bash
# Test del historial laboral (modulo 15) — 12/11/2026.
#
# Fija el bug del cargo ancho: HISTORIAL_LABORAL_EMPLEADO.CARGO_ANTERIOR/NUEVO
# era VARCHAR(30) mientras EMPLEADOS.CARGO es VARCHAR(50). El trigger
# TR_AUDITORIA_PERFIL_EMPLEADO copia OLD.CARGO/NEW.CARGO ahi dentro, asi que un
# empleado con cargo de 31 a 50 caracteres NO puede cambiar de cargo, ni
# recibir un aumento, ni ser despedido: el INSERT del trigger da error 1406 y
# se cae el UPDATE entero. Editar nombre, cedula, email o telefono si funciona,
# porque el trigger solo escribe cuando cambia cargo, salario o estado.
#
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-historial-laboral.sh
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

CEDULA="999000001"
CEDULA_CORTA="999000002"
# Telefonos y email propios: los 000000000X ya estan usados por los empleados
# sembrados en TEST y el SP rechaza duplicados.
TELEFONO="9997770001"
TELEFONO_NUEVO="9997770011"
TELEFONO_CORTO="9997770002"
TELEFONO_CORTO_NUEVO="9997770019"
EMAIL="zz-historial-test@local"
EMAIL_CORTO="zz-historial-corto@local"
# Ambos pasan de 30 y no llegan a 50 (el limite de EMPLEADOS.CARGO).
CARGO_LARGO="JEFE DE DEPARTAMENTO DE OPERACIONES Y LOGISTICA"
CARGO_LARGO2="COORDINADOR GENERAL DE MANTENIMIENTO INDUSTRIAL"
CARGO_CORTO="VENDEDOR"

fallos=0
ok()    { echo "OK    $1"; }
falla() { echo "FALLA $1"; fallos=$((fallos + 1)); }

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>&1; }

# Corre una sentencia y deja la salida en SALIDA; devuelve su codigo de salida.
SALIDA=""
ejecutar() {
    SALIDA="$(Q "$1")"
    return $?
}

# Cuando una sentencia falla, el cliente 13 imprime la sentencia entre guiones
# antes del error. Se descartan esas lineas para no leerlas como resultado.
valor() { Q "$1" | grep -vE '^-+$' | head -1; }

limpiar() {
    Q "DELETE FROM EMPLEADOS WHERE CEDULA IN ('$CEDULA', '$CEDULA_CORTA')
          OR EMAIL IN ('$EMAIL', '$EMAIL_CORTO');" >/dev/null 2>&1
}
trap limpiar EXIT

limpiar

# --- 0. El test se prueba a si mismo -------------------------------------
# Si los cargos de prueba no pasan de 30, este test no esta probando nada.
largo_1="$(valor "SELECT CHAR_LENGTH('$CARGO_LARGO')")"
largo_2="$(valor "SELECT CHAR_LENGTH('$CARGO_LARGO2')")"
if [ "${largo_1:-0}" -gt 30 ] && [ "${largo_2:-0}" -gt 30 ]; then
    ok "los cargos de prueba miden ${largo_1} y ${largo_2} caracteres"
else
    falla "los cargos de prueba no pasan de 30: el test no probaria el bug"
fi

# --- 1. Un cargo largo entra sin problema --------------------------------
if ejecutar "CALL SP_INSERTAR_EMPLEADO('ZZ HISTORIAL TEST', '$CEDULA', '$CARGO_LARGO', 15000.00, '$TELEFONO', '$EMAIL', NULL);"; then
    ok "inserta un empleado con cargo de ${largo_1} caracteres"
else
    falla "no pudo insertar el empleado con cargo largo ($SALIDA)"
fi

ID_EMP="$(valor "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$CEDULA'")"
if [ -n "$ID_EMP" ]; then
    ok "el empleado quedo en EMPLEADOS (ID $ID_EMP)"
else
    # Sin escenario no tiene sentido seguir: el resto fallaria en cascada y
    # taparia la causa.
    echo ""
    echo "Resultado: no se pudo preparar el escenario (cargo largo)."
    exit 1
fi

# --- 2. Editar un campo que no toca el trigger ---------------------------
# Esto ya funcionaba antes del arreglo: el trigger solo escribe cuando cambia
# cargo, salario o estado. Queda como pin de regresion.
if ejecutar "CALL SP_ACTUALIZAR_EMPLEADO($ID_EMP, NULL, NULL, NULL, NULL, '$TELEFONO_NUEVO', NULL);"; then
    ok "actualiza nombre/telefono de un empleado con cargo largo"
else
    falla "el UPDATE de un campo comun fallo ($SALIDA)"
fi

historial="$(valor "SELECT COUNT(*) FROM HISTORIAL_LABORAL_EMPLEADO WHERE ID_EMPLEADO = $ID_EMP")"
if [ "${historial:-x}" = "0" ]; then
    ok "no escribe historial si no cambio cargo, salario ni estado"
else
    falla "escribio historial sin que cambiara nada relevante (filas: ${historial:-?})"
fi

# --- 3. Cambiar el cargo por otro cargo largo ----------------------------
if ejecutar "CALL SP_ACTUALIZAR_EMPLEADO($ID_EMP, NULL, NULL, NULL, '$CARGO_LARGO2', NULL, NULL);"; then
    ok "cambia un cargo largo por otro cargo largo"
else
    falla "el cambio de cargo largo fallo ($SALIDA)"
fi

anterior="$(valor "SELECT CARGO_ANTERIOR FROM HISTORIAL_LABORAL_EMPLEADO WHERE ID_EMPLEADO = $ID_EMP AND TIPO_CAMBIO = 'PROMOCION' ORDER BY ID_HISTORIAL_EMPLEADO DESC LIMIT 1")"
nuevo="$(valor "SELECT CARGO_NUEVO FROM HISTORIAL_LABORAL_EMPLEADO WHERE ID_EMPLEADO = $ID_EMP AND TIPO_CAMBIO = 'PROMOCION' ORDER BY ID_HISTORIAL_EMPLEADO DESC LIMIT 1")"

[ "$anterior" = "$CARGO_LARGO" ] \
    && ok "el historial guarda el cargo anterior completo" \
    || falla "el cargo anterior quedo distinto o truncado: '$anterior'"

[ "$nuevo" = "$CARGO_LARGO2" ] \
    && ok "el historial guarda el cargo nuevo completo" \
    || falla "el cargo nuevo quedo distinto o truncado: '$nuevo'"

# --- 4. Aumento sobre un empleado con cargo largo -----------------------
if ejecutar "CALL SP_AUMENTO_POR_CARGO($ID_EMP, NULL, 10.00);"; then
    ok "aplica un aumento a un empleado con cargo largo"
else
    falla "el aumento fallo ($SALIDA)"
fi

# --- 5. Despido de un empleado con cargo largo --------------------------
if ejecutar "CALL SP_DESPEDIR_EMPLEADO($ID_EMP, NULL);"; then
    ok "despide a un empleado con cargo largo"
else
    falla "el despido fallo ($SALIDA)"
fi

estado="$(valor "SELECT ESTADO FROM EMPLEADOS WHERE ID_EMPLEADO = $ID_EMP")"
[ "$estado" = "INACTIVO" ] \
    && ok "el despido dejo al empleado INACTIVO" \
    || falla "el despido no cambio el estado: '$estado'"

tipo="$(valor "SELECT TIPO_CAMBIO FROM HISTORIAL_LABORAL_EMPLEADO WHERE ID_EMPLEADO = $ID_EMP ORDER BY ID_HISTORIAL_EMPLEADO DESC LIMIT 1")"
[ "$tipo" = "CAMBIO_ESTADO" ] \
    && ok "el despido quedo registrado como CAMBIO_ESTADO" \
    || falla "el ultimo cambio no es CAMBIO_ESTADO: '$tipo'"

# --- 6. Regresion: un cargo corto se comporta igual que antes -----------
ejecutar "CALL SP_INSERTAR_EMPLEADO('ZZ HISTORIAL CORTO', '$CEDULA_CORTA', '$CARGO_CORTO', 12000.00, '$TELEFONO_CORTO', '$EMAIL_CORTO', NULL);" >/dev/null
ID_CORTO="$(valor "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '$CEDULA_CORTA'")"

if [ -n "$ID_CORTO" ] && ejecutar "CALL SP_ACTUALIZAR_EMPLEADO($ID_CORTO, NULL, NULL, NULL, 'VENDEDOR SENIOR', NULL, NULL);"; then
    ok "un cargo corto sigue cambiandose como antes"
else
    falla "un cargo corto dejo de funcionar ($SALIDA)"
fi

cargo_corto_hist="$(valor "SELECT CARGO_NUEVO FROM HISTORIAL_LABORAL_EMPLEADO WHERE ID_EMPLEADO = $ID_CORTO ORDER BY ID_HISTORIAL_EMPLEADO DESC LIMIT 1")"
[ "$cargo_corto_hist" = "VENDEDOR SENIOR" ] \
    && ok "el historial de un cargo corto no cambio" \
    || falla "el historial de un cargo corto cambio: '$cargo_corto_hist'"

echo ""
echo "Resultado: $fallos fallo(s)"
[ "$fallos" -eq 0 ]
