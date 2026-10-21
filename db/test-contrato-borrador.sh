#!/usr/bin/env bash
# Tests del flujo de contratos por UI (opciones 12 y 13).
#
# Cubre, ademas de los arreglos del 18/10/2026:
#   1. Un tipo que no sea TEMPORAL ni FIJO ya no se registra como FIJO mudo.
#   2. Un borrador que ya no sirve se puede descartar desde el menu.
#   3. Regresion: un borrador incompleto se sigue frenando.
#   4. Entrada agotada (EOF) generando el contrato (12) -> sale, no gira.
#   5. (19/10/2026) Subir (13) COTEJA el borrador contra el papel: muestra los
#      valores, y con EOF corta sin escribir nada.
#   6. El cotejo detecta un cambio (salario) y lo resume; con "N" no registra.
#   7. Registro completo de un contrato huerfano: se guarda en BALBU_TECH_TEST,
#      queda "PENDIENTE DE ALTA" y el borrador pasa a .subido.
#   8. Generar (12) NO consulta EMPLEADOS; la cedula se valida a 11 digitos.
#
# Uso:
#   DB_NAME=BALBU_TECH_TEST DB_USER=root DB_PASSWORD=<clave> \
#   BALBU_USER=<usuario> BALBU_PASS=<clave> bash db/test-contrato-borrador.sh
# El repo no guarda credenciales y este test ESCRIBE: solo corre contra
# BALBU_TECH_TEST. Usa cedulas marcador 302998878xx y las borra al salir.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-8}"          # segundos antes de declarar "colgado"
fail=0

HOST="${DB_HOST:-127.0.0.1}"
USER="${DB_USER:-root}"
PASS="${DB_PASSWORD:-}"
DB="${DB_NAME:-}"

if [ ! -x "$APP" ]; then
  echo "FALTA el binario $APP: corre 'bash build.sh' primero."
  exit 1
fi
APP_ABS="$(realpath "$APP")"

if [ -z "${BALBU_USER:-}" ] || [ -z "${BALBU_PASS:-}" ]; then
  echo "FALTA BALBU_USER / BALBU_PASS: exportalos antes de correr (el repo no guarda credenciales)."
  exit 1
fi
if [ "$DB" != "BALBU_TECH_TEST" ] && [ "$DB" != "BALBU_TECH_TEST_V92" ]; then
  echo "FALTA DB_NAME de prueba (BALBU_TECH_TEST): este test escribe y no puede correr sobre la viva."
  exit 1
fi
if [ -z "$PASS" ]; then
  echo "FALTA DB_PASSWORD: exporta la contrasena de MariaDB del usuario $USER."
  exit 1
fi

TMP="$(mktemp -d /tmp/opencode/contrato-borrador.XXXXXX)"
limpiar_marcador() {
  mariadb -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e \
    "DELETE FROM CONTRATOS WHERE CEDULA LIKE '302998878%';
     DELETE FROM EMPLEADOS WHERE CEDULA LIKE '302998878%';" 2>/dev/null
}
trap 'limpiar_marcador; rm -rf "$TMP"' EXIT

# --- helpers ---------------------------------------------------------------

# Crea un cwd aislado con su propio contratos/ y devuelve la ruta.
preparar() {
  local dir="$TMP/$1"
  mkdir -p "$dir/contratos"
  echo "$dir"
}

# Deja un .borrador con las lineas clave=valor que se le pasen.
borrador() {   # $1 = ruta, resto = lineas
  printf '%s\n' "${@:2}" > "$1"
}

# Corre la app en $1 con la entrada $2; deja la salida en $3 y devuelve el rc
# (124 = la mato el timeout, o sea que quedo girando).
correr() {
  ( cd "$1" && printf '%b' "$2" | timeout "$LIMITE" "$APP_ABS" >"$3" 2>&1 )
  local rc=$?
  if [ "$(stat -c%s "$3" 2>/dev/null || echo 0)" -gt 200000 ]; then
    head -c 200000 "$3" > "$3.recorte" && mv "$3.recorte" "$3"
  fi
  echo "$rc"
}

# Igual que correr(), pero con la entrada en un archivo: sirve cuando la
# ultima linea tiene que llegar terminada en newline (una variable de shell
# se come los newlines finales).
correr_archivo() {   # $1 = dir, $2 = archivo de entrada, $3 = salida
  ( cd "$1" && timeout "$LIMITE" "$APP_ABS" <"$2" >"$3" 2>&1 )
  local rc=$?
  if [ "$(stat -c%s "$3" 2>/dev/null || echo 0)" -gt 200000 ]; then
    head -c 200000 "$3" > "$3.recorte" && mv "$3.recorte" "$3"
  fi
  echo "$rc"
}

entroAlMenu() { grep -q "Acceso concedido \[DEV\]" "$1"; }

ok()    { echo "OK    $1"; }
fallo() { echo "FALLO $1: $2"; fail=1; }

# Chequeos comunes: entro al menu, no giro y no registro nada en la BD.
saneado() {   # $1 = nombre, $2 = rc, $3 = salida
  if ! entroAlMenu "$3"; then
    fallo "$1" "no entro al menu (¿BALBU_USER/BALBU_PASS invalidos? ¿BD caida?)"
    return 1
  fi
  if [ "$2" = "124" ]; then
    fallo "$1" "giro sin fin (timeout ${LIMITE}s)."
    return 1
  fi
  if grep -q "EXITO: CONTRATO" "$3"; then
    fallo "$1" "registro un contrato en la BD (no debia tocar la BD)."
    return 1
  fi
  return 0
}

if [ "$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" \
      -e "SELECT (SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA LIKE '302998878%')
         + (SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA LIKE '302998878%');" 2>/dev/null)" != "0" ]; then
  echo "BASE SUCIA: hay filas 302998878xx antes del test. Limpialas y volve a correr."
  exit 2
fi

# ---------------------------------------------------------------------------
# 1. Tipo invalido: no debe caer como FIJO ni llegar al SP.
#    La cedula es un ESPACIO a proposito: si el tipo invalido llegara al SP,
#    el SP lo frena por cedula en blanco antes de insertar.
# ---------------------------------------------------------------------------
echo "--- 1. tipo invalido no se registra como FIJO en silencio ---"
dir="$(preparar caso1)"
borrador "$dir/contratos/T1.borrador" \
  "nombre=Prueba Tipo" \
  "cedula= " \
  "cargo=Tester" \
  "salario=1000.00" \
  "telefono=8090000001" \
  "email=test-tipo@local.test" \
  "fecha_ingreso=2026-01-01" \
  "tipo=INDEFINIDO" \
  "meses=0" \
  "html=contratos/T1.html" \
  "generado=2026-01-01"

out="$TMP/caso1.txt"
rc="$(correr "$dir" '\n3\n13\n1\n\n16\n0\n' "$out")"
if saneado "tipo invalido" "$rc" "$out"; then
  if grep -qF "tipo invalido: 'INDEFINIDO'" "$out"; then
    if [ -f "$dir/contratos/T1.borrador" ]; then
      ok "tipo invalido (borrador intacto, no llego al SP)"
    else
      fallo "tipo invalido" "el borrador desaparecio"
    fi
  else
    fallo "tipo invalido" "no aviso del tipo invalido"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Descartar: saca de la lista un borrador que ya no sirve.
# ---------------------------------------------------------------------------
echo "--- 2. descartar un borrador que ya no sirve ---"
dir="$(preparar caso2)"
borrador "$dir/contratos/T2.borrador" \
  "nombre=Prueba Descartar" \
  "cedula= " \
  "cargo=Tester" \
  "salario=1000.00" \
  "telefono=8090000002" \
  "email=test-descartar@local.test" \
  "fecha_ingreso=2026-01-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T2.html" \
  "generado=2026-01-01"

out="$TMP/caso2.txt"
rc="$(correr "$dir" '\n3\n13\n2\n1\n\n16\n0\n' "$out")"
if saneado "descartar" "$rc" "$out"; then
  problemas=""
  grep -qF "Descartar un borrador" "$out" || problemas="no ofrecio descartar en el menu"
  grep -qF "Borrador descartado" "$out"   || problemas="${problemas:+$problemas; }no confirmo el descarte"
  [ -f "$dir/contratos/T2.borrador" ]     && problemas="${problemas:+$problemas; }siguio existiendo el .borrador"
  [ -f "$dir/contratos/T2.descartado" ]   || problemas="${problemas:+$problemas; }no quedo el .descartado"
  if [ -z "$problemas" ]; then
    ok "descartar (renombra a .descartado, no borra)"
  else
    fallo "descartar" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Regresion: un borrador incompleto se sigue frenando.
# ---------------------------------------------------------------------------
echo "--- 3. regresion: borrador incompleto (falta cargo) ---"
dir="$(preparar caso3)"
borrador "$dir/contratos/T3.borrador" \
  "nombre=Prueba Incompleto" \
  "cedula= " \
  "salario=1000.00" \
  "telefono=8090000003" \
  "email=test-incompleto@local.test" \
  "fecha_ingreso=2026-01-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T3.html" \
  "generado=2026-01-01"

out="$TMP/caso3.txt"
rc="$(correr "$dir" '\n3\n13\n1\n\n16\n0\n' "$out")"
if saneado "borrador incompleto" "$rc" "$out"; then
  if grep -qF "El borrador esta incompleto (falta 'cargo')" "$out"; then
    ok "borrador incompleto (sigue frenando)"
  else
    fallo "borrador incompleto" "no lo freno por el campo que falta"
  fi
fi

# ---------------------------------------------------------------------------
# 4. EOF generando el contrato (opcion 12): no gira.
# ---------------------------------------------------------------------------
echo "--- 4. EOF pidiendo los datos del contrato (opcion 12) ---"
dir="$(preparar caso4)"
out="$TMP/caso4.txt"
rc="$(correr "$dir" '\n3\n12\n' "$out")"
if saneado "EOF generando contrato" "$rc" "$out"; then
  if grep -qF "Operación cancelada" "$out"; then
    ok "EOF generando contrato (corta, no gira)"
  else
    fallo "EOF generando contrato" "no salio por la cancelacion esperada"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Subir (13) coteja: muestra los valores del borrador y corta con EOF.
# ---------------------------------------------------------------------------
echo "--- 5. cotejo contra el papel: muestra valores y corta con EOF ---"
dir="$(preparar caso5)"
borrador "$dir/contratos/T5.borrador" \
  "nombre=Prueba Cotejo" \
  "cedula=30299887800" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000010" \
  "email=test-cotejo@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T5.html" \
  "generado=2026-10-19"

out="$TMP/caso5.txt"
# Un Enter (nombre) y despues EOF: asi se ven dos prompts del cotejo.
rc="$(correr "$dir" '\n3\n13\n1\n\n' "$out")"
if saneado "cotejo EOF" "$rc" "$out"; then
  problemas=""
  grep -qF "COTEJO CONTRA EL PAPEL FIRMADO" "$out" || problemas="no mostro el cotejo"
  grep -qF "Nombre [Prueba Cotejo]" "$out"        || problemas="${problemas:+$problemas; }no ofrecio el nombre del borrador"
  grep -qF "Cedula [30299887800]" "$out"          || problemas="${problemas:+$problemas; }no ofrecio la cedula"
  grep -qF "Operación cancelada" "$out"           || problemas="${problemas:+$problemas; }no corto con EOF"
  [ -f "$dir/contratos/T5.borrador" ]             || problemas="${problemas:+$problemas; }el borrador desaparecio"
  if [ -z "$problemas" ]; then
    ok "cotejo (valores visibles, EOF corta sin escribir)"
  else
    fallo "cotejo EOF" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Cotejo con un cambio: resume la diferencia y con "N" no registra.
#    Entradas: 8 campos (nombre..email), S/N = N.
# ---------------------------------------------------------------------------
echo "--- 6. cambio en el cotejo: resumen y N no registra ---"
dir="$(preparar caso6)"
borrador "$dir/contratos/T6.borrador" \
  "nombre=Prueba Cambio" \
  "cedula=30299887801" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000011" \
  "email=test-cambio@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T6.html" \
  "generado=2026-10-19"

# nombre, cedula, cargo (Enter) + salario 18000 + tipo, fecha, telefono, email (Enter)
entrada="$(printf '\n3\n13\n1\n\n\n\n18000\n\n\n\n\nN\n16\n0\n')"
out="$TMP/caso6.txt"
rc="$(correr "$dir" "$entrada" "$out")"
if saneado "cambio en cotejo" "$rc" "$out"; then
  problemas=""
  grep -qF "Cambios detectados" "$out" || problemas="no mostro el resumen de cambios"
  grep -qF "salario: 10000.00 -> 18000.00" "$out" || problemas="${problemas:+$problemas; }no listo el cambio de salario"
  grep -qF "No se registro nada." "$out" || problemas="${problemas:+$problemas; }no respeto la N"
  [ -f "$dir/contratos/T6.borrador" ] || problemas="${problemas:+$problemas; }el borrador desaparecio"
  if [ -z "$problemas" ]; then
    ok "cotejo con cambio (resume y no registra con N)"
  else
    fallo "cambio en cotejo" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Registro completo de un contrato huerfano (la persona no esta dada de
#    alta): escribe en TEST, queda PENDIENTE DE ALTA y el borrador pasa a
#    .subido. Se limpia la cedula marcador al salir.
# ---------------------------------------------------------------------------
echo "--- 7. registro completo: huerfano PENDIENTE DE ALTA ---"
dir="$(preparar caso7)"
borrador "$dir/contratos/T7.borrador" \
  "nombre=Prueba Alta" \
  "cedula=30299887802" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000012" \
  "email=test-alta@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T7.html" \
  "generado=2026-10-19"

# 8 campos con Enter + S + Enter (sin escaneo) + volver/salir
entrada="$(printf '\n3\n13\n1\n'; printf '\n%.0s' 1 2 3 4 5 6 7 8; printf 'S\n\n16\n0\n')"
out="$TMP/caso7.txt"
rc="$(correr "$dir" "$entrada" "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "EXITO: CONTRATO" "$out" || problemas="no registro el contrato"
  grep -qF "EMPLEADO PENDIENTE DE ALTA" "$out" || problemas="${problemas:+$problemas; }no lo dejo pendiente de alta"
  grep -qF "Borrador marcado" "$out" || problemas="${problemas:+$problemas; }no marco el borrador"
  [ -f "$dir/contratos/T7.borrador" ] && problemas="${problemas:+$problemas; }siguio el .borrador"
  [ -f "$dir/contratos/T7.subido" ] || problemas="${problemas:+$problemas; }no quedo el .subido"
  filas="$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e \
    "SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA='30299887802' AND ID_EMPLEADO IS NULL AND ESTADO='ACTIVO';" 2>/dev/null)"
  [ "$filas" = "1" ] || problemas="${problemas:+$problemas; }en la BD hay $filas filas (se esperaba 1)"
  if [ -z "$problemas" ]; then
    ok "registro completo (contrato huerfano, borrador .subido)"
  else
    fallo "registro completo" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Generar (12): no consulta EMPLEADOS y valida la cedula a 11 digitos.
# ---------------------------------------------------------------------------
echo "--- 8. generar (12) con cedula que no existe y cedula corta ---"
dir="$(preparar caso8)"
out="$TMP/caso8.txt"
rc="$(correr "$dir" '\n3\n12\n123\n' "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "La cedula debe tener 11 digitos" "$out" || problemas="no rechazo la cedula corta"
  grep -qF "no esta registrada en Empleados" "$out" && problemas="${problemas:+$problemas; }sigue consultando EMPLEADOS"
  if [ -z "$problemas" ]; then
    ok "generar (12) no consulta EMPLEADOS y valida 11 digitos"
  else
    fallo "generar (12)" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 9. El alta (opcion 1) precarga los datos del contrato firmado sin empleado y
#    TR_VINCULAR_CONTRATO engancha el contrato al crearse el empleado.
# ---------------------------------------------------------------------------
echo "--- 9. alta precargada desde un contrato huerfano ---"
dir="$(preparar caso9)"
# Se limpia lo del caso 7 para que quede UN solo contrato pendiente y el "1"
# del menu sea inequivoco.
mariadb -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e "
  DELETE FROM CONTRATOS WHERE CEDULA='30299887802';
  DELETE FROM EMPLEADOS WHERE CEDULA='30299887802';" 2>/dev/null
mariadb -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e "
  INSERT INTO CONTRATOS (TIPO, FECHA_INICIO, FECHA_FIN, SALARIO, NOMBRE, CEDULA,
                         CARGO, TELEFONO, EMAIL, FECHA_INGRESO, RUTA_DOCUMENTO)
  VALUES ('FIJO', '2026-11-01', NULL, 10000.00, 'Prueba Prefill', '30299887803',
          'Tester', '8090000013', 'test-prefill@local.test', '2026-11-01',
          'contratos/T9.html');" 2>/dev/null

out="$TMP/caso9.txt"
# 3 = Empleados, 1 = Agregar, 1 = elegir el contrato, 3 Enter (tel/email/fecha)
rc="$(correr "$dir" '\n3\n1\n1\n\n\n\n16\n0\n' "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "Contratos firmados sin empleado" "$out" || problemas="no listo los contratos huerfanos"
  grep -qF "Datos cargados del contrato #" "$out" || problemas="${problemas:+$problemas; }no precargo el contrato elegido"
  grep -qF "EXITO" "$out" || problemas="${problemas:+$problemas; }no dio de alta al empleado"
  estado="$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e "
    SELECT IF((SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA='30299887803') = 1
      AND (SELECT ID_EMPLEADO FROM CONTRATOS WHERE CEDULA='30299887803')
        = (SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA='30299887803')
      AND (SELECT FECHA_INGRESO FROM EMPLEADOS WHERE CEDULA='30299887803') = '2026-11-01',
      'OK', 'FALLO');" 2>/dev/null)"
  [ "$estado" = "OK" ] || problemas="${problemas:+$problemas; }empleado/vinculo/fecha incorrectos"
  if [ -z "$problemas" ]; then
    ok "alta precargada (contrato vinculado por el trigger)"
  else
    fallo "alta precargada" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 10. Cotejo con salario corregido + S: se registra el valor NUEVO, no el del
#     borrador.
# ---------------------------------------------------------------------------
echo "--- 10. cotejo con salario corregido: registra el nuevo ---"
dir="$(preparar caso10)"
borrador "$dir/contratos/T10.borrador" \
  "nombre=Prueba Correccion" \
  "cedula=30299887804" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000014" \
  "email=test-correccion@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T10.html" \
  "generado=2026-10-19"

entrada="$(printf '\n3\n13\n1\n\n\n\n18000\n\n\n\n\nS\n\n16\n0\n')"
out="$TMP/caso10.txt"
rc="$(correr "$dir" "$entrada" "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "EXITO: CONTRATO" "$out" || problemas="no registro el contrato"
  monto="$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e \
    "SELECT SALARIO FROM CONTRATOS WHERE CEDULA='30299887804';" 2>/dev/null)"
  [ "$monto" = "18000.00" ] || problemas="${problemas:+$problemas; }guardo '$monto' (se esperaba 18000.00)"
  [ -f "$dir/contratos/T10.subido" ] || problemas="${problemas:+$problemas; }no marco el borrador"
  if [ -z "$problemas" ]; then
    ok "cotejo corrige el salario y registra el valor nuevo"
  else
    fallo "cotejo corrige salario" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 11. Cedula invalida en el cotejo: la rechaza y vuelve a pedir; con EOF
#     cancela sin escribir.
# ---------------------------------------------------------------------------
echo "--- 11. cedula invalida en el cotejo: rechaza y no escribe ---"
dir="$(preparar caso11)"
borrador "$dir/contratos/T11.borrador" \
  "nombre=Prueba Invalida" \
  "cedula=30299887806" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000015" \
  "email=test-invalida@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T11.html" \
  "generado=2026-10-19"

out="$TMP/caso11.txt"
rc="$(correr "$dir" '\n3\n13\n1\n\n123\n' "$out")"
if saneado "cedula invalida en cotejo" "$rc" "$out"; then
  if grep -qF "La cedula debe tener 11 digitos" "$out"; then
    ok "cedula invalida en el cotejo (rechazada, sin escribir)"
  else
    fallo "cedula invalida en cotejo" "no mostro el aviso de 11 digitos"
  fi
fi

# ---------------------------------------------------------------------------
# 12. Escaneo con ruta inexistente: avisa y no registra (el archivo se pide
#     antes del SP); con EOF corta.
# ---------------------------------------------------------------------------
echo "--- 12. escaneo inexistente: no registra ---"
dir="$(preparar caso12)"
borrador "$dir/contratos/T12.borrador" \
  "nombre=Prueba Escaneo" \
  "cedula=30299887807" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000016" \
  "email=test-escaneo@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T12.html" \
  "generado=2026-10-19"

{ printf '\n3\n13\n1\n'; printf '\n%.0s' 1 2 3 4 5 6 7 8; printf 'S\n/no/existe.pdf\n'; } > "$TMP/in12.txt"
out="$TMP/caso12.txt"
rc="$(correr_archivo "$dir" "$TMP/in12.txt" "$out")"
if saneado "escaneo inexistente" "$rc" "$out"; then
  problemas=""
  grep -qF "No existe ese archivo" "$out" || problemas="no aviso de la ruta inexistente"
  grep -qF "Operación cancelada" "$out" || problemas="${problemas:+$problemas; }no corto con EOF"
  filas="$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e \
    "SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA='30299887807';" 2>/dev/null)"
  [ "$filas" = "0" ] || problemas="${problemas:+$problemas; }registro $filas contrato(s)"
  [ -f "$dir/contratos/T12.borrador" ] || problemas="${problemas:+$problemas; }el borrador desaparecio"
  if [ -z "$problemas" ]; then
    ok "escaneo inexistente (avisa y no registra)"
  else
    fallo "escaneo inexistente" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 13. Opcion 14: ver los contratos por cedula (funciona sin empleado).
# ---------------------------------------------------------------------------
echo "--- 13. ver contratos por cedula (opcion 14) ---"
dir="$(preparar caso13)"
mariadb -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e "
  DELETE FROM CONTRATOS WHERE CEDULA='30299887808';
  DELETE FROM EMPLEADOS WHERE CEDULA='30299887808';
  INSERT INTO CONTRATOS (TIPO, FECHA_INICIO, FECHA_FIN, SALARIO, NOMBRE, CEDULA,
                         CARGO, TELEFONO, EMAIL, FECHA_INGRESO, RUTA_DOCUMENTO)
  VALUES ('TEMPORAL', '2026-11-01', '2027-05-01', 9000.00, 'Prueba Ver', '30299887808',
          'Tester', '8090000017', 'test-ver@local.test', '2026-11-01',
          'contratos/T13.html');" 2>/dev/null

out="$TMP/caso13.txt"
rc="$(correr "$dir" '\n3\n14\n30299887808\nN\n16\n0\n' "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "Persona: Prueba Ver - Tester" "$out" || problemas="no mostro nombre/cargo del contrato"
  grep -qF "TEMPORAL" "$out" || problemas="${problemas:+$problemas; }no mostro el tipo"
  grep -qF "PENDIENTE" "$out" || problemas="${problemas:+$problemas; }no marco el vinculo pendiente"
  if [ -z "$problemas" ]; then
    ok "ver contratos por cedula (persona sin alta)"
  else
    fallo "ver contratos por cedula" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 14. Opcion 15: finalizar el contrato ACTIVO de una cedula.
# ---------------------------------------------------------------------------
echo "--- 14. finalizar contrato por cedula (opcion 15) ---"
out="$TMP/caso14.txt"
rc="$(correr "$dir" '\n3\n15\n30299887808\nS\n16\n0\n' "$out")"
if entroAlMenu "$out" && [ "$rc" != "124" ]; then
  problemas=""
  grep -qF "EXITO: CONTRATO" "$out" || problemas="no finalizo el contrato"
  estado="$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" -e \
    "SELECT CONCAT(ESTADO, '|', FECHA_FIN) FROM CONTRATOS WHERE CEDULA='30299887808';" 2>/dev/null)"
  case "$estado" in
    FINALIZADO\|*) : ;;
    *) problemas="${problemas:+$problemas; }estado '$estado' (se esperaba FINALIZADO)" ;;
  esac
  if [ -z "$problemas" ]; then
    ok "finalizar por cedula (busca el ACTIVO y lo cierra)"
  else
    fallo "finalizar por cedula" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------
# 15. (20/10/2026) EOF en el telefono del cotejo: caso que se perdio en la
#     reescritura del 19/10 (antes vivia junto al flujo viejo de "Telefono real
#     del empleado nuevo", que giraba sin fin). Seis Enter dejan el borrador y
#     la entrada se agota en Telefono: corta con cancelacion, no gira y no
#     escribe nada.
# ---------------------------------------------------------------------------
echo "--- 15. EOF en el telefono del cotejo ---"
dir="$(preparar caso15)"
borrador "$dir/contratos/T15.borrador" \
  "nombre=Prueba EOF Telefono" \
  "cedula=30299887820" \
  "cargo=Tester" \
  "salario=10000.00" \
  "telefono=8090000020" \
  "email=test-eof-telefono@local.test" \
  "fecha_ingreso=2026-11-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T15.html" \
  "generado=2026-10-19"

# 1 = elegir el borrador; 6 Enter = nombre..fecha; despues EOF en Telefono.
out="$TMP/caso15.txt"
rc="$(correr "$dir" '\n3\n13\n1\n\n\n\n\n\n\n' "$out")"
if saneado "EOF telefono cotejo" "$rc" "$out"; then
  problemas=""
  grep -qF "Telefono [" "$out" || problemas="no llego al prompt del telefono"
  grep -qF "Operación cancelada" "$out" || problemas="${problemas:+$problemas; }no corto con EOF"
  [ -f "$dir/contratos/T15.borrador" ] || problemas="${problemas:+$problemas; }el borrador desaparecio"
  if [ -z "$problemas" ]; then
    ok "EOF en el telefono del cotejo (corta, no gira)"
  else
    fallo "EOF telefono cotejo" "$problemas"
  fi
fi

# ---------------------------------------------------------------------------

if [ "$fail" -eq 0 ]; then
  echo "TODOS LOS TESTS DE CONTRATO-BORRADOR OK"
else
  echo "TESTS CONTRATO-BORRADOR: FALLAS ARRIBA"
fi
exit $fail
