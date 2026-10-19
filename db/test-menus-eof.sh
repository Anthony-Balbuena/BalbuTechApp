#!/usr/bin/env bash
# Tests del bug "los menus giran sin fin con la entrada agotada" (EOF).
#
# El molde viejo (cin >> opcion; if (cin.fail()) { cin.clear(); ... }) NO
# termina nunca con EOF: clear() borra el flag pero el buffer sigue en EOF,
# asi que el siguiente ">>" falla al instante y la opcion nunca vale la de
# salida. El caso real llego a generar un log de 35M lineas.
#
# Uso:  BALBU_USER=<usuario> BALBU_PASS=<clave> bash db/test-menus-eof.sh
# El repo no guarda credenciales: hay que exportarlas, mismo criterio que
# db/test-contratos-subir.sh con DB_PASSWORD. Se usan para el atajo de dev
# de main.cpp (BALBU_USER/BALBU_PASS), que saltea el login y entra al menu.
set -u

APP="${APP:-./output/app}"
LIMITE="${LIMITE:-5}"          # segundos antes de declarar "colgado"
fail=0

if [ ! -x "$APP" ]; then
  echo "FALTA el binario $APP: corre 'bash build.sh' primero."
  exit 1
fi

if [ -z "${BALBU_USER:-}" ] || [ -z "${BALBU_PASS:-}" ]; then
  echo "FALTA BALBU_USER / BALBU_PASS: exportalos antes de correr (el repo no guarda credenciales)."
  exit 1
fi

TMP="$(mktemp -d /tmp/opencode/menus-eof.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Corre la app con la entrada dada. Deja la salida en $2 y devuelve el exit
# code (124 = la mato el timeout, o sea que quedo girando).
correr() {
  printf '%b' "$1" | timeout "$LIMITE" "$APP" >"$2" 2>&1
  echo $?
}

# Verifica que de verdad entro al menu (si el login de dev falla, el test
# daria verde sin haber tocado el menu: falso positivo).
entroAlMenu() {
  grep -q "Acceso concedido \[DEV\]" "$1"
}

revisar() {   # $1 = nombre del caso, $2 = entrada
  local salida="$TMP/out.txt" rc
  rc=$(correr "$2" "$salida")

  if ! entroAlMenu "$salida"; then
    echo "FALLO $1: no entro al menu (¿BALBU_USER/BALBU_PASS invalidos? ¿BD caida?)"
    fail=1
    return
  fi

  if [ "$rc" = "124" ]; then
    echo "FALLO $1: giro sin fin (timeout ${LIMITE}s)."
    fail=1
  elif [ "$rc" = "1" ]; then
    echo "FALLO $1: la app salio con exit 1."
    fail=1
  elif [ "$rc" != "0" ]; then
    echo "FALLO $1: exit $rc (se esperaba 0)."
    fail=1
  else
    echo "OK $1"
  fi
}

# 1. Regresion: la entrada normal debe seguir funcionando. El primer cin.get()
#    de main se come el '\n'; despues el menu principal lee el 0 y sale.
revisar "entrada normal (opcion 0 sale)"    '\n0\n'

# 2. El bug: entrada agotada -> debe salir, no girar.
revisar "entrada agotada (EOF)"             ''

# 3. Basura y despues EOF -> tampoco debe girar.
revisar "opcion invalida y luego EOF"       '\nabc\n'

if [ "$fail" -eq 0 ]; then
  echo "TODOS LOS TESTS DE MENUS-EOF OK"
else
  echo "TESTS MENUS-EOF: FALLAS ARRIBA"
fi
exit $fail
