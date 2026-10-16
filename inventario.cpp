#include <iostream>
#include <cstdio>
#include <limits>
#include <memory>
#include <string>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>
#include "colores.h"
#include "database.h"
#include "seguridad.h"
#include "inventario.h"

using namespace std;

void mostrarMenuInventario() {
    cout << "\n=== MODULO DE INVENTARIO ===" << endl;
    cout << "1. Ajuste de stock" << endl;
    cout << "2. Ajustar p.compra" << endl;
    cout << "3. Movimientos" << endl;
    cout << "4. Volver al Menu Principal" << endl;
    cout << "============================" << endl;
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
            printf("\n%-5s | %-25s | %-8s | %-10s | %-6s\n", "ID", "NOMBRE", "ESTADO", "P.COMPRA", "STOCK");
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
                printf("%-5d | %-25.25s | %-8s | %-10s | %-6d\n",
                       rl->getInt("ID_PRODUCTO"),
                       rl->getString("NOMBRE").c_str(),
                       rl->getString("ESTADO").c_str(),
                       bufCosto,
                       stock);
            }
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
            printf("\n%-5s | %-25s | %-8s | %-10s | %-6s\n", "ID", "NOMBRE", "ESTADO", "P.COMPRA", "STOCK");
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
                printf("%-5d | %-25.25s | %-8s | %-10s | %-6d\n",
                       rl->getInt("ID_PRODUCTO"),
                       rl->getString("NOMBRE").c_str(),
                       rl->getString("ESTADO").c_str(),
                       bufCosto,
                       stock);
            }
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

void ejecutarSubmenuInventario() {
    int opcion = 0;
    do {
        mostrarMenuInventario();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        if (cin.fail()) {
            cin.clear();
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
            opcion = -1;
        } else {
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
        }
        switch (opcion) {
            case 1:
                registrarAjuste();
                break;
            case 2:
                actualizarCostoUI();
                break;
            case 3:
                kardexUI();
                break;
            case 4:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 4) pausar();
    } while (opcion != 4);
}
