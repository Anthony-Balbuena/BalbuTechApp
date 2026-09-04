#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

void mostrarMenuUsuarios() {
    cout << "\n=== MODULO DE USUARIOS ===" << endl;
    cout << "1. Agregar Usuario" << endl;
    cout << "2. Actualizar Usuario" << endl;
    cout << "3. Cambiar Estado" << endl;
    cout << "4. Buscar Usuario" << endl;
    cout << "5. Cambiar Clave" << endl;
    cout << "6. Listar Usuarios" << endl;
    cout << "7. Volver al Menu Principal" << endl;
    cout << "=========================" << endl;
}

void registrarUsuario() {
    cout << "\n--- REGISTRO DE USUARIO ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_INSERTAR_USUARIOS()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- ROLES DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "| ID: " << RESET << res->getInt("ID_ROL")
                     << CIAN << " | Nombre_rol: " << RESET << res->getString("NOMBRE_ROL") << endl;
            }
            delete res;
        }

        if (pstmt->getMoreResults()) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- EMPLEADOS DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "| ID_EMPLEADO: " << RESET << res->getInt("ID_EMPLEADO")
                     << CIAN << " | NOMBRE_EMPLEADO: " << RESET << res->getString("NOMBRE") << endl;
            }
            delete res;
        }

        delete pstmt;

        string nombre = leerDatoSeguro("Nombre del Usuario: ");
        string clavePlana = leerDatoSeguro("Clave: ");
        string claveHash = aplicarHash(clavePlana);

        string idRolStr = leerDatoSeguro("ID del rol (Numero): ");
        int idRol = stoi(idRolStr);

        string idEmpStr = leerDatoSeguro("ID del empleado (NUMERO): ");
        int idEmpleado = stoi(idEmpStr);

        sql::PreparedStatement *pstmtInsert = globalCon->prepareStatement("CALL SP_INSERTAR_USUARIO(?, ?, ?, ?)");
        pstmtInsert->setInt(1, idEmpleado);
        pstmtInsert->setInt(2, idRol);
        pstmtInsert->setString(3, nombre);
        pstmtInsert->setString(4, claveHash);

        string respuesta = Recogermensaje(pstmtInsert);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmtInsert;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Formato numérico inválido en los campos ID." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void actualizarUsuario() {
    cout << "\n--- ACTUALIZAR USUARIO ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_ACTUALIZAR_USUARIOS()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- LISTADO GENERAL DE ROLES Y EMPLEADOS ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "\n| ID USUARIO: " << RESET << res->getInt("ID_USUARIO")
                     << CIAN << "\n| NOMBRE DEL USUARIO: " << RESET << res->getString("NOMBRE_USUARIO")
                     << CIAN << "\n| ID ROL: " << RESET << res->getInt("ID_ROL")
                     << CIAN << "\n| NOMBRE ROL: " << RESET << res->getString("NOMBRE_ROL")
                     << CIAN << "\n| ID EMPLEADO: " << RESET << res->getInt("ID_EMPLEADO")
                     << CIAN << "\n| Nombre EMPLEADO: " << RESET << res->getString("NOMBRE_EMPLEADO") << endl;
            }
            delete res;
        }
        delete pstmt;

        string idStr = leerDatoSeguro("ID del Usuario a Modificar: ");
        int idUsuario = stoi(idStr);

        cout << "Nota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
        string nuevoUsuario = leerDatoSeguro("Nuevo nombre de Usuario: ");
        string idRolStr = leerDatoSeguro("Nuevo ID Rol: ");
        string idEmpStr = leerDatoSeguro("Nuevo ID Empleado: ");

        sql::PreparedStatement *pstmtUpdate = globalCon->prepareStatement("CALL SP_ACTUALIZAR_USUARIO(?, ?, ?, ?)");
        pstmtUpdate->setInt(1, idUsuario);

        if (nuevoUsuario.empty()) pstmtUpdate->setNull(2, sql::DataType::VARCHAR);
        else pstmtUpdate->setString(2, nuevoUsuario);

        if (idRolStr.empty()) pstmtUpdate->setNull(3, sql::DataType::INTEGER);
        else pstmtUpdate->setInt(3, stoi(idRolStr));

        if (idEmpStr.empty()) pstmtUpdate->setNull(4, sql::DataType::INTEGER);
        else pstmtUpdate->setInt(4, stoi(idEmpStr));

        string respuesta = Recogermensaje(pstmtUpdate);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmtUpdate;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Formato numérico inválido en los campos ID." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void cambiarEstadoUsuario() {
    cout << "\n--- DESACTIVAR/ACTIVAR ESTADO DEL USUARIO ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_ACT_DESAC_USUARIOS()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- LISTADO DE USUARIOS, SU ESTADO Y SU EMPLEADO ---\n" << RESET << endl;
            while (res->next()) {
                cout << CIAN << "\n| ID Usuario: " << RESET << res->getInt("ID_USUARIO")
                     << CIAN << "\n| Nombre: " << RESET << res->getString("USUARIO")
                     << CIAN << "\n| Estado: " << RESET << res->getString("ESTADO")
                     << CIAN << "\n| Empleado: " << RESET << res->getString("EMPLEADO") << endl;
            }
            delete res;
        }
        delete pstmt;

        string idStr = leerDatoSeguro("Ingrese el ID del usuario: ");
        int idUsuario = stoi(idStr);

        sql::PreparedStatement *pstmtToggle = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_USUARIO(?)");
        pstmtToggle->setInt(1, idUsuario);

        string respuesta = Recogermensaje(pstmtToggle);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmtToggle;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void buscarUsuario() {
    cout << "\n--- BUSCAR USUARIO ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre de usuario o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_USUARIOS(?)");
        pstmt->setString(1, filtro);

        sql::ResultSet *res = pstmt->executeQuery();
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_USUARIO") << " | "
                 << res->getString("NOMBRE_USUARIO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron usuarios con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar usuario: " << e.what() << endl;
    }
}

void cambiarClaveUsuario() {
    cout << "\n--- CAMBIAR CLAVE DE USUARIO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del usuario: ");
        int idUsuario = stoi(idStr);

        string claveNueva = leerDatoSeguro("Nueva clave: ");
        string claveHash = aplicarHash(claveNueva);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CAMBIAR_CLAVE_USUARIO(?, ?)");
        pstmt->setInt(1, idUsuario);
        pstmt->setString(2, claveHash);

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
        cout << "\n[!] Error al cambiar clave: " << e.what() << endl;
    }
}

void listarUsuarios() {
    cout << "\n--- LISTADO DE USUARIOS ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_USUARIO, NOMBRE_USUARIO, ESTADO FROM USUARIOS ORDER BY ID_USUARIO");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | USUARIO | ESTADO" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_USUARIO") << " | "
                 << res->getString("NOMBRE_USUARIO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay usuarios registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar usuarios: " << e.what() << endl;
    }
}
