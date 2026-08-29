#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"

using namespace std;

void mostrarMenuClientes() {
    cout << "\n=== MODULO DE CLIENTES ===" << endl;
    cout << "1. Agregar Cliente" << endl;
    cout << "2. Actualizar Cliente" << endl;
    cout << "3. Cambiar Estado" << endl;
    cout << "4. Buscar Cliente" << endl;
    cout << "5. Listar Clientes" << endl;
    cout << "6. Volver al Menu Principal" << endl;
    cout << "=========================" << endl;
}

void registrarCliente() {
    cout << "\n--- REGISTRO DE CLIENTE ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre completo: ");
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");
        string direccion = leerDatoSeguro("Direccion (Enter para omitir): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_CLIENTES(?,?,?,?)");
        pstmt->setString(1, nombre);
        pstmt->setString(2, telefono);
        pstmt->setString(3, email);

        if (direccion.empty()) {
            pstmt->setNull(4, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(4, direccion);
        }

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar cliente: " << e.what() << endl;
    }
}

void actualizarCliente() {
    cout << "\n--- ACTUALIZAR CLIENTE ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del cliente: ");
        int idCliente = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string telefono = leerDatoSeguro("Nuevo telefono (Enter para omitir): ");
        string email = leerDatoSeguro("Nuevo email (Enter para omitir): ");
        string direccion = leerDatoSeguro("Nueva direccion (Enter para omitir): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_CLIENTES(?, ?, ?, ?, ?)");
        pstmt->setInt(1, idCliente);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR); else pstmt->setString(2, nombre);
        if (telefono.empty()) pstmt->setNull(3, sql::DataType::VARCHAR); else pstmt->setString(3, telefono);
        if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR); else pstmt->setString(4, email);
        if (direccion.empty()) pstmt->setNull(5, sql::DataType::VARCHAR); else pstmt->setString(5, direccion);

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
        cout << "\n[!] Error al actualizar cliente: " << e.what() << endl;
    }
}

void cambiarEstadoCliente() {
    cout << "\n--- CAMBIAR ESTADO DEL CLIENTE ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del cliente: ");
        int idCliente = stoi(idStr);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CLIENTES(?)");
        pstmt->setInt(1, idCliente);

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
        cout << "\n[!] Error al cambiar estado del cliente: " << e.what() << endl;
    }
}

void buscarCliente() {
    cout << "\n--- BUSCAR CLIENTE ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre, email o telefono o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_CLIENTE, NOMBRE, TELEFONO, EMAIL, ESTADO FROM CLIENTES WHERE (? = '' OR NOMBRE LIKE ? OR EMAIL LIKE ? OR TELEFONO LIKE ?) ORDER BY ID_CLIENTE");
        pstmt->setString(1, filtro);
        pstmt->setString(2, "%" + filtro + "%");
        pstmt->setString(3, "%" + filtro + "%");
        pstmt->setString(4, "%" + filtro + "%");

        sql::ResultSet *res = pstmt->executeQuery();
        bool encontrado = false;

        cout << "\nID | NOMBRE | TELEFONO | EMAIL | ESTADO" << endl;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_CLIENTE") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("TELEFONO") << " | "
                 << res->getString("EMAIL") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron clientes con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar cliente: " << e.what() << endl;
    }
}

void listarClientes() {
    cout << "\n--- LISTADO DE CLIENTES ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_CLIENTE, NOMBRE, TELEFONO, EMAIL, ESTADO FROM CLIENTES ORDER BY ID_CLIENTE");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE | TELEFONO | EMAIL | ESTADO" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_CLIENTE") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("TELEFONO") << " | "
                 << res->getString("EMAIL") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay clientes registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar clientes: " << e.what() << endl;
    }
}
