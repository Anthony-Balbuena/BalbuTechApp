#!/usr/bin/env bash
# (18/11/2026) Tests de la nomina: pagar los bonos dentro del sueldo del mes.
#
# POR QUE EXISTE: "pagar un bono" solo cambiaba ESTADO a PAGADO. No quedaba
# cuando ni quien, y el recibo de nomina (SP_GENERAR_RECIBO_EMPLEADO) ni siquiera
# leia BONOS_EMPLEADOS. La decision del dueno fue que el bono integra el sueldo
# del mes y que el recibo arrastra los PENDIENTE de meses anteriores.
#
# Cubre:
#   1. Las columnas de auditoria existen (FECHA_PAGO, PAGADO_POR).
#   2. SP_PAGAR_BONO deja fecha y pagador; sin sesion el pagador queda NULL y no
#      se inventa. El pagador de un bono ya PAGADO no se puede reescribir.
#   3. El recibo suma los bonos pendientes de CUALQUIER mes (arrastre) y no toca
#      SUELDO_BRUTO ni los descuentos: el tratamiento previsional del bono es
#      tema del contador y este SP no lo decide.
#   4. El recibo NO marca nada: se puede mirar veinte veces y los bonos siguen
#      PENDIENTE.
#   5. SP_PAGAR_NOMINA_EMPLEADO paga todo lo pendiente del empleado con fecha y
#      actor; la segunda vez avisa y no paga de nuevo.
#   6. Un empleado INACTIVO (despedido) igual cobra sus bonos pendientes.
#   7. El detalle por empleado lista solo lo suyo y solo lo PENDIENTE.
#
# Todo corre DENTRO de una transaccion que se revierte: no deja datos. La sesion
# se arma con un token de verdad, porque FN_USUARIO_SESION() es lo que llena
# PAGADO_POR (el bypass de admin no sirve: con root no hay sesion).
#
# Uso: DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave> \
#      bash db/test-nomina.sh
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

M() { mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" --database="$DB_NAME" -N -B "$@" 2>&1; }

# Las rutinas que este test ejercita tienen que existir: si falta alguna, un
# verde no significaria nada.
faltan=$(M -e "SELECT COUNT(*) FROM information_schema.ROUTINES
               WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE='PROCEDURE'
                 AND ROUTINE_NAME IN ('SP_PAGAR_BONO', 'SP_REGISTRAR_BONO',
                                      'SP_GENERAR_RECIBO_EMPLEADO',
                                      'SP_PAGAR_NOMINA_EMPLEADO',
                                      'SP_LISTAR_BONOS_PENDIENTES_EMPLEADO');")
if [ "$faltan" != "5" ]; then
    echo "FALLO: faltan rutinas de nomina ($faltan/5). Aplica los modulos 8 y 14 en $DB_NAME." >&2
    exit 1
fi

# S1: las columnas de auditoria. Sin ellas el resto del test no prueba nada.
columnas=$(M -e "SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'BONOS_EMPLEADOS'
                   AND COLUMN_NAME IN ('FECHA_PAGO', 'PAGADO_POR');")
if [ "$columnas" != "2" ]; then
    echo "FALLO: faltan las columnas de pago en BONOS_EMPLEADOS ($columnas/2). Aplica el modulo 14 en $DB_NAME." >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK. La ausencia del efecto se verifica aparte.
OUT=$(M --force <<'SQL'
START TRANSACTION;

-- Empleado de prueba: salario redondo para que los descuentos den exacto.
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('ZZ NOMINA TEST', 'ZZNOM001', 'PRUEBA', 10000.00, 'ZZ-NOM-01', 'zz-nom-01@test.local', CURDATE());
SET @emp = LAST_INSERT_ID();

-- Sesion real: FN_USUARIO_SESION() exige token vigente y cuenta ACTIVA.
SET @usr = (SELECT USUARIO FROM USUARIOS WHERE ESTADO = 'ACTIVO' ORDER BY ID_USUARIO LIMIT 1);
SET @id_usr = (SELECT ID_USUARIO FROM USUARIOS WHERE USUARIO = @usr);
INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA)
VALUES (REPEAT('n', 64), @id_usr, DATE_ADD(NOW(), INTERVAL 1 HOUR));
SET @TOKEN_SESION = REPEAT('n', 64);
SELECT CONCAT('USR=', @usr) AS dato;

-- Un bono de hace 45 dias (mes anterior seguro) y uno de esta semana.
CALL SP_REGISTRAR_BONO(@emp, DATE_SUB(CURDATE(), INTERVAL 45 DAY), 'BONIFICACION', 100.00, 'ZZ nomina viejo');
SET @b_viejo = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ nomina viejo');
CALL SP_REGISTRAR_BONO(@emp, DATE_SUB(CURDATE(), INTERVAL 5 DAY), 'HORAS_EXTRA', 50.00, 'ZZ nomina nuevo');
SET @b_nuevo = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ nomina nuevo');

SELECT IF(@b_viejo > 0 AND @b_nuevo > @b_viejo,
  'OK los dos bonos del test se registraron', 'FALLO no se registraron los bonos') AS prueba;

-- =====================================================================
-- A. El recibo suma los bonos y NO marca nada
-- =====================================================================
SELECT 'RECIBO_INI';
CALL SP_GENERAR_RECIBO_EMPLEADO(@emp);
SELECT 'RECIBO_FIN';

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO = @emp AND ESTADO = 'PENDIENTE') = 2,
  'OK el recibo no marca nada: los dos bonos siguen PENDIENTE',
  'FALLO el recibo marco algun bono') AS prueba;

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS
            WHERE ID_EMPLEADO = @emp AND (FECHA_PAGO IS NOT NULL OR PAGADO_POR IS NOT NULL)) = 0,
  'OK el recibo no escribe fecha ni pagador',
  'FALLO el recibo dejo rastro de un pago que nadie hizo') AS prueba;

-- =====================================================================
-- B. Detalle por empleado
-- =====================================================================
SELECT 'DETALLE_INI';
CALL SP_LISTAR_BONOS_PENDIENTES_EMPLEADO(@emp);
SELECT 'DETALLE_FIN';

-- =====================================================================
-- C. Pagar la nomina (arrastre de los dos meses)
-- =====================================================================
SELECT 'PAGO_INI';
CALL SP_PAGAR_NOMINA_EMPLEADO(@emp);
SELECT 'PAGO_FIN';

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO = @emp AND ESTADO = 'PAGADO') = 2,
  'OK pagar la nomina marca los dos bonos, tambien el del mes anterior',
  'FALLO no marco los dos bonos') AS prueba;

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS
            WHERE ID_EMPLEADO = @emp AND FECHA_PAGO = CURDATE()) = 2,
  'OK los dos bonos quedaron con la fecha de pago de hoy',
  'FALLO falta la fecha de pago') AS prueba;

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS
            WHERE ID_EMPLEADO = @emp AND PAGADO_POR = @usr) = 2,
  'OK el pagador es el usuario de la sesion', 'FALLO el pagador no es el de la sesion') AS prueba;

-- Segunda vez: no hay nada que pagar y eso NO es un error.
SELECT 'PAGO2_INI';
CALL SP_PAGAR_NOMINA_EMPLEADO(@emp);
SELECT 'PAGO2_FIN';

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS WHERE ID_EMPLEADO = @emp AND ESTADO = 'PAGADO') = 2,
  'OK pagar dos veces no duplica ni rompe nada', 'FALLO pagar dos veces altero los bonos') AS prueba;

SELECT 'DETALLE2_INI';
CALL SP_LISTAR_BONOS_PENDIENTES_EMPLEADO(@emp);
SELECT 'DETALLE2_FIN';

-- =====================================================================
-- D. Auditoria del pago de un bono suelto
-- =====================================================================
CALL SP_REGISTRAR_BONO(@emp, CURDATE(), 'BONIFICACION', 77.00, 'ZZ nomina suelto');
SET @b3 = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ nomina suelto');

CALL SP_PAGAR_BONO(@b3);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b3) = 'PAGADO',
  'OK pagar un bono suelto lo deja PAGADO', 'FALLO el bono suelto no quedo PAGADO') AS prueba;
SELECT IF((SELECT FECHA_PAGO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b3) = CURDATE(),
  'OK el pago suelto registra la fecha', 'FALLO el pago suelto no registro la fecha') AS prueba;
SELECT IF((SELECT PAGADO_POR FROM BONOS_EMPLEADOS WHERE ID_BONO = @b3) = @usr,
  'OK el pago suelto registra quien lo pago', 'FALLO el pago suelto no registro el pagador') AS prueba;

-- La auditoria es historia: un bono pagado no puede cambiar de pagador.
UPDATE BONOS_EMPLEADOS SET PAGADO_POR = 'otro_usuario' WHERE ID_BONO = @b3;
SELECT IF((SELECT PAGADO_POR FROM BONOS_EMPLEADOS WHERE ID_BONO = @b3) = @usr,
  'OK el pagador de un bono PAGADO no se puede reescribir',
  'FALLO dejo reescribir quien pago un bono ya pagado') AS prueba;

-- Sin sesion no hay pagador: la columna queda NULL y no se inventa un nombre.
SET @TOKEN_SESION = NULL;
CALL SP_REGISTRAR_BONO(@emp, CURDATE(), 'BONIFICACION', 30.00, 'ZZ nomina sin sesion');
SET @b4 = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ nomina sin sesion');

CALL SP_PAGAR_BONO(@b4);
SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b4) = 'PAGADO',
  'OK sin sesion el bono igual se puede pagar', 'FALLO sin sesion no dejo pagar') AS prueba;
SELECT IF((SELECT PAGADO_POR FROM BONOS_EMPLEADOS WHERE ID_BONO = @b4) IS NULL,
  'OK sin sesion el pagador queda vacio en vez de inventado',
  'FALLO invento un pagador sin sesion') AS prueba;
SET @TOKEN_SESION = REPEAT('n', 64);

-- =====================================================================
-- E. Un despedido igual cobra sus bonos
-- =====================================================================
UPDATE EMPLEADOS SET ESTADO = 'INACTIVO', FECHA_DESPIDO = CURDATE() WHERE ID_EMPLEADO = @emp;
CALL SP_REGISTRAR_BONO(@emp, CURDATE(), 'BONIFICACION', 20.00, 'ZZ nomina despedido');
SET @b5 = (SELECT MAX(ID_BONO) FROM BONOS_EMPLEADOS WHERE DESCRIPCION = 'ZZ nomina despedido');

SELECT 'RECIBO_INACTIVO_INI';
CALL SP_GENERAR_RECIBO_EMPLEADO(@emp);
SELECT 'RECIBO_INACTIVO_FIN';

SELECT 'PAGO_INACTIVO_INI';
CALL SP_PAGAR_NOMINA_EMPLEADO(@emp);
SELECT 'PAGO_INACTIVO_FIN';

SELECT IF((SELECT ESTADO FROM BONOS_EMPLEADOS WHERE ID_BONO = @b5) = 'PAGADO',
  'OK un empleado despedido igual cobra el bono que quedo pendiente',
  'FALLO no dejo pagarle a un despedido') AS prueba;

-- =====================================================================
-- F. Frenos: empleado inexistente y sin bonos
-- =====================================================================
CALL SP_PAGAR_NOMINA_EMPLEADO(999999);

SELECT IF((SELECT COUNT(*) FROM BONOS_EMPLEADOS
            WHERE DESCRIPCION LIKE 'ZZ nomina%' AND ESTADO = 'PENDIENTE') = 0,
  'OK los bonos del test quedaron todos pagados',
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

usr=$(printf '%s\n' "$OUT" | grep '^USR=' | head -1 | cut -d= -f2)

# A. El recibo: columnas 7 bruto, 10 neto, 11 cantidad, 12 total bonos, 13 total.
recibo=$(seccion RECIBO_INI RECIBO_FIN | head -1)
r_bruto=$(printf '%s' "$recibo"  | awk -F'\t' '{print $7}')
r_neto=$(printf '%s'  "$recibo" | awk -F'\t' '{print $10}')
r_cant=$(printf '%s'  "$recibo" | awk -F'\t' '{print $11}')
r_bonos=$(printf '%s' "$recibo" | awk -F'\t' '{print $12}')
r_total=$(printf '%s' "$recibo" | awk -F'\t' '{print $13}')

if [ "$r_bruto" = "10000.00" ]; then
    echo "  OK el recibo no cambio el sueldo bruto (10000.00)"
    oks=$((oks + 1))
else
    echo "  FALLO el sueldo bruto cambio (bruto='$r_bruto')"
    fallos=$((fallos + 1))
fi

if [ "$r_neto" = "9409.00" ]; then
    echo "  OK el neto sigue siendo sueldo menos SFS y AFP (9409.00)"
    oks=$((oks + 1))
else
    echo "  FALLO el neto cambio (neto='$r_neto')"
    fallos=$((fallos + 1))
fi

if [ "$r_cant" = "2" ] && [ "$r_bonos" = "150.00" ]; then
    echo "  OK el recibo suma los dos bonos pendientes (2 por 150.00)"
    oks=$((oks + 1))
else
    echo "  FALLO el recibo no sumo los bonos (cant='$r_cant' bonos='$r_bonos')"
    fallos=$((fallos + 1))
fi

if [ "$r_total" = "9559.00" ]; then
    echo "  OK el total a pagar es neto mas bonos (9559.00)"
    oks=$((oks + 1))
else
    echo "  FALLO el total a pagar no es neto mas bonos (total='$r_total')"
    fallos=$((fallos + 1))
fi

# B. El detalle trae los dos bonos, el viejo primero.
detalle=$(seccion DETALLE_INI DETALLE_FIN)
detalle_n=$(printf '%s\n' "$detalle" | grep -cE '^[0-9]+' || true)
detalle_primero=$(printf '%s\n' "$detalle" | grep -E '^[0-9]+' | head -1 | awk -F'\t' '{print $5}')
if [ "$detalle_n" = "2" ] && [ "$detalle_primero" = "ZZ nomina viejo" ]; then
    echo "  OK el detalle lista los dos pendientes, el mas viejo primero"
    oks=$((oks + 1))
else
    echo "  FALLO el detalle no liste los dos pendientes en orden (n='$detalle_n' primero='$detalle_primero')"
    fallos=$((fallos + 1))
fi

# C. Mensajes del pago.
if seccion PAGO_INI PAGO_FIN | grep -q 'EXITO: SE PAGARON 2 BONO'; then
    echo "  OK el pago informa cuantos bonos pago"
    oks=$((oks + 1))
else
    echo "  FALLO el pago no informo los bonos pagados"
    fallos=$((fallos + 1))
fi

if seccion PAGO2_INI PAGO2_FIN | grep -q 'AVISO:'; then
    echo "  OK pagar dos veces avisa que no habia nada pendiente"
    oks=$((oks + 1))
else
    echo "  FALLO pagar dos veces no aviso nada"
    fallos=$((fallos + 1))
fi

# D. Despues de pagar, el detalle queda vacio.
detalle2=$(seccion DETALLE2_INI DETALLE2_FIN | grep -cE '^[0-9]+' || true)
if [ "$detalle2" = "0" ]; then
    echo "  OK despues de pagar el detalle no lista nada"
    oks=$((oks + 1))
else
    echo "  FALLO el detalle sigue listando bonos ya pagados ('$detalle2')"
    fallos=$((fallos + 1))
fi

# E. El recibo de un despedido se emite igual y muestra su estado.
recibo_inactivo=$(seccion RECIBO_INACTIVO_INI RECIBO_INACTIVO_FIN | head -1)
r_estado=$(printf '%s' "$recibo_inactivo" | awk -F'\t' '{print $6}')
if [ "$r_estado" = "INACTIVO" ]; then
    echo "  OK el recibo de un despedido se emite y muestra el estado"
    oks=$((oks + 1))
else
    echo "  FALLO el recibo de un despedido no muestra el estado (estado='$r_estado')"
    fallos=$((fallos + 1))
fi

# Los frenos tienen que haberse disparado: si no, el test no probo nada.
for freno in "EL EMPLEADO NO EXISTE" "PAGADO O ANULADO NO CAMBIA"; do
    if printf '%s\n' "$OUT" | grep -q "$freno"; then
        echo "  OK freno: $freno"
        oks=$((oks + 1))
    else
        echo "  FALLO no se disparo el freno: $freno"
        fallos=$((fallos + 1))
    fi
done

echo
if [ "$fallos" -eq 0 ]; then
    echo "TEST DE NOMINA OK ($oks comprobaciones)"
    exit 0
fi
echo "TEST DE NOMINA: $fallos fallo(s)"
echo "--- salida completa ---"
printf '%s\n' "$OUT" | sed 's/^/  /'
exit 1
