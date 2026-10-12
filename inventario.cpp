#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>
#include "colores.h"
#include "database.h"
#include "seguridad.h"
#include "inventario.h"

using namespace std;

void mostrarMenuInventario() {
    cout << "\n=== MODULO DE INVENTARIO ===" << endl;
    cout << "1. Ajuste de stock" << endl;
    cout << "2. Volver al Menu Principal" << endl;
    cout << "============================" << endl;
}

static void registrarAjuste() {
    cout << "\n--- AJUSTE DE STOCK ---" << endl;
    try {
        string filtro = leerDatoSeguro("Buscar (Enter = todos, ID o nombre): ");
        try {
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
                "CALL SP_CONSULTAR_INVENTARIO(?)"));
            pl->setString(1, filtro);
            std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
            printf("\n%-5s | %-10s | %-25s | %-8s\n", "ID", "CODIGO", "NOMBRE", "CANTIDAD");
            bool hay = false;
            while (rl->next()) {
                hay = true;
                int stock = 0;
                try { stock = rl->getInt("STOCK_ACTUAL"); } catch (...) { stock = 0; }
                printf("%-5d | %-10s | %-25.25s | %-6d\n",
                       rl->getInt("ID_PRODUCTO"),
                       rl->getString("CODIGO").c_str(),
                       rl->getString("NOMBRE").c_str(),
                       stock);
            }
            if (!hay) cout << "[!] Sin coincidencias." << endl;
            drenarResultados(pl.get());
        } catch (const exception &) {
            cout << ROJO << "No se pudo listar productos." << RESET << endl;
        }

        string prodStr = leerDatoSeguro("ID producto: ");
        string empStr = leerDatoSeguro("ID empleado: ");
        string tipo = leerDatoSeguro("Tipo (ENTRADA/SALIDA): ");
        string cantStr = leerDatoSeguro("Cantidad: ");
        string obs = leerDatoSeguro("Motivo (Enter para omitir): ");

        int idProd = stoi(prodStr);
        int idEmp = stoi(empStr);
        int cant = stoi(cantStr);
        if (cant <= 0) {
            cout << ROJO << "La cantidad debe ser mayor a cero." << RESET << endl;
            return;
        }
        if (tipo != "ENTRADA" && tipo != "SALIDA") {
            cout << ROJO << "Tipo invalido. Use ENTRADA o SALIDA." << RESET << endl;
            return;
        }

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 20_SP_REGISTRAR_AJUSTE_INVENTARIO(?, ?, ?, ?, ?)"));
        pstmt->setInt(1, idProd);
        pstmt->setInt(2, idEmp);
        pstmt->setString(3, tipo);
        pstmt->setInt(4, cant);
        if (obs.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
        else pstmt->setString(5, obs);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument &) {
        cout << "\n[!] ID y cantidad deben ser numericos." << endl;
    } catch (const exception &e) {
        cout << ROJO << "Error al ajustar stock." << RESET << endl;
    }
}

void ejecutarSubmenuInventario() {
    int opcion = 0;
    do {
        mostrarMenuInventario();
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
                registrarAjuste();
                break;
            case 2:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 2) pausar();
    } while (opcion != 2);
}
