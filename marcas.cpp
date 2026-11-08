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
#include "paginacion.h"
#include "roles.h"
#include "colores.h"
#include "tabla.h"

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
        {"Cambiar estado",             "MARCAS_ESTADO", AccionMarca::Estado},
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

// (08/11/2026) Igual que en Clientes, Proveedores y Empleados: se lista antes
// de pedir el ID. "Actualizar" muestra ID y nombre; "Cambiar estado" agrega el
// estado y trae todas, activas e inactivas. Devuelven cuantas hay para no pedir
// un ID sobre una lista vacia.
// Se usa SELECT directo y no SP_LISTAR_MARCAS a proposito: ese SP exige
// MARCAS_VER con EXIGIR = 1 y estas pantallas se abren con MARCAS_EDITAR y
// MARCAS_ESTADO. Hoy los cuatro roles que las abren tienen MARCAS_VER, pero el
// dia que alguien reciba EDITAR sin VER la pantalla se le rompe. Misma regla
// documentada en "Cambio para Qt.md".
static int imprimirMarcasParaElegir();
static int imprimirMarcasParaEstado();

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
        if (imprimirMarcasParaElegir() == 0) {
            cout << "\n[!] No hay marcas registradas." << endl;
            return;
        }

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
    cout << "\n--- CAMBIAR ESTADO DE LA MARCA ---" << endl;
    try {
        if (imprimirMarcasParaEstado() == 0) {
            cout << "\n[!] No hay marcas registradas." << endl;
            return;
        }

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

// (08/11/2026) Listados paginados de 10 en 10 con paginacion.h. El encabezado y
// el dibujo de cada fila quedan aca; el LIMIT/OFFSET y el COUNT los pone el
// paginador. La tabla completa sigue usandose para las consultas por SP
// (SP_LISTAR_MARCAS / SP_BUSCAR_MARCA), que no se pueden paginar sin cambiar la
// firma del procedimiento.
static const size_t MAR_W_ID = 5, MAR_W_NOM = 30, MAR_W_EST = 9;
static const size_t MAR_ANCHO = MAR_W_ID + MAR_W_NOM + MAR_W_EST + 2 * 3;

static void imprimirEncabezadoMarcas() {
    cout << "\n"
         << tablaCelda("ID", MAR_W_ID) << " | "
         << tablaCelda("NOMBRE", MAR_W_NOM) << " | "
         << tablaCelda("ESTADO", MAR_W_EST) << "\n"
         << tablaLinea(MAR_ANCHO) << "\n";
}

static void imprimirFilaMarca(sql::ResultSet *res) {
    string estado = res->getString("ESTADO");
    cout << tablaCelda(to_string(res->getInt("ID_MARCA")), MAR_W_ID) << " | "
         << tablaCelda(res->getString("NOMBRE"), MAR_W_NOM) << " | "
         << tablaColorEstado(estado) << tablaCelda(estado, MAR_W_EST) << RESET << "\n"
         << tablaLinea(MAR_ANCHO) << "\n";
}

// Consulta directa, igual que el listado del menu: la guarda del modulo 66 vive
// en las rutinas, no en estas lecturas de pantalla.
static int imprimirMarcasParaElegir() {
    const size_t W_ID = 5, W_NOM = 30;
    const size_t ANCHO = W_ID + W_NOM + 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginado({
        "SELECT ID_MARCA, NOMBRE FROM MARCAS ORDER BY ID_MARCA",
        "SELECT COUNT(*) FROM MARCAS",
        {} }, [=](sql::ResultSet *res) {
        cout << tablaCelda(to_string(res->getInt("ID_MARCA")), W_ID) << " | "
             << tablaCelda(res->getString("NOMBRE"), W_NOM) << "\n"
             << tablaLinea(ANCHO) << "\n";
    });
}

// Para cambiar el estado alcanza con ver a quien se le cambia: ID, nombre y
// estado actual. Salen todas, activas e inactivas.
static int imprimirMarcasParaEstado() {
    const size_t W_ID = 5, W_NOM = 26, W_EST = 9;
    const size_t ANCHO = W_ID + W_NOM + W_EST + 2 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << " | "
         << tablaCelda("ESTADO", W_EST) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginado({
        "SELECT ID_MARCA, NOMBRE, ESTADO FROM MARCAS ORDER BY ID_MARCA",
        "SELECT COUNT(*) FROM MARCAS",
        {} }, [=](sql::ResultSet *res) {
        string estado = res->getString("ESTADO");
        cout << tablaCelda(to_string(res->getInt("ID_MARCA")), W_ID) << " | "
             << tablaCelda(res->getString("NOMBRE"), W_NOM) << " | "
             << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << "\n"
             << tablaLinea(ANCHO) << "\n";
    });
}

void buscarMarca() {
    cout << "\n--- BUSCAR MARCA ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre de la marca o Enter para ver todas: ");
        const string like = "%" + busqueda + "%";

        // (08/11/2026) Paginado con SELECT directo: MARCAS si tiene grant de
        // lectura para balbu_app, asi no hace falta un SP nuevo. Mismo criterio
        // de busqueda que SP_BUSCAR_MARCA (nombre parcial, vacio = todas).
        imprimirEncabezadoMarcas();
        int encontrado = mostrarPaginado({
            "SELECT ID_MARCA, NOMBRE, ESTADO FROM MARCAS "
            "WHERE (? = '' OR NOMBRE LIKE ?) ORDER BY ID_MARCA",
            "SELECT COUNT(*) FROM MARCAS WHERE (? = '' OR NOMBRE LIKE ?)",
            {busqueda, like} }, imprimirFilaMarca);

        if (encontrado == 0) {
            cout << "\n[!] No se encontraron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar marca: " << e.what() << endl;
    }
}

void listarMarcas() {
    cout << "\n--- LISTADO DE MARCAS ---" << endl;
    try {
        // (08/11/2026) Paginado con SELECT directo, igual que la busqueda.
        imprimirEncabezadoMarcas();
        mostrarPaginado({
            "SELECT ID_MARCA, NOMBRE, ESTADO FROM MARCAS ORDER BY ID_MARCA",
            "SELECT COUNT(*) FROM MARCAS",
            {} }, imprimirFilaMarca);
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

