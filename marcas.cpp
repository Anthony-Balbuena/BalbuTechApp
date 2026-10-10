#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <limits>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

void mostrarMenuMarcas() {
    cout << "\n=== MODULO DE MARCAS ===" << endl;
    cout << "1. Agregar Marca" << endl;
    cout << "2. Actualizar Marca" << endl;
    cout << "3. Activar/Desactivar Marca" << endl;
    cout << "4. Buscar Marca" << endl;
    cout << "5. Listar Marcas" << endl;
    cout << "6. Volver al Menu Principal" << endl;
    cout << "=========================" << endl;
}

void registrarMarca() {
    cout << "\n--- REGISTRO DE MARCA ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre de la marca: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_MARCA(?)"));
        pstmt->setString(1, nombre);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar marca: " << e.what() << endl;
    }
}

void actualizarMarca() {
    cout << "\n--- ACTUALIZAR MARCA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la marca: ");
        int idMarca = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_MARCA(?, ?)"));
        pstmt->setInt(1, idMarca);

        if (nombre.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, nombre);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al actualizar marca: " << e.what() << endl;
    }
}

void cambiarEstadoMarca() {
    cout << "\n--- ACTIVAR/DESACTIVAR MARCA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la marca: ");
        int idMarca = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_MARCA(?)"));
        pstmt->setInt(1, idMarca);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al cambiar estado de marca: " << e.what() << endl;
    }
}

void buscarMarca() {
    cout << "\n--- BUSCAR MARCA ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre de la marca o Enter para ver todas: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_MARCA(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        cout << "\nID | NOMBRE | ESTADO" << endl;
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_MARCA") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar marca: " << e.what() << endl;
    }
}

void listarMarcas() {
    cout << "\n--- LISTADO DE MARCAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_MARCAS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        cout << "\nID | NOMBRE | ESTADO" << endl;
        while (res->next()) {
            cout << res->getInt("ID_MARCA") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("ESTADO") << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar marcas: " << e.what() << endl;
    }
}

// Submenú de marcas: muestra el menú, lee la opción y llama a la acción.
// (Antes el menú solo se imprimía y volvía sin hacer nada.)
void ejecutarSubmenuMarcas() {
    int opcion = 0;

    do {
        mostrarMenuMarcas();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        cin.ignore(numeric_limits<streamsize>::max(), '\n');

        switch (opcion) {
            case 1:
                registrarMarca();
                break;
            case 2:
                actualizarMarca();
                break;
            case 3:
                cambiarEstadoMarca();
                break;
            case 4:
                buscarMarca();
                break;
            case 5:
                listarMarcas();
                break;
            case 6:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
    } while (opcion != 6);
}

