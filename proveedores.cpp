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

namespace {

enum class AccionProveedor { Agregar, Actualizar, Estado, Buscar, Listar, Volver };

struct OpcionProveedor {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionProveedor accion;
};

static const vector<OpcionProveedor>& opcionesProveedores() {
    static const vector<OpcionProveedor> opciones = {
        {"Agregar proveedor",            "PROVEEDORES_CREAR",  AccionProveedor::Agregar},
        {"Actualizar proveedor",         "PROVEEDORES_EDITAR", AccionProveedor::Actualizar},
        {"Activar/Desactivar proveedor", "PROVEEDORES_ESTADO", AccionProveedor::Estado},
        {"Buscar proveedor",             "PROVEEDORES_VER",    AccionProveedor::Buscar},
        {"Listar proveedores",           "PROVEEDORES_VER",    AccionProveedor::Listar},
        {"Volver al Menu Principal",     "",                   AccionProveedor::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionProveedor& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionProveedor*> opcionesVisibles() {
    vector<const OpcionProveedor*> visibles;
    for (const OpcionProveedor& opcion : opcionesProveedores()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

static void imprimirMenuProveedores(const vector<const OpcionProveedor*>& visibles) {
    cout << "\n=== MODULO PROVEEDORES ===" << endl;
    int n = 0;
    for (const OpcionProveedor* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "===========================" << endl;
}

}  // namespace

void registrarProveedor() {
    cout << "\n--- REGISTRO DE PROVEEDOR ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre completo: ");
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");
        string direccion = leerDatoSeguro("Direccion (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_PROVEEDOR(?,?,?,?)"));
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

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_PROVEEDOR(?,?,?,?,?)"));
        pstmt->setInt(1, idProveedor);

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
        cout << "\n[!] Error al actualizar proveedor: " << e.what() << endl;
    }
}

void cambiarEstadoProveedor() {
    cout << "\n--- ACTIVAR/DESACTIVAR PROVEEDOR ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del proveedor: ");
        int idProveedor = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PROVEEDOR(?)"));
        pstmt->setInt(1, idProveedor);

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
        cout << "\n[!] Error al cambiar estado del proveedor: " << e.what() << endl;
    }
}

void buscarProveedor() {
    cout << "\n--- BUSCAR PROVEEDOR ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre o telefono o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_PROVEEDORES(?)"));
        pstmt->setString(1, filtro);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-4s | %-22s | %-12s | %-30s | %-8s\n", "ID", "NOMBRE", "TELEFONO", "EMAIL", "ESTADO");
        printf("%s\n", string(88, '-').c_str());
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-30.30s | %-8s\n",
                   res->getInt("ID_PROVEEDOR"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("TELEFONO").c_str(),
                   res->getString("EMAIL").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(88, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron resultados con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar proveedor: " << e.what() << endl;
    }
}

void listarProveedores() {
    cout << "\n--- LISTADO DE PROVEEDORES ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_PROVEEDOR, NOMBRE, TELEFONO, EMAIL, ESTADO FROM PROVEEDORES ORDER BY ID_PROVEEDOR"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-4s | %-22s | %-12s | %-30s | %-8s\n", "ID", "NOMBRE", "TELEFONO", "EMAIL", "ESTADO");
        printf("%s\n", string(88, '-').c_str());
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-30.30s | %-8s\n",
                   res->getInt("ID_PROVEEDOR"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("TELEFONO").c_str(),
                   res->getString("EMAIL").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(88, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No hay proveedores registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar proveedores: " << e.what() << endl;
    }
}

void ejecutarSubmenuProveedores() {
    for (;;) {
        vector<const OpcionProveedor*> visibles = opcionesVisibles();
        imprimirMenuProveedores(visibles);

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

        const OpcionProveedor& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionProveedor::Agregar:    registrarProveedor(); break;
            case AccionProveedor::Actualizar: actualizarProveedor(); break;
            case AccionProveedor::Estado:     cambiarEstadoProveedor(); break;
            case AccionProveedor::Buscar:     buscarProveedor(); break;
            case AccionProveedor::Listar:     listarProveedores(); break;
            case AccionProveedor::Volver:     return;
        }
        pausar();
    }
}

