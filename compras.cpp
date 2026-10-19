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

void mostrarMenuCompras() {
    cout << "\n=== MODULO DE COMPRAS ===" << endl;
    cout << "1. Compra rapida (carrito)" << endl;
    cout << "2. Ver compra con IVA" << endl;
    cout << "3. Devolucion de compra" << endl;
    cout << "4. Reporte por periodo" << endl;
    cout << "5. Pagar compra" << endl;
    cout << "6. Precios por suplidor" << endl;
    cout << "7. Cancelar compra" << endl;
    cout << "8. Volver al Menu Principal" << endl;
    cout << "=========================" << endl;
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
        string sStr = leerDatoSeguro("ID suplidor (Enter = mas barato, 0 = nuevo): ");
        if (sStr.empty()) {
            if (lista.empty()) {
                cout << ROJO << "Sin historial: elegi un ID de la lista." << RESET << endl;
                return false;
            }
            l.idProveedor = lista[0].id;
            l.nombreProveedor = lista[0].nombre;
            return true;
        }
        if (sStr == "0") return registroRapidoS(l);
        if (!esNumerico(sStr)) {
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
        printf("\n%-25s | %-10s | %-19s | %-4s\n", "PROVEEDOR", "PRECIO", "FECHA", "CANT");
        bool hay = false;
        while (rh->next()) {
            hay = true;
            printf("%-25.25s | %-10.2f | %-19.19s | %-4d\n",
                   rh->getString("PROVEEDOR").c_str(),
                   (double)rh->getDouble("PRECIO"),
                   rh->getString("FECHA").c_str(),
                   rh->getInt("CANTIDAD"));
        }
        if (!hay) cout << "[!] Sin historial: primera compra." << endl;
        drenarResultados(ph.get());
    } catch (const exception &) {}
}

// dinero() ahora vive en seguridad.h/cpp (compartido con ventas).

static void mostrarCarritoCompra(const vector<LineaCompra> &carrito, double tasa) {
    (void)tasa;
    cout << "\n--- CARRITO (precios de factura, con IVA) ---" << endl;
    printf("\n%-25s | %-4s | %-22s | %-15s | %-12s\n", "PRODUCTO", "CANT", "PROVEEDOR", "P.UNIT C/ITBIS", "TOTAL");
    printf("%s\n", string(90, '-').c_str());
    double total = 0.0;
    for (auto &l : carrito) {
        // El precio escrito ya trae ITBIS: el parcial es directo.
        double parcial = l.precioCompra * l.cantidad;
        total += parcial;
        printf("%-25.25s | %-4d | %-22.22s | %-15s | %-12s\n",
               l.nombre.c_str(), l.cantidad, l.nombreProveedor.c_str(),
               dinero(l.precioCompra).c_str(), dinero(parcial).c_str());
        printf("%s\n", string(90, '-').c_str());
    }
    printf("%-25s | %-4s | %-22s | %-15s | %-12s\n", "Total con IVA =", "", "", "", dinero(total).c_str());
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
        printf("%-25s | %-4s | %-10s | %-10.2f | %-10.2f | %-10.2f\n", "Total a pagar =", "", "", vItbis, vSub, vTotal);
    } catch (const exception &) {
        cout << ROJO << "No se pudo mostrar la factura." << RESET << endl;
    }
}

static CierreCompra cerrarCompraNucleo(const vector<LineaCompra> &carrito, int idProvFijo, bool pedirProv) {
    CierreCompra out;
    if (carrito.empty()) return out;
    int idProv = idProvFijo, idEmp = 0, idCompra = 0;
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
                string empStr = leerDatoSeguro("ID empleado: ");
                if (!esNumerico(empStr)) {
                    cout << ROJO << "ID invalido (intento " << intento << " de " << MAX_INTENTOS << ")." << RESET << endl;
                    continue;
                }
                idEmp = stoi(empStr);

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
        const int W0 = 7, W1 = 25, W2 = 8;
        string borde = "+" + string(W0 + 2, '-') + "+" + string(W1 + 2, '-') + "+"
                     + string(W2 + 2, '-') + "+";
        cout << "\n" << borde << endl;
        printf("| %-*s | %-*s | %-*s |\n", W0, "ID_PROD", W1, "NOMBRE", W2, "CANTIDAD");
        cout << borde << endl;
        bool hay = false;
        while (res->next()) {
            hay = true;
            int stock = 0;
            try { stock = res->getInt("STOCK"); } catch (...) { stock = 0; }
            printf("| %-*d | %-*.25s | %-*d |\n",
                   W0, res->getInt("ID_PRODUCTO"),
                   W1, res->getString("NOMBRE").c_str(),
                   W2, stock);
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
        int idCompraDev = (int)leerNumeroConIntentos("ID compra: ", 1, 999999999);
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRA_LINEAS(?)"));
        pl->setInt(1, idCompraDev);
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
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRAS_PENDIENTES()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-7s | %-20s | %-10s | %-10s | %-10s\n", "COMPRA", "PROVEEDOR", "ESTADO", "PAGADO", "SALDO");
        bool hay = false;
        while (rl->next()) {
            hay = true;
            printf("%-7d | %-20.20s | %-10s | %-10.2f | %-10.2f\n",
                   rl->getInt("ID_COMPRA"),
                   rl->getString("PROVEEDOR").c_str(),
                   rl->getString("ESTADO").c_str(),
                   (double)rl->getDouble("PAGADO"),
                   (double)rl->getDouble("SALDO"));
        }
        drenarResultados(pl.get());
        if (!hay) {
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
        std::unique_ptr<sql::PreparedStatement> pl(globalCon->prepareStatement(
            "CALL SP_COMPRAS_ULTIMAS()"));
        std::unique_ptr<sql::ResultSet> rl(pl->executeQuery());
        printf("\n%-6s | %-20s | %-10s | %-10s\n", "ID", "PROVEEDOR", "ESTADO", "TOTAL");
        while (rl->next()) {
            printf("%-6d | %-20.20s | %-10s | %-10.2f\n",
                   rl->getInt("ID_COMPRA"),
                   rl->getString("PROVEEDOR").c_str(),
                   rl->getString("ESTADO").c_str(),
                   (double)rl->getDouble("TOTAL_CON_IVA"));
        }
        drenarResultados(pl.get());
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
        printf("\n%-25s | %-10s | %-10s | %-25s | %-10s | %-25s | %-10s\n", "PRODUCTO", "SUPLIDORES", "MAS BARATO", "BARATO EN", "MAS CARO", "CARO EN", "ULTIMA");
        bool hay = false;
        while (res->next()) {
            hay = true;
            printf("%-25.25s | %-10d | %-10.2f | %-25.25s | %-10.2f | %-25.25s | %-10.10s\n",
                   res->getString("PRODUCTO").c_str(),
                   res->getInt("SUPLIDORES"),
                   (double)res->getDouble("MAS_BARATO"),
                   res->getString("DONDE_BARATO").c_str(),
                   (double)res->getDouble("MAS_CARO"),
                   res->getString("DONDE_CARO").c_str(),
                   res->getString("ULTIMA_COMPRA").c_str());
        }
        if (!hay) cout << "[!] Sin datos: ninguna compra RECIBIDA aun." << endl;
        drenarResultados(pstmt.get());
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el reporte." << RESET << endl;
    }
}

void ejecutarSubmenuCompras() {
    int opcion = 0;
    do {
        mostrarMenuCompras();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
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
                reportePeriodoCompraUI();
                break;
            case 5:
                pagarCompraPendienteUI();
                break;
            case 6:
                verPreciosCompraUI();
                break;
            case 7:
                cancelarCompraUI();
                break;
            case 8:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 8) pausar();
    } while (opcion != 8);
}
