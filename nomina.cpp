#include <iostream>
#include <iomanip>
#include <string>
#include <memory>
#include <vector>
#include <cstdio>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "nomina.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "tabla.h"
#include "sesion.h"
#include "paginacion.h"
#include "roles.h"

using namespace std;

// (18/11/2026) Nomina: recibo del mes y pago de los bonos que incluye.
//
// Se mantiene separado de empleados.cpp por el mismo motivo que bonos.cpp y
// vacaciones.cpp: cada modulo tiene sus SP y su pantalla.
//
// Las dos mitades estan separadas a proposito y NO comparten una sola llamada:
//   - el recibo es CONSULTA (SP_GENERAR_RECIBO_EMPLEADO + el detalle de bonos):
//     se puede mirar cuantas veces se quiera y no marca nada. Un recibo no es un
//     pago; si marcara al mostrarlo, dos consultas dejarian bonos PAGADO sin que
//     salga un peso.
//   - el pago es el ACTO (SP_PAGAR_NOMINA_EMPLEADO): marca PAGADO con fecha y
//     usuario. Pide confirmacion explicita porque no se deshace.
//
// El sistema NO paga sueldos: no hay tabla de nomina. Lo que queda registrado
// son los bonos. El sueldo base se paga fuera y el recibo lo dice.

static const char* CALL_RECIBO = "CALL SP_GENERAR_RECIBO_EMPLEADO(?)";
static const char* CALL_DETALLE = "CALL SP_LISTAR_BONOS_PENDIENTES_EMPLEADO(?)";
static const char* CALL_PAGAR = "CALL SP_PAGAR_NOMINA_EMPLEADO(?)";

// El driver le pega al mensaje del SIGNAL un sufijo tecnico
// ("... (MySQL error code: 1644, SQLState: 45000 )"). Al operador no le dice
// nada y ocupa media pantalla: se recorta antes de mostrarlo.
static string mensajeLimpio(const string& texto) {
    const string tecnico = " (MySQL error code:";
    const size_t pos = texto.find(tecnico);
    return pos == string::npos ? texto : texto.substr(0, pos);
}

static void mostrarMensaje(const string& mensaje) {
    const string limpio = mensajeLimpio(mensaje);
    if (limpio.rfind("AVISO", 0) == 0) {
        cout << AMARILLO << limpio << RESET << endl;
    } else if (limpio.rfind("ERROR", 0) == 0 || limpio.rfind("Error DB", 0) == 0) {
        cout << ROJO << limpio << RESET << endl;
    } else {
        cout << VERDE << limpio << RESET << endl;
    }
}

// Lo que el recibo devolvio. cantidad = 0 significa "no hay nada que pagar".
struct ResumenNomina {
    int cantidad = 0;
    double totalBonos = 0.0;
};

// Lista paginada de empleados: es el punto de entrada de la pantalla. Se pagina
// porque la plantilla crece; el filtro no, aca se cobra a todos por igual.
static int listarEmpleadosParaNomina() {
    const size_t W_ID = 4, W_NOM = 30, W_EST = 8;
    const size_t ANCHO = W_ID + W_NOM + W_EST + 2 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << " | "
         << tablaCelda("ESTADO", W_EST) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginado({ "SELECT ID_EMPLEADO, NOMBRE, ESTADO FROM EMPLEADOS ORDER BY ID_EMPLEADO",
                             "SELECT COUNT(*) FROM EMPLEADOS",
                             {} },
        [=](sql::ResultSet *res) {
            const string estado = res->getString("ESTADO");
            cout << tablaCelda(to_string(res->getInt("ID_EMPLEADO")), W_ID) << " | "
                 << tablaCelda(res->getString("NOMBRE"), W_NOM) << " | "
                 << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << "\n"
                 << tablaLinea(ANCHO) << "\n";
        });
}

// Dibuja el recibo y devuelve false si el SP se nego (empleado inexistente).
static bool mostrarRecibo(int idEmpleado, ResumenNomina& resumen) {
    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(CALL_RECIBO));
    ps->setInt(1, idEmpleado);
    std::unique_ptr<sql::ResultSet> res(ps->executeQuery());

    if (!res->next()) {
        cout << ROJO << "No se pudo generar el recibo." << RESET << endl;
        return false;
    }

    const string nombre = res->getString("NOMBRE");
    const string cedula = res->getString("CEDULA");
    const string cargo = res->getString("CARGO");
    const string estado = res->getString("ESTADO");
    const double bruto = res->getDouble("SUELDO_BRUTO");
    const double sfs = res->getDouble("DESCUENTO_SFS");
    const double afp = res->getDouble("DESCUENTO_AFP");
    const double neto = res->getDouble("SUELDO_NETO");
    resumen.cantidad = res->getInt("CANTIDAD_BONOS_PENDIENTES");
    resumen.totalBonos = res->getDouble("TOTAL_BONOS_PENDIENTES");
    const double totalAPagar = res->getDouble("TOTAL_A_PAGAR");
    const string emision = res->getString("FECHA_EMISION");

    cout << MAGENTA << "\n=== RECIBO DE NOMINA - " << emision << " ===" << RESET << endl;
    cout << "Empleado: " << nombre << "  (" << cedula << ")" << endl;
    cout << "Cargo:    " << cargo << "   Estado: " << estado << endl;
    cout << "Sueldo bruto:      " << setw(12) << dinero(bruto) << endl;
    cout << "SFS (3.04%):       " << setw(12) << ("-" + dinero(sfs)) << endl;
    cout << "AFP (2.87%):       " << setw(12) << ("-" + dinero(afp)) << endl;
    cout << "Sueldo neto:       " << setw(12) << dinero(neto) << endl;
    cout << "Bonos (" << resumen.cantidad << "):        " << setw(12)
         << dinero(resumen.totalBonos) << endl;
    cout << AZUL << "TOTAL A PAGAR:     " << setw(12) << dinero(totalAPagar) << RESET << endl;

    // Sin esto la conexion queda con un result set abierto y la SIGUIENTE
    // consulta (el detalle de bonos) muere con "Commands out of sync".
    res.reset();
    drenarResultados(ps.get());
    return true;
}

// Detalle de los bonos que el recibo esta incluyendo. Sin esto el operador ve un
// total de bonos y no puede decir de donde sale.
static void mostrarDetalleBonos(int idEmpleado) {
    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(CALL_DETALLE));
    ps->setInt(1, idEmpleado);
    std::unique_ptr<sql::ResultSet> res(ps->executeQuery());

    const size_t W_ID = 6, W_FEC = 10, W_TIPO = 14, W_MON = 12, W_DESC = 34;
    const size_t ANCHO = W_ID + W_FEC + W_TIPO + W_MON + W_DESC + 4 * 3;
    cout << "\n--- BONOS PENDIENTES ---\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("FECHA", W_FEC) << " | "
         << tablaCelda("TIPO", W_TIPO) << " | "
         << tablaCelda("MONTO", W_MON) << " | "
         << tablaCelda("DESCRIPCION", W_DESC) << "\n"
         << tablaLinea(ANCHO) << "\n";
    while (res->next()) {
        cout << tablaCelda(to_string(res->getInt("ID_BONO")), W_ID) << " | "
             << tablaCelda(res->getString("FECHA"), W_FEC) << " | "
             << tablaCelda(res->getString("TIPO_BONO"), W_TIPO) << " | "
             << tablaCelda(dinero(res->getDouble("MONTO")), W_MON) << " | "
             << tablaCelda(res->getString("DESCRIPCION"), W_DESC) << "\n"
             << tablaLinea(ANCHO) << "\n";
    }
    // Mismo motivo que en el recibo: cerrar antes de la proxima consulta.
    res.reset();
    drenarResultados(ps.get());
}

// El acto de pagar. Confirma antes: no se deshace.
static void pagarNomina(int idEmpleado) {
    cout << "\n" << AMARILLO
         << "Si continua, los bonos pendientes quedan PAGADOS con la fecha y su usuario."
         << RESET << endl;
    string respuesta = leerDatoSeguro("Pagar la nomina de este empleado? (s/n): ");
    if (respuesta.empty() || (respuesta[0] != 's' && respuesta[0] != 'S')) {
        cout << "No se pago nada." << endl;
        return;
    }

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(CALL_PAGAR));
    ps->setInt(1, idEmpleado);
    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

void gestionarNominaUI() {
    if (!sesionActiva() || globalCon == nullptr) {
        cout << ROJO << "No hay sesión activa." << RESET << endl;
        return;
    }

    for (;;) {
        cout << MAGENTA << "\n=== NOMINA (RECIBO Y PAGO) ===" << RESET << endl;

        try {
            const int total = listarEmpleadosParaNomina();
            if (total == 0) {
                cout << "[!] No hay empleados registrados." << endl;
                pausar();
                return;
            }
        } catch (const exception& e) {
            cout << ROJO << "No se pudieron listar los empleados: "
                 << mensajeLimpio(e.what()) << RESET << endl;
            return;
        }

        int idEmpleado = 0;
        try {
            idEmpleado = (int)leerNumeroConIntentos(
                "ID del empleado (0 = volver): ", 0, 2147483647);
        } catch (const CancelarOperacionException& e) {
            cout << "\n[!] " << e.what() << endl;
            continue;
        }
        if (idEmpleado == 0) return;

        ResumenNomina resumen;
        try {
            if (!mostrarRecibo(idEmpleado, resumen)) { pausar(); continue; }
        } catch (const exception& e) {
            cout << ROJO << "No se pudo generar el recibo: "
                 << mensajeLimpio(e.what()) << RESET << endl;
            pausar();
            continue;
        }

        try {
            mostrarDetalleBonos(idEmpleado);
        } catch (const exception& e) {
            cout << ROJO << "No se pudo leer el detalle de los bonos: "
                 << mensajeLimpio(e.what()) << RESET << endl;
            pausar();
            continue;
        }

        try {
            if (resumen.cantidad == 0) {
                // No es un error: puede que ya se le haya pagado el mes.
                cout << "\nEste empleado no tiene bonos pendientes: no hay nada que pagar." << endl;
            } else {
                cout << "\n[!] El sueldo base no se registra aca: este sistema solo "
                     << "deja asentados los bonos." << endl;
                pagarNomina(idEmpleado);
            }
        } catch (const CancelarOperacionException& e) {
            cout << "\n[!] " << e.what() << endl;
        } catch (const exception& e) {
            cout << ROJO << "No se pudo pagar la nomina: "
                 << mensajeLimpio(e.what()) << RESET << endl;
        }

        pausar();
    }
}
