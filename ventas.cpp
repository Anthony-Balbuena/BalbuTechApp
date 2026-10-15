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
#include "ventas.h"

using namespace std;

struct LineaCarrito {
    int idProducto = 0;
    string codigo;
    string nombre;
    double precio = 0.0;
    int cantidad = 0;
};

void mostrarMenuVentas() {
    cout << "\n=== MODULO DE VENTAS ===" << endl;
    cout << "1. Venta rapida (carrito)" << endl;
    cout << "2. Ver venta con IVA" << endl;
    cout << "3. Cancelar venta" << endl;
    cout << "4. Anular pago" << endl;
    cout << "5. Devolucion de venta" << endl;
    cout << "6. Reporte por rango" << endl;
    cout << "7. Cierre de caja" << endl;
    cout << "8. Ganancias" << endl;
    cout << "9. Cobrar venta" << endl;
    cout << "10. Reporte por periodo" << endl;
    cout << "11. Ganancias por periodo" << endl;
    cout << "12. Garantias" << endl;
    cout << "13. Historial de venta" << endl;
    cout << "14. Volver al Menu Principal" << endl;
    cout << "========================" << endl;
}

static bool esNumerico(const string &s) {
    if (s.empty()) return false;
    for (char c : s) {
        if (!isdigit(static_cast<unsigned char>(c))) return false;
    }
    return true;
}

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
        string pick = leerDatoSeguro("ID elegido: ");
        if (!esNumerico(pick)) return false;
        return buscarPorId(stoi(pick), out);
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

static void mostrarCarrito(const vector<LineaCarrito> &carrito, double tasa) {
    cout << "\n--- CARRITO (precios con IVA) ---" << endl;
    double total = 0.0;
    for (auto &l : carrito) {
        double neto = l.precio * l.cantidad;
        // Igual que la base: ITBIS redondeado por linea, el total cuadra con el ticket.
        double parcial = neto + round(neto * tasa) / 100.0;
        double unitIVA = round(l.precio * (100.0 + tasa)) / 100.0;
        total += parcial;
        cout << l.nombre << " x" << l.cantidad
             << " | $" << unitIVA << " con ITBIS"
             << " | total $" << parcial << endl;
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

        string metStr = leerDatoSeguro("ID metodo: ");
        if (!esNumerico(metStr)) {
            cout << ROJO << "Metodo invalido." << RESET << endl;
            return;
        }
        // (11/10/2026) Se cobra el BRUTO; los triggers ya comparan contra el bruto.
        cout << "A pagar: $" << c.bruto << endl;
        string recStr = leerDatoSeguro("Monto recibido (Enter = exacto): ");
        double recibido = c.bruto;
        if (!recStr.empty()) {
            try { recibido = stod(recStr); }
            catch (...) {
                cout << ROJO << "Monto invalido." << RESET << endl;
                return;
            }
        }
        std::unique_ptr<sql::PreparedStatement> pp(globalCon->prepareStatement(
            "CALL 24_SP_REGISTRAR_PAGO(?, ?, ?, ?, ?)"));
        pp->setInt(1, c.idVenta);
        pp->setInt(2, stoi(metStr));
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
    const int MAX_INTENTOS = 3;
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
                    "CALL SP_AGREGAR_DETALLE_VENTA(?, ?, ?, ?)"));
                pstmt->setInt(1, idVenta);
                pstmt->setInt(2, l.idProducto);
                pstmt->setInt(3, l.cantidad);
                pstmt->setInt(4, idEmp);
                Recogermensaje(pstmt.get());
                drenarResultados(pstmt.get());
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
        printf("\n%-5s | %-10s | %-25s | %-10s | %-6s\n", "ID", "CODIGO", "NOMBRE", "P+IVA", "STOCK");
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK_ACTUAL"); } catch (...) { stock = 0; }
            double conIVA = round((double)res->getDouble("PRECIO") * (100.0 + tasa)) / 100.0;
            printf("%-5d | %-10s | %-25.25s | %-10.2f | %-6d\n",
                   res->getInt("ID_PRODUCTO"),
                   res->getString("CODIGO").c_str(),
                   res->getString("NOMBRE").c_str(),
                   conIVA,
                   stock);
        }
        if (!hay) cout << "[!] Sin productos activos." << endl;
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudo listar productos." << RESET << endl;
    }
}

static void ventaRapida() {
    cout << "\n--- VENTA RAPIDA ---" << endl;
    double tasa = tasaIVA();
    listarProductosParaVenta(tasa);
    cout << "Codigo de barra, ID o nombre. Vacio para cerrar." << endl;
    vector<LineaCarrito> carrito;
    while (true) {
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
        string cantStr = leerDatoSeguro("Cantidad (1): ");
        int cant = 1;
        if (!cantStr.empty()) {
            if (!esNumerico(cantStr) || stoi(cantStr) <= 0) {
                cout << ROJO << "Cantidad invalida." << RESET << endl;
                continue;
            }
            cant = stoi(cantStr);
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
            carrito.push_back(prod);
        }
        mostrarCarrito(carrito, tasa);
    }
    if (!carrito.empty()) mostrarCarrito(carrito, tasa);
    else cout << "Carrito vacio." << endl;
    if (carrito.empty()) return;
    while (true) {
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

        printf("\nID: %d | Cliente: %s | Fecha: %s | Estado: %s\n",
               vId, vCli.c_str(), vFecha.c_str(), vEstado.c_str());

        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_VENTA_LINEAS(?)"));
        pl->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-25s | %-4s | %-10s | %-10s | %-10s | %-10s\n", "Nombre del producto", "Cant", "P.UNIT", "ITBIS", "Subtotal", "Total");
        while (rl->next()) {
            printf("%-25.25s | %-4d | %-10.2f | %-10.2f | %-10.2f | %-10.2f\n",
                   rl->getString("NOMBRE").c_str(),
                   rl->getInt("CANTIDAD"),
                   (double)rl->getDouble("PRECIO_UNITARIO"),
                   (double)rl->getDouble("MONTO_ITBIS"),
                   (double)rl->getDouble("SUBTOTAL"),
                   (double)rl->getDouble("TOTAL_LINEA"));
        }
        drenarResultados(pl.get());

        printf("%-25s | %-4s | %-10s | %-10.2f | %-10.2f | %-10.2f\n", "TOTAL", "", "",
               vItbis, vSub, vTotal);
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
        string vPagos = leerDatoSeguro("Ver pagos de una venta? ID (Enter = omitir): ");
        if (!vPagos.empty()) {
            if (!esNumerico(vPagos)) {
                cout << ROJO << "ID invalido." << RESET << endl;
            } else {
                verPagosDeVenta(stoi(vPagos));
            }
        }
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

        string vStr = leerDatoSeguro("ID venta: ");
        string eStr = leerDatoSeguro("ID empleado (dueno): ");
        if (!esNumerico(vStr) || !esNumerico(eStr)) {
            cout << ROJO << "IDs invalidos." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CANCELAR_VENTA(?, ?)"));
        pstmt->setInt(1, stoi(vStr));
        pstmt->setInt(2, stoi(eStr));
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

        string pStr = leerDatoSeguro("ID pago: ");
        string eStr = leerDatoSeguro("ID empleado que anula: ");
        if (!esNumerico(pStr) || !esNumerico(eStr)) {
            cout << ROJO << "IDs invalidos." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_ANULAR_PAGO(?, ?)"));
        pstmt->setInt(1, stoi(pStr));
        pstmt->setInt(2, stoi(eStr));
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
        string anoStr = leerDatoSeguro("Ano del reporte (ej. 2026): ");
        string iniStr = leerDatoSeguro("Mes inicial (1-12): ");
        string finStr = leerDatoSeguro("Mes final (1-12): ");
        if (!esNumerico(anoStr) || !esNumerico(iniStr) || !esNumerico(finStr)) {
            cout << ROJO << "Ano y meses deben ser numeros." << RESET << endl;
            return;
        }
        int ano = stoi(anoStr);
        int mesInicio = stoi(iniStr);
        int mesFin = stoi(finStr);
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
            string modoStr = leerDatoSeguro("Opcion: ");
            if (!esNumerico(modoStr) || (modoStr != "1" && modoStr != "2")) {
                cout << ROJO << "Modo invalido, se usa mes completo." << RESET << endl;
                modoStr = "1";
            }

            int dIni = 1, dFin = maxDias;
            string filtro = "Mes completo";
            if (modoStr == "2") {
                string diStr = leerDatoSeguro("Dia de inicio (1-" + to_string(maxDias) + "): ");
                string dfStr = leerDatoSeguro("Dia de fin (1-" + to_string(maxDias) + "): ");
                if (!esNumerico(diStr) || !esNumerico(dfStr)) {
                    cout << ROJO << "Dias invalidos, se usa mes completo." << RESET << endl;
                } else {
                    dIni = stoi(diStr);
                    dFin = stoi(dfStr);
                    if (dIni < 1) dIni = 1;
                    if (dFin > maxDias) dFin = maxDias;
                    if (dIni > dFin) dFin = dIni;
                    filtro = "Dias " + to_string(dIni) + " al " + to_string(dFin);
                }
            }

            string desde = anoStr + "-" + fmt2(m) + "-" + fmt2(dIni);
            string hasta = anoStr + "-" + fmt2(m) + "-" + fmt2(dFin);

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
        string anoStr = leerDatoSeguro("Ano del reporte (ej. 2026): ");
        string iniStr = leerDatoSeguro("Mes inicial (1-12): ");
        string finStr = leerDatoSeguro("Mes final (1-12): ");
        if (!esNumerico(anoStr) || !esNumerico(iniStr) || !esNumerico(finStr)) {
            cout << ROJO << "Ano y meses deben ser numeros." << RESET << endl;
            return;
        }
        int ano = stoi(anoStr);
        int mesInicio = stoi(iniStr);
        int mesFin = stoi(finStr);
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
            string modoStr = leerDatoSeguro("Opcion: ");
            if (!esNumerico(modoStr) || (modoStr != "1" && modoStr != "2")) {
                cout << ROJO << "Modo invalido, se usa mes completo." << RESET << endl;
                modoStr = "1";
            }

            int dIni = 1, dFin = maxDias;
            string filtro = "Mes completo";
            if (modoStr == "2") {
                string diStr = leerDatoSeguro("Dia de inicio (1-" + to_string(maxDias) + "): ");
                string dfStr = leerDatoSeguro("Dia de fin (1-" + to_string(maxDias) + "): ");
                if (!esNumerico(diStr) || !esNumerico(dfStr)) {
                    cout << ROJO << "Dias invalidos, se usa mes completo." << RESET << endl;
                } else {
                    dIni = stoi(diStr);
                    dFin = stoi(dfStr);
                    if (dIni < 1) dIni = 1;
                    if (dFin > maxDias) dFin = maxDias;
                    if (dIni > dFin) dFin = dIni;
                    filtro = "Dias " + to_string(dIni) + " al " + to_string(dFin);
                }
            }

            string desde = anoStr + "-" + fmt2(m) + "-" + fmt2(dIni);
            string hasta = anoStr + "-" + fmt2(m) + "-" + fmt2(dFin);

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

        string dStr = leerDatoSeguro("ID detalle: ");
        string eStr = leerDatoSeguro("ID empleado: ");
        string cStr = leerDatoSeguro("Cantidad: ");
        if (!esNumerico(dStr) || !esNumerico(eStr) || !esNumerico(cStr) || stoi(cStr) <= 0) {
            cout << ROJO << "IDs/cantidad invalidos." << RESET << endl;
            return;
        }
        string motivo = leerDatoSeguro("Motivo: ");
        if (motivo.empty()) {
            cout << ROJO << "El motivo es obligatorio." << RESET << endl;
            return;
        }
        string gStr = leerDatoSeguro("ID garantia (Enter = sin garantia): ");
        if (!gStr.empty() && !esNumerico(gStr)) {
            cout << ROJO << "ID garantia invalido." << RESET << endl;
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

        std::unique_ptr<sql::PreparedStatement> pr(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_DEVOLUCION(?, ?, ?, ?, ?, ?)"));
        pr->setInt(1, stoi(dStr));
        if (gStr.empty()) pr->setNull(2, sql::DataType::INTEGER);
        else pr->setInt(2, stoi(gStr));
        pr->setInt(3, stoi(eStr));
        pr->setInt(4, stoi(cStr));
        pr->setString(5, motivo);
        pr->setString(6, cond);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << Recogermensaje(pr.get()) << " <<<" << endl;
        cout << "--------------------------------------------" << endl;
        drenarResultados(pr.get());

        std::unique_ptr<sql::PreparedStatement> pi(globalCon->prepareStatement(
            "CALL SP_DEVOLUCION_PENDIENTE_POR_DETALLE(?)"));
        pi->setInt(1, stoi(dStr));
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
        string vStr = leerDatoSeguro("ID venta: ");
        string eStr = leerDatoSeguro("ID empleado que cobra: ");
        if (!esNumerico(vStr) || !esNumerico(eStr)) {
            cout << ROJO << "IDs invalidos." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_VENTAS_PENDIENTES()"));
        std::unique_ptr<sql::ResultSet> rs(ps->executeQuery());
        double saldo = -1.0;
        while (rs->next()) {
            if (rs->getInt("ID_VENTA") == stoi(vStr)) saldo = rs->getDouble("SALDO");
        }
        drenarResultados(ps.get());
        if (saldo < 0) {
            cout << ROJO << "Esa venta no esta pendiente." << RESET << endl;
            return;
        }
        CierreVenta c;
        c.idVenta = stoi(vStr);
        c.idEmpleado = stoi(eStr);
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
        string dStr = leerDatoSeguro("ID detalle de venta: ");
        string diasStr = leerDatoSeguro("Dias de validez (Enter = 30): ");
        if (!esNumerico(dStr)) {
            cout << ROJO << "ID invalido." << RESET << endl;
            return;
        }
        int dias = 30;
        if (!diasStr.empty()) {
            if (!esNumerico(diasStr) || stoi(diasStr) <= 0) {
                cout << ROJO << "Dias invalidos." << RESET << endl;
                return;
            }
            dias = stoi(diasStr);
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_GARANTIA(?, ?)"));
        pstmt->setInt(1, stoi(dStr));
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
        string gStr = leerDatoSeguro("ID garantia: ");
        string desc = leerDatoSeguro("Descripcion del dano: ");
        if (!esNumerico(gStr) || desc.empty()) {
            cout << ROJO << "ID y descripcion obligatorios." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 27_SP_REGISTRAR_RECLAMO_GARANTIA(?, ?)"));
        pstmt->setInt(1, stoi(gStr));
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
        string rStr = leerDatoSeguro("ID reclamo: ");
        if (!esNumerico(rStr)) {
            cout << ROJO << "ID invalido." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 27_SP_FINALIZAR_RECLAMO_TOTAL(?)"));
        pstmt->setInt(1, stoi(rStr));
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
        cin >> opcion;
        if (cin.fail()) {
            cin.clear();
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
            opcion = -1;
        } else {
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
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
        string vStr = leerDatoSeguro("ID venta: ");
        if (!esNumerico(vStr)) {
            cout << ROJO << "ID invalido." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_HISTORIAL_VENTA(?)"));
        pstmt->setInt(1, stoi(vStr));
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
    do {
        mostrarMenuVentas();
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
                ventaRapida();
                break;
            case 2:
                verVentaConIVA();
                break;
            case 3:
                cancelarVentaUI();
                break;
            case 4:
                anularPagoUI();
                break;
            case 5:
                devolucionVentaUI();
                break;
            case 6:
                reporteVentasUI();
                break;
            case 7:
                cierreCajaUI();
                break;
            case 8:
                verGananciasUI();
                break;
            case 9:
                cobrarVentaUI();
                break;
            case 10:
                reportePeriodoUI();
                break;
            case 11:
                reportePeriodoGananciaUI();
                break;
            case 12:
                ejecutarSubmenuGarantias();
                break;
            case 13:
                historialVentaUI();
                break;
            case 14:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 14) pausar();
    } while (opcion != 14);
}
