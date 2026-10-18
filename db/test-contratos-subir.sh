#!/usr/bin/env bash
# Tests de "subir contrato = alta automatica de empleado" (S1-S3, S5 del
# feature odd/tasks/contratos-subir-alta.md). Corre contra BALBU_TECH_TEST
# dentro de un START TRANSACTION / ROLLBACK: cero residuos.
# Uso:  bash db/test-contratos-subir.sh
set -u

HOST="${DB_HOST:-127.0.0.1}"
USER="${DB_USER:-root}"
PASS="${DB_PASSWORD:-linux01}"
DB="${DB_NAME:-BALBU_TECH_TEST}"

esperados=(
  "EL TIPO DEBE SER TEMPORAL O FIJO"
  "NECESITA UNA DURACION EN MESES MAYOR A CERO"
  "YA TIENE UN CONTRATO ACTIVO"
  "PERTENECE A UN EMPLEADO INACTIVO"
  "ESE TELEFONO YA PERTENECE A OTRO EMPLEADO"
  "ESE EMAIL YA PERTENECE A OTRO EMPLEADO"
  "NECESITA TELEFONO Y EMAIL REALES"
  "HAY MAS DE UN EMPLEADO CON ESA CEDULA"
)

fail=0

# --- Baseline: ninguna cedula marcador puede existir antes de correr ---
# Si esta sucia, se aborta: seguir daria errores en cascada imposibles de leer.
base=$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" \
  -e "SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA LIKE '302998877%';" 2>/dev/null)
if [ "${base:-0}" != "0" ]; then
  echo "BASE SUCIA: $base filas con cedula marcador antes del test. Limpialas y vuelve a correr:"
  echo "  DELETE FROM CONTRATOS WHERE CEDULA LIKE '302998877%'; DELETE FROM EMPLEADOS WHERE CEDULA LIKE '302998877%';"
  exit 2
fi

# --- Ejecucion ---
OUT=$(mariadb --force -h "$HOST" -u "$USER" -p"$PASS" "$DB" 2>&1 <<'EOF'
START TRANSACTION;

-- Existe: Pedro (registrado a mano antes del contrato)
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('Pedro Prueba', '30299887779', 'Bodeguero', 10000.00, '8095552222', 'pedro.prueba@correo.test', '2026-01-15');
SELECT ID_EMPLEADO INTO @pedro FROM EMPLEADOS WHERE CEDULA = '30299887779';

-- Inactivo
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO, ESTADO)
VALUES ('Inactivo Prueba', '30299887780', 'Auxiliar', 5000.00, '8095553333', 'inactivo.prueba@correo.test', '2026-01-15', 'INACTIVO');

-- Ambigua: dos empleados con la misma cedula (CEDULA no tiene unique)
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('Ambiguo Uno', '30299887781', 'A', 6000.00, '8095554444', 'amb1@correo.test', '2026-01-15');
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('Ambiguo Dos', '30299887781', 'B', 6100.00, '8095555555', 'amb2@correo.test', '2026-01-15');

-- T1: alta de persona NUEVA -> trigger crea empleado y el contrato apunta a su ID
CALL SP_SUBIR_CONTRATO('Maria Prueba', '30299887777', 'Cajera', 12000.00,
  '8095551111', 'maria.prueba@correo.test', '2026-10-18', 'TEMPORAL', 6, 'contratos/test.html');
SELECT ID_CONTRATO INTO @c1 FROM CONTRATOS WHERE CEDULA = '30299887777';
SELECT ID_EMPLEADO INTO @m1 FROM EMPLEADOS WHERE CEDULA = '30299887777';
SELECT IF(@c1 IS NOT NULL AND @m1 IS NOT NULL
  AND (SELECT ID_EMPLEADO FROM CONTRATOS WHERE ID_CONTRATO = @c1) = @m1
  AND (SELECT ESTADO FROM EMPLEADOS WHERE ID_EMPLEADO = @m1) = 'ACTIVO'
  AND (SELECT NOMBRE FROM CONTRATOS WHERE ID_CONTRATO = @c1) = 'Maria Prueba',
  'OK alta nueva', 'FALLO alta nueva') AS prueba;

-- T2: subir contrato a un empleado YA EXISTENTE -> vincula, no duplica
CALL SP_SUBIR_CONTRATO('Pedro Prueba', '30299887779', 'Bodeguero', 10000.00,
  '8095552222', 'pedro.prueba@correo.test', '2026-01-15', 'FIJO', NULL, 'contratos/test2.html');
SELECT IF((SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA = '30299887779') = 1
  AND (SELECT ID_EMPLEADO FROM CONTRATOS WHERE CEDULA = '30299887779') = @pedro,
  'OK vinculo', 'FALLO vinculo') AS prueba;

-- T3: freno un solo contrato ACTIVO por cedula
CALL SP_SUBIR_CONTRATO('Maria Prueba', '30299887777', 'Cajera', 12000.00,
  '8095551111', 'maria.prueba@correo.test', '2026-10-18', 'FIJO', NULL, 'x.html');

-- T4: freno empleado INACTIVO
CALL SP_SUBIR_CONTRATO('Inactivo Prueba', '30299887780', 'Auxiliar', 5000.00,
  '8095553333', 'inactivo.prueba@correo.test', '2026-01-15', 'FIJO', NULL, NULL);

-- T5: freno telefono que ya es de otro empleado (persona nueva)
CALL SP_SUBIR_CONTRATO('Tel Prueba', '30299887782', 'Auxiliar', 9000.00,
  '8095552222', 'tel.ajeno@correo.test', '2026-10-18', 'FIJO', NULL, NULL);

-- T6: persona nueva sin datos reales de contacto (default "-")
CALL SP_SUBIR_CONTRATO('Sin Dato Prueba', '30299887784', 'Auxiliar', 9000.00,
  '-', '-', '2026-10-18', 'FIJO', NULL, NULL);

-- T7: freno email que ya es de otro empleado (persona nueva)
CALL SP_SUBIR_CONTRATO('Mail Prueba', '30299887783', 'Auxiliar', 9000.00,
  '8095556666', 'pedro.prueba@correo.test', '2026-10-18', 'FIJO', NULL, NULL);

-- T8: temporal sin meses
CALL SP_SUBIR_CONTRATO('Meses Prueba', '30299887785', 'Auxiliar', 7000.00,
  '8095557777', 'meses@correo.test', '2026-10-18', 'TEMPORAL', NULL, NULL);

-- T9: tipo invalido
CALL SP_SUBIR_CONTRATO('Tipo Prueba', '30299887785', 'Auxiliar', 7000.00,
  '8095557777', 'meses@correo.test', '2026-10-18', 'INDEFINIDO', NULL, NULL);

-- T10: cedula ambigua -> el trigger frena (no se crea contrato)
CALL SP_SUBIR_CONTRATO('Ambiguo Tres', '30299887781', 'C', 6200.00,
  '8095558888', 'amb3@correo.test', '2026-10-18', 'FIJO', NULL, 't.html');

ROLLBACK;
EOF
)

# --- Verificaciones ---
# 1. Ninguna "FALLO" en las aserciones
if echo "$OUT" | grep -q "FALLO"; then
  echo "$OUT" | grep "FALLO"
  fail=1
fi

# 2. Las dos altas exitosas ocurrieron
n_exit=$(echo "$OUT" | grep -c "EXITO")
if [ "$n_exit" -ne 2 ]; then
  echo "FALTA EXITO: se esperaban 2, hay $n_exit"
  fail=1
fi

# 3. Cada freno esperado se disparo exactamente
for e in "${esperados[@]}"; do
  n=$(echo "$OUT" | grep -c "$e")
  if [ "$n" -lt 1 ]; then
    echo "NO SE DISPARO: $e"
    fail=1
  fi
done

# 4. Ningun ERROR inesperado (p.ej. SP inexistente)
while IFS= read -r line; do
  match=0
  for e in "${esperados[@]}"; do
    case "$line" in *"$e"*) match=1 ;; esac
  done
  if [ "$match" -eq 0 ]; then
    echo "ERROR INESPERADO: $line"
    fail=1
  fi
done < <(echo "$OUT" | grep "^ERROR")

# 5. Residuos: tras ROLLBACK no queda rastro de las cedulas marcador
post=$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" \
  -e "SELECT (SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA LIKE '302998877%')
     + (SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA LIKE '302998877%');" 2>/dev/null)
if [ "${post:-x}" != "0" ]; then
  echo "RESIDUOS: $post filas quedaron tras el rollback"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "TODOS LOS TESTS DE CONTRATOS-SUBIR OK"
else
  echo "TESTS CONTRATOS-SUBIR: FALLAS DETALLADAS ARRIBA"
fi
exit $fail
