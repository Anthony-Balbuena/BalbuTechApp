#include <cctype>
#include <cmath>
#include <cstdio>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>
#include "colores.h"
#include "database.h"
#include "seguridad.h"
#include "caja.h"
#include "roles.h"
#include "tabla.h"
#include "web_export.h"
#include "ventas.h"

using namespace std;

struct LineaCarrito {
    int idProducto = 0;
    string codigo;
    string nombre;
    double precio = 0.0;
    int cantidad = 0;
    double descuento = 0.0; // % de descuento de la línea (16/10/2026)
};

namespace {

enum class AccionVenta {
    VentaRapida, VerVentaIVA, CancelarVenta, AnularPago, Devolucion,
    ReporteRango, CierreCaja, Ganancias, CobrarVenta, ReportePeriodo,
    GananciasPeriodo, Garantias, Historial, ExportarWeb, Volver
};

struct OpcionVenta {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionVenta accion;
};

// (22/10/2026) Menu por permisos: las acciones sobre una venta piden
// GESTIONAR_VENTAS y las de lectura/reportes CONSULTAR_REPORTES. Antes la lista
// era fija y despachaba por numero, asi que un rol con GESTIONAR_VENTAS pero sin
// CONSULTAR_REPORTES veia igual los reportes (y la exportacion web, que era el
// unico caso con chequeo adentro del switch).
// (23/10/2026) El historial de venta tiene permiso propio
// (CONSULTAR_HISTORIAL_VENTA) para que VENDEDOR lo vea sin CONSULTAR_REPORTES.
// Garantias sigue con GESTIONAR_VENTAS: no se creo un permiso nuevo para ella.
static const vector<OpcionVenta>& opcionesVentas() {
    static const vector<OpcionVenta> opciones = {
        {"Venta rapida (carrito)",       "GESTIONAR_VENTAS",   AccionVenta::VentaRapida},
        {"Ver venta con IVA",            "GESTIONAR_VENTAS",   AccionVenta::VerVentaIVA},
        {"Cancelar venta",               "GESTIONAR_VENTAS",   AccionVenta::CancelarVenta},
        {"Anular pago",                  "GESTIONAR_VENTAS",   AccionVenta::AnularPago},
        {"Devolucion de venta",          "GESTIONAR_VENTAS",   AccionVenta::Devolucion},
        {"Reporte por rango",            "CONSULTAR_REPORTES", AccionVenta::ReporteRango},
        {"Cierre de caja",               "GESTIONAR_VENTAS",   AccionVenta::CierreCaja},
        {"Ganancias",                    "CONSULTAR_REPORTES", AccionVenta::Ganancias},
        {"Cobrar venta",                 "GESTIONAR_VENTAS",   AccionVenta::CobrarVenta},
        {"Reporte por periodo",          "CONSULTAR_REPORTES", AccionVenta::ReportePeriodo},
        {"Ganancias por periodo",        "CONSULTAR_REPORTES", AccionVenta::GananciasPeriodo},
        {"Garantias",                    "GESTIONAR_VENTAS",   AccionVenta::Garantias},
        {"Historial de venta",           "CONSULTAR_HISTORIAL_VENTA", AccionVenta::Historial},
        {"Exportar datos para la web",   "CONSULTAR_REPORTES", AccionVenta::ExportarWeb},
        {"Volver al Menu Principal",     "",                   AccionVenta::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionVenta& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionVenta*> opcionesVisibles() {
    vector<const OpcionVenta*> visibles;
    for (const OpcionVenta& opcion : opcionesVentas()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuVentas(const vector<const OpcionVenta*>& visibles) {
    cout << "\n=== MODULO DE VENTAS ===" << endl;
    int n = 0;
    for (const OpcionVenta* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "========================" << endl;
}

}  // namespace

static bool buscarPorId(int id, LineaCarrito &out) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
        pstmt->setString(1, to_string(id));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool ok = false;
        while (!ok && res->next()) {
            if (res->getInt("ID_PRODUCTO") == id && res->getString("ESTADO") == "ACTIVO") {
                out.idProducto = id;
                out.codigo = res->getString("CODIGO");
                out.nombre = res->getString("NOMBRE");
                out.precio = res->getDouble("PRECIO");
                ok = true;
            }
        }
        drenarResultados(pstmt.get());
        return ok;
    } catch (const exception &) {
        return false;
    }
}

static bool buscarPorCodigo(const string &codigo, LineaCarrito &out) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
        pstmt->setString(1, codigo);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool ok = false;
        while (!ok && res->next()) {
            if (res->getString("CODIGO") == codigo && res->getString("ESTADO") == "ACTIVO") {
                out.idProducto = res->getInt("ID_PRODUCTO");
                out.codigo = codigo;
                out.nombre = res->getString("NOMBRE");
                out.precio = res->getDouble("PRECIO");
                ok = true;
            }
        }
        drenarResultados(pstmt.get());
        return ok;
    } catch (const exception &) {
        return false;
    }
}

static int stockDe(int idProducto) {
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

static bool resolverProducto(const string &entrada, LineaCarrito &out) {
    if (esNumerico(entrada)) {
        if (buscarPorId(stoi(entrada), out)) return true;
    }
    if (buscarPorCodigo(entrada, out)) return true;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
        pstmt->setString(1, entrada);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        struct Cand { int id; string codigo; string nombre; double precio; };
        vector<Cand> lista;
        while (res->next()) {
            Cand c;
            c.id = res->getInt("ID_PRODUCTO");
            c.codigo = res->getString("CODIGO");
            c.nombre = res->getString("NOMBRE");
            c.precio = res->getDouble("PRECIO");
            lista.push_back(c);
        }
        drenarResultados(pstmt.get());
        if (lista.empty()) return false;
        if (lista.size() == 1) {
            out.idProducto = lista[0].id;
            out.codigo = lista[0].codigo;
            out.nombre = lista[0].nombre;
            out.precio = lista[0].precio;
            return true;
        }
        cout << "\nCoincidencias:" << endl;
        for (auto &c : lista) {
            cout << c.id << " | " << c.codigo << " | " << c.nombre << " | $" << c.precio << endl;
        }
        int pick = (int)leerNumeroConIntentos("ID elegido: ", 1, 999999999);
        return buscarPorId(pick, out);
    } catch (const exception &) {
        return false;
    }
}

static double tasaIVA() {
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

// (17/10/2026) Aviso de stock minimo: NO bloquea, solo avisa.
// cantPorDescontar = lo que falta descontar (pre-venta: lo del carrito;
// post-venta: 0 porque el descuento ya ocurrio).
static void avisoStockCritico(int idProducto, int cantPorDescontar) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_INVENTARIO(?)"));
        pstmt->setString(1, to_string(idProducto));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        while (res->next()) {
            if (res->getInt("ID_PRODUCTO") != idProducto) continue;
            int stock = 0, minimo = 0;
            try { stock = res->getInt("STOCK_ACTUAL"); } catch (...) {}
            try { minimo = res->getInt("STOCK_MINIMO"); } catch (...) {}
            int quedan = stock - cantPorDescontar;
            if (quedan <= minimo) {
                string estado = (quedan <= 0) ? "AGOTADO" : "CRITICO";
                cout << AMARILLO << "[!] " << res->getString("NOMBRE")
                     << ": quedan " << quedan << " (minimo " << minimo
                     << ") - " << estado << ", considera reponer." << RESET << endl;
            }
            break;
        }
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        // Sin poder consultar no molesta la venta.
    }
}

static void mostrarCarrito(const vector<LineaCarrito> &carrito, double tasa) {
    cout << "\n--- CARRITO (precios con IVA) ---" << endl;
    double total = 0.0;
    for (size_t i = 0; i < carrito.size(); ++i) {
        auto &l = carrito[i];
        // Bruto con descuento; ITBIS redondeado por linea (igual que la base).
        double neto = round(l.precio * l.cantidad * (100.0 - l.descuento)) / 100.0;
        double parcial = neto + round(neto * tasa) / 100.0;
        double unitIVA = round(l.precio * (100.0 - l.descuento) * (100.0 + tasa)) / 10000.0;
        total += parcial;
        cout << (i + 1) << ". " << l.nombre << " x" << l.cantidad;
        if (l.descuento > 0) cout << " -" << l.descuento << "%";
        cout << " | $" << unitIVA << " con ITBIS" << " | total $" << parcial << endl;
    }
    cout << "Total con IVA: $" << total << endl;
}

struct CierreVenta {
    int idVenta = 0;
    int idEmpleado = 0;
    double subtotal = 0.0;
    double bruto = 0.0;
};

static void mostrarFactura(int idVenta);

static void pagarVenta(const CierreVenta &c) {
    if (c.idVenta <= 0) return;
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
        // (11/10/2026) Se cobra el BRUTO; los triggers ya comparan contra el bruto.
        cout << "Total a pagar = $" << c.bruto << endl;
        double recibido = leerNumeroConIntentos("Monto recibido (Enter = " + dinero(c.bruto) + "): ", 0.01, 999999999, &c.bruto);
        if (recibido != c.bruto) cout << "Monto recibido: $" << recibido << endl;
        std::unique_ptr<sql::PreparedStatement> pp(globalCon->prepareStatement(
            "CALL 24_SP_REGISTRAR_PAGO(?, ?, ?, ?, ?)"));
        pp->setInt(1, c.idVenta);
        pp->setInt(2, idMetodo);
        pp->setDouble(3, c.bruto);
        pp->setInt(4, c.idEmpleado);
        pp->setDouble(5, recibido);
        string msg = Recogermensaje(pp.get());
        drenarResultados(pp.get());
        cout << VERDE << msg << RESET << endl;

        std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
            "CALL SP_VENTA_ESTADO(?)"));
        pe->setInt(1, c.idVenta);
        std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
        if (re->next()) cout << "Estado final: " << re->getString("ESTADO") << endl;
        drenarResultados(pe.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "Pago fallido: " << e.what() << RESET << endl;
    }
}

static CierreVenta cerrarVenta(const vector<LineaCarrito> &carrito) {
    CierreVenta out;
    if (carrito.empty()) return out;
    int idEmp = 0, idCli = 0, idVenta = 0;
    try {
        bool iniciada = false;
        for (int intento = 1; intento <= MAX_INTENTOS && !iniciada; ++intento) {
            try {
                string empStr = leerDatoSeguro("ID empleado: ");
                string cliStr = leerDatoSeguro("ID cliente: ");
                if (!esNumerico(empStr) || !esNumerico(cliStr)) {
                    cout << ROJO << "IDs invalidos (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
                    continue;
                }
                idEmp = stoi(empStr);
                idCli = stoi(cliStr);

                std::unique_ptr<sql::Statement> stmt(globalCon->createStatement());
                stmt->execute("CALL 21_SP_INICIAR_VENTA(" + to_string(idEmp) + ", " + to_string(idCli) + ", @nv)");
                {
                    // La llamada deja el MENSAJE como result-set pendiente: hay que
                    // consumirlo antes de pedir @nv o cae "Commands out of sync".
                    std::unique_ptr<sql::ResultSet> r0(stmt->getResultSet());
                    if (r0) { while (r0->next()) {} }
                }
                drenarResultados(stmt.get());
                std::unique_ptr<sql::Statement> stmt2(globalCon->createStatement());
                std::unique_ptr<sql::ResultSet> resId(stmt2->executeQuery("SELECT @nv AS IDV"));
                idVenta = 0;
                if (resId->next()) {
                    try { idVenta = resId->getInt("IDV"); } catch (...) { idVenta = 0; }
                }
                drenarResultados(stmt2.get());
                if (idVenta <= 0) {
                    cout << ROJO << "No se pudo iniciar la venta (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
                    continue;
                }
                iniciada = true;
            } catch (const CancelarOperacionException &) {
                throw;
            } catch (const exception &e) {
                idVenta = 0;
                cout << ROJO << e.what() << " (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
            }
        }
        if (!iniciada) {
            cout << ROJO << "Venta no iniciada. El carrito se mantiene: volve a elegir Cerrar." << RESET << endl;
            return out;
        }
        cout << VERDE << "Venta #" << idVenta << " iniciada." << RESET << endl;

        for (auto &l : carrito) {
            try {
                std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                    "CALL SP_AGREGAR_DETALLE_VENTA(?, ?, ?, ?, ?)"));
                pstmt->setInt(1, idVenta);
                pstmt->setInt(2, l.idProducto);
                pstmt->setInt(3, l.cantidad);
                pstmt->setInt(4, idEmp);
                pstmt->setDouble(5, l.descuento);
                string rLinea = Recogermensaje(pstmt.get());
                drenarResultados(pstmt.get());
                if (rLinea.rfind("Error DB:", 0) == 0) throw runtime_error(rLinea);
            } catch (const exception &e) {
                cout << ROJO << "Linea " << l.nombre << " fallo: " << e.what() << RESET << endl;
                try {
                    std::unique_ptr<sql::PreparedStatement> pc(globalCon->prepareStatement(
                        "CALL SP_CANCELAR_VENTA(?, ?)"));
                    pc->setInt(1, idVenta);
                    pc->setInt(2, idEmp);
                    Recogermensaje(pc.get());
                    drenarResultados(pc.get());
                    cout << "Venta #" << idVenta << " cancelada para no dejar basura." << endl;
                } catch (const exception &) {
                    cout << ROJO << "No se pudo cancelar la venta parcial." << RESET << endl;
                }
                return out;
            }
        }

        // Aviso con el stock real ya descontado (lo pedido: alerta al vender).
        for (auto &l : carrito) avisoStockCritico(l.idProducto, 0);

        std::unique_ptr<sql::PreparedStatement> pv(globalCon->prepareStatement(
            "CALL SP_VENTA_ENCABEZADO(?)"));
        pv->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> res(pv->executeQuery());
        if (res->next()) {
            out.idVenta = idVenta;
            out.idEmpleado = idEmp;
            out.subtotal = res->getDouble("SUBTOTAL");
            out.bruto = res->getDouble("TOTAL_CON_IVA");
        }
        drenarResultados(pv.get());
        if (out.idVenta > 0) {
            cout << "\n=========== BALBUTECH ===========" << endl;
            cout << "--- FACTURA #" << idVenta << " ---" << endl;
            mostrarFactura(idVenta);
        }
        return out;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "Error al cerrar la venta: " << e.what() << RESET << endl;
    }
    return out;
}

static void listarProductosParaVenta(double tasa) {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_INVENTARIO('')"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-5s | %-10s | %-25s | %-10s | %-6s | %-s\n", "ID", "CODIGO", "NOMBRE", "P+IVA", "STOCK", "ESTATUS");
        printf("%s\n", string(78, '-').c_str());
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK_ACTUAL"); } catch (...) { stock = 0; }
            string estatus = "OK";
            try { estatus = res->getString("ESTATUS_STOCK"); } catch (...) {}
            double conIVA = round((double)res->getDouble("PRECIO") * (100.0 + tasa)) / 100.0;
            printf("%-5d | %-10s | %-25.25s | %-10.2f | %-6d | ", 
                   res->getInt("ID_PRODUCTO"),
                   res->getString("CODIGO").c_str(),
                   res->getString("NOMBRE").c_str(),
                   conIVA,
                   stock);
            const string &c = (estatus == "AGOTADO" || estatus == "CR\u00cdTICO") ? ROJO
                              : (estatus == "STOCK BAJO") ? AMARILLO : VERDE;
            cout << c << estatus << RESET << endl;
        }
        if (!hay) cout << "[!] Sin productos activos." << endl;
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudo listar productos." << RESET << endl;
    }
}

static void ventaRapida() {
    cout << "\n--- VENTA RAPIDA ---" << endl;
    if (!hayTurnoAbierto()) {
        cout << "[!] Sin turno de caja abierto: la venta se guarda igual y el"
             " cobro se anota por fecha." << endl;
    }
    double tasa = tasaIVA();
    listarProductosParaVenta(tasa);
    cout << "Codigo de barra, ID o nombre. Vacio para cerrar." << endl;
    vector<LineaCarrito> carrito;
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
        LineaCarrito prod;
        if (!resolverProducto(entrada, prod)) {
            cout << ROJO << "Sin coincidencia." << RESET << endl;
            continue;
        }
        double dUno = 1;
        int cant = (int)leerNumeroConIntentos("Cantidad (1): ", 1, 999999999, &dUno);
        double dCero = 0.0;
        double desc = 0.0;
        bool yaEnCarrito = false;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto) yaEnCarrito = true;
        }
        // El descuento se pide al crear la línea; si el producto ya está,
        // se suman cantidades y se conserva el descuento original.
        if (!yaEnCarrito) {
            desc = leerNumeroConIntentos("Descuento % (Enter = 0): ", 0, 100, &dCero);
        }
        int enCarrito = 0;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto) enCarrito = l.cantidad;
        }
        int stock = stockDe(prod.idProducto);
        if (cant + enCarrito > stock) {
            cout << ROJO << "Stock insuficiente. Hay " << stock << "." << RESET << endl;
            continue;
        }
        bool existe = false;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto) {
                l.cantidad += cant;
                existe = true;
                break;
            }
        }
        if (!existe) {
            prod.cantidad = cant;
            prod.descuento = desc;
            carrito.push_back(prod);
        }
        mostrarCarrito(carrito, tasa);
        // Aviso post-agregado: cuánto quedaría si se cierra la venta ahora.
        int totalEnCarrito = 0;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto) totalEnCarrito = l.cantidad;
        }
        avisoStockCritico(prod.idProducto, totalEnCarrito);
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            break;
        }
    }
    if (!carrito.empty()) mostrarCarrito(carrito, tasa);
    else cout << "Carrito vacio." << endl;
    if (carrito.empty()) return;
    while (true) {
        double dNingunoQ2 = -1;
        int qid = (int)leerNumeroConIntentos("Quitar algo? (ID producto, Enter = no): ", 1, 999999999, &dNingunoQ2);
        if (qid >= 0) {
            size_t antes = carrito.size();
            for (auto it = carrito.begin(); it != carrito.end(); ) {
                if (it->idProducto == qid) it = carrito.erase(it);
                else ++it;
            }
            if (carrito.size() == antes) cout << ROJO << "Ese ID no esta en el carrito." << RESET << endl;
            if (carrito.empty()) { cout << "Carrito vacio." << endl; return; }
            mostrarCarrito(carrito, tasa);
        }
        string cerrar = leerDatoSeguro("Cerrar venta? (s/n): ");
        if (cerrar != "s" && cerrar != "S") {
            cout << "Venta no guardada." << endl;
            return;
        }
        CierreVenta c = cerrarVenta(carrito);
        if (c.idVenta <= 0) continue;
        string pagar = leerDatoSeguro("Pagar ahora? (s/n): ");
        if (pagar == "s" || pagar == "S") pagarVenta(c);
        else cout << "Queda EN_PROCESO para cobrar despues." << endl;
        return;
    }
}

static void mostrarFactura(int idVenta) {
    try {
        std::unique_ptr<sql::PreparedStatement> ph(globalCon->prepareStatement(
            "CALL SP_VENTA_ENCABEZADO(?)"));
        ph->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> rh(ph->executeQuery());
        if (!rh->next()) {
            cout << ROJO << "No existe esa venta." << RESET << endl;
            drenarResultados(ph.get());
            return;
        }
        int vId = rh->getInt("ID_VENTA");
        string vCli = rh->getString("CLIENTE");
        string vFecha = rh->getString("FECHA");
        string vEstado = rh->getString("ESTADO");
        double vSub = rh->getDouble("SUBTOTAL");
        double vItbis = rh->getDouble("ITBIS");
        double vTotal = rh->getDouble("TOTAL_CON_IVA");
        drenarResultados(ph.get());

        cout << "\nID: " << vId << " | Cliente: " << vCli
             << " | Fecha: " << vFecha << " | Estado: "
             << tablaColorEstado(vEstado) << vEstado << RESET << "\n";

        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_VENTA_LINEAS(?)"));
        pl->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        const size_t W_PROD = 25, W_CANT = 4, W_PUNIT = 10, W_DESC = 7,
                     W_ITBIS = 10, W_SUB = 10, W_TOT = 10;
        const size_t ANCHO = W_PROD + W_CANT + W_PUNIT + W_DESC + W_ITBIS +
                             W_SUB + W_TOT + 6 * 3;
        cout << "\n"
             << tablaCelda("Nombre del producto", W_PROD) << " | "
             << tablaCelda("Cant", W_CANT) << " | "
             << tablaCelda("P.UNIT", W_PUNIT) << " | "
             << tablaCelda("DESC", W_DESC) << " | "
             << tablaCelda("ITBIS", W_ITBIS) << " | "
             << tablaCelda("Subtotal", W_SUB) << " | "
             << tablaCelda("Total", W_TOT) << "\n"
             << tablaLinea(ANCHO) << "\n";
        while (rl->next()) {
            double pct = rl->getDouble("PORCENTAJE_DESCUENTO");
            char descCol[16];
            if (pct > 0) snprintf(descCol, sizeof(descCol), "-%.4g%%", pct);
            else snprintf(descCol, sizeof(descCol), "%s", "-");
            char pUnit[24], itbis[24], sub[24], tot[24];
            snprintf(pUnit, sizeof(pUnit), "%.2f", (double)rl->getDouble("PRECIO_UNITARIO"));
            snprintf(itbis, sizeof(itbis), "%.2f", (double)rl->getDouble("MONTO_ITBIS"));
            snprintf(sub, sizeof(sub), "%.2f", (double)rl->getDouble("SUBTOTAL"));
            snprintf(tot, sizeof(tot), "%.2f", (double)rl->getDouble("TOTAL_LINEA"));
            cout << tablaCelda(rl->getString("NOMBRE"), W_PROD) << " | "
                 << tablaCelda(to_string(rl->getInt("CANTIDAD")), W_CANT) << " | "
                 << tablaCelda(pUnit, W_PUNIT) << " | "
                 << tablaCelda(descCol, W_DESC) << " | "
                 << tablaCelda(itbis, W_ITBIS) << " | "
                 << tablaCelda(sub, W_SUB) << " | "
                 << tablaCelda(tot, W_TOT) << "\n"
                 << tablaLinea(ANCHO) << "\n";
        }
        drenarResultados(pl.get());

        char vItbisStr[24], vSubStr[24], vTotStr[24];
        snprintf(vItbisStr, sizeof(vItbisStr), "%.2f", vItbis);
        snprintf(vSubStr, sizeof(vSubStr), "%.2f", vSub);
        snprintf(vTotStr, sizeof(vTotStr), "%.2f", vTotal);
        cout << tablaCelda("Total a pagar =", W_PROD) << " | "
             << tablaCelda("", W_CANT) << " | "
             << tablaCelda("", W_PUNIT) << " | "
             << tablaCelda("", W_DESC) << " | "
             << tablaCelda(vItbisStr, W_ITBIS) << " | "
             << tablaCelda(vSubStr, W_SUB) << " | "
             << tablaCelda(vTotStr, W_TOT) << "\n"
             << tablaLinea(ANCHO) << "\n";
    } catch (const exception &) {
        cout << ROJO << "No se pudo mostrar la factura." << RESET << endl;
    }
}

static void verPagosDeVenta(int idVenta) {
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_PAGOS_POR_VENTA(?)"));
        pl->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-7s | %-12s | %-10s | %-10s | %-15s\n", "ID_PAGO", "METODO", "MONTO", "RECIBIDO", "EMPLEADO");
        bool hay = false;
        while (rl->next()) {
            hay = true;
            printf("%-7d | %-12.12s | %-10.2f | %-10.2f | %-15.15s\n",
                   rl->getInt("ID_PAGO"),
                   rl->getString("NOMBRE_METODO").c_str(),
                   (double)rl->getDouble("MONTO"),
                   (double)rl->getDouble("MONTO_RECIBIDO"),
                   rl->getString("NOMBRE_EMPLEADO").c_str());
        }
        if (!hay) cout << "[!] La venta no tiene pagos." << endl;
        drenarResultados(pl.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudieron ver los pagos." << RESET << endl;
    }
}

static void verVentaConIVA() {
    cout << "\n--- VENTAS REGISTRADAS ---" << endl;

    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_VENTAS_ULTIMAS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        vector<int> ids;
        while (rl->next()) ids.push_back(rl->getInt("ID_VENTA"));
        drenarResultados(pl.get());
        if (ids.empty()) {
            cout << "[!] Sin ventas registradas." << endl;
            return;
        }
        for (int id : ids) mostrarFactura(id);
        double dNinguno = -1;
        int vPagos = (int)leerNumeroConIntentos("Ver pagos de una venta? ID (Enter = omitir): ", 1, 999999999, &dNinguno);
        if (vPagos >= 0) verPagosDeVenta(vPagos);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "Error al consultar ventas." << RESET << endl;
    }
}

static void cancelarVentaUI() {
    cout << "\n--- CANCELAR VENTA ---" << endl;
    cout << "Solo ventas EN_PROCESO sin pagos. Repone el stock." << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_VENTAS_ULTIMAS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-6s | %-20s | %-10s | %-10s\n", "ID", "CLIENTE", "ESTADO", "TOTAL");
        while (rl->next()) {
            printf("%-6d | %-20.20s | %-10s | %-10.2f\n",
                   rl->getInt("ID_VENTA"),
                   rl->getString("CLIENTE").c_str(),
                   rl->getString("ESTADO").c_str(),
                   (double)rl->getDouble("TOTAL_CON_IVA"));
        }
        drenarResultados(pl.get());

        int idVentaCanc = (int)leerNumeroConIntentos("ID venta: ", 1, 999999999);
        int idEmpCanc = (int)leerNumeroConIntentos("ID empleado (dueno): ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CANCELAR_VENTA(?, ?)"));
        pstmt->setInt(1, idVentaCanc);
        pstmt->setInt(2, idEmpCanc);
        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo cancelar (verificá estado, pagos y dueno)." << RESET << endl;
    }
}

static void anularPagoUI() {
    cout << "\n--- ANULAR PAGO ---" << endl;
    cout << "Si la venta estaba REALIZADA, vuelve a EN_PROCESO y cae el bono." << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_PAGOS_ULTIMOS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-7s | %-6s | %-12s | %-10s | %-10s | %-15s\n", "ID_PAGO", "VENTA", "METODO", "MONTO", "RECIBIDO", "EMPLEADO");
        while (rl->next()) {
            printf("%-7d | %-6d | %-12.12s | %-10.2f | %-10.2f | %-15.15s\n",
                   rl->getInt("ID_PAGO"),
                   rl->getInt("ID_VENTA"),
                   rl->getString("NOMBRE_METODO").c_str(),
                   (double)rl->getDouble("MONTO"),
                   (double)rl->getDouble("MONTO_RECIBIDO"),
                   rl->getString("NOMBRE_EMPLEADO").c_str());
        }
        drenarResultados(pl.get());

        int idPagoAnula = (int)leerNumeroConIntentos("ID pago: ", 1, 999999999);
        int idEmpAnula = (int)leerNumeroConIntentos("ID empleado que anula: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_ANULAR_PAGO(?, ?)"));
        pstmt->setInt(1, idPagoAnula);
        pstmt->setInt(2, idEmpAnula);
        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo anular el pago." << RESET << endl;
    }
}

static bool fechaValida(const string &s) {
    if (s.size() != 10 || s[4] != '-' || s[7] != '-') return false;
    int y = 0, m = 0, d = 0;
    if (sscanf(s.c_str(), "%d-%d-%d", &y, &m, &d) != 3) return false;
    return y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
}

static void cierreCajaUI() {
    cout << "\n--- CIERRE DE CAJA ---" << endl;
    try {
        string fecha = leerDatoSeguro("Fecha (AAAA-MM-DD): ");
        if (!fechaValida(fecha)) {
            cout << ROJO << "Formato invalido. Use AAAA-MM-DD." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CIERRE_CAJA(?)"));
        pstmt->setString(1, fecha);
        // Result set 1: resumen del dia (se cierra antes de pedir el siguiente).
        {
            std::unique_ptr<sql::ResultSet> r1(pstmt->executeQuery());
            if (r1->next()) {
                printf("\nFecha: %s | Ventas: %d | Realizado: $%.2f | Cobrado: $%.2f\n",
                       r1->getString("FECHA").c_str(),
                       r1->getInt("VENTAS_DEL_DIA"),
                       (double)r1->getDouble("MONTO_REALIZADO"),
                       (double)r1->getDouble("COBRADO"));
            }
        }
        // Result sets 2 y 3: por estado y por metodo.
        if (pstmt->getMoreResults()) {
            std::unique_ptr<sql::ResultSet> r2(pstmt->getResultSet());
            printf("\n%-12s | %-8s | %-10s\n", "ESTADO", "CANT", "MONTO");
            while (r2 && r2->next()) {
                printf("%-12s | %-8d | %-10.2f\n",
                       r2->getString("ESTADO").c_str(),
                       r2->getInt("CANTIDAD"),
                       (double)r2->getDouble("MONTO"));
            }
            r2.reset();
        }
        if (pstmt->getMoreResults()) {
            std::unique_ptr<sql::ResultSet> r3(pstmt->getResultSet());
            printf("\n%-12s | %-8s | %-10s\n", "METODO", "OPS", "COBRADO");
            while (r3 && r3->next()) {
                printf("%-12.12s | %-8d | %-10.2f\n",
                       r3->getString("METODO").c_str(),
                       r3->getInt("OPERACIONES"),
                       (double)r3->getDouble("COBRADO"));
            }
        }
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo generar el cierre." << RESET << endl;
    }
}

static void reporteVentasUI() {
    cout << "\n--- REPORTE DE VENTAS ---" << endl;
    try {
        string ini = leerDatoSeguro("Fecha inicio (AAAA-MM-DD): ");
        string fin = leerDatoSeguro("Fecha fin (AAAA-MM-DD): ");
        if (!fechaValida(ini) || !fechaValida(fin)) {
            cout << ROJO << "Formato invalido. Use AAAA-MM-DD." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_REPORTE_VENTAS(?, ?)"));
        pstmt->setString(1, ini);
        pstmt->setString(2, fin);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-6s | %-19s | %-10s | %-15s | %-20s | %-10s | %-10s | %-10s\n",
               "ID", "FECHA", "ESTADO", "EMPLEADO", "CLIENTE", "TOTAL", "PAGADO", "SALDO");
        bool hay = false;
        while (res->next()) {
            hay = true;
            printf("%-6d | %-19.19s | %-10s | %-15.15s | %-20.20s | %-10.2f | %-10.2f | %-10.2f\n",
                   res->getInt("ID_VENTA"),
                   res->getString("FECHA").c_str(),
                   res->getString("ESTADO").c_str(),
                   res->getString("EMPLEADO").c_str(),
                   res->getString("CLIENTE").c_str(),
                   (double)res->getDouble("TOTAL"),
                   (double)res->getDouble("PAGADO"),
                   (double)res->getDouble("SALDO"));
        }
        if (!hay) cout << "[!] Sin ventas en el rango." << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo generar el reporte." << RESET << endl;
    }
}

static int diasEnMes(int ano, int mes) {
    if (mes == 2) {
        if ((ano % 4 == 0 && ano % 100 != 0) || (ano % 400 == 0)) return 29;
        return 28;
    }
    if (mes == 4 || mes == 6 || mes == 9 || mes == 11) return 30;
    return 31;
}

static const char *nombreMes(int mes) {
    static const char *nombres[] = {"", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                                   "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"};
    if (mes < 1 || mes > 12) return "";
    return nombres[mes];
}

static string fmt2(int n) {
    char buf[8];
    snprintf(buf, sizeof(buf), "%02d", n);
    return string(buf);
}

static void reportePeriodoUI() {
    cout << "\n--- REPORTE POR PERIODO ---" << endl;
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
            int maxDias = diasEnMes(ano, m);
            cout << "\n[Mes: " << nombreMes(m) << " " << ano << "]" << endl;
            cout << "  1. Mes completo" << endl;
            cout << "  2. Rango de dias (max " << maxDias << ")" << endl;
            double dUno = 1;
            string modoStr = leerNumeroConIntentos("Opcion: ", 1, 2, &dUno) == 2 ? "2" : "1";

            int dIni = 1, dFin = maxDias;
            string filtro = "Mes completo";
            if (modoStr == "2") {
                dIni = (int)leerNumeroConIntentos("Dia de inicio (1-" + to_string(maxDias) + "): ", 1, maxDias);
                dFin = (int)leerNumeroConIntentos("Dia de fin (1-" + to_string(maxDias) + "): ", dIni, maxDias);
                filtro = "Dias " + to_string(dIni) + " al " + to_string(dFin);
            }

            string desde = to_string(ano) + "-" + fmt2(m) + "-" + fmt2(dIni);
            string hasta = to_string(ano) + "-" + fmt2(m) + "-" + fmt2(dFin);

            std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                "CALL SP_REPORTE_PERIODO(?, ?)"));
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
            cout << " [ " << nombreMes(m) << " " << ano << " ]" << endl;
            cout << "--------------------------------------------------" << endl;
            printf(" %-14s: %s\n", "Filtro", filtro.c_str());
            printf(" %-14s: %d\n", "Transacciones", trans);
            printf(" %-14s: $%.2f\n", "Subtotal", sub);
            printf(" %-14s: $%.2f\n", "ITBIS", itbis);
            printf(" %-14s: $%.2f\n", "Total", bruto);
        }

        cout << "\n===================================================" << endl;
        cout << " RESUMEN CONSOLIDADO (" << nombreMes(mesInicio) << " - " << nombreMes(mesFin) << " " << ano << ")" << endl;
        cout << "===================================================" << endl;
        printf(" %-14s: %d\n", "Transacciones", transGlobal);
        printf(" %-14s: $%.2f\n", "Subtotal", subGlobal);
        printf(" %-14s: $%.2f\n", "ITBIS", itbisGlobal);
        printf(" %-14s: $%.2f\n", "Gran total", brutoGlobal);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo generar el reporte." << RESET << endl;
    }
}

static void reportePeriodoGananciaUI() {
    cout << "\n--- GANANCIAS POR PERIODO (sin IVA) ---" << endl;
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
        double subGlobal = 0.0, brutaGlobal = 0.0, devGlobal = 0.0, netaGlobal = 0.0;

        for (int m = mesInicio; m <= mesFin; ++m) {
            int maxDias = diasEnMes(ano, m);
            cout << "\n[Mes: " << nombreMes(m) << " " << ano << "]" << endl;
            cout << "  1. Mes completo" << endl;
            cout << "  2. Rango de dias (max " << maxDias << ")" << endl;
            double dUno = 1;
            string modoStr = leerNumeroConIntentos("Opcion: ", 1, 2, &dUno) == 2 ? "2" : "1";

            int dIni = 1, dFin = maxDias;
            string filtro = "Mes completo";
            if (modoStr == "2") {
                dIni = (int)leerNumeroConIntentos("Dia de inicio (1-" + to_string(maxDias) + "): ", 1, maxDias);
                dFin = (int)leerNumeroConIntentos("Dia de fin (1-" + to_string(maxDias) + "): ", dIni, maxDias);
                filtro = "Dias " + to_string(dIni) + " al " + to_string(dFin);
            }

            string desde = to_string(ano) + "-" + fmt2(m) + "-" + fmt2(dIni);
            string hasta = to_string(ano) + "-" + fmt2(m) + "-" + fmt2(dFin);

            std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                "CALL SP_REPORTE_PERIODO_GANANCIA(?, ?)"));
            pstmt->setString(1, desde);
            pstmt->setString(2, hasta);
            std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
            int trans = 0;
            double sub = 0.0, bruta = 0.0, dev = 0.0, neta = 0.0;
            if (res->next()) {
                trans = res->getInt("TRANSACCIONES");
                sub = res->getDouble("SUBTOTAL");
                bruta = res->getDouble("BRUTA");
                dev = res->getDouble("DEVUELTA");
                neta = res->getDouble("NETA");
            }
            drenarResultados(pstmt.get());

            transGlobal += trans;
            subGlobal += sub;
            brutaGlobal += bruta;
            devGlobal += dev;
            netaGlobal += neta;

            cout << "\n--------------------------------------------------" << endl;
            cout << " [ " << nombreMes(m) << " " << ano << " ]" << endl;
            cout << "--------------------------------------------------" << endl;
            printf(" %-14s: %s\n", "Filtro", filtro.c_str());
            printf(" %-14s: %d\n", "Transacciones", trans);
            printf(" %-14s: $%.2f\n", "Subtotal", sub);
            printf(" %-14s: $%.2f\n", "Ganancia bruta", bruta);
            printf(" %-14s: $%.2f\n", "Devuelta", dev);
            printf(" %-14s: $%.2f\n", "Ganancia neta", neta);
        }

        cout << "\n===================================================" << endl;
        cout << " RESUMEN CONSOLIDADO (" << nombreMes(mesInicio) << " - " << nombreMes(mesFin) << " " << ano << ")" << endl;
        cout << "===================================================" << endl;
        printf(" %-14s: %d\n", "Transacciones", transGlobal);
        printf(" %-14s: $%.2f\n", "Subtotal", subGlobal);
        printf(" %-14s: $%.2f\n", "Ganancia bruta", brutaGlobal);
        printf(" %-14s: $%.2f\n", "Devuelta", devGlobal);
        printf(" %-14s: $%.2f\n", "Ganancia neta", netaGlobal);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo generar el reporte." << RESET << endl;
    }
}

static void devolucionVentaUI() {
    cout << "\n--- DEVOLUCION DE VENTA ---" << endl;
    cout << "Registra la devolucion PENDIENTE y luego aprueba o rechaza." << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_DETALLES_VENDIDOS_ULTIMOS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-8s | %-6s | %-25s | %-4s\n", "ID_DET", "VENTA", "PRODUCTO", "CANT");
        while (rl->next()) {
            printf("%-8d | %-6d | %-25.25s | %-4d\n",
                   rl->getInt("ID_DETALLE_VENTA"),
                   rl->getInt("ID_VENTA"),
                   rl->getString("NOMBRE").c_str(),
                   rl->getInt("CANTIDAD"));
        }
        drenarResultados(pl.get());

        int idDet = (int)leerNumeroConIntentos("ID detalle: ", 1, 999999999);
        int idEmp = (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        int cantDev = (int)leerNumeroConIntentos("Cantidad: ", 1, 999999999);
        string motivo = leerDatoSeguro("Motivo: ");
        if (motivo.empty()) {
            cout << ROJO << "El motivo es obligatorio." << RESET << endl;
            return;
        }
        double dNingunoG = -1;
        int gId = (int)leerNumeroConIntentos("ID garantia (Enter = sin garantia): ", 1, 999999999, &dNingunoG);
        string condStr = leerDatoSeguro("Condicion [BUENO/DANADO/USADO] (Enter = BUENO): ");
        string cond = "BUENO";
        if (!condStr.empty()) {
            if (condStr != "BUENO" && condStr != "DANADO" && condStr != "USADO") {
                cout << ROJO << "Condicion invalida." << RESET << endl;
                return;
            }
            cond = condStr;
        }

        std::unique_ptr<sql::PreparedStatement> pr(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_DEVOLUCION(?, ?, ?, ?, ?, ?)"));
        pr->setInt(1, idDet);
        if (gId < 0) pr->setNull(2, sql::DataType::INTEGER);
        else pr->setInt(2, gId);
        pr->setInt(3, idEmp);
        pr->setInt(4, cantDev);
        pr->setString(5, motivo);
        pr->setString(6, cond);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << Recogermensaje(pr.get()) << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pr.get());

        std::unique_ptr<sql::PreparedStatement> pi(globalCon->prepareStatement(
            "CALL SP_DEVOLUCION_PENDIENTE_POR_DETALLE(?)"));
        pi->setInt(1, idDet);
        std::unique_ptr<sql::ResultSet> ri(pi->executeQuery());
        int idDev = 0;
        if (ri->next()) idDev = ri->getInt("ID_DEVOLUCION");
        drenarResultados(pi.get());
        if (idDev <= 0) return;

        string dec = leerDatoSeguro("Aprobar / Rechazar / Enter deja PENDIENTE [a/r/Enter]: ");
        if (dec == "a" || dec == "A") {
            std::unique_ptr<sql::PreparedStatement> pa(globalCon->prepareStatement(
                "CALL 25_SP_PROCESAR_DEVOLUCION(?, 'APROBADA')"));
            pa->setInt(1, idDev);
            cout << ">>> " << Recogermensaje(pa.get()) << " <<<" << endl;
            drenarResultados(pa.get());
        } else if (dec == "r" || dec == "R") {
            string mot2 = leerDatoSeguro("Motivo del rechazo: ");
            if (mot2.empty()) {
                cout << ROJO << "El motivo es obligatorio." << RESET << endl;
                return;
            }
            std::unique_ptr<sql::PreparedStatement> pr2(globalCon->prepareStatement(
                "CALL 26_SP_RECHAZAR_DEVOLUCION(?, ?)"));
            pr2->setInt(1, idDev);
            pr2->setString(2, mot2);
            cout << ">>> " << Recogermensaje(pr2.get()) << " <<<" << endl;
            drenarResultados(pr2.get());
        } else {
            cout << "Queda PENDIENTE." << endl;
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo registrar la devolucion." << RESET << endl;
    }
}

static void verGananciasUI() {
    cout << "\n--- GANANCIAS (interno, sin IVA) ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pm(globalCon->prepareStatement(
            "CALL SP_GANANCIAS_MENSUAL()"));
        std::unique_ptr<sql::ResultSet> rm(pm->executeQuery());
        printf("\n%-7s | %-6s | %-10s | %-10s | %-10s | %-10s\n", "MES", "VENTAS", "SUBTOTAL", "BRUTA", "DEVUELTA", "NETA");
        bool hayMes = false;
        while (rm->next()) {
            hayMes = true;
            printf("%-7s | %-6d | %-10.2f | %-10.2f | %-10.2f | %-10.2f\n",
                   rm->getString("MES").c_str(),
                   rm->getInt("VENTAS"),
                   (double)rm->getDouble("SUBTOTAL"),
                   (double)rm->getDouble("GANANCIA_BRUTA"),
                   (double)rm->getDouble("GANANCIA_DEVUELTA"),
                   (double)rm->getDouble("GANANCIA_NETA"));
        }
        if (!hayMes) cout << "[!] Sin ganancias registradas." << endl;
        drenarResultados(pm.get());

        string mes = leerDatoSeguro("Mes (AAAA-MM, Enter = ultimas lineas): ");
        if (!mes.empty()) {
            bool okMes = mes.size() == 7 && mes[4] == '-';
            for (size_t k = 0; okMes && k < mes.size(); k++) {
                if (k == 4) continue;
                if (!isdigit(static_cast<unsigned char>(mes[k]))) okMes = false;
            }
            if (!okMes) {
                cout << ROJO << "Mes invalido. Use AAAA-MM." << RESET << endl;
                return;
            }
        }
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_GANANCIAS_LINEAS(?)"));
        pl->setString(1, mes);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-6s | %-19s | %-25s | %-4s | %-10s | %-10s | %-10s | %-10s\n", "VENTA", "FECHA", "PRODUCTO", "CANT", "ITBIS", "P.COMPRA", "P.VENTA", "GANANCIA");
        while (rl->next()) {
            double itbis = 0.0, pcompra = 0.0, pventa = 0.0, neta = 0.0;
            bool sinCosto = false;
            try { itbis = rl->getDouble("ITBIS"); } catch (...) { itbis = 0.0; }
            try { pcompra = rl->getDouble("COSTO_TOTAL"); sinCosto = rl->wasNull(); } catch (...) { sinCosto = true; }
            try { pventa = rl->getDouble("TOTAL_LINEA"); } catch (...) { pventa = 0.0; }
            try { neta = rl->getDouble("GANANCIA_NETA"); } catch (...) { neta = 0.0; }
            char bCompra[16];
            if (sinCosto) snprintf(bCompra, sizeof(bCompra), "%s", "---");
            else snprintf(bCompra, sizeof(bCompra), "%.2f", pcompra);
            printf("%-6d | %-19.19s | %-25.25s | %-4d | %-10.2f | %-10s | %-10.2f | %-10.2f\n",
                   rl->getInt("ID_VENTA"),
                   rl->getString("FECHA").c_str(),
                   rl->getString("PRODUCTO").c_str(),
                   rl->getInt("CANTIDAD"),
                   itbis, bCompra, pventa, neta);
        }
        drenarResultados(pl.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudieron ver las ganancias." << RESET << endl;
    }
}

static void cobrarVentaUI() {
    cout << "\n--- COBRAR VENTA EN PROCESO ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_VENTAS_PENDIENTES()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-6s | %-10s | %-10s | %-10s\n", "VENTA", "ESTADO", "PAGADO", "SALDO");
        bool hay = false;
        while (rl->next()) {
            hay = true;
            printf("%-6d | %-10s | %-10.2f | %-10.2f\n",
                   rl->getInt("ID_VENTA"),
                   rl->getString("ESTADO").c_str(),
                   (double)rl->getDouble("PAGADO"),
                   (double)rl->getDouble("SALDO"));
        }
        drenarResultados(pl.get());
        if (!hay) {
            cout << "[!] Sin ventas pendientes." << endl;
            return;
        }
        int idVenta = (int)leerNumeroConIntentos("ID venta: ", 1, 999999999);
        int idEmp = (int)leerNumeroConIntentos("ID empleado que cobra: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_VENTAS_PENDIENTES()"));
        std::unique_ptr<sql::ResultSet> rs(ps->executeQuery());
        double saldo = -1.0;
        while (rs->next()) {
            if (rs->getInt("ID_VENTA") == idVenta) saldo = rs->getDouble("SALDO");
        }
        drenarResultados(ps.get());
        if (saldo < 0) {
            cout << ROJO << "Esa venta no esta pendiente." << RESET << endl;
            return;
        }
        CierreVenta c;
        c.idVenta = idVenta;
        c.idEmpleado = idEmp;
        c.subtotal = saldo;
        c.bruto = saldo;
        pagarVenta(c);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo cobrar." << RESET << endl;
    }
}

static void garantiaRegistrarUI() {
    cout << "\n--- REGISTRAR GARANTIA ---" << endl;
    try {
        int idDetGar = (int)leerNumeroConIntentos("ID detalle de venta: ", 1, 999999999);
        double defDias = 30.0;
        int dias = (int)leerNumeroConIntentos("Dias de validez (Enter = 30): ", 1, 999999999, &defDias);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_GARANTIA(?, ?)"));
        pstmt->setInt(1, idDetGar);
        pstmt->setInt(2, dias);
        cout << ">>> " << Recogermensaje(pstmt.get()) << " <<<" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo registrar la garantia." << RESET << endl;
    }
}

static void reclamoRegistrarUI() {
    cout << "\n--- RECLAMAR GARANTIA ---" << endl;
    try {
        int gIdR = (int)leerNumeroConIntentos("ID garantia: ", 1, 999999999);
        string desc = leerDatoSeguro("Descripcion del dano: ");
        if (desc.empty()) {
            cout << ROJO << "La descripcion es obligatoria." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 27_SP_REGISTRAR_RECLAMO_GARANTIA(?, ?)"));
        pstmt->setInt(1, gIdR);
        pstmt->setString(2, desc);
        cout << ">>> " << Recogermensaje(pstmt.get()) << " <<<" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo registrar el reclamo." << RESET << endl;
    }
}

static void reclamoFinalizarUI() {
    cout << "\n--- FINALIZAR RECLAMO ---" << endl;
    try {
        int rId = (int)leerNumeroConIntentos("ID reclamo: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 27_SP_FINALIZAR_RECLAMO_TOTAL(?)"));
        pstmt->setInt(1, rId);
        cout << ">>> " << Recogermensaje(pstmt.get()) << " <<<" << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo finalizar el reclamo." << RESET << endl;
    }
}

static void ejecutarSubmenuGarantias() {
    int opcion = 0;
    do {
        cout << "\n=== GARANTIAS ===" << endl;
        cout << "1. Registrar garantia" << endl;
        cout << "2. Reclamar garantia" << endl;
        cout << "3. Finalizar reclamo" << endl;
        cout << "4. Volver" << endl;
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        switch (opcion) {
            case 1: garantiaRegistrarUI(); break;
            case 2: reclamoRegistrarUI(); break;
            case 3: reclamoFinalizarUI(); break;
            case 4: break;
            default: cout << ROJO << "Opcion no valida." << RESET << endl; break;
        }
        if (opcion != 4) pausar();
    } while (opcion != 4);
}

static void historialVentaUI() {
    cout << "\n--- HISTORIAL DE VENTA ---" << endl;
    try {
        int vHist = (int)leerNumeroConIntentos("ID venta: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_HISTORIAL_VENTA(?)"));
        pstmt->setInt(1, vHist);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-19s | %-10s | %-10s | %-15s | %-30s\n", "FECHA", "DE", "A", "EMPLEADO", "MOTIVO");
        bool hay = false;
        while (res->next()) {
            hay = true;
            string ant;
            try { ant = res->getString("ESTADO_ANTERIOR"); } catch (...) { ant = "---"; }
            printf("%-19.19s | %-10s | %-10s | %-15.15s | %-30.30s\n",
                   res->getString("FECHA").c_str(),
                   ant.c_str(),
                   res->getString("ESTADO_NUEVO").c_str(),
                   res->getString("EMPLEADO").c_str(),
                   res->getString("MOTIVO").c_str());
        }
        if (!hay) cout << "[!] Sin historial." << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el historial." << RESET << endl;
    }
}

void ejecutarSubmenuVentas() {
    int opcion = 0;
    while (true) {
        vector<const OpcionVenta*> visibles = opcionesVisibles();
        imprimirMenuVentas(visibles);
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionVenta& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionVenta::VentaRapida:      ventaRapida(); break;
            case AccionVenta::VerVentaIVA:      verVentaConIVA(); break;
            case AccionVenta::CancelarVenta:    cancelarVentaUI(); break;
            case AccionVenta::AnularPago:       anularPagoUI(); break;
            case AccionVenta::Devolucion:       devolucionVentaUI(); break;
            case AccionVenta::ReporteRango:     reporteVentasUI(); break;
            case AccionVenta::CierreCaja:       cierreCajaUI(); break;
            case AccionVenta::Ganancias:        verGananciasUI(); break;
            case AccionVenta::CobrarVenta:      cobrarVentaUI(); break;
            case AccionVenta::ReportePeriodo:   reportePeriodoUI(); break;
            case AccionVenta::GananciasPeriodo: reportePeriodoGananciaUI(); break;
            case AccionVenta::Garantias:        ejecutarSubmenuGarantias(); break;
            case AccionVenta::Historial:        historialVentaUI(); break;
            case AccionVenta::ExportarWeb:      exportarDatosWeb(); break;
            case AccionVenta::Volver:           return;
        }
        pausar();
    }
}
