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
// Proveedores y Categorias, la lista visible se arma antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionMarca { Agregar, Actualizar, Estado, Buscar, Listar, Volver };

struct OpcionMarca {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionMarca accion;
};

static const vector<OpcionMarca>& opcionesMarcas() {
    static const vector<OpcionMarca> opciones = {
        {"Agregar Marca",              "MARCAS_CREAR",  AccionMarca::Agregar},
        {"Actualizar Marca",           "MARCAS_EDITAR", AccionMarca::Actualizar},
        {"Activar/Desactivar Marca",   "MARCAS_ESTADO", AccionMarca::Estado},
        {"Buscar Marca",               "MARCAS_VER",    AccionMarca::Buscar},
        {"Listar Marcas",              "MARCAS_VER",    AccionMarca::Listar},
        {"Volver al Menu Principal",   "",              AccionMarca::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionMarca& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionMarca*> opcionesVisibles() {
    vector<const OpcionMarca*> visibles;
    for (const OpcionMarca& opcion : opcionesMarcas()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuMarcas(const vector<const OpcionMarca*>& visibles) {
    cout << "\n=== MODULO DE MARCAS ===" << endl;
    int n = 0;
    for (const OpcionMarca* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=========================" << endl;
}

}  // namespace

void registrarMarca() {
    cout << "\n--- REGISTRO DE MARCA ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre de la marca: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_MARCA(?)"));
        pstmt->setString(1, nombre);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar marca: " << e.what() << endl;
    }
}

void actualizarMarca() {
    cout << "\n--- ACTUALIZAR MARCA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la marca: ");
        int idMarca = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_MARCA(?, ?)"));
        pstmt->setInt(1, idMarca);

        if (nombre.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, nombre);
        }

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
        cout << "\n[!] Error al actualizar marca: " << e.what() << endl;
    }
}

void cambiarEstadoMarca() {
    cout << "\n--- ACTIVAR/DESACTIVAR MARCA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la marca: ");
        int idMarca = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_MARCA(?)"));
        pstmt->setInt(1, idMarca);

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
        cout << "\n[!] Error al cambiar estado de marca: " << e.what() << endl;
    }
}

void buscarMarca() {
    cout << "\n--- BUSCAR MARCA ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre de la marca o Enter para ver todas: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_MARCA(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_MARCA"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar marca: " << e.what() << endl;
    }
}

void listarMarcas() {
    cout << "\n--- LISTADO DE MARCAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_MARCAS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        while (res->next()) {
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_MARCA"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar marcas: " << e.what() << endl;
    }
}

// Submenu de marcas: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion. Cada accion pide su permiso
// fino (MARCAS_CREAR, EDITAR, ESTADO o VER).
void ejecutarSubmenuMarcas() {
    for (;;) {
        vector<const OpcionMarca*> visibles = opcionesVisibles();
        imprimirMenuMarcas(visibles);

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

        const OpcionMarca& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionMarca::Agregar:     registrarMarca(); break;
            case AccionMarca::Actualizar:  actualizarMarca(); break;
            case AccionMarca::Estado:      cambiarEstadoMarca(); break;
            case AccionMarca::Buscar:      buscarMarca(); break;
            case AccionMarca::Listar:      listarMarcas(); break;
            case AccionMarca::Volver:      return;
        }
        pausar();
    }
}

