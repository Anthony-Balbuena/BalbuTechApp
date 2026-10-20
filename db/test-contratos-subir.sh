#!/usr/bin/env bash
# Tests de "subir contrato" (19/10/2026).
# El contrato se firma ANTES del alta: CONTRATOS es el registro del papel, no
# crea empleados. Si la cedula ya existe en EMPLEADOS se vincula al momento; si
# no, ID_EMPLEADO queda NULL y TR_VINCULAR_CONTRATO lo completa cuando el alta
# ocurre despues.
# Corre contra BALBU_TECH_TEST dentro de un START TRANSACTION / ROLLBACK:
# cero residuos.
# Uso:  DB_PASSWORD=<clave> bash db/test-contratos-subir.sh
set -u

HOST="${DB_HOST:-127.0.0.1}"
USER="${DB_USER:-root}"
PASS="${DB_PASSWORD:-}"
DB="${DB_NAME:-BALBU_TECH_TEST}"

# Sin credencial en el repo: exporta DB_PASSWORD al correr el test.
if [ -z "$PASS" ]; then
  echo "FALTA DB_PASSWORD: exporta la contrasena de MariaDB del usuario $USER antes de correr (el repo no guarda credenciales)."
  exit 1
fi

esperados=(
  "YA TIENE UN CONTRATO ACTIVO"
  "PERTENECE A UN EMPLEADO INACTIVO"
  "HAY MAS DE UN EMPLEADO CON ESA CEDULA"
  "NECESITA UNA DURACION EN MESES MAYOR A CERO"
  "EL TIPO DEBE SER TEMPORAL O FIJO"
)

fail=0

# --- Baseline: ninguna cedula marcador puede existir antes de correr ---
# Si esta sucia, se aborta: seguir daria errores en cascada imposibles de leer.
base=$(mariadb -N -h "$HOST" -u "$USER" -p"$PASS" "$DB" \
  -e "SELECT (SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA LIKE '302998877%')
     + (SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA LIKE '302998877%');" 2>/dev/null)
if [ "${base:-0}" != "0" ]; then
  echo "BASE SUCIA: $base filas con cedula marcador antes del test. Limpialas y vuelve a correr:"
  echo "  DELETE FROM CONTRATOS WHERE CEDULA LIKE '302998877%'; DELETE FROM EMPLEADOS WHERE CEDULA LIKE '302998877%';"
  exit 2
fi

# --- Ejecucion ---
OUT=$(mariadb --force -h "$HOST" -u "$USER" -p"$PASS" "$DB" 2>&1 <<'EOF'
START TRANSACTION;

-- Existe: Pedro (registrado a mano en el modulo de empleados)
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

-- T1: cedula que NO existe -> registra el contrato, NO crea al empleado
CALL SP_SUBIR_CONTRATO('Maria Prueba', '30299887777', 'Cajera', 12000.00,
  '8095551111', 'maria.prueba@correo.test', '2026-10-18', 'TEMPORAL', 6, 'contratos/test.html');
SELECT IF((SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA = '30299887777') = 0
  AND (SELECT COUNT(*) FROM CONTRATOS WHERE CEDULA = '30299887777') = 1
  AND (SELECT ID_EMPLEADO FROM CONTRATOS WHERE CEDULA = '30299887777') IS NULL,
  'OK contrato sin empleado', 'FALLO contrato sin empleado') AS prueba;

-- T1b: FECHA_INICIO sale de la fecha de ingreso (no de CURDATE) y FECHA_FIN
--      del temporal se calcula desde ahi
SELECT IF((SELECT FECHA_INICIO FROM CONTRATOS WHERE CEDULA = '30299887777') = '2026-10-18'
  AND (SELECT FECHA_FIN FROM CONTRATOS WHERE CEDULA = '30299887777') = '2027-04-18',
  'OK fechas desde el ingreso', 'FALLO fechas desde el ingreso') AS prueba;

-- T2: subir contrato a un empleado YA EXISTENTE -> vincula, no duplica
CALL SP_SUBIR_CONTRATO('Pedro Prueba', '30299887779', 'Bodeguero', 10000.00,
  '8095552222', 'pedro.prueba@correo.test', '2026-01-15', 'FIJO', NULL, 'contratos/test2.html');
SELECT IF((SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA = '30299887779') = 1
  AND (SELECT ID_EMPLEADO FROM CONTRATOS WHERE CEDULA = '30299887779') = @pedro
  AND (SELECT NOMBRE FROM CONTRATOS WHERE CEDULA = '30299887779') = 'Pedro Prueba',
  'OK vinculo', 'FALLO vinculo') AS prueba;

-- T2b: FIJO = sin fecha fin
SELECT IF((SELECT FECHA_FIN FROM CONTRATOS WHERE CEDULA = '30299887779') IS NULL,
  'OK fijo sin fecha fin', 'FALLO fijo con fecha fin') AS prueba;

-- T3: freno un solo contrato ACTIVO por cedula
CALL SP_SUBIR_CONTRATO('Pedro Prueba', '30299887779', 'Bodeguero', 10000.00,
  '8095552222', 'pedro.prueba@correo.test', '2026-01-15', 'FIJO', NULL, 'x.html');

-- T4: freno empleado INACTIVO
CALL SP_SUBIR_CONTRATO('Inactivo Prueba', '30299887780', 'Auxiliar', 5000.00,
  '8095553333', 'inactivo.prueba@correo.test', '2026-01-15', 'FIJO', NULL, NULL);

-- T5: cedula ambigua -> el SP frena (no se crea contrato)
CALL SP_SUBIR_CONTRATO('Ambiguo Tres', '30299887781', 'C', 6200.00,
  '8095558888', 'amb3@correo.test', '2026-10-18', 'FIJO', NULL, 't.html');

-- T6: temporal sin meses (cedula sin contrato ni empleado)
CALL SP_SUBIR_CONTRATO('Meses Prueba', '30299887782', 'Auxiliar', 7000.00,
  '8095557777', 'meses@correo.test', '2026-10-18', 'TEMPORAL', NULL, NULL);

-- T7: tipo invalido
CALL SP_SUBIR_CONTRATO('Tipo Prueba', '30299887782', 'Auxiliar', 7000.00,
  '8095557777', 'meses@correo.test', '2026-10-18', 'INDEFINIDO', NULL, NULL);

-- T8: el alta posterior engancha el contrato huerfano (TR_VINCULAR_CONTRATO)
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO)
VALUES ('Maria Prueba', '30299887777', 'Cajera', 12000.00, '8095551111', 'maria.prueba@correo.test', '2026-10-18');
SELECT IF((SELECT ID_EMPLEADO FROM CONTRATOS WHERE CEDULA = '30299887777')
  = (SELECT ID_EMPLEADO FROM EMPLEADOS WHERE CEDULA = '30299887777'),
  'OK trigger vincula al dar el alta', 'FALLO trigger vincula') AS prueba;

-- T9: historial por cedula (antes y despues del alta)
CALL SP_CONTRATOS_POR_CEDULA('30299887777');
CALL SP_CONTRATOS_POR_CEDULA('30299887779');

ROLLBACK;
EOF
)

# --- Verificaciones ---
# 1. Ninguna "FALLO" en las aserciones
if echo "$OUT" | grep -q "FALLO"; then
  echo "$OUT" | grep "FALLO"
  fail=1
fi

# 2. Dos subidas exitosas (T1 huerfano + T2 vinculado)
n_exit=$(echo "$OUT" | grep -c "EXITO")
if [ "$n_exit" -ne 2 ]; then
  echo "FALTA EXITO: se esperaba 2, hay $n_exit"
  fail=1
fi

# 3. El mensaje distingue pendiente de alta y vinculado
if ! echo "$OUT" | grep -q "EMPLEADO PENDIENTE DE ALTA"; then
  echo "NO DICE 'PENDIENTE DE ALTA': $OUT"
  fail=1
fi
if ! echo "$OUT" | grep -q "EMPLEADO VINCULADO"; then
  echo "NO DICE VINCULADO: $OUT"
  fail=1
fi
if echo "$OUT" | grep -q "NUEVO CREADO"; then
  echo "SIGUE DICIENDO 'NUEVO CREADO'"
  fail=1
fi

# 4. El historial por cedula devuelve el contrato
if ! echo "$OUT" | grep -q "Cajera"; then
  echo "EL HISTORIAL POR CEDULA NO DEVOLVIO EL CONTRATO"
  fail=1
fi

# 5. Cada freno esperado se disparo
for e in "${esperados[@]}"; do
  n=$(echo "$OUT" | grep -c "$e")
  if [ "$n" -lt 1 ]; then
    echo "NO SE DISPARO: $e"
    fail=1
  fi
done

# 6. Ningun ERROR inesperado (p.ej. SP inexistente)
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

# 7. Residuos: tras ROLLBACK no queda rastro de las cedulas marcador
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
