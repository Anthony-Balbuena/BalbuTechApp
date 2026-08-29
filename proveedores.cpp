#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"

using namespace std;

void mostrarMenuProveedores() {
    cout << "\n=== MODULO PROVEEDORES ===" << endl;
    cout << "1. Agregar proveedor" << endl;
    cout << "2. Actualizar proveedor" << endl;
    cout << "3. Activar/Desactivar proveedor" << endl;
    cout << "4. Buscar proveedor" << endl;
    cout << "5. Listar proveedores" << endl;
    cout << "6. Volver al Menu Principal" << endl;
    cout << "===========================" << endl;
}

void registrarProveedor() {
    cout << "\n--- REGISTRO DE PROVEEDOR ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre completo: ");
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");
        string direccion = leerDatoSeguro("Direccion (Enter para omitir): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_PROVEEDOR(?,?,?,?)");
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
    } catch (const invalid_argument&) {
        cout << "\n[!] Los datos ingresados no son válidos." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar proveedor: " << e.what() << endl;
    }
}

void actualizarProveedor() {
    cout << "\n--- ACTUALIZAR PROVEEDOR ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del proveedor: ");
        int idProveedor = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string telefono = leerDatoSeguro("Nuevo telefono (Enter para omitir): ");
        string email = leerDatoSeguro("Nuevo email (Enter para omitir): ");
        string direccion = leerDatoSeguro("Nueva direccion (Enter para omitir): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_PROVEEDOR(?,?,?,?,?)");
        pstmt->setInt(1, idProveedor);

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
        cout << "\n[!] Error al actualizar proveedor: " << e.what() << endl;
    }
}

void cambiarEstadoProveedor() {
    cout << "\n--- ACTIVAR/DESACTIVAR PROVEEDOR ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del proveedor: ");
        int idProveedor = stoi(idStr);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PROVEEDOR(?)");
        pstmt->setInt(1, idProveedor);

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
        cout << "\n[!] Error al cambiar estado del proveedor: " << e.what() << endl;
    }
}

void buscarProveedor() {
    cout << "\n--- BUSCAR PROVEEDOR ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre o telefono o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_LISTAR_PROVEEDORES(?)");
        pstmt->setString(1, filtro);

        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE | TELEFONO | EMAIL | ESTADO" << endl;
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_PROVEEDOR") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("TELEFONO") << " | "
                 << res->getString("EMAIL") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron resultados con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar proveedor: " << e.what() << endl;
    }
}

void listarProveedores() {
    cout << "\n--- LISTADO DE PROVEEDORES ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_PROVEEDOR, NOMBRE, TELEFONO, EMAIL, ESTADO FROM PROVEEDORES ORDER BY ID_PROVEEDOR");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE | TELEFONO | EMAIL | ESTADO" << endl;
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_PROVEEDOR") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("TELEFONO") << " | "
                 << res->getString("EMAIL") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay proveedores registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar proveedores: " << e.what() << endl;
    }
}
