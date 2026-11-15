#!/usr/bin/env bash
# Test de auditoria de permisos (modulo 13) — 12/11/2026.
#
# Fija los tres defectos que tenia la bitacora antes del 12/11/2026:
#   1. el trigger solo escuchaba UPDATE (ni alta ni baja),
#   2. no guardaba quien lo hizo,
#   3. al borrar el permiso la FK ponia ID_PERMISO en NULL y la fila de
#      bitacora se quedaba sin saber de quien era.
#
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-auditoria-permisos.sh
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

CEDULA="999000003"
TELEFONO="9997770003"
EMAIL="zz-auditoria-permisos@local"

fallos=0
ok()    { echo "OK    $1"; }
falla() { echo "FALLA $1"; fallos=$((fallos + 1)); }

Q() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -e "$1" 2>&1; }

SALIDA=""
ejecutar() {
    SALIDA="$(Q "$1")"
    return $?
}

# Cuando una sentencia falla, el cliente imprime la sentencia entre guiones
# antes del error. Si devolvieramos esa linea, un assert podria darla por
# buena: por eso en error se imprime por stderr y se devuelve vacio.
valor() {
    local out code
    out="$(Q "$1")"; code=$?
    if [ "$code" -ne 0 ]; then
        echo "  (valor falló: $(printf '%s' "$out" | grep -vE '^-+$' | tr '\n' ' '))" >&2
        return 1
    fi
    printf '%s\n' "$out" | grep -vE '^-+$' | head -1
}

limpiar() {
    # Orden importa: borrar los permisos dispara el trigger de BAJA, que escribe
    # filas nuevas en la bitacora. Primero los permisos, despues sus filas de
    # bitacora y por ultimo el empleado; si no, quedan BAJA huerfanas.
    Q "DELETE FROM PERMISOS_EMPLEADOS
        WHERE ID_EMPLEADO IN (SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CEDULA');" >/dev/null 2>&1
    Q "DELETE FROM LOG_AUDITORIA_PERMISOS
        WHERE ID_EMPLEADO IN (SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CEDULA');" >/dev/null 2>&1
    Q "DELETE FROM EMPLEADOS WHERE CEDULA='$CEDULA';" >/dev/null 2>&1
}
trap limpiar EXIT

limpiar

# --- 0. Escenario ---------------------------------------------------------
ejecutar "CALL SP_INSERTAR_EMPLEADO('ZZ AUDITORIA PERMISOS', '$CEDULA', 'VENDEDOR', 12000.00, '$TELEFONO', '$EMAIL', NULL);" >/dev/null
ID_EMP="$(valor "SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='$CEDULA'")"
if [ -z "$ID_EMP" ]; then
    echo "Resultado: no se pudo preparar el escenario (empleado de prueba)."
    exit 1
fi

ACTOR="$(valor "SELECT MIN(ID_USUARIO) FROM USUARIOS")"
if [ -z "$ACTOR" ]; then
    echo "Resultado: no hay usuarios para usar como actor."
    exit 1
fi

# --- 1. Alta (INSERT) -----------------------------------------------------
if ejecutar "SET @ID_USUARIO_ACTUAL = $ACTOR;
             INSERT INTO PERMISOS_EMPLEADOS (ID_EMPLEADO, TIPO_PERMISO, FECHA_INICIO, FECHA_FIN, DESCRIPCION)
             VALUES ($ID_EMP, 'MEDICO', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'auditoria');"; then
    ok "inserta un permiso con sesion activa"
else
    falla "no pudo insertar el permiso ($SALIDA)"
fi

ID_PERM="$(valor "SELECT ID_PERMISO FROM PERMISOS_EMPLEADOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_PERMISO DESC LIMIT 1")"

accion="$(valor "SELECT ACCION FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$accion" = "ALTA" ] \
    && ok "el alta quedo registrada como ALTA" \
    || falla "el alta no quedo registrada: '$accion'"

estado_ant="$(valor "SELECT IFNULL(ESTADO_ANTERIOR,'(null)') FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
estado_nue="$(valor "SELECT ESTADO_NUEVO FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$estado_ant" = "(null)" ] && [ "$estado_nue" = "PENDIENTE" ] \
    && ok "el alta guarda estado anterior NULL y nuevo PENDIENTE" \
    || falla "el alta guardo estados raros: antes='$estado_ant' nuevo='$estado_nue'"

tipo="$(valor "SELECT TIPO_PERMISO FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$tipo" = "MEDICO" ] \
    && ok "el alta guarda el tipo de permiso" \
    || falla "el alta no guardo el tipo: '$tipo'"

# --- 2. Actor -------------------------------------------------------------
actor="$(valor "SELECT ID_USUARIO_ADMIN FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$actor" = "$ACTOR" ] \
    && ok "guarda quien hizo el cambio (ID $ACTOR)" \
    || falla "no guardo el actor: '$actor' (esperaba $ACTOR)"

# --- 3. Cambio de estado (UPDATE) ----------------------------------------
if ejecutar "SET @ID_USUARIO_ACTUAL = $ACTOR;
             UPDATE PERMISOS_EMPLEADOS SET ESTADO='APROBADO' WHERE ID_PERMISO=$ID_PERM;"; then
    ok "aprueba el permiso"
else
    falla "no pudo aprobar el permiso ($SALIDA)"
fi

accion="$(valor "SELECT ACCION FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
ant="$(valor "SELECT ESTADO_ANTERIOR FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
nue="$(valor "SELECT ESTADO_NUEVO FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$accion" = "CAMBIO_ESTADO" ] && [ "$ant" = "PENDIENTE" ] && [ "$nue" = "APROBADO" ] \
    && ok "el cambio de estado queda registrado con antes y despues" \
    || falla "el cambio de estado quedo mal: accion='$accion' antes='$ant' nuevo='$nue'"

# --- 4. Update que no cambia estado --------------------------------------
antes="$(valor "SELECT COUNT(*) FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP")"
ejecutar "SET @ID_USUARIO_ACTUAL = $ACTOR;
          UPDATE PERMISOS_EMPLEADOS SET DESCRIPCION='otra cosa' WHERE ID_PERMISO=$ID_PERM;" >/dev/null
despues="$(valor "SELECT COUNT(*) FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP")"
[ -n "$antes" ] && [ "$antes" = "$despues" ] \
    && ok "un cambio que no toca el estado no escribe bitacora" \
    || falla "escribio bitacora de un cambio sin estado ($antes -> $despues)"

# --- 5. Sin sesion no rompe, y el actor queda NULL -----------------------
if ejecutar "SET @ID_USUARIO_ACTUAL = NULL;
             UPDATE PERMISOS_EMPLEADOS SET ESTADO='RECHAZADO' WHERE ID_PERMISO=$ID_PERM;"; then
    ok "sin sesion el cambio se aplica igual (el trigger no aborta)"
else
    falla "sin sesion el cambio fallo ($SALIDA)"
fi

actor="$(valor "SELECT IFNULL(ID_USUARIO_ADMIN,'(null)') FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$actor" = "(null)" ] \
    && ok "sin sesion el actor queda NULL" \
    || falla "sin sesion el actor quedo '$actor'"

# --- 6. Baja (DELETE) -----------------------------------------------------
if ejecutar "SET @ID_USUARIO_ACTUAL = $ACTOR;
             DELETE FROM PERMISOS_EMPLEADOS WHERE ID_PERMISO=$ID_PERM;"; then
    ok "borra el permiso"
else
    falla "no pudo borrar el permiso ($SALIDA)"
fi

accion="$(valor "SELECT ACCION FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$accion" = "BAJA" ] \
    && ok "la baja quedo registrada como BAJA" \
    || falla "la baja no quedo registrada: '$accion'"

perm_ant="$(valor "SELECT IFNULL(ESTADO_ANTERIOR,'(null)') FROM LOG_AUDITORIA_PERMISOS WHERE ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$perm_ant" = "RECHAZADO" ] \
    && ok "la baja guarda el estado que tenia" \
    || falla "la baja no guardo el estado anterior: '$perm_ant'"

# Lo importante: despues del borrado el registro sigue sabiendo de quien era.
emp_baja="$(valor "SELECT ID_EMPLEADO FROM LOG_AUDITORIA_PERMISOS WHERE ACCION='BAJA' AND ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
tipo_baja="$(valor "SELECT TIPO_PERMISO FROM LOG_AUDITORIA_PERMISOS WHERE ACCION='BAJA' AND ID_EMPLEADO=$ID_EMP ORDER BY ID_LOG DESC LIMIT 1")"
[ "$emp_baja" = "$ID_EMP" ] && [ "$tipo_baja" = "MEDICO" ] \
    && ok "la fila de BAJA conserva empleado y tipo despues del borrado" \
    || falla "la fila de BAJA perdio la identidad: empleado='$emp_baja' tipo='$tipo_baja'"

# --- 7. Vista -------------------------------------------------------------
empleado_nombre="$(valor "SELECT EMPLEADO FROM VIEW_HISTORIAL_PERMISOS WHERE ACCION='ALTA' AND ID_EMPLEADO=$ID_EMP LIMIT 1")"
[ "$empleado_nombre" = "ZZ AUDITORIA PERMISOS" ] \
    && ok "la vista resuelve el nombre del empleado" \
    || falla "la vista no resolvio el empleado: '$empleado_nombre'"

usuario_nombre="$(valor "SELECT USUARIO_ADMIN FROM VIEW_HISTORIAL_PERMISOS WHERE ACCION='ALTA' AND ID_EMPLEADO=$ID_EMP LIMIT 1")"
[ -n "$usuario_nombre" ] && [ "$usuario_nombre" != "NULL" ] \
    && ok "la vista resuelve el nombre del usuario que lo hizo" \
    || falla "la vista no resolvio el usuario: '$usuario_nombre'"

# --- 8. Lector paginado ---------------------------------------------------
total_sp="$(valor "CALL SP_CONTAR_AUDITORIA_PERMISOS();")"
total_tabla="$(valor "SELECT COUNT(*) FROM LOG_AUDITORIA_PERMISOS")"
[ "$total_sp" = "$total_tabla" ] \
    && ok "SP_CONTAR_AUDITORIA_PERMISOS coincide con la tabla ($total_tabla)" \
    || falla "el conteo del SP ($total_sp) no coincide con la tabla ($total_tabla)"

if SALIDA="$(Q "CALL SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO(1, 2);")"; then
    pagina="$(printf '%s\n' "$SALIDA" | grep -vE '^-+$' | grep -c .)"
    [ "$pagina" = "2" ] \
        && ok "el paginado devuelve 2 filas con por_pagina=2" \
        || falla "el paginado devolvio '$pagina' filas, esperaba 2"
else
    falla "el paginado fallo: $SALIDA"
fi

# --- 9. Mapeo de permisos -------------------------------------------------
sinexistente="$(valor "SELECT COUNT(*) FROM PERMISO_POR_RUTINA
                        WHERE RUTINA IN ('SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO','SP_CONTAR_AUDITORIA_PERMISOS')
                          AND PERMISO = 'GESTIONAR_PERMISOS_EMPLEADO'")"
[ "$sinexistente" = "2" ] \
    && ok "las dos rutinas nuevas estan mapeadas a GESTIONAR_PERMISOS_EMPLEADO" \
    || falla "mapeo de las rutinas nuevas: '${sinexistente:-?}' (esperaba 2)"

echo ""
echo "Resultado: $fallos fallo(s)"
[ "$fallos" -eq 0 ]
