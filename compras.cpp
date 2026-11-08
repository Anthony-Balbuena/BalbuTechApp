#include <cctype>
#include <cmath>
#include <cstdio>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>
#include "colores.h"
#include "database.h"
#include "seguridad.h"
#include "paginacion.h"
#include "roles.h"
#include "sesion.h"
#include "tabla.h"
#include "compras.h"

using namespace std;

struct LineaCompra {
    int idProducto = 0;
    string codigo;
    string nombre;
    int cantidad = 0;
    double precioCompra = 0.0;
    int idProveedor = 0;
    string nombreProveedor;
};

struct CierreCompra {
    int idCompra = 0;
    int idEmpleado = 0;
    double subtotal = 0.0;
    double bruto = 0.0;
};

// ---------------------------------------------------------------------------
// Submenu dinamico: cada accion pide su permiso fino. Igual que el menu
// principal (roles.cpp) y los submenus de Usuarios, Empleados, Clientes,
// Proveedores, Categorias, Marcas y Metodos de pago, la lista visible se arma
// antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionCompra { Registrar, Ver, Devolver, Reportes, Pagar, Precios, Cancelar, Volver };

struct OpcionCompra {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionCompra accion;
};

static const vector<OpcionCompra>& opcionesCompras() {
    static const vector<OpcionCompra> opciones = {
        {"Compra rapida (carrito)",      "COMPRAS_REGISTRAR", AccionCompra::Registrar},
        {"Ver compra con IVA",           "COMPRAS_VER",       AccionCompra::Ver},
        {"Devolucion de compra",         "COMPRAS_DEVOLVER",  AccionCompra::Devolver},
        {"Reporte por periodo",          "COMPRAS_REPORTES",  AccionCompra::Reportes},
        {"Pagar compra",                 "COMPRAS_PAGAR",     AccionCompra::Pagar},
        {"Precios por suplidor",         "COMPRAS_REPORTES",  AccionCompra::Precios},
        {"Cancelar compra",              "COMPRAS_CANCELAR",  AccionCompra::Cancelar},
        {"Volver al Menu Principal",     "",                  AccionCompra::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionCompra& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionCompra*> opcionesVisibles() {
    vector<const OpcionCompra*> visibles;
    for (const OpcionCompra& opcion : opcionesCompras()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuCompras(const vector<const OpcionCompra*>& visibles) {
    cout << "\n=== MODULO DE COMPRAS ===" << endl;
    int n = 0;
    for (const OpcionCompra* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=========================" << endl;
}

}  // namespace


static double tasaIVAC() {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "SELECT FN_TASA_ITBIS() AS TASA"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        double tasa = 18.0;
        if (res->next()) tasa = res->getDouble("TASA");
        drenarResultados(pstmt.get());
        return tasa > 0 ? tasa : 18.0;
    } catch (const exception &) {
        return 18.0;
    }
}

static bool resolverProductoC(const string &entrada, LineaCompra &out);

static bool registroRapidoC(const string &entrada, LineaCompra &out) {
    try {
        vector<pair<int, string>> marcas, categorias, proveedores;
        try {
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement("CALL PARA_INSERTAR_PRODUCTO()"));
            if (pl->execute()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                while (rc && rc->next()) {
                    categorias.emplace_back(rc->getInt("ID_CATEGORIA"), rc->getString("NOMBRE"));
                }
            }
            if (pl->getMoreResults()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                while (rc && rc->next()) {
                    marcas.emplace_back(rc->getInt("ID_MARCA"), rc->getString("NOMBRE"));
                }
            }
            if (pl->getMoreResults()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                while (rc && rc->next()) {
                    proveedores.emplace_back(rc->getInt("ID_PROVEEDOR"), rc->getString("NOMBRE"));
                }
            }
            drenarResultados(pl.get());
        } catch (...) {}
        auto mostrarListaC = [](const char *titulo, const vector<pair<int, string>> &v) {
            cout << CIAN << "\n--- " << titulo << " ---\n" << RESET;
            if (v.empty()) cout << "[!] Sin registros." << endl;
            for (auto &p : v) {
                cout << CIAN << "ID: " << RESET << p.first
                     << CIAN << " | " << RESET << p.second << endl;
            }
        };
        string nombre = leerDatoSeguro("Nombre [" + entrada + "]: ");
        if (nombre.empty()) nombre = entrada;
        string descripcion = nombre;
        if (descripcion.size() < 10) descripcion += " - registro rapido";
        string codigo = leerDatoSeguro("Codigo [" + entrada + "]: ");
        if (codigo.empty()) codigo = entrada;
        mostrarListaC("MARCAS", marcas);
        int mc = (int)leerNumeroConIntentos("ID marca: ", 1, 999999999);
        mostrarListaC("CATEGORIAS", categorias);
        int ct = (int)leerNumeroConIntentos("ID categoria: ", 1, 999999999);
        double pc = leerNumeroConIntentos("Precio de compra $: ", 0, 999999999.99);
        double pv = leerNumeroConIntentos("Precio de venta $: ", 0.01, 999999999.99);
        mostrarListaC("PROVEEDORES", proveedores);
        int pr = (int)leerNumeroConIntentos("ID proveedor: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_INSERTAR_PRODUCTO(?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        pstmt->setString(1, nombre);
        pstmt->setString(2, descripcion);
        pstmt->setDouble(3, pc);
        pstmt->setDouble(4, pv);
        pstmt->setString(5, codigo);
        pstmt->setInt(6, mc);
        pstmt->setInt(7, ct);
        pstmt->setInt(8, pr);
        pstmt->setNull(9, sql::DataType::VARCHAR);
        string msg = Recogermensaje(pstmt.get());
        drenarResultados(pstmt.get());
        cout << VERDE << msg << RESET << endl;
        return resolverProductoC(codigo, out);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
        return false;
    } catch (const exception &) {
        cout << ROJO << "No se pudo registrar." << RESET << endl;
        return false;
    }
}

static bool resolverProductoC(const string &entrada, LineaCompra &out) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
        pstmt->setString(1, entrada);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        struct Cand { int id; string codigo; string nombre; };
        vector<Cand> lista;
        bool exacto = false;
        while (res->next()) {
            if (res->getString("ESTADO") != "ACTIVO") continue;
            Cand c{res->getInt("ID_PRODUCTO"), res->getString("CODIGO"), res->getString("NOMBRE")};
            if ((esNumerico(entrada) && c.id == stoi(entrada)) || c.codigo == entrada) {
                out.idProducto = c.id;
                out.codigo = c.codigo;
                out.nombre = c.nombre;
                exacto = true;
                break;
            }
            lista.push_back(c);
        }
        drenarResultados(pstmt.get());
        if (exacto) return true;
        if (lista.empty()) {
            if (esNumerico(entrada)) return false;
            if (!tienePermiso("GESTIONAR_PRODUCTOS")) {
                cout << ROJO << "No existe y no tenes permiso para crear productos." << RESET << endl;
                return false;
            }
            string r = leerDatoSeguro("No existe. Registrar rapido? (s/n): ");
            if (r != "s" && r != "S") return false;
            return registroRapidoC(entrada, out);
        }
        if (lista.size() == 1) {
            out.idProducto = lista[0].id;
            out.codigo = lista[0].codigo;
            out.nombre = lista[0].nombre;
            return true;
        }
        cout << "\nCoincidencias:" << endl;
        for (auto &c : lista) cout << c.id << " | " << c.codigo << " | " << c.nombre << endl;
        int pick = (int)leerNumeroConIntentos("ID elegido: ", 1, 999999999);
        return resolverProductoC(to_string(pick), out);
    } catch (const exception &) {
        return false;
    }
}

static int stockDeC(int idProducto) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_INVENTARIO(?)"));
        pstmt->setString(1, to_string(idProducto));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        int stock = 0;
        while (res->next()) {
            if (res->getInt("ID_PRODUCTO") == idProducto) {
                try { stock = res->getInt("STOCK_ACTUAL"); } catch (...) { stock = 0; }
                break;
            }
        }
        drenarResultados(pstmt.get());
        return stock;
    } catch (const exception &) {
        return 0;
    }
}

// Alta rapida de suplidor sin salir de la compra. Telefono/email opcionales.
static bool registroRapidoS(LineaCompra &l, const string &sugerido = "") {
    try {
        string etiqueta = "Nombre del nuevo suplidor";
        if (!sugerido.empty()) etiqueta += " [" + sugerido + "]";
        etiqueta += ": ";
        string nombre = leerDatoSeguro(etiqueta);
        if (nombre.empty()) nombre = sugerido;
        if (nombre.empty()) {
            cout << ROJO << "El nombre es obligatorio." << RESET << endl;
            return false;
        }
        string tel = leerDatoSeguro("Telefono (Enter = omitir): ");
        string mail = leerDatoSeguro("Email (Enter = omitir): ");
        std::unique_ptr<sql::PreparedStatement> pi(globalCon->prepareStatement(
            "CALL SP_INSERTAR_PROVEEDOR(?, ?, ?, ?)"));
        pi->setString(1, nombre);
        if (tel.empty()) pi->setNull(2, sql::DataType::VARCHAR);
        else pi->setString(2, tel);
        if (mail.empty()) pi->setNull(3, sql::DataType::VARCHAR);
        else pi->setString(3, mail);
        pi->setNull(4, sql::DataType::VARCHAR);
        string msg = Recogermensaje(pi.get());
        drenarResultados(pi.get());
        cout << VERDE << msg << RESET << endl;
        int nuevoId = 0;
        try {
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
                "SELECT LAST_INSERT_ID()"));
            std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
            if (rl->next()) nuevoId = rl->getInt(1);
            drenarResultados(pl.get());
        } catch (...) {}
        if (nuevoId <= 0) {
            cout << ROJO << "No se pudo obtener el ID del suplidor." << RESET << endl;
            return false;
        }
        l.idProveedor = nuevoId;
        try {
            std::unique_ptr<sql::PreparedStatement> pv2(globalCon->prepareStatement(
                "CALL SP_PROVEEDOR_ACTIVO(?)"));
            pv2->setInt(1, nuevoId);
            std::unique_ptr<sql::ResultSet> rv2(pv2->executeQuery());
            if (rv2->next()) l.nombreProveedor = rv2->getString("NOMBRE");
            else l.nombreProveedor = nombre;
            drenarResultados(pv2.get());
        } catch (...) {
            l.nombreProveedor = nombre;
        }
        return true;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
        return false;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo registrar: " << e.what() << RESET << endl;
        return false;
    }
}

static bool elegirSuplidor(LineaCompra &l) {
    // Las altas rapidas de suplidor exigen el permiso del modulo Proveedores.
    bool puedeCrearProv = tienePermiso("PROVEEDORES_CREAR");
    try {
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_PRODUCTO_SUPLIDORES(?)"));
        ps->setInt(1, l.idProducto);
        std::unique_ptr<sql::ResultSet> rs(ps->executeQuery());
        struct Sup { int id; string nombre; double precio; };
        vector<Sup> lista;
        while (rs->next()) {
            lista.push_back({rs->getInt("ID_PROVEEDOR"), rs->getString("PROVEEDOR"),
                             static_cast<double>(rs->getDouble("ULTIMO_PRECIO"))});
        }
        drenarResultados(ps.get());
        // Grilla 2 cols: ID_PROV | PROVEEDOR. Sin historial: todos los activos.
        const int WS0 = 7, WS1 = 20;
        string bordeS = "+" + string(WS0 + 2, '-') + "+" + string(WS1 + 2, '-') + "+";
        if (!lista.empty()) {
            cout << "\nLo venden:" << endl;
            cout << bordeS << endl;
            printf("| %-*s | %-*s |\n", WS0, "ID_PROV", WS1, "PROVEEDOR");
            cout << bordeS << endl;
            for (auto &s : lista) {
                printf("| %-*d | %-*.20s |\n", WS0, s.id, WS1, s.nombre.c_str());
            }
            cout << bordeS << endl;
        } else {
            try {
                std::unique_ptr<sql::PreparedStatement> pt(globalCon->prepareStatement(
                    "CALL SP_LISTAR_PROVEEDORES('')"));
                std::unique_ptr<sql::ResultSet> rt(pt->executeQuery());
                struct SupT { int id; string nombre; };
                vector<SupT> todos;
                while (rt->next()) {
                    try {
                        if (rt->getString("ESTADO") != "ACTIVO") continue;
                    } catch (...) {}
                    int sid = 0;
                    try { sid = rt->getInt("ID_PROVEEDOR"); } catch (...) { continue; }
                    string sn = "---";
                    try { sn = rt->getString("NOMBRE"); } catch (...) {}
                    if (sid > 0) todos.push_back({sid, sn});
                }
                drenarResultados(pt.get());
                if (!todos.empty()) {
                    cout << "\nSuplidores:" << endl;
                    cout << bordeS << endl;
                    printf("| %-*s | %-*s |\n", WS0, "ID_PROV", WS1, "PROVEEDOR");
                    cout << bordeS << endl;
                    for (auto &s : todos) {
                        printf("| %-*d | %-*.20s |\n", WS0, s.id, WS1, s.nombre.c_str());
                    }
                    cout << bordeS << endl;
                }
            } catch (const exception &) {}
        }
        string sStr = leerDatoSeguro(puedeCrearProv
            ? "ID suplidor (Enter = mas barato, 0 = nuevo): "
            : "ID suplidor (Enter = mas barato): ");
        if (sStr.empty()) {
            if (lista.empty()) {
                cout << ROJO << "Sin historial: elegi un ID de la lista." << RESET << endl;
                return false;
            }
            l.idProveedor = lista[0].id;
            l.nombreProveedor = lista[0].nombre;
            return true;
        }
        if (sStr == "0") {
            if (puedeCrearProv) return registroRapidoS(l);
            cout << ROJO << "ID invalido." << RESET << endl;
            return false;
        }
        if (!esNumerico(sStr)) {
            if (!puedeCrearProv) {
                cout << ROJO << "No existe y no tenes permiso para crear suplidores." << RESET << endl;
                return false;
            }
            string r = leerDatoSeguro("Registrar '" + sStr + "' como nuevo suplidor? (s/n): ");
            if (r != "s" && r != "S") return false;
            return registroRapidoS(l, sStr);
        }
        int idSup = stoi(sStr);
        std::unique_ptr<sql::PreparedStatement> pv(globalCon->prepareStatement(
            "CALL SP_PROVEEDOR_ACTIVO(?)"));
        pv->setInt(1, idSup);
        std::unique_ptr<sql::ResultSet> rv(pv->executeQuery());
        bool ok = false;
        if (rv->next()) {
            l.idProveedor = idSup;
            l.nombreProveedor = rv->getString("NOMBRE");
            ok = true;
        } else {
            cout << ROJO << "Suplidor inexistente o inactivo." << RESET << endl;
            // Drenar ANTES de otro comando en la misma conexion (si no: Commands out of sync).
            drenarResultados(pv.get());
            if (!puedeCrearProv) {
                cout << ROJO << "No tenes permiso para crear suplidores." << RESET << endl;
                return false;
            }
            string r = leerDatoSeguro("Registrar uno nuevo sin salir de la compra? (s/n): ");
            if (r == "s" || r == "S") return registroRapidoS(l);
            return false;
        }
        drenarResultados(pv.get());
        return ok;
    } catch (const exception &) {
        return false;
    }
}

static void mostrarHistorialPrecios(int idProducto) {
    try {
        std::unique_ptr<sql::PreparedStatement> ph(globalCon->prepareStatement(
            "CALL SP_PRODUCTO_HISTORIAL_PRECIOS(?)"));
        ph->setInt(1, idProducto);
        std::unique_ptr<sql::ResultSet> rh(ph->executeQuery());
        // (08/11/2026) tablaCelda: el proveedor puede traer acentos y printf
        // cuenta bytes, no columnas.
        const size_t W_PROV = 25, W_PRE = 10, W_FEC = 19, W_CAN = 4;
        const size_t ANCHO = W_PROV + W_PRE + W_FEC + W_CAN + 3 * 3;
        cout << "\n"
             << tablaCelda("PROVEEDOR", W_PROV) << " | "
             << tablaCelda("PRECIO", W_PRE) << " | "
             << tablaCelda("FECHA", W_FEC) << " | "
             << tablaCelda("CANT", W_CAN) << "\n"
             << tablaLinea(ANCHO) << "\n";
        bool hay = false;
        while (rh->next()) {
            hay = true;
            char precio[24];
            snprintf(precio, sizeof(precio), "%.2f", (double)rh->getDouble("PRECIO"));
            cout << tablaCelda(rh->getString("PROVEEDOR"), W_PROV) << " | "
                 << tablaCelda(precio, W_PRE) << " | "
                 << tablaCelda(rh->getString("FECHA"), W_FEC) << " | "
                 << tablaCelda(to_string(rh->getInt("CANTIDAD")), W_CAN) << "\n"
                 << tablaLinea(ANCHO) << "\n";
        }
        if (!hay) cout << "[!] Sin historial: primera compra." << endl;
        drenarResultados(ph.get());
    } catch (const exception &) {}
}

// dinero() ahora vive en seguridad.h/cpp (compartido con ventas).

static void mostrarCarritoCompra(const vector<LineaCompra> &carrito, double tasa) {
    (void)tasa;
    cout << "\n--- CARRITO (precios de factura, con IVA) ---" << endl;
    // (08/11/2026) tablaCelda: el nombre del producto y el proveedor pueden
    // traer acentos o simbolos, y printf corre las columnas.
    const size_t W_PRO = 25, W_CAN = 4, W_PROV = 22, W_UNI = 15, W_TOT = 12;
    const size_t ANCHO = W_PRO + W_CAN + W_PROV + W_UNI + W_TOT + 4 * 3;
    cout << "\n"
         << tablaCelda("PRODUCTO", W_PRO) << " | "
         << tablaCelda("CANT", W_CAN) << " | "
         << tablaCelda("PROVEEDOR", W_PROV) << " | "
         << tablaCelda("P.UNIT C/ITBIS", W_UNI) << " | "
         << tablaCelda("TOTAL", W_TOT) << "\n"
         << tablaLinea(ANCHO) << "\n";
    double total = 0.0;
    for (auto &l : carrito) {
        // El precio escrito ya trae ITBIS: el parcial es directo.
        double parcial = l.precioCompra * l.cantidad;
        total += parcial;
        cout << tablaCelda(l.nombre, W_PRO) << " | "
             << tablaCelda(to_string(l.cantidad), W_CAN) << " | "
             << tablaCelda(l.nombreProveedor, W_PROV) << " | "
             << tablaCelda(dinero(l.precioCompra), W_UNI) << " | "
             << tablaCelda(dinero(parcial), W_TOT) << "\n"
             << tablaLinea(ANCHO) << "\n";
    }
    cout << tablaCelda("Total con IVA =", W_PRO) << " | "
         << tablaCelda("", W_CAN) << " | "
         << tablaCelda("", W_PROV) << " | "
         << tablaCelda("", W_UNI) << " | "
         << tablaCelda(dinero(total), W_TOT) << "\n"
         << tablaLinea(ANCHO) << endl;
}

static void mostrarFacturaCompra(int idCompra) {
    try {
        std::unique_ptr<sql::PreparedStatement> ph(globalCon->prepareStatement(
            "CALL SP_COMPRA_ENCABEZADO(?)"));
        ph->setInt(1, idCompra);
        std::unique_ptr<sql::ResultSet> rh(ph->executeQuery());
        if (!rh->next()) {
            cout << ROJO << "No existe esa compra." << RESET << endl;
            drenarResultados(ph.get());
            return;
        }
        printf("\n=========== BALBUTECH ===========\n");
        printf("ID: %d | Proveedor: %s | Fecha: %s | Estado: %s\n",
               rh->getInt("ID_COMPRA"), rh->getString("PROVEEDOR").c_str(),
               rh->getString("FECHA").c_str(), rh->getString("ESTADO").c_str());
        double vItbis = rh->getDouble("ITBIS");
        double vSub = rh->getDouble("SUBTOTAL");
        double vTotal = rh->getDouble("TOTAL_CON_IVA");
        drenarResultados(ph.get());

        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRA_LINEAS(?)"));
        pl->setInt(1, idCompra);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        // (08/11/2026) tablaCelda: el nombre del producto puede traer acentos.
        const size_t W_NOM = 25, W_CAN = 4, W_MON = 10;
        const size_t ANCHO = W_NOM + W_CAN + W_MON * 4 + 5 * 3;
        cout << "\n"
             << tablaCelda("Nombre del producto", W_NOM) << " | "
             << tablaCelda("Cant", W_CAN) << " | "
             << tablaCelda("P.UNIT", W_MON) << " | "
             << tablaCelda("ITBIS", W_MON) << " | "
             << tablaCelda("Subtotal", W_MON) << " | "
             << tablaCelda("Total", W_MON) << "\n"
             << tablaLinea(ANCHO) << "\n";
        while (rl->next()) {
            char uni[24], itb[24], sub[24], tot[24];
            snprintf(uni, sizeof(uni), "%.2f", (double)rl->getDouble("PRECIO_UNITARIO"));
            snprintf(itb, sizeof(itb), "%.2f", (double)rl->getDouble("MONTO_ITBIS"));
            snprintf(sub, sizeof(sub), "%.2f", (double)rl->getDouble("SUBTOTAL"));
            snprintf(tot, sizeof(tot), "%.2f", (double)rl->getDouble("TOTAL_LINEA"));
            cout << tablaCelda(rl->getString("NOMBRE"), W_NOM) << " | "
                 << tablaCelda(to_string(rl->getInt("CANTIDAD")), W_CAN) << " | "
                 << tablaCelda(uni, W_MON) << " | "
                 << tablaCelda(itb, W_MON) << " | "
                 << tablaCelda(sub, W_MON) << " | "
                 << tablaCelda(tot, W_MON) << "\n";
        }
        drenarResultados(pl.get());
        char itbT[24], subT[24], totT[24];
        snprintf(itbT, sizeof(itbT), "%.2f", vItbis);
        snprintf(subT, sizeof(subT), "%.2f", vSub);
        snprintf(totT, sizeof(totT), "%.2f", vTotal);
        cout << tablaLinea(ANCHO) << "\n"
             << tablaCelda("Total a pagar =", W_NOM) << " | "
             << tablaCelda("", W_CAN) << " | "
             << tablaCelda("", W_MON) << " | "
             << tablaCelda(itbT, W_MON) << " | "
             << tablaCelda(subT, W_MON) << " | "
             << tablaCelda(totT, W_MON) << "\n"
             << tablaLinea(ANCHO) << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo mostrar la factura." << RESET << endl;
    }
}

static CierreCompra cerrarCompraNucleo(const vector<LineaCompra> &carrito, int idProvFijo, bool pedirProv) {
    CierreCompra out;
    if (carrito.empty()) return out;
    int idProv = idProvFijo, idEmp = sesionActual.idEmpleado, idCompra = 0;
    if (idEmp <= 0) {
        cout << ROJO << "La sesión no tiene un empleado asociado." << RESET << endl;
        return out;
    }
    try {
        bool iniciada = false;
        for (int intento = 1; intento <= MAX_INTENTOS && !iniciada; ++intento) {
            try {
                if (pedirProv) {
                    string provStr = leerDatoSeguro("ID proveedor: ");
                    if (!esNumerico(provStr)) {
                        cout << ROJO << "ID invalido (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
                        continue;
                    }
                    idProv = stoi(provStr);
                }

                std::unique_ptr<sql::Statement> stmt(globalCon->createStatement());
                stmt->execute("CALL 19_SP_INICIAR_COMPRA(" + to_string(idProv) + ", " + to_string(idEmp) + ", @nc)");
                {
                    std::unique_ptr<sql::ResultSet> r0(stmt->getResultSet());
                    if (r0) { while (r0->next()) {} }
                }
                drenarResultados(stmt.get());
                std::unique_ptr<sql::Statement> stmt2(globalCon->createStatement());
                std::unique_ptr<sql::ResultSet> resId(stmt2->executeQuery("SELECT @nc AS IDC"));
                idCompra = 0;
                if (resId->next()) {
                    try { idCompra = resId->getInt("IDC"); } catch (...) { idCompra = 0; }
                }
                drenarResultados(stmt2.get());
                if (idCompra <= 0) {
                    cout << ROJO << "No se pudo iniciar la compra (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
                    continue;
                }
                iniciada = true;
            } catch (const CancelarOperacionException &) {
                throw;
            } catch (const exception &e) {
                idCompra = 0;
                cout << ROJO << e.what() << " (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
            }
        }
        if (!iniciada) {
            cout << ROJO << "Compra no iniciada. El carrito se mantiene: volve a elegir Cerrar." << RESET << endl;
            return out;
        }
        cout << VERDE << "Compra #" << idCompra << " iniciada." << RESET << endl;

        for (auto &l : carrito) {
            try {
                std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                    "CALL 22_SP_AGREGAR_DETALLE_COMPRA(?, ?, ?, ?)"));
                pstmt->setInt(1, idCompra);
                pstmt->setInt(2, l.idProducto);
                pstmt->setInt(3, l.cantidad);
                pstmt->setDouble(4, l.precioCompra);
                string rLinea = Recogermensaje(pstmt.get());
                drenarResultados(pstmt.get());
                if (rLinea.rfind("Error DB:", 0) == 0) throw runtime_error(rLinea);
            } catch (const exception &e) {
                cout << ROJO << "Linea " << l.nombre << " fallo: " << e.what() << RESET << endl;
                try {
                    std::unique_ptr<sql::PreparedStatement> pc(globalCon->prepareStatement(
                        "CALL SP_CANCELAR_COMPRA(?, ?)"));
                    pc->setInt(1, idCompra);
                    pc->setInt(2, idEmp);
                    Recogermensaje(pc.get());
                    drenarResultados(pc.get());
                    cout << "Compra #" << idCompra << " cancelada para no dejar basura." << endl;
                } catch (const exception &) {
                    cout << ROJO << "No se pudo cancelar la compra parcial." << RESET << endl;
                }
                return out;
            }
        }

        std::unique_ptr<sql::PreparedStatement> pv(globalCon->prepareStatement(
            "CALL SP_COMPRA_ENCABEZADO(?)"));
        pv->setInt(1, idCompra);
        std::unique_ptr<sql::ResultSet> res(pv->executeQuery());
        if (res->next()) {
            out.idCompra = idCompra;
            out.idEmpleado = idEmp;
            out.subtotal = res->getDouble("SUBTOTAL");
            out.bruto = res->getDouble("TOTAL_CON_IVA");
        }
        drenarResultados(pv.get());
        if (out.idCompra > 0) mostrarFacturaCompra(idCompra);
        return out;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "Error al cerrar la compra: " << e.what() << RESET << endl;
    }
    return out;
}

static CierreCompra cerrarCompraForzada(const vector<LineaCompra> &grupo, int idProv) {
    return cerrarCompraNucleo(grupo, idProv, false);
}

// Dueño de la compra = empleado que la registró (lo usa el pago con Enter).
static int duenoDeCompra(int idCompra) {
    try {
        std::unique_ptr<sql::PreparedStatement> q(globalCon->prepareStatement(
            "SELECT ID_EMPLEADO FROM COMPRAS WHERE ID_COMPRA = ?"));
        q->setInt(1, idCompra);
        std::unique_ptr<sql::ResultSet> r(q->executeQuery());
        int id = 0;
        if (r->next()) { try { id = r->getInt("ID_EMPLEADO"); } catch (...) {} }
        drenarResultados(q.get());
        return id;
    } catch (const exception &) { return 0; }
}

static string etiquetaEmpleado(int idEmp, bool esDueno) {
    string n;
    if (idEmp > 0) {
        try {
            std::unique_ptr<sql::PreparedStatement> q(globalCon->prepareStatement(
                "SELECT NOMBRE FROM EMPLEADOS WHERE ID_EMPLEADO = ?"));
            q->setInt(1, idEmp);
            std::unique_ptr<sql::ResultSet> r(q->executeQuery());
            if (r->next()) n = r->getString("NOMBRE");
            drenarResultados(q.get());
        } catch (const exception &) {}
    }
    if (n.empty()) n = "DUENO";
    else if (esDueno) n += " (dueno)";
    return n;
}

static void pagarCompra(const CierreCompra &c) {
    if (c.idCompra <= 0) return;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_LISTAR_METODOS_PAGO()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        cout << "\n--- METODOS DE PAGO ---" << endl;
        bool hay = false;
        while (rl->next()) {
            hay = true;
            cout << rl->getInt("ID_METODO_PAGO") << " | " << rl->getString("NOMBRE") << endl;
        }
        if (!hay) cout << "Sin metodos registrados." << endl;
        drenarResultados(pl.get());
        if (!hay) return;

        int idMetodo = (int)leerNumeroConIntentos("ID metodo: ", 1, 999999999);
        cout << "A pagar: $" << c.bruto << endl;
        double pagado = leerNumeroConIntentos("Monto pagado (Enter = " + dinero(c.bruto) + "): ", 0.01, c.bruto, &c.bruto);
        if (pagado != c.bruto) cout << "Monto pagado: $" << pagado << endl;
        double defCero = 0.0;
        string nomDueno = etiquetaEmpleado(duenoDeCompra(c.idCompra), true);
        double empVal = leerNumeroConIntentos("ID empleado que paga (Enter = " + nomDueno + "): ", 0, 999999999, &defCero);
        if (empVal > 0) {
            cout << "Empleado que paga: " << etiquetaEmpleado((int)empVal, false) << endl;
        }
        std::unique_ptr<sql::PreparedStatement> pp(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_PAGO_COMPRA(?, ?, ?, ?)"));
        pp->setInt(1, c.idCompra);
        pp->setInt(2, idMetodo);
        pp->setDouble(3, pagado);
        if (empVal <= 0) pp->setNull(4, sql::DataType::INTEGER);
        else pp->setInt(4, (int)empVal);
        string msg = Recogermensaje(pp.get());
        drenarResultados(pp.get());
        cout << VERDE << msg << RESET << endl;

        std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
            "CALL SP_COMPRA_ENCABEZADO(?)"));
        pe->setInt(1, c.idCompra);
        std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
        if (re->next()) {
            cout << "Estado final: " << re->getString("ESTADO") << endl;
            if (re->getString("ESTADO") != "RECIBIDA")
                printf("Saldo restante: $%.2f\n", c.bruto - pagado);
        }
        drenarResultados(pe.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "Pago fallido: " << e.what() << RESET << endl;
    }
}

static void listarProductosParaCompra() {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO('')"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        // Grilla: ID_PROD | NOMBRE | CANTIDAD(stock). El suplidor se elige despues.
        // (08/11/2026) tablaCelda en vez de printf: el nombre del producto puede
        // traer acentos o simbolos y corria las columnas del borde.
        const size_t W0 = 7, W1 = 25, W2 = 8;
        string borde = "+" + string(W0 + 2, '-') + "+" + string(W1 + 2, '-') + "+"
                     + string(W2 + 2, '-') + "+";
        cout << "\n" << borde << "\n"
             << "| " << tablaCelda("ID_PROD", W0)
             << " | " << tablaCelda("NOMBRE", W1)
             << " | " << tablaCelda("CANTIDAD", W2) << " |\n"
             << borde << "\n";
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK"); } catch (...) { stock = 0; }
            cout << "| " << tablaCelda(to_string(res->getInt("ID_PRODUCTO")), W0)
                 << " | " << tablaCelda(res->getString("NOMBRE"), W1)
                 << " | " << tablaCelda(to_string(stock), W2) << " |\n";
        }
        cout << borde << endl;
        if (!hay) cout << "[!] Sin productos activos." << endl;
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudo listar productos." << RESET << endl;
    }
}

static void compraRapida() {
    cout << "\n--- COMPRA RAPIDA ---" << endl;
    double tasa = tasaIVAC();
    listarProductosParaCompra();
    cout << "Codigo de barra, ID o nombre. Vacio para cerrar." << endl;
    vector<LineaCompra> carrito;
    while (true) {
        try {
        string entrada;
        try {
            entrada = leerDatoSeguro("Producto: ");
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            break;
        }
        if (entrada.empty()) break;
        LineaCompra prod;
        if (!resolverProductoC(entrada, prod)) {
            cout << ROJO << "Sin coincidencia." << RESET << endl;
            continue;
        }
        cout << "Producto: " << prod.idProducto << " (" << prod.nombre << ")" << endl;
        cout << "Stock actual: " << stockDeC(prod.idProducto) << endl;
        int cant = (int)leerNumeroConIntentos("Cantidad: ", 1, 999999999);
        double precio = leerNumeroConIntentos("Precio de factura c/u $ (con ITBIS): ", 0.01, 999999999.99);
        mostrarHistorialPrecios(prod.idProducto);
        if (!elegirSuplidor(prod)) {
            cout << ROJO << "Sin suplidor no hay linea." << RESET << endl;
            continue;
        }
        bool existe = false;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto && l.precioCompra == precio
                && l.idProveedor == prod.idProveedor) {
                l.cantidad += cant;
                existe = true;
                break;
            }
        }
        if (!existe) {
            prod.cantidad = cant;
            prod.precioCompra = precio;
            carrito.push_back(prod);
        }
        mostrarCarritoCompra(carrito, tasa);
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            break;
        }
    }
    if (carrito.empty()) {
        cout << "Carrito vacio." << endl;
        return;
    }
    mostrarCarritoCompra(carrito, tasa);
    // Una factura = un suplidor: se parte el carrito por suplidor.
    vector<int> suplidores;
    for (auto &l : carrito) {
        bool visto = false;
        for (int s : suplidores) if (s == l.idProveedor) { visto = true; break; }
        if (!visto) suplidores.push_back(l.idProveedor);
    }
    if (suplidores.size() > 1) {
        cout << AZUL << "Mezclaste " << suplidores.size()
             << " suplidores: se crean " << suplidores.size() << " compras (una por factura)." << RESET << endl;
    }
    while (true) {
        string cerrar = leerDatoSeguro("Cerrar compra? (s/n): ");
        if (cerrar != "s" && cerrar != "S") {
            cout << "Compra no guardada." << endl;
            return;
        }
        bool todoOk = true;
        for (size_t gi = 0; gi < suplidores.size(); ++gi) {
            int sup = suplidores[gi];
            vector<LineaCompra> grupo;
            double brutoGrupo = 0.0;
            string nomSup;
            for (auto &l : carrito) if (l.idProveedor == sup) {
                grupo.push_back(l);
                brutoGrupo += l.precioCompra * l.cantidad;
                nomSup = l.nombreProveedor;
            }
            printf("\n=========== FACTURA %d DE %d: %d - %s ($%.2f) ===========\n",
                   (int)gi + 1, (int)suplidores.size(), sup, nomSup.c_str(), brutoGrupo);
            CierreCompra c = cerrarCompraForzada(grupo, sup);
            if (c.idCompra <= 0) { todoOk = false; break; }
            string pagar = leerDatoSeguro("Pagar compra #" + to_string(c.idCompra) + " ahora? (s/n): ");
            if (pagar == "s" || pagar == "S") pagarCompra(c);
            else cout << "Queda ABIERTA para pagar despues." << endl;
        }
        if (todoOk) return;
    }
}

// (08/11/2026) Listado paginado de compras, compartido por "Ver compra con
// IVA", "Devolucion de compra" y "Cancelar compra": las tres piden un ID y
// antes lo pedian a ciegas (o traian las ultimas 20 sin forma de llegar a una
// vieja). El LIMIT vive en SP_COMPRAS_ULTIMAS_PAGINADO (modulo 39).
static int listarComprasPaginado() {
    const size_t W_ID = 6, W_PROV = 22, W_FEC = 10, W_EST = 10, W_TOT = 12;
    const size_t ANCHO = W_ID + W_PROV + W_FEC + W_EST + W_TOT + 4 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("PROVEEDOR", W_PROV) << " | "
         << tablaCelda("FECHA", W_FEC) << " | "
         << tablaCelda("ESTADO", W_EST) << " | "
         << tablaCelda("TOTAL", W_TOT) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginadoSP(
        "CALL SP_COMPRAS_ULTIMAS_PAGINADO(?, ?)",
        "CALL SP_CONTAR_COMPRAS()",
        {},
        [=](sql::ResultSet *res) {
            char total[24];
            snprintf(total, sizeof(total), "%.2f", (double)res->getDouble("TOTAL_CON_IVA"));
            string estado = res->getString("ESTADO");
            cout << tablaCelda(to_string(res->getInt("ID_COMPRA")), W_ID) << " | "
                 << tablaCelda(res->getString("PROVEEDOR"), W_PROV) << " | "
                 << tablaCelda(res->getString("FECHA"), W_FEC) << " | "
                 << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << " | "
                 << tablaCelda(total, W_TOT) << "\n"
                 << tablaLinea(ANCHO) << "\n";
        });
}

static void verCompraConIVA() {
    cout << "\n--- COMPRAS REGISTRADAS ---" << endl;
    try {
        // (08/11/2026) Antes imprimia la factura completa de las ultimas 20
        // compras: una pared de texto. Ahora lista de 10 en 10 y muestra la
        // factura de la que se elige.
        if (listarComprasPaginado() == 0) {
            cout << "[!] Sin compras registradas." << endl;
            return;
        }
        int idCompra = (int)leerNumeroConIntentos("ID compra a ver: ", 1, 999999999);
        mostrarFacturaCompra(idCompra);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "Error al consultar compras." << RESET << endl;
    }
}

static void devolucionCompraUI() {
    cout << "\n--- DEVOLUCION DE COMPRA ---" << endl;
    try {
        if (listarComprasPaginado() == 0) {
            cout << "[!] Sin compras registradas." << endl;
            return;
        }
        int idCompraDev = (int)leerNumeroConIntentos("ID compra: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRA_LINEAS(?)"));
        pl->setInt(1, idCompraDev);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        // (08/11/2026) tablaCelda (printf contaba bytes).
        const size_t W_DET = 8, W_PRO = 25, W_CAN = 4, W_PRE = 10;
        const size_t ANCHO = W_DET + W_PRO + W_CAN + W_PRE + 3 * 3;
        cout << "\n"
             << tablaCelda("ID_DET", W_DET) << " | "
             << tablaCelda("PRODUCTO", W_PRO) << " | "
             << tablaCelda("CANT", W_CAN) << " | "
             << tablaCelda("PRECIO", W_PRE) << "\n"
             << tablaLinea(ANCHO) << "\n";
        bool hay = false;
        while (rl->next()) {
            hay = true;
            char precio[24];
            snprintf(precio, sizeof(precio), "%.2f", (double)rl->getDouble("PRECIO_UNITARIO"));
            cout << tablaCelda(to_string(rl->getInt("ID_DETALLE_COMPRA")), W_DET) << " | "
                 << tablaCelda(rl->getString("NOMBRE"), W_PRO) << " | "
                 << tablaCelda(to_string(rl->getInt("CANTIDAD")), W_CAN) << " | "
                 << tablaCelda(precio, W_PRE) << "\n"
                 << tablaLinea(ANCHO) << "\n";
        }
        drenarResultados(pl.get());
        if (!hay) {
            cout << "[!] La compra no tiene lineas." << endl;
            return;
        }
        int idDet = (int)leerNumeroConIntentos("ID detalle: ", 1, 999999999);
        int idEmp = (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        int cantDev = (int)leerNumeroConIntentos("Cantidad: ", 1, 999999999);
        string motivo = leerDatoSeguro("Motivo: ");
        if (motivo.empty()) {
            cout << ROJO << "El motivo es obligatorio." << RESET << endl;
            return;
        }
        string condStr = leerDatoSeguro("Condicion [BUENO/DANADO/USADO] (Enter = BUENO): ");
        string cond = "BUENO";
        if (!condStr.empty()) {
            if (condStr != "BUENO" && condStr != "DANADO" && condStr != "USADO") {
                cout << ROJO << "Condicion invalida." << RESET << endl;
                return;
            }
            cond = condStr;
        }
        std::unique_ptr<sql::PreparedStatement> pr0(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_DEVOLUCION_COMPRA(?, ?, ?, ?, ?, @dv)"));
        pr0->setInt(1, idDet);
        pr0->setInt(2, idEmp);
        pr0->setInt(3, cantDev);
        pr0->setString(4, motivo);
        pr0->setString(5, cond);
        pr0->execute();
        drenarResultados(pr0.get());
        std::unique_ptr<sql::Statement> stmt2(globalCon->createStatement());
        std::unique_ptr<sql::ResultSet> ri(stmt2->executeQuery("SELECT @dv AS IDD"));
        int idDev = 0;
        if (ri->next()) {
            try { idDev = ri->getInt("IDD"); } catch (...) { idDev = 0; }
        }
        drenarResultados(stmt2.get());
        if (idDev <= 0) {
            cout << ROJO << "No se pudo registrar la devolucion." << RESET << endl;
            return;
        }
        cout << "Devolucion #" << idDev << " PENDIENTE." << endl;
        string dec = leerDatoSeguro("Procesar / Rechazar / Enter deja PENDIENTE [p/r/Enter]: ");
        if (dec == "p" || dec == "P") {
            std::unique_ptr<sql::PreparedStatement> pa(globalCon->prepareStatement(
                "CALL SP_PROCESAR_DEVOLUCION_COMPRA(?, 'PROCESADA', NULL)"));
            pa->setInt(1, idDev);
            cout << ">>> " << Recogermensaje(pa.get()) << " <<<" << endl;
            drenarResultados(pa.get());
        } else if (dec == "r" || dec == "R") {
            string mot2 = leerDatoSeguro("Motivo del rechazo: ");
            if (mot2.empty()) {
                cout << ROJO << "El motivo es obligatorio." << endl;
                return;
            }
            std::unique_ptr<sql::PreparedStatement> pr(globalCon->prepareStatement(
                "CALL SP_PROCESAR_DEVOLUCION_COMPRA(?, 'RECHAZADA', ?)"));
            pr->setInt(1, idDev);
            pr->setString(2, mot2);
            cout << ">>> " << Recogermensaje(pr.get()) << " <<<" << endl;
            drenarResultados(pr.get());
        } else {
            cout << "Queda PENDIENTE." << endl;
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo registrar la devolucion." << RESET << endl;
    }
}

static int diasEnMesC(int ano, int mes) {
    if (mes == 2) {
        if ((ano % 4 == 0 && ano % 100 != 0) || (ano % 400 == 0)) return 29;
        return 28;
    }
    if (mes == 4 || mes == 6 || mes == 9 || mes == 11) return 30;
    return 31;
}

static const char *nombreMesC(int mes) {
    static const char *nombres[] = {"", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                                    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"};
    if (mes < 1 || mes > 12) return "";
    return nombres[mes];
}

static string fmt2C(int n) {
    char buf[8];
    snprintf(buf, sizeof(buf), "%02d", n);
    return string(buf);
}

static void reportePeriodoCompraUI() {
    cout << "\n--- REPORTE DE COMPRAS POR PERIODO ---" << endl;
    try {
        int ano = (int)leerNumeroConIntentos("Ano del reporte (ej. 2026): ", 2000, 2100);
        int mesInicio = (int)leerNumeroConIntentos("Mes inicial (1-12): ", 1, 12);
        int mesFin = (int)leerNumeroConIntentos("Mes final (1-12): ", 1, 12);
        if (ano < 2000 || ano > 2100 || mesInicio < 1 || mesInicio > 12 ||
            mesFin < 1 || mesFin > 12 || mesInicio > mesFin) {
            cout << ROJO << "Rango de meses invalido." << RESET << endl;
            return;
        }

        int transGlobal = 0;
        double subGlobal = 0.0, itbisGlobal = 0.0, brutoGlobal = 0.0;

        for (int m = mesInicio; m <= mesFin; ++m) {
            int maxDias = diasEnMesC(ano, m);
            cout << "\n[Mes: " << nombreMesC(m) << " " << ano << "]" << endl;
            cout << "  1. Mes completo" << endl;
            cout << "  2. Rango de dias (max " << maxDias << ")" << endl;
            double dUnoC = 1;
            string modoStr = leerNumeroConIntentos("Opcion: ", 1, 2, &dUnoC) == 2 ? "2" : "1";

            int dIni = 1, dFin = maxDias;
            string filtro = "Mes completo";
            if (modoStr == "2") {
                dIni = (int)leerNumeroConIntentos("Dia de inicio (1-" + to_string(maxDias) + "): ", 1, maxDias);
                dFin = (int)leerNumeroConIntentos("Dia de fin (1-" + to_string(maxDias) + "): ", dIni, maxDias);
                filtro = "Dias " + to_string(dIni) + " al " + to_string(dFin);
            }

            string desde = to_string(ano) + "-" + fmt2C(m) + "-" + fmt2C(dIni);
            string hasta = to_string(ano) + "-" + fmt2C(m) + "-" + fmt2C(dFin);

            std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                "CALL SP_REPORTE_PERIODO_COMPRA(?, ?)"));
            pstmt->setString(1, desde);
            pstmt->setString(2, hasta);
            std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
            int trans = 0;
            double sub = 0.0, itbis = 0.0, bruto = 0.0;
            if (res->next()) {
                trans = res->getInt("TRANSACCIONES");
                sub = res->getDouble("SUBTOTAL");
                itbis = res->getDouble("ITBIS");
                bruto = res->getDouble("BRUTO");
            }
            drenarResultados(pstmt.get());

            transGlobal += trans;
            subGlobal += sub;
            itbisGlobal += itbis;
            brutoGlobal += bruto;

            cout << "\n--------------------------------------------------" << endl;
            cout << " [ " << nombreMesC(m) << " " << ano << " ]" << endl;
            cout << "--------------------------------------------------" << endl;
            printf(" %-14s: %s\n", "Filtro", filtro.c_str());
            printf(" %-14s: %d\n", "Transacciones", trans);
            printf(" %-14s: $%.2f\n", "Subtotal", sub);
            printf(" %-14s: $%.2f\n", "ITBIS", itbis);
            printf(" %-14s: $%.2f\n", "Total", bruto);
        }

        cout << "\n===================================================" << endl;
        cout << " RESUMEN CONSOLIDADO (" << nombreMesC(mesInicio) << " - " << nombreMesC(mesFin) << " " << ano << ")" << endl;
        cout << "===================================================" << endl;
        printf(" %-14s: %d\n", "Transacciones", transGlobal);
        printf(" %-14s: $%.2f\n", "Subtotal", subGlobal);
        printf(" %-14s: $%.2f\n", "ITBIS", itbisGlobal);
        printf(" %-14s: $%.2f\n", "Gran total", brutoGlobal);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo generar el reporte." << RESET << endl;
    }
}

static void pagarCompraPendienteUI() {
    cout << "\n--- PAGAR COMPRA ABIERTA ---" << endl;
    try {
        // (08/11/2026) Paginado de 10 en 10: antes traia las 20 mas recientes y
        // una pendiente vieja quedaba inalcanzable.
        const size_t W_ID = 7, W_PROV = 22, W_EST = 10, W_MON = 10;
        const size_t ANCHO = W_ID + W_PROV + W_EST + W_MON * 2 + 4 * 3;
        cout << "\n"
             << tablaCelda("COMPRA", W_ID) << " | "
             << tablaCelda("PROVEEDOR", W_PROV) << " | "
             << tablaCelda("ESTADO", W_EST) << " | "
             << tablaCelda("PAGADO", W_MON) << " | "
             << tablaCelda("SALDO", W_MON) << "\n"
             << tablaLinea(ANCHO) << "\n";

        const int hay = mostrarPaginadoSP(
            "CALL SP_COMPRAS_PENDIENTES_PAGINADO(?, ?)",
            "CALL SP_CONTAR_COMPRAS_PENDIENTES()",
            {},
            [=](sql::ResultSet *res) {
                char pagado[24], saldo[24];
                snprintf(pagado, sizeof(pagado), "%.2f", (double)res->getDouble("PAGADO"));
                snprintf(saldo, sizeof(saldo), "%.2f", (double)res->getDouble("SALDO"));
                string estado = res->getString("ESTADO");
                cout << tablaCelda(to_string(res->getInt("ID_COMPRA")), W_ID) << " | "
                     << tablaCelda(res->getString("PROVEEDOR"), W_PROV) << " | "
                     << tablaColorEstado(estado) << tablaCelda(estado, W_EST) << RESET << " | "
                     << tablaCelda(pagado, W_MON) << " | "
                     << tablaCelda(saldo, W_MON) << "\n"
                     << tablaLinea(ANCHO) << "\n";
            });

        if (hay == 0) {
            cout << "[!] Sin compras pendientes." << endl;
            return;
        }

        int idCompraPag = (int)leerNumeroConIntentos("ID compra: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_COMPRAS_PENDIENTES()"));
        std::unique_ptr<sql::ResultSet> rs(ps->executeQuery());
        double saldo = -1.0;
        while (rs->next()) {
            if (rs->getInt("ID_COMPRA") == idCompraPag) saldo = rs->getDouble("SALDO");
        }
        drenarResultados(ps.get());
        if (saldo < 0) {
            cout << ROJO << "Esa compra no esta pendiente." << RESET << endl;
            return;
        }
        CierreCompra c;
        c.idCompra = idCompraPag;
        c.idEmpleado = 0;
        c.subtotal = saldo;
        c.bruto = saldo;
        pagarCompra(c);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo pagar." << RESET << endl;
    }
}

static void cancelarCompraUI() {
    cout << "\n--- CANCELAR COMPRA ---" << endl;
    cout << "Solo compras ABIERTA sin pagos. Repone el stock." << endl;
    try {
        if (listarComprasPaginado() == 0) {
            cout << "[!] Sin compras registradas." << endl;
            return;
        }
        int idCompraCanc = (int)leerNumeroConIntentos("ID compra: ", 1, 999999999);
        int idEmpCanc = (int)leerNumeroConIntentos("ID empleado (dueno): ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CANCELAR_COMPRA(?, ?)"));
        pstmt->setInt(1, idCompraCanc);
        pstmt->setInt(2, idEmpCanc);
        cout << ">>> " << Recogermensaje(pstmt.get()) << " <<<" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo cancelar (verifica estado, pagos y dueno)." << RESET << endl;
    }
}

static void verPreciosCompraUI() {
    cout << "\n--- PRECIOS POR SUPLIDOR (barato y caro) ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_REPORTE_PRECIOS_COMPRA()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        const size_t W_PROD = 25, W_SUP = 10, W_BAR = 10, W_DONDE_BAR = 25,
                     W_CARO = 10, W_DONDE_CAR = 25, W_ULT = 10;
        const size_t ANCHO = W_PROD + W_SUP + W_BAR + W_DONDE_BAR + W_CARO +
                             W_DONDE_CAR + W_ULT + 6 * 3;
        cout << "\n"
             << tablaCelda("PRODUCTO", W_PROD) << " | "
             << tablaCelda("SUPLIDORES", W_SUP) << " | "
             << tablaCelda("MAS BARATO", W_BAR) << " | "
             << tablaCelda("BARATO EN", W_DONDE_BAR) << " | "
             << tablaCelda("MAS CARO", W_CARO) << " | "
             << tablaCelda("CARO EN", W_DONDE_CAR) << " | "
             << tablaCelda("ULTIMA", W_ULT) << "\n"
             << tablaLinea(ANCHO) << "\n";
        bool hay = false;
        while (res->next()) {
            hay = true;
            char masBarato[24], masCaro[24];
            snprintf(masBarato, sizeof(masBarato), "%.2f", (double)res->getDouble("MAS_BARATO"));
            snprintf(masCaro, sizeof(masCaro), "%.2f", (double)res->getDouble("MAS_CARO"));
            cout << tablaCelda(res->getString("PRODUCTO"), W_PROD) << " | "
                 << tablaCelda(to_string(res->getInt("SUPLIDORES")), W_SUP) << " | "
                 << tablaCelda(masBarato, W_BAR) << " | "
                 << tablaCelda(res->getString("DONDE_BARATO"), W_DONDE_BAR) << " | "
                 << tablaCelda(masCaro, W_CARO) << " | "
                 << tablaCelda(res->getString("DONDE_CARO"), W_DONDE_CAR) << " | "
                 << tablaCelda(res->getString("ULTIMA_COMPRA"), W_ULT) << "\n"
                 << tablaLinea(ANCHO) << "\n";
        }
        if (!hay) cout << "[!] Sin datos: ninguna compra RECIBIDA aun." << endl;
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el reporte." << RESET << endl;
    }
}

// Submenu de compras: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion. Cada accion pide su permiso
// fino (COMPRAS_REGISTRAR, VER, DEVOLVER, REPORTES, PAGAR o CANCELAR).
void ejecutarSubmenuCompras() {
    for (;;) {
        vector<const OpcionCompra*> visibles = opcionesVisibles();
        imprimirMenuCompras(visibles);

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

        const OpcionCompra& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionCompra::Registrar: compraRapida(); break;
            case AccionCompra::Ver:       verCompraConIVA(); break;
            case AccionCompra::Devolver:  devolucionCompraUI(); break;
            case AccionCompra::Reportes:  reportePeriodoCompraUI(); break;
            case AccionCompra::Pagar:     pagarCompraPendienteUI(); break;
            case AccionCompra::Precios:   verPreciosCompraUI(); break;
            case AccionCompra::Cancelar:  cancelarCompraUI(); break;
            case AccionCompra::Volver:    return;
        }
        pausar();
    }
}
