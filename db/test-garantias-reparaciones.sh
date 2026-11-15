#!/usr/bin/env bash
# Test del flujo de reparaciones con repuesto (15/11/2026).
# Verifica, contra TEST:
#   - SP_REGISTRAR_AVANCE_REPARACION con repuesto descuenta stock real y deja
#     la bitacora (MOVIMIENTOS_INVENTARIO + HISTORIAL_MOVIMIENTOS_PRODUCTO).
#   - El costo del repuesto se congela desde P_COMPRA (no lo dicta el cliente).
#   - Si no alcanza el stock, frena y NO deja la fila del avance (atomico).
#   - Un producto que no esta marcado ES_REPUESTO no se puede consumir.
#   - Un avance sin repuesto (solo mano de obra) pasa y no toca stock.
#   - SP_FINALIZAR_RECLAMO cierra el reclamo, sella quien cerro y deja auditoria.
#   - Regresion de T13: el ajuste manual de inventario sigue funcionando igual
#     despues de extraer SP_MOVER_STOCK.
# Todo corre en una transaccion que se revierte al final.
# Uso: DB_NAME=BALBU_TECH_TEST bash db/test-garantias-reparaciones.sh
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

# Reimportar los modulos que el test toca: sobre una base existente los 1050
# (tabla existe) y 1061 (indice/columna duplicada) son el resultado esperado.
for MOD in "modulos/9- PRODUCTOS.sql" "modulos/17- INVENTARIO.sql" "modulos/25- GARANTIAS.sql"; do
    log=$(mktemp)
    mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
        --default-character-set=utf8mb4 --database="$DB_NAME" --force \
        < "$MOD" >"$log" 2>&1
    reales=$(grep -E "^ERROR" "$log" | grep -vcE "^ERROR (1050|1061|1265) " || true)
    if [ "$reales" -gt 0 ]; then
        echo "FALLO: $reales error(es) real(es) al aplicar $MOD:" >&2
        grep -E "^ERROR" "$log" | grep -vE "^ERROR (1050|1061|1265) " | head -3 >&2
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
done

# Reimportar reescribe los SPs SIN la guarda de permisos: hay que reponerla o
# check-app-sps.sh falla despues. El test conecta como admin, que la saltea.
if ! python3 db/injectar-guardas.py "$DB_NAME" --aplicar >/dev/null 2>&1; then
    echo "FALLO: no se pudieron reinyectar las guardas" >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK.
# (15/11/2026) La salida de error se GUARDA, no se descarta. Con 2>/dev/null un
# ERROR 1406 (token de 67 caracteres en una columna CHAR(64)) se tragaba y hacia
# fallar 14 casos sin decir por que: se leia como "no inserto la fila" cuando en
# realidad el bloque nunca llego a correr. Al final se reportan los errores que
# NO son reglas de negocio.
ERR=$(mktemp)
OUT=$(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
      --database="$DB_NAME" -N -B --force <<'SQL' 2>"$ERR"
START TRANSACTION;

SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);
SET @usr = (SELECT ID_USUARIO FROM USUARIOS ORDER BY ID_USUARIO LIMIT 1);
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @ID_USUARIO_ACTUAL = @usr;
-- (15/11/2026) El avance valida autorizacion contra la SESION, no contra el
-- parametro. @usr es el admin, que es gerencia (GARANTIAS_ASIGNAR), asi que
-- puede actuar en nombre de otro: los casos de abajo siguen pasando.
-- (15/11/2026) El token tiene que entrar en SESIONES.TOKEN, que es CHAR(64).
-- Con 67 caracteres daba ERROR 1406 y, como el bloque de abajo corre con
-- 2>/dev/null, el error se tragaba y los casos fallaban sin decir por que.
SET @token_ger = 'zzrep_ger_000000000000000000000000000000000000000000000000000000';
INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA)
VALUES (@token_ger, @usr, DATE_ADD(NOW(), INTERVAL 1 HOUR));
SET @TOKEN_SESION = @token_ger;

INSERT INTO CATEGORIAS (NOMBRE) VALUES ('ZZ REP CAT');
SET @cat = LAST_INSERT_ID();
INSERT INTO PROVEEDORES (NOMBRE) VALUES ('ZZ REP PROV');
SET @prov = LAST_INSERT_ID();
INSERT INTO CLIENTES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
VALUES ('ZZ REP CLI', '8090000077', 'zzrep@test.local', 'x');
SET @cli = LAST_INSERT_ID();

-- Repuesto del catalogo: codigo propio, NO se vende, con stock.
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO,
                       ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, ES_REPUESTO)
VALUES ('ZZ REP PIEZA', 'Repuesto de prueba', 100.00, 60.00, 'ZZREP-1', 'ACTIVO',
        @mar, @cat, @prov, 1);
SET @rep = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@rep, 5, 1, 'ZZ');

-- Producto vendible normal (no es repuesto).
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO,
                       ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, ES_REPUESTO)
VALUES ('ZZ REP VENDIBLE', 'Vendible de prueba', 100.00, 60.00, 'ZZREP-2', 'ACTIVO',
        @mar, @cat, @prov, 0);
SET @vend = LAST_INSERT_ID();
INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@vend, 5, 1, 'ZZ');

-- Cadena: venta -> detalle -> garantia -> reclamo -> asignacion
INSERT INTO VENTAS (ESTADO, ID_EMPLEADO, ID_CLIENTE, TOTAL)
VALUES ('EN_PROCESO', @emp, @cli, 0);
SET @venta = LAST_INSERT_ID();
INSERT INTO DETALLES_VENTA (ID_VENTA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
VALUES (@venta, @vend, 1, 100.00, 0.00);
SET @det = LAST_INSERT_ID();
INSERT INTO GARANTIAS (ID_DETALLE_VENTA, FECHA_INICIO, FECHA_FIN, ESTADO, ID_EMPLEADO)
VALUES (@det, CURRENT_DATE, DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY), 'ACTIVA', @emp);
SET @gar = LAST_INSERT_ID();
INSERT INTO RECLAMOS_GARANTIAS (ID_GARANTIA, DESCRIPCION, ESTADO, ID_EMPLEADO)
VALUES (@gar, 'Probe de reparacion', 'PENDIENTE', @emp);
SET @rec = LAST_INSERT_ID();
INSERT INTO ASIGNACIONES_RECLAMOS (ID_RECLAMO_GARAN, ID_EMPLEADO, PRIORIDAD, ESTADO_ASIGNACION)
VALUES (@rec, @emp, 'MEDIA', 'EN_PROCESO');
SET @asi = LAST_INSERT_ID();

-- 1. Avance CON repuesto: descuenta stock y deja bitacora.
CALL SP_REGISTRAR_AVANCE_REPARACION(@asi, @usr, 'Cambio de pieza', @rep, 2, 0, 30, 'EN_PROCESO', NULL);
SELECT 'REP_STOCK_BAJA',      IF(STOCK_ACTUAL = 3, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;
SELECT 'REP_FILA',            IF(COUNT(*) = 1, 'OK', 'FAIL') FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asi AND ID_PRODUCTO = @rep AND CANTIDAD_REPUESTO = 2;
SELECT 'REP_COSTO_CONGELADO', IF(COSTO_REPUESTO = 120.00, 'OK', CONCAT('FAIL(', COSTO_REPUESTO, ')')) FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asi;
SELECT 'REP_MOVIMIENTO',      IF(COUNT(*) = 1, 'OK', 'FAIL') FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO = @rep AND TIPO_MOVIMIENTO = 'SALIDA' AND OBSERVACION = CONCAT('Repuesto para reparacion #', @asi);
SELECT 'REP_HISTORIAL',       IF(COUNT(*) = 1, 'OK', 'FAIL') FROM HISTORIAL_MOVIMIENTOS_PRODUCTO WHERE ID_PRODUCTO = @rep AND STOCK_ANTERIOR = 5 AND STOCK_NUEVO = 3;
SELECT 'REP_ACTOR_BITACORA',  IF(COUNT(*) = 1, 'OK', 'FAIL') FROM MOVIMIENTOS_INVENTARIO WHERE ID_PRODUCTO = @rep AND ID_EMPLEADO = @emp;

-- 2. Cantidad mayor al stock: frena y NO deja fila (el avance es atomico).
CALL SP_REGISTRAR_AVANCE_REPARACION(@asi, @usr, 'Intento excesivo', @rep, 99, 0, 10, 'EN_PROCESO', NULL);
SELECT 'EXCESO_SIN_FILA',     IF(COUNT(*) = 1, 'OK', CONCAT('FAIL(', COUNT(*), ')')) FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asi;
SELECT 'EXCESO_STOCK_INTACTO',IF(STOCK_ACTUAL = 3, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;

-- 3. Producto NO marcado como repuesto: frena y no toca su stock.
--    La linea de venta del fixture ya le bajo 1 al insertarse (trigger de venta),
--    asi que se compara contra el stock de ANTES de la llamada.
SET @vend_antes = (SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = @vend);
CALL SP_REGISTRAR_AVANCE_REPARACION(@asi, @usr, 'Producto vendible', @vend, 1, 0, 10, 'EN_PROCESO', NULL);
SELECT 'NO_REPUESTO_FRENA',   IF(COUNT(*) = 1, 'OK', CONCAT('FAIL(', COUNT(*), ')')) FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asi;
SELECT 'NO_REPUESTO_STOCK',   IF(STOCK_ACTUAL = @vend_antes, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ' vs ', @vend_antes, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @vend;

-- 4. Avance SIN repuesto (solo mano de obra): pasa y no toca stock.
CALL SP_REGISTRAR_AVANCE_REPARACION(@asi, @usr, 'Solo mano de obra', NULL, NULL, 500.00, 20, 'EN_PROCESO', NULL);
SELECT 'SIN_REPUESTO_PASA',   IF(COUNT(*) = 1, 'OK', 'FAIL') FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asi AND ID_PRODUCTO IS NULL AND COSTO_REPUESTO = 500.00;

-- 5. Cierre por asignacion: cierra el reclamo, sella quien cerro y deja auditoria.
CALL SP_FINALIZAR_RECLAMO(@asi, 'cerrado en el test');
SELECT 'CIERRE_RECLAMO',      IF(ESTADO = 'CERRADO', 'OK', CONCAT('FAIL(', ESTADO, ')')) FROM RECLAMOS_GARANTIAS WHERE ID_RECLAMO_GARAN = @rec;
SELECT 'CIERRE_ASIGNACION',   IF(ESTADO_ASIGNACION = 'COMPLETADO', 'OK', 'FAIL') FROM ASIGNACIONES_RECLAMOS WHERE ID_ASIGNACION = @asi;
SELECT 'CIERRE_FECHA',        IF(FECHA_CIERRE IS NOT NULL, 'OK', 'FAIL') FROM RECLAMOS_GARANTIAS WHERE ID_RECLAMO_GARAN = @rec;
SELECT 'CIERRE_AUDITORIA',    IF(COUNT(*) = 1, 'OK', 'FAIL') FROM AUDITORIA_SISTEMA WHERE TABLA_AFECTADA = 'RECLAMOS_GARANTIAS' AND ID_REGISTRO_AFECTADO = @rec AND ACCION = 'UPDATE' AND VALOR_ANTERIOR = 'PENDIENTE' AND VALOR_NUEVO = 'CERRADO';

-- 6. Regresion de T13: el ajuste manual de inventario sigue igual.
CALL 20_SP_REGISTRAR_AJUSTE_INVENTARIO(@rep, @emp, 'ENTRADA', 4, 'ZZ ajuste manual');
SELECT 'AJUSTE_ENTRADA_OK',   IF(STOCK_ACTUAL = 7, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;
CALL 20_SP_REGISTRAR_AJUSTE_INVENTARIO(@rep, @emp, 'SALIDA', 999, 'ZZ ajuste excesivo');
SELECT 'AJUSTE_INSUF_FRENA',  IF(STOCK_ACTUAL = 7, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;

-- 7. T11: el flag ES_REPUESTO entra por el alta de producto (10mo parametro).
CALL SP_INSERTAR_PRODUCTO('ZZ REP ALTA', 'alta por SP', 10.00, 20.00, 'ZZREP-ALTA',
                          @mar, @cat, @prov, NULL, 1);
SELECT 'PRODUCTO_ES_REPUESTO', IF(COUNT(*) = 1, 'OK', 'FAIL') FROM PRODUCTOS WHERE CODIGO = 'ZZREP-ALTA' AND ES_REPUESTO = 1;

-- 8. T12: la guarda fuerte. El vendedor no puede vender un repuesto.
CALL SP_AGREGAR_DETALLE_VENTA(@venta, @rep, 1, @emp, 0);
SELECT 'VENTA_REPUESTO_FRENA', IF(COUNT(*) = 0, 'OK', CONCAT('FAIL(', COUNT(*), ')')) FROM DETALLES_VENTA WHERE ID_VENTA = @venta AND ID_PRODUCTO = @rep;

-- 9. AUTORIZACION del avance (15/11/2026): un tecnico solo toca SUS asignaciones.
--    Empleados propios porque USUARIOS.ID_EMPLEADO es UNIQUE.
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO, ESTADO)
VALUES ('ZZ REP TEC ASIGNADO', 'ZZREP-T1', 'Tecnico', 1.00, '8090000001', 'zzrep-t1@test.local', CURRENT_DATE, 'ACTIVO');
SET @empT1 = LAST_INSERT_ID();
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO, ESTADO)
VALUES ('ZZ REP TEC AJENO', 'ZZREP-T2', 'Tecnico', 1.00, '8090000002', 'zzrep-t2@test.local', CURRENT_DATE, 'ACTIVO');
SET @empT2 = LAST_INSERT_ID();

INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA, ESTADO)
VALUES (@empT1, (SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL='TECNICO'), 'zzrep_t1', 'x', 'ACTIVO');
SET @usrT1 = LAST_INSERT_ID();
INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA, ESTADO)
VALUES (@empT2, (SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL='TECNICO'), 'zzrep_t2', 'x', 'ACTIVO');
SET @usrT2 = LAST_INSERT_ID();

INSERT INTO ASIGNACIONES_RECLAMOS (ID_RECLAMO_GARAN, ID_EMPLEADO, PRIORIDAD, ESTADO_ASIGNACION)
VALUES (@rec, @empT1, 'MEDIA', 'EN_PROCESO');
SET @asiT = LAST_INSERT_ID();

-- Sesion del tecnico AJENO: la asignacion es de @empT1, no de el. Debe frenar.
SET @token_t2 = 'zzrep_t2_0000000000000000000000000000000000000000000000000000000';
INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA) VALUES (@token_t2, @usrT2, DATE_ADD(NOW(), INTERVAL 1 HOUR));
SET @TOKEN_SESION = @token_t2;
SET @ID_USUARIO_ACTUAL = @usrT2;
CALL SP_REGISTRAR_AVANCE_REPARACION(@asiT, @usrT2, 'avance ajeno', @rep, 1, 0, 5, 'EN_PROCESO', NULL);
SELECT 'AVANCE_AJENO_FRENA', IF(COUNT(*) = 0, 'OK', CONCAT('FAIL(', COUNT(*), ')')) FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asiT;
SELECT 'AVANCE_AJENO_SIN_STOCK', IF(STOCK_ACTUAL = 7, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;

-- Sesion del tecnico ASIGNADO: la asignacion es suya. Debe pasar.
SET @token_t1 = 'zzrep_t1_0000000000000000000000000000000000000000000000000000000';
INSERT INTO SESIONES (TOKEN, ID_USUARIO, EXPIRA) VALUES (@token_t1, @usrT1, DATE_ADD(NOW(), INTERVAL 1 HOUR));
SET @TOKEN_SESION = @token_t1;
SET @ID_USUARIO_ACTUAL = @usrT1;
CALL SP_REGISTRAR_AVANCE_REPARACION(@asiT, @usrT1, 'avance propio', @rep, 1, 0, 5, 'EN_PROCESO', NULL);
SELECT 'AVANCE_PROPIO_PASA', IF(COUNT(*) = 1, 'OK', 'FAIL') FROM DETALLE_REPARACIONES WHERE ID_ASIGNACION = @asiT;
SELECT 'AVANCE_PROPIO_STOCK', IF(STOCK_ACTUAL = 6, 'OK', CONCAT('FAIL(', STOCK_ACTUAL, ')')) FROM INVENTARIO WHERE ID_PRODUCTO = @rep;

ROLLBACK;
SQL
)

# ---------------------------------------------------------------------------
# Los SP que devuelven CONJUNTOS (no una celda) se verifican sobre su salida:
# se marcan los bloques y se mira que producto aparece en cada uno.
# ---------------------------------------------------------------------------
SALIDA2=$(mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
          --database="$DB_NAME" -N -B --force <<'SQL' 2>>"$ERR"
START TRANSACTION;
SET @mar = (SELECT ID_MARCA FROM MARCAS ORDER BY ID_MARCA LIMIT 1);
SET @cat = (SELECT ID_CATEGORIA FROM CATEGORIAS ORDER BY ID_CATEGORIA LIMIT 1);
SET @prov = (SELECT ID_PROVEEDOR FROM PROVEEDORES ORDER BY ID_PROVEEDOR LIMIT 1);
SET @emp = (SELECT ID_EMPLEADO FROM EMPLEADOS ORDER BY ID_EMPLEADO LIMIT 1);

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, ES_REPUESTO)
VALUES ('ZZ REP FILTRO', 'x', 10.00, 5.00, 'ZZREP-FILTRO', 'ACTIVO', @mar, @cat, @prov, 1);
SET @repM = LAST_INSERT_ID();
INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, P_COMPRA, CODIGO, ESTADO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR, ES_REPUESTO)
VALUES ('ZZ REP VENDIBLE', 'x', 10.00, 5.00, 'ZZREP-VEND', 'ACTIVO', @mar, @cat, @prov, 0);
SET @vendM = LAST_INSERT_ID();

-- (15/11/2026) S11: el reporte de compras separa repuesto de reventa. La compra
-- lleva 3 del repuesto (15.00) y 2 del vendible (10.00); el pago la deja RECIBIDA
-- sola, porque el trigger exige el 100% para marcarla.
SET @metM = (SELECT ID_METODO_PAGO FROM METODOS_PAGO ORDER BY ID_METODO_PAGO LIMIT 1);
INSERT INTO COMPRAS (ID_PROVEEDOR, ID_EMPLEADO, TOTAL, ESTADO) VALUES (@prov, @emp, 0, 'ABIERTA');
SET @cmp = LAST_INSERT_ID();
INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
VALUES (@cmp, @repM, 3, 5.00, 0.00);
INSERT INTO DETALLE_COMPRA (ID_COMPRA, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO, MONTO_ITBIS)
VALUES (@cmp, @vendM, 2, 5.00, 0.00);
CALL SP_REGISTRAR_PAGO_COMPRA(@cmp, @metM, (SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @cmp), @emp);

-- Un empleado con usuario de rol TECNICO: es lo que SP_TECNICOS_DISPONIBLES
-- lista. Va uno propio porque USUARIOS.ID_EMPLEADO es UNIQUE y los empleados que
-- ya existen tienen su usuario.
INSERT INTO EMPLEADOS (NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO, ESTADO)
VALUES ('ZZ REP TECNICO', 'ZZREP-TEC', 'Tecnico', 1.00, '8090000000', 'zzrep-tec@test.local', CURRENT_DATE, 'ACTIVO');
SET @empTec = LAST_INSERT_ID();
INSERT INTO USUARIOS (ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA, ESTADO)
VALUES (@empTec, (SELECT ID_ROL FROM ROLES WHERE NOMBRE_ROL = 'TECNICO'), 'zzrep_tec', 'x', 'ACTIVO');

SELECT 'MARK_EXCLUIR';
CALL SP_CONSULTAR_PRODUCTOS_FILTRADO('ZZ REP', 'EXCLUIR');
SELECT 'MARK_SOLO';
CALL SP_CONSULTAR_PRODUCTOS_FILTRADO('ZZ REP', 'SOLO');
SELECT 'MARK_INCLUIR';
CALL SP_CONSULTAR_PRODUCTOS_FILTRADO('ZZ REP', 'INCLUIR');
SELECT 'MARK_CONTAR';
CALL SP_CONTAR_PRODUCTOS_FILTRADOS('ZZ REP', 'EXCLUIR');
SELECT 'MARK_TECNICOS';
CALL SP_TECNICOS_DISPONIBLES();
SELECT 'MARK_REPORTE';
CALL SP_REPORTE_PERIODO_COMPRA(CURRENT_DATE, CURRENT_DATE);
ROLLBACK;
SQL
)

bloque() {
    printf '%s\n' "$SALIDA2" | awk -v ini="MARK_$1" '
        $0 == ini { on = 1; next }
        /^MARK_/  { on = 0 }
        on        { print }
    '
}

b_exc=$(bloque EXCLUIR)
b_sol=$(bloque SOLO)
b_inc=$(bloque INCLUIR)
b_cnt=$(bloque CONTAR)
b_tec=$(bloque TECNICOS)
b_rep=$(bloque REPORTE)

r_exc=FAIL
if printf '%s' "$b_exc" | grep -q 'ZZREP-VEND' && ! printf '%s' "$b_exc" | grep -q 'ZZREP-FILTRO'; then r_exc=OK; fi
r_sol=FAIL
if printf '%s' "$b_sol" | grep -q 'ZZREP-FILTRO' && ! printf '%s' "$b_sol" | grep -q 'ZZREP-VEND'; then r_sol=OK; fi
r_inc=FAIL
if printf '%s' "$b_inc" | grep -q 'ZZREP-FILTRO' && printf '%s' "$b_inc" | grep -q 'ZZREP-VEND'; then r_inc=OK; fi
r_cnt=FAIL
if [ "$(printf '%s' "$b_cnt" | tr -d '[:space:]')" = "1" ]; then r_cnt=OK; fi
r_tec=FAIL
if [ "$(printf '%s\n' "$b_tec" | grep -c .)" = "1" ]; then r_tec=OK; fi
# (15/11/2026) La fila del reporte: TRANSACCIONES SUBTOTAL ITBIS BRUTO REPUESTO REVENTA.
# Lo que importa ademas de 15/10 es el SUBTOTAL: tiene que dar 25.00 y no 50.00.
# Si el destino se hubiera joineado al nivel principal, SUM(C.TOTAL) se habria
# multiplicado por las 2 lineas de la compra.
r_rep=FAIL
if printf '%s' "$b_rep" | grep -qE '^1	25\.00	0\.00	25\.00	15\.00	10\.00$'; then r_rep=OK; fi

OUT="$OUT
FILTRO_EXCLUIR	$r_exc
FILTRO_SOLO	$r_sol
FILTRO_INCLUIR	$r_inc
FILTRO_CONTAR	$r_cnt
TECNICO_LISTA	$r_tec
REPORTE_DESTINO	$r_rep"

total=0
fallos=0
ESPERADOS=29
while IFS=$'\t' read -r caso res; do
    # Los SP devuelven su propio result set de una columna ("EXITO: ..."): no
    # traen RES y no son casos.
    [ -z "$res" ] && continue
    total=$((total + 1))
    if [ "$res" = "OK" ]; then
        printf '  OK    %s\n' "$caso"
    else
        fallos=$((fallos + 1))
        printf '  FALLO %s -> %s\n' "$caso" "$res"
    fi
done <<< "$OUT"

# (15/11/2026) Diagnostico. Los SIGNAL de regla de negocio (SQLSTATE 45000 /
# ERROR 1644) son ESPERADOS: hay casos que DEBEN fallar. Cualquier otro error es
# estructural —el esquema o el propio test estan rotos— y sin esto se lee como
# "el SP no inserto la fila", que manda a buscar el problema al lugar equivocado.
if [ -s "$ERR" ]; then
    estructurales=$(grep -E "^ERROR" "$ERR" | grep -vE "SQLSTATE 45000|ERROR 1644" | sort -u | head -5)
    if [ -n "$estructurales" ]; then
        echo
        echo "  ERRORES ESTRUCTURALES (no son reglas de negocio):"
        printf '%s\n' "$estructurales" | sed 's/^/    /'
    fi
fi
rm -f "$ERR"

echo
echo "  total: $total de $ESPERADOS   fallos: $fallos"
if [ "$total" -ne "$ESPERADOS" ]; then
    echo "FALLO: se esperaban $ESPERADOS casos y llegaron $total (SQL roto o conexion)." >&2
    exit 1
fi
[ "$fallos" -eq 0 ] || exit 1
