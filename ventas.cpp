#include <cctype>
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
    cout << "5. Volver al Menu Principal" << endl;
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
            "SELECT ID_PRODUCTO, CODIGO, NOMBRE, PRECIO FROM PRODUCTOS WHERE ID_PRODUCTO = ? AND ESTADO = 'ACTIVO'"));
        pstmt->setInt(1, id);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool ok = false;
        if (res->next()) {
            out.idProducto = res->getInt("ID_PRODUCTO");
            out.codigo = res->getString("CODIGO");
            out.nombre = res->getString("NOMBRE");
            out.precio = res->getDouble("PRECIO");
            ok = true;
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
            "SELECT ID_PRODUCTO, CODIGO, NOMBRE, PRECIO FROM PRODUCTOS WHERE CODIGO = ? AND ESTADO = 'ACTIVO'"));
        pstmt->setString(1, codigo);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool ok = false;
        if (res->next()) {
            out.idProducto = res->getInt("ID_PRODUCTO");
            out.codigo = res->getString("CODIGO");
            out.nombre = res->getString("NOMBRE");
            out.precio = res->getDouble("PRECIO");
            ok = true;
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
            "SELECT STOCK_ACTUAL FROM INVENTARIO WHERE ID_PRODUCTO = ?"));
        pstmt->setInt(1, idProducto);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        int stock = 0;
        if (res->next()) stock = res->getInt("STOCK_ACTUAL");
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

static void mostrarCarrito(const vector<LineaCarrito> &carrito) {
    cout << "\n--- CARRITO ---" << endl;
    double total = 0.0;
    for (auto &l : carrito) {
        double parcial = l.precio * l.cantidad;
        total += parcial;
        cout << l.nombre << " x" << l.cantidad
             << " | $" << l.precio << " c/u"
             << " | parcial $" << parcial << endl;
    }
    cout << "Parcial (sin IVA): $" << total << endl;
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
        cout << "A cobrar (total): $" << c.bruto << " (subtotal $" << c.subtotal << ")" << endl;
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
            "SELECT ESTADO FROM VENTAS WHERE ID_VENTA = ?"));
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
    try {
        string empStr = leerDatoSeguro("ID empleado: ");
        string cliStr = leerDatoSeguro("ID cliente: ");
        if (!esNumerico(empStr) || !esNumerico(cliStr)) {
            cout << ROJO << "IDs invalidos." << RESET << endl;
            return out;
        }
        int idEmp = stoi(empStr);
        int idCli = stoi(cliStr);

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
        int idVenta = 0;
        if (resId->next()) idVenta = resId->getInt("IDV");
        drenarResultados(stmt2.get());
        if (idVenta <= 0) {
            cout << ROJO << "No se pudo iniciar la venta." << RESET << endl;
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
            "SELECT SUBTOTAL, ITBIS, TOTAL_CON_IVA FROM VISTA_VENTA_CON_IVA WHERE ID_VENTA = ?"));
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

static void listarProductosParaVenta() {
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_CONSULTAR_INVENTARIO('')"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-5s | %-10s | %-25s | %-8s | %-6s\n", "ID", "CODIGO", "NOMBRE", "PRECIO", "STOCK");
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK_ACTUAL"); } catch (...) { stock = 0; }
            printf("%-5d | %-10s | %-25.25s | %-8.2f | %-6d\n",
                   res->getInt("ID_PRODUCTO"),
                   res->getString("CODIGO").c_str(),
                   res->getString("NOMBRE").c_str(),
                   (double)res->getDouble("PRECIO"),
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
    listarProductosParaVenta();
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
        mostrarCarrito(carrito);
    }
    if (!carrito.empty()) mostrarCarrito(carrito);
    else cout << "Carrito vacio." << endl;
    if (carrito.empty()) return;
    string cerrar = leerDatoSeguro("Cerrar venta? (s/n): ");
    if (cerrar != "s" && cerrar != "S") {
        cout << "Venta no guardada." << endl;
        return;
    }
    CierreVenta c = cerrarVenta(carrito);
    if (c.idVenta <= 0) return;
    string pagar = leerDatoSeguro("Pagar ahora? (s/n): ");
    if (pagar == "s" || pagar == "S") pagarVenta(c);
    else cout << "Queda EN_PROCESO para cobrar despues." << endl;
}

static void mostrarFactura(int idVenta) {
    try {
        std::unique_ptr<sql::PreparedStatement> ph(globalCon->prepareStatement(
            "SELECT ID_VENTA, CLIENTE, FECHA, ESTADO, SUBTOTAL, ITBIS, TOTAL_CON_IVA "
            "FROM VISTA_VENTA_CON_IVA WHERE ID_VENTA = ?"));
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
            "SELECT P.NOMBRE, DV.CANTIDAD, DV.PRECIO_UNITARIO, DV.SUBTOTAL, DV.MONTO_ITBIS, "
            "(DV.SUBTOTAL + DV.MONTO_ITBIS) AS TOTAL_LINEA "
            "FROM DETALLES_VENTA DV JOIN PRODUCTOS P ON P.ID_PRODUCTO = DV.ID_PRODUCTO "
            "WHERE DV.ID_VENTA = ? ORDER BY DV.ID_DETALLE_VENTA"));
        pl->setInt(1, idVenta);
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-25s | %-4s | %-10s | %-10s | %-10s\n", "Nombre del producto", "Cant", "ITBIS", "Subtotal", "Total");
        while (rl->next()) {
            printf("%-25.25s | %-4d | %-10.2f | %-10.2f | %-10.2f\n",
                   rl->getString("NOMBRE").c_str(),
                   rl->getInt("CANTIDAD"),
                   (double)rl->getDouble("MONTO_ITBIS"),
                   (double)rl->getDouble("SUBTOTAL"),
                   (double)rl->getDouble("TOTAL_LINEA"));
        }
        drenarResultados(pl.get());

        printf("%-25s | %-4s | %-10.2f | %-10.2f | %-10.2f\n", "TOTAL", "",
               vItbis, vSub, vTotal);
    } catch (const exception &) {
        cout << ROJO << "No se pudo mostrar la factura." << RESET << endl;
    }
}

static void verVentaConIVA() {
    cout << "\n--- VENTAS REGISTRADAS ---" << endl;

    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "SELECT ID_VENTA FROM VENTAS "
            "ORDER BY ID_VENTA DESC LIMIT 20"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        vector<int> ids;
        while (rl->next()) ids.push_back(rl->getInt("ID_VENTA"));
        drenarResultados(pl.get());
        if (ids.empty()) {
            cout << "[!] Sin ventas registradas." << endl;
            return;
        }
        for (int id : ids) mostrarFactura(id);
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
            "SELECT ID_VENTA, CLIENTE, ESTADO, SUBTOTAL, ITBIS, TOTAL_CON_IVA "
            "FROM VISTA_VENTA_CON_IVA ORDER BY ID_VENTA DESC LIMIT 20"));
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
            "SELECT ID_PAGO, ID_VENTA, NOMBRE_METODO, MONTO, MONTO_RECIBIDO, NOMBRE_EMPLEADO "
            "FROM VISTA_RESUMEN_PAGOS ORDER BY ID_PAGO DESC LIMIT 20"));
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
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 5) pausar();
    } while (opcion != 5);
}
