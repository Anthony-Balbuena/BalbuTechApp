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

void mostrarMenuMetodosPago() {
    cout << "\n=== MODULO DE METODOS DE PAGO ===" << endl;
    cout << "1. Agregar Metodo" << endl;
    cout << "2. Actualizar Datos" << endl;
    cout << "3. Activar/Desactivar Metodo" << endl;
    cout << "4. Buscar Metodo" << endl;
    cout << "5. Listar Metodos" << endl;
    cout << "6. Volver al Menu Principal" << endl;
    cout << "===============================" << endl;
}

void registrarMetodoPago() {
    cout << "\n--- REGISTRO DE METODO DE PAGO ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre del metodo: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_METODO_PAGO (?)"));
        pstmt->setString(1, nombre);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar metodo de pago: " << e.what() << endl;
    }
}

void actualizarMetodoPago() {
    cout << "\n--- ACTUALIZAR METODO DE PAGO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del metodo de pago: ");
        int idMetodo = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_METODO_PAGO (?,?)"));
        pstmt->setInt(1, idMetodo);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

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
        cout << "\n[!] Error al actualizar metodo de pago: " << e.what() << endl;
    }
}

void cambiarEstadoMetodoPago() {
    cout << "\n--- CAMBIAR ESTADO DEL METODO DE PAGO ---" << endl;
    try {
        string idStr = leerDatoSeguro("Ingrese el ID del metodo de pago: ");
        int idMetodo = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_METODO_PAGO(?)"));
        pstmt->setInt(1, idMetodo);

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
        cout << "\n[!] Error al cambiar estado del metodo de pago: " << e.what() << endl;
    }
}

void buscarMetodoPago() {
    cout << "\n--- BUSCAR METODOS DE PAGO ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese el nombre o presione Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_METODOS_PAGO(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        cout << "\n" << string(50, '-') << endl;
        printf("%-8s | %-35s\n", "ID", "METODO DE PAGO");
        cout << string(50, '-') << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-8d | %-35s\n",
                   res->getInt("ID_METODO_PAGO"),
                   res->getString("NOMBRE").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se hallaron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
        cout << string(50, '-') << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar metodo de pago: " << e.what() << endl;
    }
}

void listarMetodosPago() {
    cout << "\n--- LISTADO DE METODOS DE PAGO ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_METODO_PAGO, NOMBRE, ESTADO FROM METODOS_PAGO ORDER BY ID_METODO_PAGO"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        cout << "\nID | NOMBRE | ESTADO" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_METODO_PAGO") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay metodos de pago registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar metodos de pago: " << e.what() << endl;
    }
}

// Submenú de métodos de pago: muestra el menú, lee la opción y llama a la acción.
// (Antes el módulo estaba huérfano: con menú pero sin entrada desde ningún lado.)
void ejecutarSubmenuMetodosPago() {
    int opcion = 0;

    do {
        mostrarMenuMetodosPago();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        cin.ignore(numeric_limits<streamsize>::max(), '\n');

        switch (opcion) {
            case 1:
                registrarMetodoPago();
                break;
            case 2:
                actualizarMetodoPago();
                break;
            case 3:
                cambiarEstadoMetodoPago();
                break;
            case 4:
                buscarMetodoPago();
                break;
            case 5:
                listarMetodosPago();
                break;
            case 6:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
    } while (opcion != 6);
}

