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
// principal (roles.cpp) y los submenus de Usuarios, Empleados, Clientes,
// Proveedores, Categorias y Marcas, la lista visible se arma antes de
// imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionMetodoPago { Agregar, Actualizar, Estado, Buscar, Listar, Volver };

struct OpcionMetodoPago {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionMetodoPago accion;
};

static const vector<OpcionMetodoPago>& opcionesMetodosPago() {
    static const vector<OpcionMetodoPago> opciones = {
        {"Agregar Metodo",             "METODOS_PAGO_CREAR",  AccionMetodoPago::Agregar},
        {"Actualizar Datos",           "METODOS_PAGO_EDITAR", AccionMetodoPago::Actualizar},
        {"Activar/Desactivar Metodo",  "METODOS_PAGO_ESTADO", AccionMetodoPago::Estado},
        {"Buscar Metodo",              "METODOS_PAGO_VER",    AccionMetodoPago::Buscar},
        {"Listar Metodos",             "METODOS_PAGO_VER",    AccionMetodoPago::Listar},
        {"Volver al Menu Principal",   "",                    AccionMetodoPago::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionMetodoPago& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionMetodoPago*> opcionesVisibles() {
    vector<const OpcionMetodoPago*> visibles;
    for (const OpcionMetodoPago& opcion : opcionesMetodosPago()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuMetodosPago(const vector<const OpcionMetodoPago*>& visibles) {
    cout << "\n=== MODULO DE METODOS DE PAGO ===" << endl;
    int n = 0;
    for (const OpcionMetodoPago* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "===============================" << endl;
}

}  // namespace

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
        cout << "\n" << string(46, '-') << endl;
        printf("%-8s | %-35s\n", "ID", "METODO DE PAGO");
        cout << string(46, '-') << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-8d | %-35.35s\n",
                   res->getInt("ID_METODO_PAGO"),
                   res->getString("NOMBRE").c_str());
            cout << string(46, '-') << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se hallaron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }

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

        cout << "\n" << string(57, '-') << endl;
        printf("%-8s | %-35s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        cout << string(57, '-') << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-8d | %-35.35s | %-8s\n",
                   res->getInt("ID_METODO_PAGO"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
            cout << string(57, '-') << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay metodos de pago registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar metodos de pago: " << e.what() << endl;
    }
}

// Submenu de metodos de pago: arma la lista visible con los permisos de la
// sesion, numera sobre lo visible y despacha por accion. Cada accion pide su
// permiso fino (METODOS_PAGO_CREAR, EDITAR, ESTADO o VER).
void ejecutarSubmenuMetodosPago() {
    for (;;) {
        vector<const OpcionMetodoPago*> visibles = opcionesVisibles();
        imprimirMenuMetodosPago(visibles);

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

        const OpcionMetodoPago& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionMetodoPago::Agregar:     registrarMetodoPago(); break;
            case AccionMetodoPago::Actualizar:  actualizarMetodoPago(); break;
            case AccionMetodoPago::Estado:      cambiarEstadoMetodoPago(); break;
            case AccionMetodoPago::Buscar:      buscarMetodoPago(); break;
            case AccionMetodoPago::Listar:      listarMetodosPago(); break;
            case AccionMetodoPago::Volver:      return;
        }
        pausar();
    }
}

