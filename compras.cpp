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
#include "compras.h"

using namespace std;

struct LineaCompra {
    int idProducto = 0;
    string codigo;
    string nombre;
    int cantidad = 0;
    double precioCompra = 0.0;
};

struct CierreCompra {
    int idCompra = 0;
    int idEmpleado = 0;
    double subtotal = 0.0;
    double bruto = 0.0;
};

void mostrarMenuCompras() {
    cout << "\n=== MODULO DE COMPRAS ===" << endl;
    cout << "1. Compra rapida (carrito)" << endl;
    cout << "2. Ver compra con IVA" << endl;
    cout << "3. Devolucion de compra" << endl;
    cout << "4. Volver al Menu Principal" << endl;
    cout << "=========================" << endl;
}

static bool esNumericoC(const string &s) {
    if (s.empty()) return false;
    for (char c : s) {
        if (!isdigit(static_cast<unsigned char>(c))) return false;
    }
    return true;
}

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
        cout << "\n--- REGISTRO RAPIDO (sin salir de la compra) ---" << endl;
        try {
            std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement("CALL PARA_INSERTAR_PRODUCTO()"));
            if (pl->execute()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                cout << CIAN << "\n--- CATEGORIAS ---" << RESET << endl;
                while (rc && rc->next()) {
                    cout << CIAN << "ID: " << RESET << rc->getInt("ID_CATEGORIA")
                         << CIAN << " | " << RESET << rc->getString("NOMBRE") << endl;
                }
            }
            if (pl->getMoreResults()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                cout << CIAN << "\n--- MARCAS ---" << RESET << endl;
                while (rc && rc->next()) {
                    cout << CIAN << "ID: " << RESET << rc->getInt("ID_MARCA")
                         << CIAN << " | " << RESET << rc->getString("NOMBRE") << endl;
                }
            }
            if (pl->getMoreResults()) {
                std::unique_ptr<sql::ResultSet> rc(pl->getResultSet());
                cout << CIAN << "\n--- PROVEEDORES ---" << RESET << endl;
                while (rc && rc->next()) {
                    cout << CIAN << "ID: " << RESET << rc->getInt("ID_PROVEEDOR")
                         << CIAN << " | " << RESET << rc->getString("NOMBRE") << endl;
                }
            }
            drenarResultados(pl.get());
        } catch (...) {}
        string nombre = leerDatoSeguro("Nombre [" + entrada + "]: ");
        if (nombre.empty()) nombre = entrada;
        string descripcion = nombre;
        if (descripcion.size() < 10) descripcion += " - registro rapido";
        string codigo = leerDatoSeguro("Codigo [" + entrada + "]: ");
        if (codigo.empty()) codigo = entrada;
        string pvStr = leerDatoSeguro("Precio de venta $: ");
        string pcStr = leerDatoSeguro("Precio de compra $: ");
        string mcStr = leerDatoSeguro("ID marca: ");
        string ctStr = leerDatoSeguro("ID categoria: ");
        string pv2Str = leerDatoSeguro("ID proveedor: ");
        double pv = stod(pvStr), pc = stod(pcStr);
        int mc = stoi(mcStr), ct = stoi(ctStr), pr = stoi(pv2Str);
        if (pv <= 0 || pc < 0) {
            cout << ROJO << "Precios invalidos." << RESET << endl;
            return false;
        }
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
            if ((esNumericoC(entrada) && c.id == stoi(entrada)) || c.codigo == entrada) {
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
            if (esNumericoC(entrada)) return false;
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
        string pick = leerDatoSeguro("ID elegido: ");
        if (!esNumericoC(pick)) return false;
        return resolverProductoC(pick, out);
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

static void mostrarCarritoCompra(const vector<LineaCompra> &carrito, double tasa) {
    (void)tasa;
    cout << "\n--- CARRITO (precios de factura, con IVA) ---" << endl;
    double total = 0.0;
    for (auto &l : carrito) {
        // El precio escrito ya trae ITBIS: el parcial es directo.
        double parcial = l.precioCompra * l.cantidad;
        total += parcial;
        cout << l.nombre << " x" << l.cantidad
             << " | $" << l.precioCompra << " con ITBIS"
             << " | total $" << parcial << endl;
    }
    cout << "Total con IVA: $" << total << endl;
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
        printf("%-25s | %-4s | %-10s | %-10.2f | %-10.2f | %-10.2f\n", "TOTAL", "", "", vItbis, vSub, vTotal);
    } catch (const exception &) {
        cout << ROJO << "No se pudo mostrar la factura." << RESET << endl;
    }
}

static CierreCompra cerrarCompra(const vector<LineaCompra> &carrito) {
    CierreCompra out;
    if (carrito.empty()) return out;
    try {
        string provStr = leerDatoSeguro("ID proveedor: ");
        string empStr = leerDatoSeguro("ID empleado: ");
        if (!esNumericoC(provStr) || !esNumericoC(empStr)) {
            cout << ROJO << "IDs invalidos." << RESET << endl;
            return out;
        }
        int idProv = stoi(provStr);
        int idEmp = stoi(empStr);

        std::unique_ptr<sql::Statement> stmt(globalCon->createStatement());
        stmt->execute("CALL 19_SP_INICIAR_COMPRA(" + to_string(idProv) + ", " + to_string(idEmp) + ", @nc)");
        {
            std::unique_ptr<sql::ResultSet> r0(stmt->getResultSet());
            if (r0) { while (r0->next()) {} }
        }
        drenarResultados(stmt.get());
        std::unique_ptr<sql::Statement> stmt2(globalCon->createStatement());
        std::unique_ptr<sql::ResultSet> resId(stmt2->executeQuery("SELECT @nc AS IDC"));
        int idCompra = 0;
        if (resId->next()) idCompra = resId->getInt("IDC");
        drenarResultados(stmt2.get());
        if (idCompra <= 0) {
            cout << ROJO << "No se pudo iniciar la compra." << RESET << endl;
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
                Recogermensaje(pstmt.get());
                drenarResultados(pstmt.get());
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

        string metStr = leerDatoSeguro("ID metodo: ");
        if (!esNumericoC(metStr)) {
            cout << ROJO << "Metodo invalido." << RESET << endl;
            return;
        }
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
        string empStr = leerDatoSeguro("ID empleado que paga (Enter = dueno): ");
        std::unique_ptr<sql::PreparedStatement> pp(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_PAGO_COMPRA(?, ?, ?, ?)"));
        pp->setInt(1, c.idCompra);
        pp->setInt(2, stoi(metStr));
        pp->setDouble(3, c.bruto);
        if (empStr.empty()) pp->setNull(4, sql::DataType::INTEGER);
        else pp->setInt(4, stoi(empStr));
        string msg = Recogermensaje(pp.get());
        drenarResultados(pp.get());
        cout << VERDE << msg << RESET << endl;

        std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
            "CALL SP_COMPRA_ENCABEZADO(?)"));
        pe->setInt(1, c.idCompra);
        std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
        if (re->next()) cout << "Estado final: " << re->getString("ESTADO") << endl;
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
        printf("\n%-5s | %-25s | %-8s | %-25s\n", "ID", "NOMBRE", "CANTIDAD", "PROVEEDOR");
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK"); } catch (...) { stock = 0; }
            string prov = "---";
            try { prov = res->getString("PROVEEDOR"); } catch (...) {}
            printf("%-5d | %-25.25s | %-8d | %-25.25s\n",
                   res->getInt("ID_PRODUCTO"),
                   res->getString("NOMBRE").c_str(),
                   stock,
                   prov.c_str());
        }
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
        cout << "Stock actual: " << stockDeC(prod.idProducto) << endl;
        string cantStr = leerDatoSeguro("Cantidad: ");
        if (!esNumericoC(cantStr) || stoi(cantStr) <= 0) {
            cout << ROJO << "Cantidad invalida." << RESET << endl;
            continue;
        }
        string precioStr = leerDatoSeguro("Precio de factura c/u $ (con ITBIS): ");
        double precio = 0.0;
        try { precio = stod(precioStr); } catch (...) { precio = 0.0; }
        if (precio <= 0) {
            cout << ROJO << "Precio invalido." << RESET << endl;
            continue;
        }
        int cant = stoi(cantStr);
        bool existe = false;
        for (auto &l : carrito) {
            if (l.idProducto == prod.idProducto && l.precioCompra == precio) {
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
    }
    if (carrito.empty()) {
        cout << "Carrito vacio." << endl;
        return;
    }
    mostrarCarritoCompra(carrito, tasa);
    string cerrar = leerDatoSeguro("Cerrar compra? (s/n): ");
    if (cerrar != "s" && cerrar != "S") {
        cout << "Compra no guardada." << endl;
        return;
    }
    CierreCompra c = cerrarCompra(carrito);
    if (c.idCompra <= 0) return;
    string pagar = leerDatoSeguro("Pagar ahora? (s/n): ");
    if (pagar == "s" || pagar == "S") pagarCompra(c);
    else cout << "Queda ABIERTA para pagar despues." << endl;
}

static void verCompraConIVA() {
    cout << "\n--- COMPRAS REGISTRADAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRAS_ULTIMAS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        vector<int> ids;
        while (rl->next()) ids.push_back(rl->getInt("ID_COMPRA"));
        drenarResultados(pl.get());
        if (ids.empty()) {
            cout << "[!] Sin compras registradas." << endl;
            return;
        }
        for (int id : ids) mostrarFacturaCompra(id);
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "Error al consultar compras." << RESET << endl;
    }
}

static void devolucionCompraUI() {
    cout << "\n--- DEVOLUCION DE COMPRA ---" << endl;
    try {
        string cStr = leerDatoSeguro("ID compra: ");
        if (!esNumericoC(cStr)) {
            cout << ROJO << "ID invalido." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRA_LINEAS(?)"));
        pl->setInt(1, stoi(cStr));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-8s | %-25s | %-4s | %-10s\n", "ID_DET", "PRODUCTO", "CANT", "PRECIO");
        bool hay = false;
        while (rl->next()) {
            hay = true;
            printf("%-8d | %-25.25s | %-4d | %-10.2f\n",
                   rl->getInt("ID_DETALLE_COMPRA"),
                   rl->getString("NOMBRE").c_str(),
                   rl->getInt("CANTIDAD"),
                   (double)rl->getDouble("PRECIO_UNITARIO"));
        }
        drenarResultados(pl.get());
        if (!hay) {
            cout << "[!] La compra no tiene lineas." << endl;
            return;
        }
        string dStr = leerDatoSeguro("ID detalle: ");
        string eStr = leerDatoSeguro("ID empleado: ");
        string kStr = leerDatoSeguro("Cantidad: ");
        if (!esNumericoC(dStr) || !esNumericoC(eStr) || !esNumericoC(kStr) || stoi(kStr) <= 0) {
            cout << ROJO << "IDs/cantidad invalidos." << RESET << endl;
            return;
        }
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
        pr0->setInt(1, stoi(dStr));
        pr0->setInt(2, stoi(eStr));
        pr0->setInt(3, stoi(kStr));
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

void ejecutarSubmenuCompras() {
    int opcion = 0;
    do {
        mostrarMenuCompras();
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
                compraRapida();
                break;
            case 2:
                verCompraConIVA();
                break;
            case 3:
                devolucionCompraUI();
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
