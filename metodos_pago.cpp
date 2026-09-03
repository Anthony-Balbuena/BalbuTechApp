#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
//#include "colores.h"

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

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_METODO_PAGO (?)");
        pstmt->setString(1, nombre);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_METODO_PAGO (?,?)");
        pstmt->setInt(1, idMetodo);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_METODO_PAGO(?)");
        pstmt->setInt(1, idMetodo);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_METODOS_PAGO(?)");
        pstmt->setString(1, busqueda);

        sql::ResultSet *res = pstmt->executeQuery();
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

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar metodo de pago: " << e.what() << endl;
    }
}

void listarMetodosPago() {
    cout << "\n--- LISTADO DE METODOS DE PAGO ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_METODO_PAGO, NOMBRE, ESTADO FROM METODOS_PAGO ORDER BY ID_METODO_PAGO");
        sql::ResultSet *res = pstmt->executeQuery();

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

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar metodos de pago: " << e.what() << endl;
    }
}
