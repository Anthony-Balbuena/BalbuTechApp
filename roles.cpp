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

void mostrarMenuRoles() {
    cout << "\n=== MODULO DE ROLES ===" << endl;
    cout << "1. Agregar Rol" << endl;
    cout << "2. Actualizar Rol" << endl;
    cout << "3. Buscar Rol" << endl;
    cout << "4. Listar Roles" << endl;
    cout << "5. Volver al Menu Principal" << endl;
    cout << "=======================" << endl;
}

void registrarRol() {
    cout << "\n--- REGISTRO DE ROL ---" << endl;
    try {
        string nombreRol = leerDatoSeguro("Nombre del rol: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_ROL(?)");
        pstmt->setString(1, nombreRol);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar rol: " << e.what() << endl;
    }
}

void actualizarRol() {
    cout << "\n--- ACTUALIZAR ROL ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del rol: ");
        int idRol = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre del rol: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_ROL(?, ?)");
        pstmt->setInt(1, idRol);

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
        cout << "\n[!] Error al actualizar rol: " << e.what() << endl;
    }
}

void buscarRol() {
    cout << "\n--- BUSCAR ROLES ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre del rol o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_ROLES(?)");
        pstmt->setString(1, busqueda);

        sql::ResultSet *res = pstmt->executeQuery();
        string separator = string(50, '-');
        cout << "\n" << separator << endl;
        printf("%-5s | %-30s\n", "ID", "NOMBRE DEL ROL");
        cout << separator << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s\n",
                   res->getInt("ID_ROL"),
                   res->getString("NOMBRE_ROL").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se hallaron roles con el filtro: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
        cout << separator << endl;

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar rol: " << e.what() << endl;
    }
}

void listarRoles() {
    cout << "\n--- LISTADO DE ROLES ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE DEL ROL" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_ROL") << " | "
                 << res->getString("NOMBRE_ROL") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay roles registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar roles: " << e.what() << endl;
    }
}
