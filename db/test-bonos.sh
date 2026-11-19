#!/usr/bin/env bash
# (18/11/2026) Tests del modulo 14 (BONOS_EMPLEADOS).
#
# POR QUE EXISTE: la viva tenia 11 bonos PENDIENTE por $10.330 que nadie podia
# ver ni pagar. Los genera un trigger (TR_AUTO_FINALIZAR_VENTA, modulo 24) y no
# habia pantalla. Cablear la pantalla sin red es justo lo que no se hace.
#
# Cubre:
#   1. Alta manual: queda PENDIENTE con su monto y su tipo.
#   2. Los frenos del alta: monto > 100000, tipo desconocido, fecha de mas de
#      60 dias (TR_VALIDAR_FECHA_BONO).
#   3. Listado paginado por estado: la pagina 1 trae el bono nuevo y el CONTAR
#      coincide con la tabla.
#   4. Pagar: PENDIENTE -> PAGADO. Pagar dos veces avisa. Un ANULADO no se paga.
#   5. Anular: PENDIENTE -> ANULADO. Anular dos veces avisa. Un PAGADO no se
#      anula ni se le cambia el monto (TR_BLOQUEAR_CAMBIO_BONO).
#   6. VISTA_TOTAL_BONOS_POR_EMPLEADO no cuenta lo ANULADO como bonificado.
#
# Todo corre DENTRO de una transaccion que se revierte: no deja datos.
# No necesita el binario de la app: es SQL puro.
#
# Uso: DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave> \
#      bash db/test-bonos.sh
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

cd "$(dirname "$0")/.." || exit 1

M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" "$@" 2>&1; }

# Las rutinas que este test ejercita tienen que existir. Si falta alguna, el
# test no puede decir nada: mejor cortar que dar un verde vacio.
faltan=$(M -N -B -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                   WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE='PROCEDURE'
                     AND ROUTINE_NAME IN ('SP_REGISTRAR_BONO', 'SP_PAGAR_BONO',
                                          'SP_ANULAR_BONO', 'SP_LISTAR_BONOS_PAGINADO',
                                          'SP_CONTAR_BONOS');")
if [ "$faltan" != "5" ]; then
    echo "FALLO: faltan rutinas del modulo de bonos ($faltan/5). Aplica el modulo 14 en $DB_NAME." >&2
    exit 1
fi

# El listado sin paginar se retiro: si volviera, seria una segunda forma de
# leer lo mismo (y otra cosa que mantener).
viejo=$(M -N -B -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                    WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_LISTAR_BONOS';")
if [ "$viejo" != "0" ]; then
    echo "FALLO: SP_LISTAR_BONOS volvio a existir; el paginado lo reemplazo." >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK. La ausencia del efecto se verifica aparte.
OUT=$(M --force <<'SQL'
START TRANSACTION;

SET @emp = (SELECT MIN(ID_EMPLEADO) FROM EMPLEADOS);
SET @hoy = CURDATE();

-- =====================================================================
-- A. Alta manual
-- =====================================================================
CALL SP_REGISTRAR_BONO(@emp, @hoy, 'BONIFICACION', 1000.00, 'ZZ bono del test');
SET @b1 = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ bono del test');
SELECT CONCAT('BONO1=', @b1) AS dato;

SELECT IF(@b1 IS NOT NULL AND @b1 > 0,
  'OK el bono se registro', 'FALLO el bono no se registro') AS prueba;
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 'PENDIENTE',
  'OK el bono nuevo queda PENDIENTE', 'FALLO el bono no quedo PENDIENTE') AS prueba;
SELECT IF((SELECT MONTO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 1000.00,
  'OK el monto es el que se pidio', 'FALLO el monto no coincide') AS prueba;
SELECT IF((SELECT TIPO_BONO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 'BONIFICACION',
  'OK el tipo es el que se pidio', 'FALLO el tipo no coincide') AS prueba;

-- B. Frenos del alta
CALL SP_REGISTRAR_BONO(@emp, @hoy, 'BONIFICACION', 100001.00, 'ZZ monto excedido');
SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ monto excedido') = 0,
  'OK no dejo registrar un monto mayor a 100000', 'FALLO acepto un monto fuera de tope') AS prueba;

CALL SP_REGISTRAR_BONO(@emp, @hoy, 'BONO_INVENTADO', 100.00, 'ZZ tipo invalido');
SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ tipo invalido') = 0,
  'OK no dejo registrar un tipo desconocido', 'FALLO acepto un tipo desconocido') AS prueba;

CALL SP_REGISTRAR_BONO(@emp, DATE_SUB(@hoy, INTERVAL 61 DAY), 'BONIFICACION', 100.00, 'ZZ fecha vieja');
SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ fecha vieja') = 0,
  'OK no dejo registrar un bono de hace mas de 60 dias', 'FALLO acepto una fecha vieja') AS prueba;

-- =====================================================================
-- C. Listado paginado (se compara en bash: un CALL no se lee como valor)
-- =====================================================================
SELECT 'FASE_CONTAR' AS marca;
CALL SP_CONTAR_BONOS('PENDIENTE');
SELECT 'FASE_CONTAR_ESPERADO' AS marca;
SELECT COUNT(*) AS TOTAL FROM BONOS_EMPLEADOS WHERE ESTADO = 'PENDIENTE';
SELECT 'FASE_CONTAR_FIN' AS marca;

SELECT 'FASE_PAGINA' AS marca;
CALL SP_LISTAR_BONOS_PAGINADO('PENDIENTE', 1, 10);
SELECT 'FASE_PAGINA_FIN' AS marca;

-- =====================================================================
-- D. Pagar
-- =====================================================================
CALL SP_PAGAR_BONO(@b1);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 'PAGADO',
  'OK pagar deja el bono en PAGADO', 'FALLO el bono no quedo PAGADO') AS prueba;

CALL SP_PAGAR_BONO(@b1);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 'PAGADO',
  'OK pagar dos veces no rompe ni duplica nada', 'FALLO pagar dos veces altero el bono') AS prueba;

CALL SP_ANULAR_BONO(@b1);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 'PAGADO',
  'OK no dejo anular un bono ya PAGADO', 'FALLO anulo un bono PAGADO') AS prueba;

UPDATE BONOS_EMPLEADOS SET MONTO = 5000.00 WHERE ID_BONO = @b1;
SELECT IF((SELECT MONTO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b1) = 1000.00,
  'OK el monto de un bono PAGADO no se puede cambiar',
  'FALLO dejo cambiar el monto de un PAGADO') AS prueba;

-- =====================================================================
-- E. Anular
-- =====================================================================
CALL SP_REGISTRAR_BONO(@emp, @hoy, 'HORAS_EXTRA', 250.00, 'ZZ bono a anular');
SET @b2 = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ bono a anular');

SET @total_antes = (SELECT IFNULL(TOTAL_BONIFICADO, 0) FROM VISTA_TOTAL_BONOS_POR_EMPLEADO
                     WHERE ID_EMPLEADO = @emp);

CALL SP_ANULAR_BONO(@b2);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b2) = 'ANULADO',
  'OK anular deja el bono en ANULADO', 'FALLO el bono no quedo ANULADO') AS prueba;

CALL SP_ANULAR_BONO(@b2);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b2) = 'ANULADO',
  'OK anular dos veces no rompe nada', 'FALLO anular dos veces altero el bono') AS prueba;

CALL SP_PAGAR_BONO(@b2);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b2) = 'ANULADO',
  'OK no dejo pagar un bono ANULADO', 'FALLO pago un bono ANULADO') AS prueba;

-- La vista NO tiene que contar lo anulado como dinero bonificado.
SET @total_desp = (SELECT IFNULL(TOTAL_BONIFICADO, 0) FROM VISTA_TOTAL_BONOS_POR_EMPLEADO
                    WHERE ID_EMPLEADO = @emp);
SELECT IF(@total_desp = @total_antes - 250.00,
  'OK la vista deja de contar el bono ANULADO como bonificado',
  'FALLO la vista sigue contando lo anulado') AS prueba;

-- =====================================================================
-- F. Cierre
-- =====================================================================
SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS
            WHERE DESCRIPCION LIKE 'ZZ%' AND ESTADO = 'PENDIENTE') = 0,
  'OK los bonos del test quedaron PAGADO o ANULADO',
  'FALLO quedo algun bono del test en PENDIENTE') AS prueba;

ROLLBACK;
SQL
)

# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
fallos=$(printf '%s\n' "$OUT" | grep -c "^FALLO" || true)
oks=$(printf '%s\n' "$OUT" | grep -c "^OK" || true)

printf '%s\n' "$OUT" | grep "^OK" | sed 's/^/  /'

# Seccion entre dos marcas (el cliente imprime la marca como fila propia).
seccion() {
    printf '%s\n' "$OUT" | awk -v a="$1" -v b="$2" '$0 == a {on=1; next} $0 == b {on=0} on'
}

# C1: el CONTAR coincide con la tabla.
cuenta_sp=$(seccion FASE_CONTAR FASE_CONTAR_ESPERADO | grep -E '^[0-9]+$' | head -1)
cuenta_tabla=$(seccion FASE_CONTAR_ESPERADO FASE_CONTAR_FIN | grep -E '^[0-9]+$' | head -1)
if [ -n "$cuenta_sp" ] && [ "$cuenta_sp" = "$cuenta_tabla" ]; then
    echo "  OK el CONTAR de pendientes coincide con la tabla ($cuenta_sp)"
    oks=$((oks + 1))
else
    echo "  FALLO el CONTAR no coincide con la tabla (sp='$cuenta_sp' tabla='$cuenta_tabla')"
    fallos=$((fallos + 1))
fi

# C2: la pagina 1 trae el bono nuevo.
b1=$(printf '%s\n' "$OUT" | grep '^BONO1=' | head -1 | cut -d= -f2)
en_pagina=$(seccion FASE_PAGINA FASE_PAGINA_FIN | awk -F'\t' -v id="$b1" '$1 == id' | wc -l)
if [ -n "$b1" ] && [ "$en_pagina" = "1" ]; then
    echo "  OK el bono nuevo (ID $b1) cae en la primera pagina de pendientes"
    oks=$((oks + 1))
else
    echo "  FALLO el bono nuevo (ID '$b1') no cae en la primera pagina"
    fallos=$((fallos + 1))
fi

# Los frenos tienen que haberse disparado: si no, el test no probo nada.
for freno in "EL MONTO EXCEDE" "TIPO DE BONO DESCONOCIDO" "60 D" \
             "YA HABIA SIDO PAGADO" "QUE YA FUE PAGADO" "QUE ESTA ANULADO" \
             "PAGADO O ANULADO NO CAMBIA"; do
    if ! printf '%s\n' "$OUT" | grep -q "$freno"; then
        echo "NO SE DISPARO el freno esperado: $freno"
        fallos=$((fallos + 1))
    fi
done

echo
if [ "$fallos" -eq 0 ]; then
    echo "TODOS LOS TESTS DE BONOS OK ($oks comprobaciones)"
    exit 0
fi
echo "TESTS DE BONOS: $fallos fallo(s)"
exit 1
