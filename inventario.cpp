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
#include "roles.h"
#include "tabla.h"
#include "inventario.h"

using namespace std;

static bool imprimirTablaProductos(sql::ResultSet *rl) {
    const size_t W_ID = 5, W_NOM = 25, W_EST = 9, W_COSTO = 10, W_STOCK = 6;
    const size_t ANCHO = W_ID + W_NOM + W_EST + W_COSTO + W_STOCK + 4 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("NOMBRE", W_NOM) << " | "
         << tablaCelda("ESTADO", W_EST) << " | "
         << tablaCelda("P.COMPRA", W_COSTO) << " | "
         << tablaCelda("STOCK", W_STOCK) << "\n"
         << tablaLinea(ANCHO) << "\n";
    bool hay = false;
    while (rl->next()) {
        hay = true;
        int stock = 0;
        try { stock = rl->getInt("STOCK"); } catch (...) { stock = 0; }
        double costo = 0.0;
        bool sinCosto = false;
        try { costo = rl->getDouble("P_COMPRA"); sinCosto = rl->wasNull(); } catch (...) { sinCosto = true; }
        char bufCosto[16];
        if (sinCosto) snprintf(bufCosto, sizeof(bufCosto), "%s", "---");
        else snprintf(bufCosto, sizeof(bufCosto), "%.2f", costo);
        string estado = rl->getString("ESTADO");
        cout << tablaCelda(to_string(rl->getInt("ID_PRODUCTO")), W_ID) << " | "
             << tablaCelda(rl->getString("NOMBRE"), W_NOM) << " | "
             << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << " | "
             << tablaCelda(bufCosto, W_COSTO) << " | "
             << tablaCelda(to_string(stock), W_STOCK) << "\n"
             << tablaLinea(ANCHO) << "\n";
    }
    return hay;
}

static void registrarAjuste() {
    cout << "\n--- AJUSTE DE STOCK ---" << endl;
    try {
        string filtro = leerDatoSeguro("Buscar (Enter = todos, ID o nombre): ");
        try {
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
                "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
            pl->setString(1, filtro);
            std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
            bool hay = imprimirTablaProductos(rl.get());
            if (!hay) cout << "[!] Sin coincidencias." << endl;
            drenarResultados(pl.get());
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
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
                "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
            pl->setString(1, filtro);
            std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
            bool hay = imprimirTablaProductos(rl.get());
            if (!hay) cout << "[!] Sin coincidencias." << endl;
            drenarResultados(pl.get());
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

static string aColumna(const string &s, size_t maxCols) {
    // El printf cuenta BYTES y la terminal muestra COLUMNAS: cada
    // multibyte (ej. ™) se vuelve un solo '?' para no correr la tabla.
    string out;
    size_t cols = 0;
    for (size_t i = 0; i < s.size() && cols < maxCols;) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c < 0x80) { out += s[i]; i++; cols++; }
        else {
            out += '?';
            i++;
            while (i < s.size() && (static_cast<unsigned char>(s[i]) & 0xC0) == 0x80) i++;
            cols++;
        }
    }
    return out;
}

static void kardexUI() {
    cout << "\n--- MOVIMIENTOS DE STOCK ---" << endl;
    try {
        double dTodos = -1;
        int idProd = (int)leerNumeroConIntentos("ID producto (Enter = todos): ", 1, 999999999, &dTodos);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            idProd < 0 ? "CALL SP_KARDEX_TODOS()" : "CALL SP_KARDEX_PRODUCTO(?)"));
        if (idProd >= 0) pstmt->setInt(1, idProd);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-6s | %-25s | %-19s | %-10s | %-6s | %-15s | %-30s\n", "MOV", "PRODUCTO", "FECHA", "TIPO", "CANT", "EMPLEADO", "MOTIVO");
        printf("%s\n", string(129, '-').c_str());
        bool hay = false;
        while (res->next()) {
            hay = true;
            string motivo;
            try { motivo = res->getString("OBSERVACION"); } catch (...) { motivo = ""; }
            printf("%-6d | %-25s | %-19s | %-10s | %-6d | %-15s | %-30s\n",
                   res->getInt("ID_MOVIMIENTO"),
                   aColumna(res->getString("PRODUCTO"), 25).c_str(),
                   res->getString("FECHA").c_str(),
                   res->getString("TIPO_MOVIMIENTO").c_str(),
                   res->getInt("CANTIDAD"),
                   aColumna(res->getString("EMPLEADO"), 15).c_str(),
                   aColumna(motivo, 30).c_str());
            printf("%s\n", string(129, '-').c_str());
        }
        if (!hay) cout << "[!] Sin movimientos." << endl;
        drenarResultados(pstmt.get());
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
