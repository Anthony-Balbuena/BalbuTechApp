#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <limits>
#include <vector>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "roles.h"
#include "colores.h"

using namespace std;

// ---------------------------------------------------------------------------
// Submenu dinamico: cada accion pide su permiso fino. Igual que el menu
// principal (roles.cpp) y los submenus de Usuarios y Empleados, la lista
// visible se arma antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionCliente { Agregar, Actualizar, Estado, Buscar, Listar, Volver };

struct OpcionCliente {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionCliente accion;
};

static const vector<OpcionCliente>& opcionesClientes() {
    static const vector<OpcionCliente> opciones = {
        {"Agregar Cliente",           "CLIENTES_CREAR",  AccionCliente::Agregar},
        {"Actualizar Cliente",        "CLIENTES_EDITAR", AccionCliente::Actualizar},
        {"Cambiar Estado",            "CLIENTES_ESTADO", AccionCliente::Estado},
        {"Buscar Cliente",            "CLIENTES_VER",    AccionCliente::Buscar},
        {"Listar Clientes",           "CLIENTES_VER",    AccionCliente::Listar},
        {"Volver al Menu Principal",  "",                AccionCliente::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionCliente& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionCliente*> opcionesVisibles() {
    vector<const OpcionCliente*> visibles;
    for (const OpcionCliente& opcion : opcionesClientes()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuClientes(const vector<const OpcionCliente*>& visibles) {
    cout << "\n=== MODULO DE CLIENTES ===" << endl;
    int n = 0;
    for (const OpcionCliente* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=========================" << endl;
}

}  // namespace

void registrarCliente() {
    cout << "\n--- REGISTRO DE CLIENTE ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre completo: ");
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");
        string direccion = leerDatoSeguro("Direccion (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_CLIENTES(?,?,?,?)"));
        pstmt->setString(1, nombre);
        pstmt->setString(2, telefono);
        pstmt->setString(3, email);

        if (direccion.empty()) {
            pstmt->setNull(4, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(4, direccion);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
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

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_CLIENTES(?, ?, ?, ?, ?)"));
        pstmt->setInt(1, idCliente);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR); else pstmt->setString(2, nombre);
        if (telefono.empty()) pstmt->setNull(3, sql::DataType::VARCHAR); else pstmt->setString(3, telefono);
        if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR); else pstmt->setString(4, email);
        if (direccion.empty()) pstmt->setNull(5, sql::DataType::VARCHAR); else pstmt->setString(5, direccion);

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
        cout << "\n[!] Error al actualizar cliente: " << e.what() << endl;
    }
}

void cambiarEstadoCliente() {
    cout << "\n--- CAMBIAR ESTADO DEL CLIENTE ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del cliente: ");
        int idCliente = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CLIENTES(?)"));
        pstmt->setInt(1, idCliente);

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
        cout << "\n[!] Error al cambiar estado del cliente: " << e.what() << endl;
    }
}

void buscarCliente() {
    cout << "\n--- BUSCAR CLIENTE ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre, email o telefono o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_CLIENTE, NOMBRE, TELEFONO, EMAIL, ESTADO FROM CLIENTES WHERE (? = '' OR NOMBRE LIKE ? OR EMAIL LIKE ? OR TELEFONO LIKE ?) ORDER BY ID_CLIENTE"));
        pstmt->setString(1, filtro);
        pstmt->setString(2, "%" + filtro + "%");
        pstmt->setString(3, "%" + filtro + "%");
        pstmt->setString(4, "%" + filtro + "%");

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool encontrado = false;

        printf("\n%-4s | %-22s | %-12s | %-30s | %-8s\n", "ID", "NOMBRE", "TELEFONO", "EMAIL", "ESTADO");
        printf("%s\n", string(88, '-').c_str());
        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-30.30s | %-8s\n",
                   res->getInt("ID_CLIENTE"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("TELEFONO").c_str(),
                   res->getString("EMAIL").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(88, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron clientes con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar cliente: " << e.what() << endl;
    }
}

void listarClientes() {
    cout << "\n--- LISTADO DE CLIENTES ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_CLIENTE, NOMBRE, TELEFONO, EMAIL, ESTADO FROM CLIENTES ORDER BY ID_CLIENTE"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-4s | %-22s | %-12s | %-30s | %-8s\n", "ID", "NOMBRE", "TELEFONO", "EMAIL", "ESTADO");
        printf("%s\n", string(88, '-').c_str());
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-30.30s | %-8s\n",
                   res->getInt("ID_CLIENTE"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("TELEFONO").c_str(),
                   res->getString("EMAIL").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(88, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No hay clientes registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar clientes: " << e.what() << endl;
    }
}

// Submenu de clientes: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion.
void ejecutarSubmenuClientes() {
    for (;;) {
        vector<const OpcionCliente*> visibles = opcionesVisibles();
        imprimirMenuClientes(visibles);

        int opcion = 0;
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            return;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionCliente& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionCliente::Agregar:     registrarCliente(); break;
            case AccionCliente::Actualizar:  actualizarCliente(); break;
            case AccionCliente::Estado:      cambiarEstadoCliente(); break;
            case AccionCliente::Buscar:      buscarCliente(); break;
            case AccionCliente::Listar:      listarClientes(); break;
            case AccionCliente::Volver:      return;
        }
        pausar();
    }
}

