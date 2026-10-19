#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <memory>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "web_export.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

// Exporta las ventas reales del año a Pagina_Web/datos-web.js para que la
// pagina web muestre numeros de verdad en vez de Math.random().
//
// La pagina solo necesita, por cada mes: transacciones, subtotal, ITBIS y
// total. Sale de VENTAS (solo ESTADO='REALIZADA') y DETALLES_VENTA (donde
// viven el subtotal con descuento y el ITBIS por linea).
//
// Nota sobre los filtros de dias: la pagina permite filtrar por rango de dias,
// pero este archivo exporta el mes ENTERO. El filtro de dias es una vista de la
// pagina sobre estos totales; por ahora la pagina usa el mes completo. Es el
// limite honesto de tener los datos precargados sin servidor (lo que se
// resuelve el dia que haya API).

// Escapa un numero a JSON con punto decimal (nunca coma).
static string jsonNum(double v) {
    ostringstream ss;
    ss << fixed << setprecision(2) << v;
    return ss.str();
}

void exportarDatosWeb() {
    try {
        cout << "\n=== EXPORTAR DATOS PARA LA WEB ===" << endl;
        int anio = (int)leerNumeroConIntentos("Anio a exportar: ", 2000, 2100);

        // Totales por mes desde VENTAS (solo REALIZADA)
        std::unique_ptr<sql::PreparedStatement> pv(globalCon->prepareStatement(
            "SELECT MONTH(FECHA) AS MES, COUNT(*) AS TRANSACCIONES, "
            "IFNULL(SUM(TOTAL), 0) AS TOTAL "
            "FROM VENTAS "
            "WHERE ESTADO = 'REALIZADA' AND YEAR(FECHA) = ? "
            "GROUP BY MONTH(FECHA) ORDER BY MES"));
        pv->setInt(1, anio);
        std::unique_ptr<sql::ResultSet> rv(pv->executeQuery());

        // Subtotal e ITBIS por mes desde DETALLES_VENTA, uniendo con su venta
        std::unique_ptr<sql::PreparedStatement> pd(globalCon->prepareStatement(
            "SELECT MONTH(v.FECHA) AS MES, "
            "IFNULL(SUM(d.SUBTOTAL), 0) AS SUBTOTAL, "
            "IFNULL(SUM(d.MONTO_ITBIS), 0) AS ITBIS "
            "FROM DETALLES_VENTA d "
            "JOIN VENTAS v ON v.ID_VENTA = d.ID_VENTA "
            "WHERE v.ESTADO = 'REALIZADA' AND YEAR(v.FECHA) = ? "
            "GROUP BY MONTH(v.FECHA)"));
        pd->setInt(1, anio);
        std::unique_ptr<sql::ResultSet> rd(pd->executeQuery());

        struct Mes { int trans = 0; double subtotal = 0, itbis = 0, total = 0; };
        Mes meses[13];  // 1..12

        while (rv->next()) {
            int m = rv->getInt("MES");
            if (m >= 1 && m <= 12) {
                meses[m].trans = rv->getInt("TRANSACCIONES");
                meses[m].total = rv->getDouble("TOTAL");  // provisorio (sin ITBIS)
            }
        }
        drenarResultados(pv.get());

        while (rd->next()) {
            int m = rd->getInt("MES");
            if (m >= 1 && m <= 12) {
                meses[m].subtotal = rd->getDouble("SUBTOTAL");
                meses[m].itbis = rd->getDouble("ITBIS");
            }
        }
        drenarResultados(pd.get());

        // OJO: en la BD, VENTAS.TOTAL guarda el subtotal SIN ITBIS (el ITBIS vive
        // por linea en DETALLES_VENTA.MONTO_ITBIS). El total real para la pagina
        // es lo cobrado = subtotal + ITBIS.
        for (int m = 1; m <= 12; m++) {
            if (meses[m].subtotal == 0 && meses[m].itbis == 0) {
                // mes sin detalles: el total del encabezado es lo unico que hay
                continue;
            }
            meses[m].total = meses[m].subtotal + meses[m].itbis;
        }

        // Escribir datos-web.js
        ofstream fout("Pagina_Web/datos-web.js");
        if (!fout) throw runtime_error("No se pudo escribir Pagina_Web/datos-web.js");

        fout << "// Generado por la app BalbuTech (" << anio << "). No editar a mano.\n";
        fout << "// Los datos salen de VENTAS (ESTADO='REALIZADA') y DETALLES_VENTA.\n";
        fout << "const datosWeb = {\n";
        fout << "  anio: " << anio << ",\n";
        fout << "  meses: {\n";

        int totalTrans = 0;
        double totalMonto = 0;
        for (int m = 1; m <= 12; m++) {
            fout << "    " << m << ": { transacciones: " << meses[m].trans
                 << ", subtotal: " << jsonNum(meses[m].subtotal)
                 << ", itbis: " << jsonNum(meses[m].itbis)
                 << ", total: " << jsonNum(meses[m].total) << " }";
            if (m < 12) fout << ",";
            fout << "\n";
            totalTrans += meses[m].trans;
            totalMonto += meses[m].total;
        }
        fout << "  }\n};\n";
        fout.close();

        cout << "\nExportado a Pagina_Web/datos-web.js (anio " << anio << ")." << endl;
        cout << "Transacciones: " << totalTrans << " | Total: " << dinero(totalMonto) << endl;
        cout << "Abre la pagina con Live Server de VS Code para ver los datos reales." << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo exportar: " << e.what() << RESET << endl;
    }
}
