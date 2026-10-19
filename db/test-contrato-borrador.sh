#!/usr/bin/env bash
# Tests del flujo de borradores de contrato (opcion 13 "Subir contrato").
#
# Cubre los arreglos del 18/10/2026 en contrato.cpp:
#   1. Un tipo que no sea TEMPORAL ni FIJO ya no se registra como FIJO mudo
#      (antes "== TEMPORAL" mandaba todo lo demas al SP como fijo).
#   2. Un borrador que ya no sirve se puede descartar desde el menu (antes el
#      que quedaba huerfano trababa la lista para siempre).
#   3. Regresion: un borrador incompleto se sigue frenando.
#   4. Entrada agotada (EOF) en el flujo de contratos -> sale, no gira.
#
# Uso:  BALBU_USER=<usuario> BALBU_PASS=<clave> bash db/test-contrato-borrador.sh
# El repo no guarda credenciales: hay que exportarlas, mismo criterio que
# db/test-contratos-subir.sh y db/test-menus-eof.sh. Se usan para el atajo de
# dev de main.cpp (BALBU_USER/BALBU_PASS), que saltea el login.
#
# La BD solo se LEE: los cuatro casos cortan antes de escribir. Los que llegan
# al SP lo hacen con una cedula en blanco (a proposito), y el SP frena por
# cedula antes de insertar. El test corre la app en un directorio temporal con
# su propio contratos/, asi que no toca los borradores reales ni el repo.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"          # segundos antes de declarar "colgado"
fail=0

if [ ! -x "$APP" ]; then
  echo "FALTA el binario $APP: corre 'bash build.sh' primero."
  exit 1
fi
APP_ABS="$(realpath "$APP")"

if [ -z "${BALBU_USER:-}" ] || [ -z "${BALBU_PASS:-}" ]; then
  echo "FALTA BALBU_USER / BALBU_PASS: exportalos antes de correr (el repo no guarda credenciales)."
  exit 1
fi

TMP="$(mktemp -d /tmp/opencode/contrato-borrador.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

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
# OJO: con la entrada agotada el binario viejo imprimia sin parar; el tope de
# LIMITE evita que eso llene el disco, pero la salida se recorta despues.
correr() {
  ( cd "$1" && printf '%b' "$2" | timeout "$LIMITE" "$APP_ABS" >"$3" 2>&1 )
  local rc=$?
  # Solo se miran las primeras 200 KB: alcanza para los assert y no deja el
  # temporal lleno de millones de lineas repetidas.
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

# ---------------------------------------------------------------------------
# 1. Tipo invalido: no debe caer como FIJO ni llegar al SP.
#
# La cedula es UN ESPACIO a proposito: si el tipo invalido llegara al SP
# (comportamiento viejo) el SP lo frena por cedula en blanco ANTES de
# insertar, asi el caso tambien es libre de escrituras cuando da rojo.
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
#    Con un solo borrador, la opcion de descartar es la 2.
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
# 4. EOF generando el contrato (opcion 12): el pedido de nombre giraba sin fin.
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
# 5. EOF pidiendo el telefono de un empleado nuevo: giraba sin fin.
#    Requiere que la cedula no exista en EMPLEADOS (solo se consulta).
# ---------------------------------------------------------------------------
echo "--- 5. EOF pidiendo el telefono de un empleado nuevo ---"
dir="$(preparar caso5)"
borrador "$dir/contratos/T5.borrador" \
  "nombre=Prueba Huerfano" \
  "cedula=TEST-EOF-0001" \
  "cargo=Tester" \
  "salario=1000.00" \
  "telefono=-" \
  "email=-" \
  "fecha_ingreso=2026-01-01" \
  "tipo=FIJO" \
  "meses=0" \
  "html=contratos/T5.html" \
  "generado=2026-01-01"

out="$TMP/caso5.txt"
rc="$(correr "$dir" '\n3\n13\n1\n' "$out")"
if saneado "EOF telefono empleado nuevo" "$rc" "$out"; then
  if grep -qF "Operación cancelada" "$out"; then
    ok "EOF telefono empleado nuevo (corta, no gira)"
  else
    fallo "EOF telefono empleado nuevo" "no salio por la cancelacion esperada"
  fi
fi

# ---------------------------------------------------------------------------

if [ "$fail" -eq 0 ]; then
  echo "TODOS LOS TESTS DE CONTRATO-BORRADOR OK"
else
  echo "TESTS CONTRATO-BORRADOR: FALLAS ARRIBA"
fi
exit $fail
