#include <iostream>
#include <cstdio>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>
#include "colores.h"
#include "database.h"
#include "seguridad.h"
#include "paginacion.h"
#include "roles.h"
#include "tabla.h"
#include "inventario.h"

using namespace std;

// (08/11/2026) Encabezado y fila por separado para poder paginar: el paginador
// pide la fila, la pantalla imprime el encabezado una vez.
static const size_t INV_W_ID = 5, INV_W_NOM = 25, INV_W_EST = 9,
                    INV_W_COSTO = 10, INV_W_STOCK = 6;
static const size_t INV_ANCHO =
    INV_W_ID + INV_W_NOM + INV_W_EST + INV_W_COSTO + INV_W_STOCK + 4 * 3;

static void imprimirEncabezadoProductosInv() {
    cout << "\n"
         << tablaCelda("ID", INV_W_ID) << " | "
         << tablaCelda("NOMBRE", INV_W_NOM) << " | "
         << tablaCelda("ESTADO", INV_W_EST) << " | "
         << tablaCelda("P.COMPRA", INV_W_COSTO) << " | "
         << tablaCelda("STOCK", INV_W_STOCK) << "\n"
         << tablaLinea(INV_ANCHO) << "\n";
}

static void imprimirFilaProductoInv(sql::ResultSet *rl) {
    int stock = 0;
    try { stock = rl->getInt("STOCK"); } catch (...) { stock = 0; }
    double costo = 0.0;
    bool sinCosto = false;
    try { costo = rl->getDouble("P_COMPRA"); sinCosto = rl->wasNull(); } catch (...) { sinCosto = true; }
    char bufCosto[16];
    if (sinCosto) snprintf(bufCosto, sizeof(bufCosto), "%s", "---");
    else snprintf(bufCosto, sizeof(bufCosto), "%.2f", costo);
    string estado = rl->getString("ESTADO");
    cout << tablaCelda(to_string(rl->getInt("ID_PRODUCTO")), INV_W_ID) << " | "
         << tablaCelda(rl->getString("NOMBRE"), INV_W_NOM) << " | "
         << tablaColorEstado(estado) << tablaCelda(estado, INV_W_EST) << RESET << " | "
         << tablaCelda(bufCosto, INV_W_COSTO) << " | "
         << tablaCelda(to_string(stock), INV_W_STOCK) << "\n"
         << tablaLinea(INV_ANCHO) << "\n";
}

static void registrarAjuste() {
    cout << "\n--- AJUSTE DE STOCK ---" << endl;
    try {
        string filtro = leerDatoSeguro("Buscar (Enter = todos, ID o nombre): ");
        try {
            // (08/11/2026) Paginado de 10 en 10 con el par de SPs del modulo 9.
            imprimirEncabezadoProductosInv();
            mostrarPaginadoSP(
                "CALL SP_CONSULTAR_PRODUCTOS_PAGINADO(?, ?, ?)",
                "CALL SP_CONTAR_PRODUCTOS_FILTRADOS(?)",
                {filtro},
                imprimirFilaProductoInv);
        } catch (const exception &) {
            cout << ROJO << "No se pudo listar productos." << RESET << endl;
        }

        int idProd = (int)leerNumeroConIntentos("ID producto: ", 1, 999999999);
        int idEmp = (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        string tipo = leerDatoSeguro("Tipo (ENTRADA/SALIDA): ");
        int cant = (int)leerNumeroConIntentos("Cantidad: ", 1, 999999999);
        string obs = leerDatoSeguro("Motivo (Enter para omitir): ");
        if (tipo != "ENTRADA" && tipo != "SALIDA") {
            cout << ROJO << "Tipo invalido. Use ENTRADA o SALIDA." << RESET << endl;
            return;
        }

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 20_SP_REGISTRAR_AJUSTE_INVENTARIO(?, ?, ?, ?, ?)"));
        pstmt->setInt(1, idProd);
        pstmt->setInt(2, idEmp);
        pstmt->setString(3, tipo);
        pstmt->setInt(4, cant);
        if (obs.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
        else pstmt->setString(5, obs);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument &) {
        cout << "\n[!] ID y cantidad deben ser numericos." << endl;
    } catch (const exception &e) {
        cout << ROJO << "Error al ajustar stock." << RESET << endl;
    }
}

static void actualizarCostoUI() {
    cout << "\n--- AJUSTAR PRECIO DE COMPRA ---" << endl;
    try {
        string filtro = leerDatoSeguro("Buscar (Enter = todos, ID o nombre): ");
        try {
            // (08/11/2026) Paginado de 10 en 10, igual que el ajuste de stock.
            imprimirEncabezadoProductosInv();
            mostrarPaginadoSP(
                "CALL SP_CONSULTAR_PRODUCTOS_PAGINADO(?, ?, ?)",
                "CALL SP_CONTAR_PRODUCTOS_FILTRADOS(?)",
                {filtro},
                imprimirFilaProductoInv);
        } catch (const exception &) {
            cout << ROJO << "No se pudo listar productos." << RESET << endl;
        }

        int idProd = (int)leerNumeroConIntentos("ID producto: ", 1, 999999999);
        double costo = leerNumeroConIntentos("Precio de compra $: ", 0, 999999999.99);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_ACTUALIZAR_PRODUCTOS(?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?)"));
        pstmt->setInt(1, idProd);
        pstmt->setDouble(2, costo);
        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument &) {
        cout << "\n[!] ID y costo deben ser numericos." << endl;
    } catch (const exception &) {
        cout << ROJO << "Error al actualizar costo." << RESET << endl;
    }
}

static void kardexUI() {
    cout << "\n--- MOVIMIENTOS DE STOCK ---" << endl;
    try {
        double dTodos = -1;
        int idProd = (int)leerNumeroConIntentos("ID producto (Enter = todos): ", 1, 999999999, &dTodos);
        const int filtroProd = (idProd < 0) ? 0 : idProd;

        // (08/11/2026) Paginado de 10 en 10: SP_KARDEX_TODOS cortaba en 50 y el
        // historial viejo era inalcanzable. Ademas se dibuja con tablaCelda:
        // el aColumna() de antes cambiaba los acentos por '?'.
        const size_t W_MOV = 6, W_PROD = 25, W_FEC = 19, W_TIPO = 10,
                     W_CANT = 6, W_EMP = 15, W_MOT = 30;
        const size_t ANCHO = W_MOV + W_PROD + W_FEC + W_TIPO + W_CANT + W_EMP + W_MOT + 6 * 3;
        cout << "\n"
             << tablaCelda("MOV", W_MOV) << " | "
             << tablaCelda("PRODUCTO", W_PROD) << " | "
             << tablaCelda("FECHA", W_FEC) << " | "
             << tablaCelda("TIPO", W_TIPO) << " | "
             << tablaCelda("CANT", W_CANT) << " | "
             << tablaCelda("EMPLEADO", W_EMP) << " | "
             << tablaCelda("MOTIVO", W_MOT) << "\n"
             << tablaLinea(ANCHO) << "\n";

        const int hay = mostrarPaginadoSPCon(
            "CALL SP_KARDEX_PAGINADO(?, ?, ?)",
            "CALL SP_CONTAR_MOVIMIENTOS(?)",
            [filtroProd](sql::PreparedStatement *ps, unsigned int &n) {
                ps->setInt(n++, filtroProd);
            },
            [=](sql::ResultSet *res) {
                string motivo;
                try { motivo = res->getString("OBSERVACION"); } catch (...) { motivo = ""; }
                cout << tablaCelda(to_string(res->getInt("ID_MOVIMIENTO")), W_MOV) << " | "
                     << tablaCelda(res->getString("PRODUCTO"), W_PROD) << " | "
                     << tablaCelda(res->getString("FECHA"), W_FEC) << " | "
                     << tablaCelda(res->getString("TIPO_MOVIMIENTO"), W_TIPO) << " | "
                     << tablaCelda(to_string(res->getInt("CANTIDAD")), W_CANT) << " | "
                     << tablaCelda(res->getString("EMPLEADO"), W_EMP) << " | "
                     << tablaCelda(motivo, W_MOT) << "\n"
                     << tablaLinea(ANCHO) << "\n";
            });

        if (hay == 0) cout << "[!] Sin movimientos." << endl;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el kardex." << RESET << endl;
    }
}

namespace {

enum class AccionInventario {
    AjusteStock, AjustarCosto, Movimientos, Volver
};

struct OpcionInventario {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionInventario accion;
};

// (24/10/2026) Mismo patron que el resto de los submenus: lista visible
// numerada y Volver como opcion. (26/10/2026) Cada accion tiene su propio
// permiso INVENTARIO_*, asi que un rol puede ver solo algunas y la
// numeracion se reacomoda sobre lo visible.
static const vector<OpcionInventario>& opcionesInventario() {
    static const vector<OpcionInventario> opciones = {
        {"Ajuste de stock",          "INVENTARIO_AJUSTAR", AccionInventario::AjusteStock},
        {"Ajustar p.compra",         "INVENTARIO_COSTO",   AccionInventario::AjustarCosto},
        {"Movimientos",              "INVENTARIO_VER",     AccionInventario::Movimientos},
        {"Volver al Menu Principal", "",                   AccionInventario::Volver}
    };
    return opciones;
}

static bool puedeVerOpcionInventario(const OpcionInventario& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionInventario*> opcionesInventarioVisibles() {
    vector<const OpcionInventario*> visibles;
    for (const OpcionInventario& opcion : opcionesInventario()) {
        if (puedeVerOpcionInventario(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuInventario(const vector<const OpcionInventario*>& visibles) {
    cout << "\n=== MODULO DE INVENTARIO ===" << endl;
    int n = 0;
    for (const OpcionInventario* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "============================" << endl;
}

}  // namespace

void ejecutarSubmenuInventario() {
    int opcion = 0;

    while (true) {
        vector<const OpcionInventario*> visibles = opcionesInventarioVisibles();
        imprimirMenuInventario(visibles);
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionInventario& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionInventario::AjusteStock:   registrarAjuste(); break;
            case AccionInventario::AjustarCosto:  actualizarCostoUI(); break;
            case AccionInventario::Movimientos:   kardexUI(); break;
            case AccionInventario::Volver:        return;
        }
        pausar();
    }
}
