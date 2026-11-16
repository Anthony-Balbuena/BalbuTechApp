#!/usr/bin/env bash
# (15/11/2026) Tests del flujo de COMPRAS (modulo 19).
#
# POR QUE EXISTE: era el unico flujo grande del sistema SIN test. De los 25
# tests, ninguno registraba una compra, la pagaba ni la devolvia. Eso bloqueaba
# centralizar la formula del BRUTO en el lado de escritura (SP_REGISTRAR_PAGO_
# COMPRA y cuatro triggers), que es exactamente lo que NO hay que tocar sin red.
#
# Cubre:
#   1. Alta de compra y de lineas: la linea cuadra AL CENTAVO con la factura
#      del suplidor (el ITBIS absorbe el redondeo).
#   2. El TOTAL de la compra es la suma de los subtotales.
#   3. El BRUTO = TOTAL + ITBIS y las vistas de compra coinciden entre si
#      (VW_COMPRA_NETA vs VISTA_COMPRA_CON_IVA) y con la factura.
#   4. El saldo pendiente: bruto - pagado, y la compra sale del listado al
#      saldarse.
#   5. Estados: ABIERTA -> RECIBIDA al pagar el bruto completo.
#   6. La DEVOLUCION procesada baja el TOTAL por el subtotal devuelto y netea
#      el ITBIS, y el bruto sigue coincidiendo.
#   7. El stock sube con la linea y baja con la devolucion.
#   8. Los frenos: producto repetido, compra ya recibida, cantidad devuelta
#      mayor a la comprada.
#
# Todo corre DENTRO de una transaccion que se revierte: no deja datos.
# No necesita el binario de la app: es SQL puro.
#
# Uso: DB_NAME=BALBU_TECH_TEST DB_ADMIN_USER=root DB_ADMIN_PASSWORD=<clave> \
#      bash db/test-compras.sh
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
faltan=$(M -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES
                   WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE='PROCEDURE'
                     AND ROUTINE_NAME IN ('19_SP_INICIAR_COMPRA', '22_SP_AGREGAR_DETALLE_COMPRA',
                                          'SP_REGISTRAR_PAGO_COMPRA', 'SP_REGISTRAR_DEVOLUCION_COMPRA',
                                          'SP_PROCESAR_DEVOLUCION_COMPRA', 'SP_CANCELAR_COMPRA');")
if [ "$faltan" != "6" ]; then
    echo "FALLO: faltan rutinas del flujo de compras ($faltan/6). Aplica el modulo 19 en $DB_NAME." >&2
    exit 1
fi

# --force: los casos "debe fallar" son errores esperados y el cliente tiene que
# seguir hasta el ROLLBACK. La ausencia del efecto se verifica aparte.
OUT=$(M --force <<'SQL'
START TRANSACTION;

SET @emp  = (SELECT MIN(ID_EMPLEADO) FROM EMPLEADOS);
SET @met  = (SELECT MIN(ID_METODO_PAGO) FROM METODOS_PAGO);
SET @mar  = (SELECT MIN(ID_MARCA) FROM MARCAS);
SET @cat  = (SELECT MIN(ID_CATEGORIA) FROM CATEGORIAS);
SET @tasa = FN_TASA_ITBIS();

INSERT INTO PROVEEDORES (NOMBRE, TELEFONO, EMAIL, DIRECCION)
VALUES ('ZZ COMPRA PROV', '8090000001', 'zz.compra.prov@correo.test', 'Calle Prueba 1');
SET @prov = LAST_INSERT_ID();

INSERT INTO PRODUCTOS (NOMBRE, DESCRIPCION, PRECIO, CODIGO, ID_MARCA, ID_CATEGORIA, ID_PROVEEDOR)
VALUES ('ZZ COMPRA PROD', 'marcador del test de compras', 900.00, 'ZZ-COMPRA', @mar, @cat, @prov);
SET @prod = LAST_INSERT_ID();

INSERT INTO INVENTARIO (ID_PRODUCTO, STOCK_ACTUAL, STOCK_MINIMO, UBICACION)
VALUES (@prod, 10, 1, 'ZZ');
SET @stock0 = 10;

-- =====================================================================
-- A. Alta de la compra y de la linea
-- =====================================================================
CALL 19_SP_INICIAR_COMPRA(@prov, @emp, @compra);
SELECT IF((SELECT ESTADO FROM COMPRAS WHERE ID_COMPRA = @compra) = 'ABIERTA',
  'OK compra iniciada en ABIERTA', 'FALLO la compra no quedo ABIERTA') AS prueba;
SELECT IF((SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @compra) = 0.00,
  'OK la compra arranca con TOTAL 0', 'FALLO la compra no arranca en 0') AS prueba;

SET @cant  = 10;
SET @pfact = 118.00;   -- precio DE FACTURA (con ITBIS incluido)
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@compra, @prod, @cant, @pfact);
SET @det = (SELECT ID_DETALLE_COMPRA FROM DETALLE_COMPRA
             WHERE ID_COMPRA = @compra AND ID_PRODUCTO = @prod);

-- 1. La linea cuadra al centavo con la factura del suplidor. Es la regla que
--    hace que el ITBIS absorba el redondeo: subtotal + itbis = cantidad * factura.
SELECT IF((SELECT SUBTOTAL + MONTO_ITBIS FROM DETALLE_COMPRA WHERE ID_DETALLE_COMPRA = @det)
          = @cant * @pfact,
  'OK la linea cuadra AL CENTAVO con la factura del suplidor',
  'FALLO la linea no cuadra con la factura') AS prueba;

-- 2. El TOTAL de la compra es la suma de los subtotales (netos).
SELECT IF((SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @compra)
          = (SELECT SUM(SUBTOTAL) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra),
  'OK el TOTAL es la suma de los subtotales', 'FALLO el TOTAL no es la suma de subtotales') AS prueba;

-- 3. El BRUTO = TOTAL + ITBIS, y ademas iguala la factura del suplidor.
SELECT IF((SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra)
          = (SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @compra)
            + (SELECT SUM(MONTO_ITBIS) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra),
  'OK el BRUTO es TOTAL + ITBIS de las lineas', 'FALLO el BRUTO no es TOTAL + ITBIS') AS prueba;
SELECT IF((SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra) = @cant * @pfact,
  'OK el BRUTO iguala la factura del suplidor', 'FALLO el BRUTO no iguala la factura') AS prueba;

-- 4. Las dos vistas de compra coinciden entre si (era el punto del refactor:
--    antes la formula vivia en dos estilos distintos).
SELECT IF((SELECT TOTAL_CON_IVA FROM VISTA_COMPRA_CON_IVA WHERE ID_COMPRA = @compra)
          = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK VISTA_COMPRA_CON_IVA coincide con VW_COMPRA_NETA',
  'FALLO las dos vistas de compra DISCREPAN') AS prueba;
SELECT IF((SELECT ITBIS FROM VISTA_COMPRA_CON_IVA WHERE ID_COMPRA = @compra)
          = (SELECT ITBIS_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK el ITBIS de la vista coincide con el de la vista neta',
  'FALLO el ITBIS discrepa entre las vistas') AS prueba;

-- 5. Stock: sube con la linea.
SELECT IF((SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = @prod) = @stock0 + @cant,
  'OK el stock subio con la linea', 'FALLO el stock no subio') AS prueba;

-- 6. Pendiente: aparece y su saldo es el bruto (no el subtotal).
SELECT IF((SELECT COUNT(*) FROM VISTA_COMPRAS_PENDIENTES_PAGO WHERE ID_COMPRA = @compra) = 1,
  'OK la compra aparece en pendientes de pago', 'FALLO no aparece en pendientes') AS prueba;
SELECT IF((SELECT SALDO FROM VISTA_COMPRAS_PENDIENTES_PAGO WHERE ID_COMPRA = @compra)
          = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK el saldo pendiente es el BRUTO', 'FALLO el saldo no es el bruto') AS prueba;
SELECT IF((SELECT SALDO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra)
          = (SELECT BRUTO_NETO - PAGADO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK VW_COMPRA_NETA.SALDO = BRUTO - PAGADO', 'FALLO el SALDO no es BRUTO - PAGADO') AS prueba;

-- 7. FRENO: el mismo producto dos veces.
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@compra, @prod, 1, @pfact);
SELECT IF((SELECT COUNT(*) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra) = 1,
  'OK no dejo agregar el mismo producto dos veces', 'FALLO agrego el producto repetido') AS prueba;

-- =====================================================================
-- B. Pago parcial y pago total
-- =====================================================================
SET @bruto = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra);
CALL SP_REGISTRAR_PAGO_COMPRA(@compra, @met, 500.00, @emp);

SELECT IF((SELECT ESTADO FROM COMPRAS WHERE ID_COMPRA = @compra) = 'ABIERTA',
  'OK con pago parcial la compra sigue ABIERTA', 'FALLO quedo RECIBIDA con pago parcial') AS prueba;
SELECT IF((SELECT SALDO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra) = @bruto - 500.00,
  'OK el saldo bajo por el pago parcial', 'FALLO el saldo no bajo con el pago') AS prueba;

CALL SP_REGISTRAR_PAGO_COMPRA(@compra, @met, @bruto - 500.00, @emp);

SELECT IF((SELECT ESTADO FROM COMPRAS WHERE ID_COMPRA = @compra) = 'RECIBIDA',
  'OK al pagar el BRUTO completo queda RECIBIDA', 'FALLO no quedo RECIBIDA al pagar todo') AS prueba;
SELECT IF((SELECT SALDO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra) = 0.00,
  'OK saldada: el saldo queda en 0', 'FALLO el saldo no quedo en 0') AS prueba;
SELECT IF((SELECT COUNT(*) FROM VISTA_COMPRAS_PENDIENTES_PAGO WHERE ID_COMPRA = @compra) = 0,
  'OK saldada: SALE del listado de pendientes', 'FALLO sigue en pendientes estando saldada') AS prueba;

-- 8. FRENO: ya no acepta lineas nuevas.
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@compra, @prod, 1, @pfact);
SELECT IF((SELECT COUNT(*) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra) = 1,
  'OK no dejo agregar lineas a una compra ya RECIBIDA', 'FALLO acepto lineas en una RECIBIDA') AS prueba;

-- =====================================================================
-- C. Devolucion: baja el TOTAL y netea el ITBIS
-- =====================================================================
SET @cant_dev = 4;
CALL SP_REGISTRAR_DEVOLUCION_COMPRA(@det, @emp, @cant_dev, 'ZZ devolucion de prueba', 'BUENO', @dev);

SELECT IF((SELECT ESTADO FROM DEVOLUCION_COMPRA WHERE ID_DEVOLUCION_COMPRA = @dev) = 'PENDIENTE',
  'OK la devolucion queda PENDIENTE al registrarse', 'FALLO la devolucion no quedo PENDIENTE') AS prueba;
-- Una PENDIENTE todavía NO mueve nada.
SELECT IF((SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @compra) = @bruto - (SELECT SUM(MONTO_ITBIS) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra),
  'OK una devolucion PENDIENTE todavia no toca el TOTAL', 'FALLO la PENDIENTE ya movio el TOTAL') AS prueba;

CALL SP_PROCESAR_DEVOLUCION_COMPRA(@dev, 'PROCESADA', NULL);

SET @sub_dev  = (SELECT SUBTOTAL_DEVUELTO FROM DEVOLUCION_COMPRA WHERE ID_DEVOLUCION_COMPRA = @dev);
SET @itb_dev  = (SELECT MONTO_ITBIS_DEVUELTO FROM DEVOLUCION_COMPRA WHERE ID_DEVOLUCION_COMPRA = @dev);
SET @total_n  = (SELECT TOTAL FROM COMPRAS WHERE ID_COMPRA = @compra);
SET @itbis_n  = (SELECT SUM(MONTO_ITBIS) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra) - @itb_dev;

SELECT IF(@sub_dev > 0 AND @itb_dev > 0,
  'OK la devolucion calculo su subtotal y su ITBIS', 'FALLO la devolucion no calculo los montos') AS prueba;
-- El subtotal devuelto baja el TOTAL (lo hace TR_PROCESAR_DEVOLUCION_COMPRA).
SELECT IF(@total_n = (SELECT SUM(SUBTOTAL) FROM DETALLE_COMPRA WHERE ID_COMPRA = @compra) - @sub_dev,
  'OK el TOTAL bajo por el subtotal devuelto', 'FALLO el TOTAL no bajo por la devolucion') AS prueba;
-- El ITBIS devuelto NO se resta dos veces: la vista lo netea una sola vez.
SELECT IF(@itbis_n = (SELECT ITBIS_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK el ITBIS neteado coincide (la devolucion no se cuenta dos veces)',
  'FALLO el ITBIS neteado no coincide') AS prueba;
SELECT IF((SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra) = @total_n + @itbis_n,
  'OK tras la devolucion el BRUTO sigue siendo TOTAL + ITBIS',
  'FALLO tras la devolucion el BRUTO no cuadra') AS prueba;
SELECT IF((SELECT TOTAL_CON_IVA FROM VISTA_COMPRA_CON_IVA WHERE ID_COMPRA = @compra)
          = (SELECT BRUTO_NETO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra),
  'OK las vistas siguen coincidiendo despues de la devolucion',
  'FALLO las vistas discrepan despues de la devolucion') AS prueba;
-- La compra quedo pagada de mas: el saldo ahora es a favor (negativo).
SELECT IF((SELECT SALDO FROM VW_COMPRA_NETA WHERE ID_COMPRA = @compra) = @total_n + @itbis_n - @bruto,
  'OK el saldo refleja el pago de mas (a favor del negocio)',
  'FALLO el saldo no refleja la devolucion') AS prueba;

-- Stock: baja con la devolucion.
SELECT IF((SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = @prod) = @stock0 + @cant - @cant_dev,
  'OK el stock bajo con la devolucion', 'FALLO el stock no bajo con la devolucion') AS prueba;

-- 9. FRENO: devolver mas de lo comprado (ya se devolvieron 4 de 10, quedan 6).
CALL SP_REGISTRAR_DEVOLUCION_COMPRA(@det, @emp, 7, 'ZZ de mas', 'BUENO', @dev2);
SELECT IF((SELECT COUNT(*) FROM DEVOLUCION_COMPRA WHERE ID_DETALLE_COMPRA = @det) = 1,
  'OK no dejo devolver mas de lo comprado', 'FALLO acepto una devolucion de mas') AS prueba;

-- =====================================================================
-- D. Cancelar una compra aparte
-- =====================================================================
CALL 19_SP_INICIAR_COMPRA(@prov, @emp, @compra2);
CALL 22_SP_AGREGAR_DETALLE_COMPRA(@compra2, @prod, 2, @pfact);
CALL SP_CANCELAR_COMPRA(@compra2, @emp);

SELECT IF((SELECT ESTADO FROM COMPRAS WHERE ID_COMPRA = @compra2) = 'CANCELADA',
  'OK la compra cancelada queda CANCELADA', 'FALLO no quedo CANCELADA') AS prueba;
SELECT IF((SELECT COUNT(*) FROM VISTA_COMPRAS_PENDIENTES_PAGO WHERE ID_COMPRA = @compra2) = 0,
  'OK una compra CANCELADA no aparece en pendientes',
  'FALLO la cancelada aparece en pendientes') AS prueba;

-- =====================================================================
-- E. Cierre: ninguna compra del test quedo en un estado raro
-- =====================================================================
SELECT IF((SELECT COUNT(*) FROM COMPRAS WHERE ID_PROVEEDOR = @prov AND ESTADO NOT IN ('RECIBIDA','CANCELADA')) = 0,
  'OK las compras del test terminaron RECIBIDA o CANCELADA',
  'FALLO alguna compra quedo en un estado inesperado') AS prueba;

-- =====================================================================
-- F. El reporte por periodo tiene que coincidir con la vista
-- =====================================================================
-- (15/11/2026) El reporte arma SUBTOTAL/ITBIS/BRUTO con su propia agregacion.
-- Este control lo ancla a VW_COMPRA_NETA: si alguien cambia una definicion y no
-- la otra, los numeros dejan de coincidir y esto lo caza. Se emiten los DOS
-- resultados con marcas y se comparan en bash, DENTRO de la transaccion.
SELECT 'FASE_REPORTE' AS marca;
CALL SP_REPORTE_PERIODO_COMPRA(DATE_SUB(CURDATE(), INTERVAL 1 DAY), CURDATE());
SELECT 'FASE_REPORTE_ESPERADO' AS marca;
SELECT ROUND(IFNULL(SUM(SUBTOTAL_ORIGINAL), 0), 2) AS SUBTOTAL,
       ROUND(IFNULL(SUM(ITBIS_NETO), 0), 2)       AS ITBIS,
       ROUND(IFNULL(SUM(BRUTO_NETO), 0), 2)       AS BRUTO
  FROM VW_COMPRA_NETA
 WHERE ESTADO = 'RECIBIDA'
   AND DATE(FECHA) BETWEEN DATE_SUB(CURDATE(), INTERVAL 1 DAY) AND CURDATE();
SELECT 'FASE_FIN' AS marca;

ROLLBACK;
SQL
)

# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
fallos=$(printf '%s
' "$OUT" | grep -c "^FALLO" || true)
oks=$(printf '%s
' "$OUT" | grep -c "^OK" || true)

# ---------------------------------------------------------------------------
# El reporte por periodo contra la vista (seccion E)
# ---------------------------------------------------------------------------
seccion() {   # $1 = marca inicial, $2 = marca final
    printf '%s
' "$OUT" | awk -v a="$1" -v b="$2" '$0 == a {on=1; next} $0 == b {on=0} on'
}
# La linea del reporte trae TRANSACCIONES, SUBTOTAL, ITBIS, BRUTO; la esperada
# trae SUBTOTAL, ITBIS, BRUTO. Se comparan los tres ultimos contra los tres.
rep_tres=$(seccion FASE_REPORTE FASE_REPORTE_ESPERADO | grep -E "^[0-9]" | head -1 | awk -F'	' '{print $2"|"$3"|"$4}')
esp_tres=$(seccion FASE_REPORTE_ESPERADO FASE_FIN    | grep -E "^[0-9]" | head -1 | awk -F'	' '{print $1"|"$2"|"$3}')
if [ -n "$rep_tres" ] && [ "$rep_tres" = "$esp_tres" ]; then
    echo "  OK el reporte por periodo coincide con VW_COMPRA_NETA (SUBTOTAL|ITBIS|BRUTO = $rep_tres)"
    oks=$((oks + 1))
else
    echo "  FALLO el reporte por periodo NO coincide con la vista (reporte='$rep_tres' vista='$esp_tres')"
    fallos=$((fallos + 1))
fi


printf '%s\n' "$OUT" | grep "^OK" | sed 's/^/  /'

# Un ERROR que no sea de los frenos esperados delata un problema del test o del SP.
inesperados=$(printf '%s\n' "$OUT" | grep "^ERROR" | grep -vcE "PRODUCTO YA AGREGADO|NO ESTA ABIERTA|SUPERA LO COMPRADO" || true)

if [ "$inesperados" -gt 0 ]; then
    echo
    echo "ERRORES INESPERADOS:"
    printf '%s\n' "$OUT" | grep "^ERROR" | grep -vE "PRODUCTO YA AGREGADO|NO ESTA ABIERTA|SUPERA LO COMPRADO" | sed 's/^/  /'
fi

# Los TRES frenos tienen que haberse disparado: si no, el test no probo nada.
for freno in "PRODUCTO YA AGREGADO" "NO ESTA ABIERTA" "SUPERA LO COMPRADO"; do
    if ! printf '%s\n' "$OUT" | grep -q "$freno"; then
        echo "NO SE DISPARO el freno esperado: $freno"
        fallos=$((fallos + 1))
    fi
done

echo
if [ "$fallos" -eq 0 ] && [ "$inesperados" -eq 0 ]; then
    echo "TODOS LOS TESTS DE COMPRAS OK ($oks comprobaciones)"
    exit 0
fi
echo "TESTS DE COMPRAS: $fallos fallo(s), $inesperados error(es) inesperado(s)"
exit 1
