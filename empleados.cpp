#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"

using namespace std;

void mostrarMenuEmpleados() {
    cout << "\n=== MODULO DE EMPLEADOS ===" << endl;
    cout << "1. Agregar Empleado" << endl;
    cout << "2. Actualizar Datos" << endl;
    cout << "3. Despedir Empleado" << endl;
    cout << "4. Reactivar Empleado" << endl;
    cout << "5. Buscar Empleado" << endl;
    cout << "6. Listar Empleados" << endl;
    cout << "7. Volver al Menu Principal" << endl;
    cout << "=============================" << endl;
}

void registrarEmpleado() {
    cout << "\n--- REGISTRO DE EMPLEADO ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre Completo: ");
        string cedula = leerDatoSeguro("Cedula: ");
        string cargo = leerDatoSeguro("Cargo: ");
        string salStr = leerDatoSeguro("Salario: ");
        double salario = stod(salStr);
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_EMPLEADO(?, ?, ?, ?, ?, ?)");
        pstmt->setString(1, nombre);
        pstmt->setString(2, cedula);
        pstmt->setString(3, cargo);
        pstmt->setDouble(4, salario);
        pstmt->setString(5, telefono);
        pstmt->setString(6, email);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El salario debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar empleado: " << e.what() << endl;
    }
}

void actualizarEmpleado() {
    cout << "\n--- ACTUALIZAR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string cedula = leerDatoSeguro("Nueva cédula (Enter para omitir): ");
        string email = leerDatoSeguro("Nuevo email (Enter para omitir): ");
        string cargo = leerDatoSeguro("Nuevo cargo (Enter para omitir): ");
        string telefono = leerDatoSeguro("Nuevo telefono (Enter para omitir): ");
        string salStr = leerDatoSeguro("Nuevo salario (0 para omitir): ");
        double salario = salStr.empty() ? 0 : stod(salStr);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_EMPLEADO(?, ?, ?, ?, ?, ?, ?)");
        pstmt->setInt(1, idEmpleado);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR); else pstmt->setString(2, nombre);
        if (cedula.empty()) pstmt->setNull(3, sql::DataType::VARCHAR); else pstmt->setString(3, cedula);
        if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR); else pstmt->setString(4, email);
        if (cargo.empty()) pstmt->setNull(5, sql::DataType::VARCHAR); else pstmt->setString(5, cargo);
        if (telefono.empty()) pstmt->setNull(6, sql::DataType::VARCHAR); else pstmt->setString(6, telefono);
        if (salario <= 0) pstmt->setNull(7, sql::DataType::DOUBLE); else pstmt->setDouble(7, salario);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID o el salario deben ser numéricos." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al actualizar empleado: " << e.what() << endl;
    }
}

void despedirEmpleado() {
    cout << "\n--- DESPEDIR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);

        string fecha = leerDatoSeguro("Fecha (YYYY-MM-DD) o Enter para hoy: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_DESPEDIR_EMPLEADO(?, ?)");
        pstmt->setInt(1, idEmpleado);

        if (fecha.empty()) {
            pstmt->setNull(2, sql::DataType::DATE);
        } else {
            pstmt->setString(2, fecha);
        }

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
        cout << "\n[!] Error al despedir empleado: " << e.what() << endl;
    }
}

void reactivarEmpleado() {
    cout << "\n--- REACTIVAR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);
        string salStr = leerDatoSeguro("Nuevo salario: ");
        double nuevoSalario = stod(salStr);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_REACTIVAR_EMPLEADO(?, ?)");
        pstmt->setInt(1, idEmpleado);
        pstmt->setDouble(2, nuevoSalario);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID y el salario deben ser numéricos." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al reactivar empleado: " << e.what() << endl;
    }
}

void buscarEmpleado() {
    cout << "\n--- BUSCAR EMPLEADO ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre, cédula o cargo o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_EMPLEADO, NOMBRE, CEDULA, CARGO, ESTADO FROM EMPLEADOS WHERE (? = '' OR NOMBRE LIKE ? OR CEDULA LIKE ? OR CARGO LIKE ?) ORDER BY ID_EMPLEADO");
        pstmt->setString(1, filtro);
        pstmt->setString(2, "%" + filtro + "%");
        pstmt->setString(3, "%" + filtro + "%");
        pstmt->setString(4, "%" + filtro + "%");

        sql::ResultSet *res = pstmt->executeQuery();
        bool encontrado = false;

        cout << "\nID | NOMBRE | CEDULA | CARGO | ESTADO" << endl;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_EMPLEADO") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("CEDULA") << " | "
                 << res->getString("CARGO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron empleados con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar empleado: " << e.what() << endl;
    }
}

void listarEmpleados() {
    cout << "\n--- LISTADO DE EMPLEADOS ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_EMPLEADO, NOMBRE, CEDULA, CARGO, ESTADO FROM EMPLEADOS ORDER BY ID_EMPLEADO");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE | CEDULA | CARGO | ESTADO" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_EMPLEADO") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("CEDULA") << " | "
                 << res->getString("CARGO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay empleados registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar empleados: " << e.what() << endl;
    }
}
