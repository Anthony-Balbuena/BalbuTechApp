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
// principal (roles.cpp) y los submenus de Usuarios, Empleados, Clientes y
// Proveedores, la lista visible se arma antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionCategoria { Agregar, Actualizar, Estado, Buscar, Volver };

struct OpcionCategoria {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionCategoria accion;
};

static const vector<OpcionCategoria>& opcionesCategorias() {
    static const vector<OpcionCategoria> opciones = {
        {"Agregar Categoria",            "CATEGORIAS_CREAR",  AccionCategoria::Agregar},
        {"Actualizar Categoria",         "CATEGORIAS_EDITAR", AccionCategoria::Actualizar},
        {"Activar/Desactivar Categoria", "CATEGORIAS_ESTADO", AccionCategoria::Estado},
        {"Buscar Categoria",             "CATEGORIAS_VER",    AccionCategoria::Buscar},
        {"Volver al Menu Principal",     "",                  AccionCategoria::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionCategoria& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionCategoria*> opcionesVisibles() {
    vector<const OpcionCategoria*> visibles;
    for (const OpcionCategoria& opcion : opcionesCategorias()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuCategorias(const vector<const OpcionCategoria*>& visibles) {
    cout << "\n=== MODULO DE CATEGORIAS ===" << endl;
    int n = 0;
    for (const OpcionCategoria* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=============================" << endl;
}

}  // namespace

void registrarCategoria() {
    cout << "\n--- REGISTRO DE CATEGORIA ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre de la categoria: ");
        string descripcion = leerDatoSeguro("Descripcion (Enter para omitir): ");
        string icono = leerDatoSeguro("Icono (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_CATEGORIA(?, ?, ?)"));
        pstmt->setString(1, nombre);

        if (descripcion.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, descripcion);
        }

        if (icono.empty()) {
            pstmt->setNull(3, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(3, icono);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar categoria: " << e.what() << endl;
    }
}

void actualizarCategoria() {
    cout << "\n--- ACTUALIZAR CATEGORIA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la categoria: ");
        int idCategoria = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string descripcion = leerDatoSeguro("Nueva descripcion (Enter para omitir): ");
        string icono = leerDatoSeguro("Nuevo icono (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_CATEGORIA(?, ?, ?, ?)"));
        pstmt->setInt(1, idCategoria);

        if (nombre.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, nombre);
        }

        if (descripcion.empty()) {
            pstmt->setNull(3, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(3, descripcion);
        }

        if (icono.empty()) {
            pstmt->setNull(4, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(4, icono);
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
        cout << "\n[!] Error al actualizar categoria: " << e.what() << endl;
    }
}

void cambiarEstadoCategoria() {
    cout << "\n--- ACTIVAR/DESACTIVAR CATEGORIA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la categoria: ");
        int idCategoria = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CATEGORIA(?)"));
        pstmt->setInt(1, idCategoria);

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
        cout << "\n[!] Error al cambiar estado de categoria: " << e.what() << endl;
    }
}

void buscarCategoria() {
    cout << "\n--- BUSCAR CATEGORIA ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre de la categoria o Enter para ver todas: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_CATEGORIA(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_CATEGORIA"),
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
        cout << "\n[!] Error al buscar categoria: " << e.what() << endl;
    }
}

// (11/10/2026) Función comentada: buscar-con-Enter cubre lo mismo.
#if 0
void listarCategorias() {
    cout << "\n--- LISTADO DE CATEGORIAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_CATEGORIAS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_CATEGORIA"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No hay categorias registradas." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar categorias: " << e.what() << endl;
    }
}
#endif

// Submenu de categorias: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion. Cada accion pide su permiso
// fino (CATEGORIAS_CREAR, EDITAR, ESTADO o VER).
void ejecutarSubmenuCategorias() {
    for (;;) {
        vector<const OpcionCategoria*> visibles = opcionesVisibles();
        imprimirMenuCategorias(visibles);

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

        const OpcionCategoria& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionCategoria::Agregar:     registrarCategoria(); break;
            case AccionCategoria::Actualizar:  actualizarCategoria(); break;
            case AccionCategoria::Estado:      cambiarEstadoCategoria(); break;
            case AccionCategoria::Buscar:      buscarCategoria(); break;
            case AccionCategoria::Volver:      return;
        }
        pausar();
    }
}

