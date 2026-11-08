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
        {"Cambiar estado",               "PROVEEDORES_ESTADO", AccionProveedor::Estado},
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

// (08/11/2026) Igual que en Clientes y Empleados: se lista antes de pedir el
// ID. "Actualizar" muestra ID y nombre; "Cambiar estado" agrega el estado y
// trae todos, activos e inactivos. Devuelven cuantos hay para no pedir un ID
// sobre una lista vacia.
static int imprimirProveedoresParaElegir();
static int imprimirProveedoresParaEstado();

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
        if (imprimirProveedoresParaElegir() == 0) {
            cout << "\n[!] No hay proveedores registrados." << endl;
            return;
        }

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
    cout << "\n--- CAMBIAR ESTADO DEL PROVEEDOR ---" << endl;
    try {
        if (imprimirProveedoresParaEstado() == 0) {
            cout << "\n[!] No hay proveedores registrados." << endl;
            return;
        }

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

// (08/11/2026) Listados paginados de 10 en 10 con paginacion.h. El encabezado y
// el dibujo de cada fila quedan aca; el LIMIT/OFFSET y el COUNT los pone el
// paginador. La tabla completa sigue usandose para las consultas por SP, que no
// se pueden paginar sin cambiar la firma del procedimiento.
static const size_t PROV_W_ID = 4, PROV_W_NOM = 22, PROV_W_TEL = 12,
                    PROV_W_MAIL = 30, PROV_W_EST = 9;
static const size_t PROV_ANCHO =
    PROV_W_ID + PROV_W_NOM + PROV_W_TEL + PROV_W_MAIL + PROV_W_EST + 4 * 3;

static void imprimirEncabezadoProveedores() {
    cout << "\n"
         << tablaCelda("ID", PROV_W_ID) << " | "
         << tablaCelda("NOMBRE", PROV_W_NOM) << " | "
         << tablaCelda("TELEFONO", PROV_W_TEL) << " | "
         << tablaCelda("EMAIL", PROV_W_MAIL) << " | "
         << tablaCelda("ESTADO", PROV_W_EST) << "\n"
         << tablaLinea(PROV_ANCHO) << "\n";
}

static void imprimirFilaProveedor(sql::ResultSet *res) {
    string estado = res->getString("ESTADO");
    cout << tablaCelda(to_string(res->getInt("ID_PROVEEDOR")), PROV_W_ID) << " | "
         << tablaCelda(res->getString("NOMBRE"), PROV_W_NOM) << " | "
         << tablaCelda(res->getString("TELEFONO"), PROV_W_TEL) << " | "
         << tablaCelda(res->getString("EMAIL"), PROV_W_MAIL) << " | "
         << tablaColorEstado(estado) << tablaCelda(estado, PROV_W_EST) << RESET << "\n"
         << tablaLinea(PROV_ANCHO) << "\n";
}

static int imprimirTablaProveedores(sql::ResultSet *res) {
    imprimirEncabezadoProveedores();
    int n = 0;
    while (res->next()) {
        ++n;
        imprimirFilaProveedor(res);
    }
    return n;
}

// Consulta directa, igual que el listado del menu: la guarda del modulo 66 vive
// en las rutinas, no en estas lecturas de pantalla.
static int imprimirProveedoresParaElegir() {
    const size_t W_ID = 4, W_NOM = 30;
    const size_t ANCHO = W_ID + W_NOM + 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginado({
        "SELECT ID_PROVEEDOR, NOMBRE FROM PROVEEDORES ORDER BY ID_PROVEEDOR",
        "SELECT COUNT(*) FROM PROVEEDORES",
        {} }, [=](sql::ResultSet *res) {
        cout << tablaCelda(to_string(res->getInt("ID_PROVEEDOR")), W_ID) << " | "
             << tablaCelda(res->getString("NOMBRE"), W_NOM) << "\n"
             << tablaLinea(ANCHO) << "\n";
    });
}

// Para cambiar el estado alcanza con ver a quien se le cambia: ID, nombre y
// estado actual. Salen todos, activos e inactivos.
static int imprimirProveedoresParaEstado() {
    const size_t W_ID = 4, W_NOM = 26, W_EST = 9;
    const size_t ANCHO = W_ID + W_NOM + W_EST + 2 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << " | "
         << tablaCelda("ESTADO", W_EST) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginado({
        "SELECT ID_PROVEEDOR, NOMBRE, ESTADO FROM PROVEEDORES ORDER BY ID_PROVEEDOR",
        "SELECT COUNT(*) FROM PROVEEDORES",
        {} }, [=](sql::ResultSet *res) {
        string estado = res->getString("ESTADO");
        cout << tablaCelda(to_string(res->getInt("ID_PROVEEDOR")), W_ID) << " | "
             << tablaCelda(res->getString("NOMBRE"), W_NOM) << " | "
             << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << "\n"
             << tablaLinea(ANCHO) << "\n";
    });
}

void buscarProveedor() {
    cout << "\n--- BUSCAR PROVEEDOR ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre o telefono o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_PROVEEDORES(?)"));
        pstmt->setString(1, filtro);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        bool encontrado = imprimirTablaProveedores(res.get()) > 0;

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

        bool encontrado = imprimirTablaProveedores(res.get()) > 0;

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

