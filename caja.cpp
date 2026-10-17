#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <iomanip>
#include <sstream>
#include <limits>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "caja.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

// Modulo de caja por turnos (archivo 41- TURNO_CAJA.sql).
// Un turno va de la apertura al cierre; el cuadre (esperado vs real)
// lo calcula SP_CERRAR_TURNO. La app no bloquea ventas sin turno: solo avisa.

// Pide la caja con Enter = CAJA 1 (la unica por ahora).
static string pedirCaja() {
    string caja = leerDatoSeguro("Caja (Enter = CAJA 1): ");
    if (caja.empty()) caja = "CAJA 1";
    return caja;
}

bool hayTurnoAbierto() {
    // Lectura minima de una cuenta (sin SP: es un COUNT de una fila).
    try {
        std::unique_ptr<sql::PreparedStatement> p(globalCon->prepareStatement(
            "SELECT COUNT(*) AS N FROM TURNO_CAJA WHERE ESTADO = 'ABIERTO'"));
        std::unique_ptr<sql::ResultSet> r(p->executeQuery());
        bool hay = r->next() && r->getInt("N") > 0;
        drenarResultados(p.get());
        return hay;
    } catch (const exception &) {
        return true; // sin poder consultar no molesta la venta
    }
}

static void abrirCajaUI() {
    cout << "\n--- ABRIR CAJA ---" << endl;
    try {
        string caja = pedirCaja();
        double idEmp = leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        double monto = leerNumeroConIntentos("Monto inicial (Enter = 0): ", 0, 999999999, nullptr);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_ABRIR_TURNO(?, ?, ?)"));
        pstmt->setString(1, caja);
        pstmt->setInt(2, (int)idEmp);
        pstmt->setDouble(3, monto);
        string msg = Recogermensaje(pstmt.get());
        drenarResultados(pstmt.get());
        if (msg.rfind("Error DB:", 0) == 0 || msg.rfind("ERROR:", 0) == 0) {
            cout << ROJO << msg << RESET << endl;
            return;
        }
        cout << VERDE << msg << RESET << endl;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo abrir la caja." << RESET << endl;
    }
}

static void estadoCajaUI() {
    cout << "\n--- ESTADO DE LA CAJA ---" << endl;
    try {
        string caja = pedirCaja();
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_ESTADO_TURNO(?)"));
        pstmt->setString(1, caja);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool sinTurno = true;
        while (res->next()) {
            if (res->getString("ESTADO_TURNO") == "SIN TURNO") break;
            sinTurno = false;
            cout << "Turno #" << res->getInt("ID_TURNO")
                 << " (" << res->getString("CAJA") << ") | Abierto por: "
                 << res->getString("EMPLEADO_APERTURA")
                 << " | " << res->getString("FECHA_APERTURA") << endl;
            cout << "Monto apertura:  " << dinero(res->getDouble("MONTO_INICIAL")) << endl;
            cout << "Cobrado hasta ahora: " << dinero(res->getDouble("COBRADO_HASTA_AHORA")) << endl;
            cout << VERDE << "Saldo esperado en caja: "
                 << dinero(res->getDouble("SALDO_ESPERADO_VIVO")) << RESET << endl;
        }
        if (sinTurno) cout << "[!] Sin turno abierto en " << caja << "." << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el estado." << RESET << endl;
    }
}

static void cerrarCajaUI() {
    cout << "\n--- CIERRE DE CAJA (CUADRE) ---" << endl;
    try {
        string caja = pedirCaja();
        // Buscamos el turno abierto de esa caja para no pedir el ID a mano.
        int idTurno = 0;
        {
            std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
                "CALL SP_ESTADO_TURNO(?)"));
            pe->setString(1, caja);
            std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
            while (re->next()) {
                if (re->getString("ESTADO_TURNO") == "SIN TURNO") break;
                idTurno = re->getInt("ID_TURNO");
                cout << "Turno #" << idTurno << " | Abierto por: "
                     << re->getString("EMPLEADO_APERTURA") << endl;
                cout << "Monto apertura: " << dinero(re->getDouble("MONTO_INICIAL"))
                     << " | Esperado ahora: " << dinero(re->getDouble("SALDO_ESPERADO_VIVO")) << endl;
            }
            drenarResultados(pe.get());
        }
        if (idTurno == 0) {
            cout << ROJO << "Sin turno abierto en " << caja << ": nada que cerrar." << RESET << endl;
            return;
        }
        double real = leerNumeroConIntentos("Cierre real (lo que cuente): ", 0, 999999999);
        double idEmp = leerNumeroConIntentos("ID empleado que cierra: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CERRAR_TURNO(?, ?, ?)"));
        pstmt->setInt(1, idTurno);
        pstmt->setDouble(2, real);
        pstmt->setInt(3, (int)idEmp);
        // Recogermensaje drenaria el resumen; leemos los dos a mano:
        // primero el MENSAJE del cuadre, despues el resumen (getMoreResults).
        string msg;
        std::unique_ptr<sql::ResultSet> rm(pstmt->executeQuery());
        if (rm && rm->next()) msg = rm->getString("MENSAJE");
        std::unique_ptr<sql::ResultSet> res;
        if (pstmt->getMoreResults()) res.reset(pstmt->getResultSet());
        while (res && res->next()) {
            double dif = res->getDouble("DIFERENCIA");
            cout << "Turno #" << res->getInt("ID_TURNO") << " (" << res->getString("CAJA") << ") CERRADO" << endl;
            cout << "Apertura: " << res->getString("FECHA_APERTURA")
                 << " | Cierre: " << res->getString("FECHA_CIERRE") << endl;
            cout << "Abrió: " << res->getString("EMPLEADO_APERTURA")
                 << " | Cerró: " << res->getString("EMPLEADO_CIERRE") << endl;
            cout << "Monto apertura: " << dinero(res->getDouble("MONTO_INICIAL")) << endl;
            cout << "Esperado: " << dinero(res->getDouble("SALDO_ESPERADO"))
                 << " | Real: " << dinero(res->getDouble("SALDO_REAL")) << endl;
            if (dif == 0) {
                cout << VERDE << ">>> DIFERENCIA: 0 (CUADRA) <<<" << RESET << endl;
            } else if (dif < 0) {
                cout << ROJO << ">>> DIFERENCIA: " << dinero(dif) << " (FALTA) <<<" << RESET << endl;
            } else {
                cout << ">>> DIFERENCIA: +" << dinero(dif) << " (SOBRA) <<<" << endl;
            }
        }
        drenarResultados(pstmt.get());
        if (msg.rfind("Error DB:", 0) == 0 || msg.rfind("ERROR:", 0) == 0) {
            cout << ROJO << msg << RESET << endl;
        } else if (!msg.empty()) {
            cout << VERDE << msg << RESET << endl;
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const sql::SQLException &e) {
        cout << ROJO << "Error DB: " << e.what() << RESET << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo cerrar la caja." << RESET << endl;
    }
}

void mostrarMenuCaja() {
    cout << "\n=== MODULO DE CAJA ===" << endl;
    cout << "1. Abrir caja" << endl;
    cout << "2. Estado de la caja" << endl;
    cout << "3. Cerrar caja (cuadre)" << endl;
    cout << "4. Volver al Menu Principal" << endl;
    cout << "======================" << endl;
}

void ejecutarSubmenuCaja() {
    int opcion = 0;

    do {
        mostrarMenuCaja();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        if (cin.fail()) {
            cin.clear();
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
            opcion = -1;
        } else {
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
        }

        switch (opcion) {
            case 1:
                abrirCajaUI();
                break;
            case 2:
                estadoCajaUI();
                break;
            case 3:
                cerrarCajaUI();
                break;
            case 4:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 4) pausar();
    } while (opcion != 4);
}
