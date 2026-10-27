#include <iostream>
#include <string>
#include <vector>
#include <utility>
#include <cstdio>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <limits>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "roles.h"
#include "colores.h"

using namespace std;

namespace {

enum class AccionProducto {
    Agregar, Actualizar, Estado, Buscar, ConsultarInventario, ReporteStock, Volver
};

struct OpcionProducto {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionProducto accion;
};

// (22/10/2026) Menu por permisos: las tres acciones de escritura piden
// GESTIONAR_PRODUCTOS y las tres de consulta CONSULTAR_PRODUCTOS. Antes la lista
// era fija y despachaba por numero, asi que un rol que solo consulta
// (CONTABILIDAD tiene CONSULTAR_PRODUCTOS) veia igual el alta, la baja y la
// actualizacion.
static const vector<OpcionProducto>& opcionesProductos() {
    static const vector<OpcionProducto> opciones = {
        {"Agregar Productos",           "GESTIONAR_PRODUCTOS", AccionProducto::Agregar},
        {"Actualizar Datos",            "GESTIONAR_PRODUCTOS", AccionProducto::Actualizar},
        {"Activar/Desactivar Producto", "GESTIONAR_PRODUCTOS", AccionProducto::Estado},
        {"Buscar Producto",             "CONSULTAR_PRODUCTOS", AccionProducto::Buscar},
        {"Consultar Inventario",        "CONSULTAR_PRODUCTOS", AccionProducto::ConsultarInventario},
        {"Reporte De Stock",            "CONSULTAR_PRODUCTOS", AccionProducto::ReporteStock},
        {"Volver Al Menu Principal",    "",                     AccionProducto::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionProducto& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionProducto*> opcionesVisibles() {
    vector<const OpcionProducto*> visibles;
    for (const OpcionProducto& opcion : opcionesProductos()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuProductos(const vector<const OpcionProducto*>& visibles) {
    cout << "\n=== MODULO DE PRODUCTOS ===" << endl;
    int n = 0;
    for (const OpcionProducto* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "===========================" << endl;
}

}  // namespace

void registrarProducto() {
    cout << "\n---- REGISTRO DE PRODUCTO ---" << endl;

    vector<pair<int, string>> marcas, categorias, proveedores;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_INSERTAR_PRODUCTO()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            while (res && res->next()) {
                categorias.emplace_back(res->getInt("ID_CATEGORIA"), res->getString("NOMBRE"));
            }
        }

        if (pstmt->getMoreResults()) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            while (res && res->next()) {
                marcas.emplace_back(res->getInt("ID_MARCA"), res->getString("NOMBRE"));
            }
        }

        if (pstmt->getMoreResults()) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            while (res && res->next()) {
                proveedores.emplace_back(res->getInt("ID_PROVEEDOR"), res->getString("NOMBRE"));
            }
        }

        drenarResultados(pstmt.get());
    } catch (const sql::SQLException &e) {
        cerr << ROJO << "Error al mostrar las listas: " << RESET << e.what() << endl;
    }

    auto mostrarLista = [](const char *titulo, const vector<pair<int, string>> &v) {
        cout << CIAN << "\n--- " << titulo << " ---\n" << RESET;
        if (v.empty()) cout << "[!] Sin registros." << endl;
        for (auto &p : v) {
            cout << CIAN << "ID: " << RESET << p.first
                 << CIAN << " | " << RESET << p.second << endl;
        }
    };

    try {
        string nombre = leerDatoSeguro("\nNombre del Producto: ");
        string codigo = leerDatoSeguro("\nCodigo del producto (Ej: CPU-001): ");
        string descripcion = leerDatoSeguro("\nDescripcion del Producto: ");

        mostrarLista("MARCAS", marcas);
        int idMarca = (int)leerNumeroConIntentos("\nMarca del producto (ID-NUMERO): ", 1, 999999999);

        mostrarLista("CATEGORIAS", categorias);
        int idCategoria = (int)leerNumeroConIntentos("\nCategoria del Producto (ID-NUMERO): ", 1, 999999999);

        double dCero = 0;
        double compra = leerNumeroConIntentos("\nPrecio de compra $ (Enter = 0): ", 0, 999999999.99, &dCero);

        double precio = leerNumeroConIntentos("\nPrecio de venta del Producto $ (sin ITBIS): ", 0.01, 999999999.99);
        try {
            std::unique_ptr<sql::PreparedStatement> pt(globalCon->prepareStatement(
                "SELECT FN_TASA_ITBIS() AS TASA"));
            std::unique_ptr<sql::ResultSet> rt(pt->executeQuery());
            double tasa = 18.0;
            if (rt->next()) tasa = rt->getDouble("TASA");
            drenarResultados(pt.get());
            cout << CIAN << "El cliente pagara: $" << (long long)llround(precio * (100.0 + tasa) / 100.0)
                 << " (ITBIS incluido)" << RESET << endl;
        } catch (...) {}

        mostrarLista("PROVEEDORES", proveedores);
        int idProveedor = (int)leerNumeroConIntentos("\nID del Proveedor (ID-NUMERO): ", 1, 999999999);

        string imagen = leerDatoSeguro("\nImagen (ruta o URL, presione Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_PRODUCTO(?,?,?,?,?,?,?,?,?)"));
        pstmt->setString(1, nombre);
        pstmt->setString(2, descripcion);
        pstmt->setDouble(3, compra);
        pstmt->setDouble(4, precio);
        pstmt->setString(5, codigo);
        pstmt->setInt(6, idMarca);
        pstmt->setInt(7, idCategoria);
        pstmt->setInt(8, idProveedor);

        if (imagen.empty()) {
            pstmt->setNull(9, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(9, imagen);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Ingresaste letras en campos numéricos (ID o Precio)." << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE SISTEMA: " << e.what() << endl;
    }
}

void actualizarProducto() {
    cout << "\n--- ACTUALIZAR DATOS DE PRODUCTO ---" << endl;

    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_ACTUALIZARDATOS()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- LISTADO GENERAL DE PRODUCTOS, CATEGORÍAS Y MARCAS ---\n" << RESET;

            while (res->next()) {
                cout << CIAN << "\n | ID Producto: " << RESET << res->getInt("ID_PRODUCTO")
                     << CIAN << "\n | Producto: " << RESET << res->getString("PRODUCTO")
                     << CIAN << "\n | Precio: " << RESET << "$" << res->getDouble("PRECIO")
                     << CIAN << "\n | ID CATEGORIA: " << RESET << res->getInt("ID_CATEGORIA")
                     << CIAN << "\n | Categoría: " << RESET << res->getString("CATEGORIA")
                     << CIAN << "\n | ID Marca : " << RESET << res->getInt("ID_MARCA")
                     << CIAN << "\n | Marca: " << RESET << res->getString("MARCA") << endl;
            }
        }

        drenarResultados(pstmt.get());
    } catch (const sql::SQLException &e) {
        cerr << CIAN << "Error al mostrar las listas: " << RESET << e.what() << endl;
    }

    try {
        int idProducto = (int)leerNumeroConIntentos("ID del producto a modificar (NUMERO): ", 1, 999999999);

        cout << "\nNota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
        cout << "----------------------------------------------------------------------" << endl;

        string nombre = leerDatoSeguro("Nuevo nombre: ");
        string codigo = leerDatoSeguro("Nuevo codigo: ");
        string descripcion = leerDatoSeguro("Nueva descripcion: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_PRODUCTOS(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        pstmt->setInt(1, idProducto);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

        if (descripcion.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
        else pstmt->setString(3, descripcion);

        double dMenosUno = -1;
        double vPrecio = leerNumeroConIntentos("Nuevo precio $ (Enter = omitir): ", 0.01, 999999999.99, &dMenosUno);
        if (vPrecio < 0) pstmt->setNull(4, sql::DataType::DOUBLE);
        else pstmt->setDouble(4, vPrecio);

        if (codigo.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
        else pstmt->setString(5, codigo);

        int vMarca = (int)leerNumeroConIntentos("Nueva Marca (ID NUMERO, Enter = omitir): ", 1, 999999999, &dMenosUno);
        if (vMarca < 0) pstmt->setNull(6, sql::DataType::INTEGER);
        else pstmt->setInt(6, vMarca);

        int vCat = (int)leerNumeroConIntentos("Nueva Categoria (ID NUMERO, Enter = omitir): ", 1, 999999999, &dMenosUno);
        if (vCat < 0) pstmt->setNull(7, sql::DataType::INTEGER);
        else pstmt->setInt(7, vCat);

        int vProv = (int)leerNumeroConIntentos("Nuevo Proveedor (ID NUMERO, Enter para omitir): ", 1, 999999999, &dMenosUno);
        if (vProv < 0) pstmt->setNull(8, sql::DataType::INTEGER);
        else pstmt->setInt(8, vProv);

        string imagenRaw = leerDatoSeguro("Nueva Imagen (ruta o URL, Enter para omitir): ");
        if (imagenRaw.empty()) pstmt->setNull(9, sql::DataType::VARCHAR);
        else pstmt->setString(9, imagenRaw);

        double vCosto = leerNumeroConIntentos("Precio de compra $ (Enter para omitir): ", 0, 999999999.99, &dMenosUno);
        if (vCosto < 0) pstmt->setNull(10, sql::DataType::DOUBLE);
        else pstmt->setDouble(10, vCosto);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Formato numérico incorrecto en la entrada." << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE DB: " << e.what() << endl;
    }
}

void cambiarEstadoProducto() {
    cout << "\n --- DESACTIVAR/ACTIVAR ESTADO DEL PRODUCTO ---" << endl;

    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_ACTIVARODESACTIVAR_PROC()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- LISTADO DE LOS PRODUCTOS Y SU ESTADO ---\n" << RESET << endl;
            while (res->next()) {
                cout << CIAN << "\n | ID Producto: " << RESET << res->getInt("ID_PRODUCTO")
                     << CIAN << "\n | Nombre: " << RESET << res->getString("Nombre")
                     << CIAN << "\n | Estado: " << RESET << res->getString("ESTADO") << endl;
            }
        }

        drenarResultados(pstmt.get());
    } catch (const sql::SQLException &e) {
        cerr << ROJO << "Error al mostrar la lista: " << RESET << e.what() << endl;
    }

    try {
        int idProducto = (int)leerNumeroConIntentos("Ingrese el ID del producto (NUMERO): ", 1, 999999999);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PRODUCTOS(?)"));
        pstmt->setInt(1, idProducto);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: El ID debe ser un número entero." << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
    }
}

void buscarProducto() {
    cout << "\n--- BUSCAR PRODUCTOS ---" << endl;

    try {
        string busqueda = leerDatoSeguro("Ingrese (NOMBRE O CODIGO DEL PRODUCTO) o Enter para todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        const char *FMT = "%-5s | %-10s | %-25s | %-12s | %-20s | %-10s | %-10s | %-8s | %-8s\n";
        const int ANCHO = 5 + 10 + 25 + 12 + 20 + 10 + 10 + 8 + 8 + 8 * 3;
        cout << "\n" << string(ANCHO, '-') << endl;
        printf(FMT, "ID", "CODIGO", "NOMBRE", "MARCA", "CATEGORIA", "PRECIO", "P.COMPRA", "CANTIDAD", "ESTADO");
        cout << string(ANCHO, '-') << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            string costoStr;
            try {
                double costo = res->getDouble("P_COMPRA");
                costoStr = res->wasNull() ? "---" : ("$" + to_string((long long)llround(costo)));
            } catch (...) { costoStr = "---"; }
            int stock = 0;
            try { stock = res->getInt("STOCK"); } catch (...) { stock = 0; }
            char bufPrecio[16];
            snprintf(bufPrecio, sizeof(bufPrecio), "$%.0f", (double)res->getDouble("PRECIO"));
            printf("%-5d | %-10s | %-25.25s | %-12.12s | %-20.20s | %-10s | %-10s | %-8d | %-8s\n",
                   res->getInt("ID_PRODUCTO"),
                   res->getString("CODIGO").c_str(),
                   res->getString("NOMBRE").c_str(),
                   res->getString("MARCA").c_str(),
                   res->getString("CATEGORIA").c_str(),
                   bufPrecio,
                   costoStr.c_str(),
                   stock,
                   res->getString("ESTADO").c_str());
        }

        cout << string(ANCHO, '-') << endl;

        if (!encontrado) {
            cout << "\n [!] No se encontraron productos con el filtro: ["
                 << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
        //cout << "----------------------------------------------------------------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
    }
}

// (27/10/2026) Tablas del inventario con celdas alineadas. printf cuenta
// bytes, no columnas: "CRÍTICO" ocupa 8 bytes pero 7 columnas y desalinea.
// Estas helpers recortan y rellenan por code point UTF-8 para que los acentos
// se conserven y la tabla quede derecha.
static size_t anchoVisible(const string &s) {
    size_t n = 0;
    for (size_t i = 0; i < s.size(); ) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c < 0x80) i += 1;
        else if ((c & 0xE0) == 0xC0) i += 2;
        else if ((c & 0xF0) == 0xE0) i += 3;
        else if ((c & 0xF8) == 0xF0) i += 4;
        else i += 1;
        ++n;
    }
    return n;
}

static string recortarVisible(const string &s, size_t maxCols) {
    string out;
    size_t cols = 0;
    for (size_t i = 0; i < s.size() && cols < maxCols; ) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t len = 1;
        if (c >= 0x80) {
            if ((c & 0xE0) == 0xC0) len = 2;
            else if ((c & 0xF0) == 0xE0) len = 3;
            else if ((c & 0xF8) == 0xF0) len = 4;
            if (i + len > s.size()) break;
        }
        out.append(s, i, len);
        i += len;
        ++cols;
    }
    return out;
}

static string celda(const string &s, size_t width) {
    string out = recortarVisible(s, width);
    size_t n = anchoVisible(out);
    if (n < width) out.append(width - n, ' ');
    return out;
}

static const string &colorEstatus(const string &estatus) {
    if (estatus == "AGOTADO" || estatus == "CRÍTICO") return ROJO;
    if (estatus == "STOCK BAJO") return AMARILLO;
    return VERDE;
}

void consultarInventario() {
    cout << "\n============================================\n";
    cout << "        CONSULTA DE INVENTARIO BALBU_TECH     \n";
    cout << "============================================\n";

    try {
        cout << "Ingrese término de búsqueda (Código, Nombre o Categoría)\n";
        string busqueda = leerDatoSeguro("[Presione Enter para listar todo el inventario]: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_CONSULTAR_INVENTARIO(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        const size_t W_ID = 6, W_COD = 10, W_PROD = 25, W_CAT = 20, W_MARCA = 12,
                     W_STOCK = 6, W_MIN = 7, W_PRECIO = 9, W_EST = 10;
        const size_t ANCHO = W_ID + W_COD + W_PROD + W_CAT + W_MARCA + W_STOCK +
                             W_MIN + W_PRECIO + W_EST + 8 * 3;
        const string linea(ANCHO, '-');

        int cont = 0;
        cout << "\n"
             << celda("ID", W_ID) << " | "
             << celda("CODIGO", W_COD) << " | "
             << celda("PRODUCTO", W_PROD) << " | "
             << celda("CATEGORIA", W_CAT) << " | "
             << celda("MARCA", W_MARCA) << " | "
             << celda("STOCK", W_STOCK) << " | "
             << celda("MINIMO", W_MIN) << " | "
             << celda("PRECIO", W_PRECIO) << " | "
             << celda("ESTATUS", W_EST) << "\n"
             << linea << "\n";

        while (res->next()) {
            cont++;
            char precio[24];
            snprintf(precio, sizeof(precio), "$%.0f", (double)res->getDouble("PRECIO"));
            string estatus;
            try { estatus = res->getString("ESTATUS_STOCK"); } catch (...) { estatus = "OK"; }
            const string &color = colorEstatus(estatus);
            cout << celda(to_string(res->getInt("ID_PRODUCTO")), W_ID) << " | "
                 << celda(res->getString("CODIGO"), W_COD) << " | "
                 << celda(res->getString("NOMBRE"), W_PROD) << " | "
                 << celda(res->getString("CATEGORIA"), W_CAT) << " | "
                 << celda(res->getString("MARCA"), W_MARCA) << " | "
                 << celda(to_string(res->getInt("STOCK_ACTUAL")), W_STOCK) << " | "
                 << celda(to_string(res->getInt("STOCK_MINIMO")), W_MIN) << " | "
                 << celda(precio, W_PRECIO) << " | "
                 << color << celda(estatus, W_EST) << RESET << "\n"
                 << linea << "\n";
        }

        if (cont == 0) {
            cout << "\n[!] No se encontraron registros en el inventario que coincidan con: \"" << busqueda << "\"\n";
        } else {
            cout << "\n[+] Total de filas mostradas: " << cont << "\n";
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE SISTEMA AL CONSULTAR INVENTARIO: " << e.what() << endl;
    }
}

void reporteStockCritico() {
    cout << "\n======================================================\n";
    cout << "        REPORTE DE STOCK CRÍTICO (BALBU_TECH)         \n";
    cout << "======================================================\n";
    cout << " Listando productos que están en o por debajo de su mínimo:\n\n";

    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_REPORTE_STOCK_CRITICO()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        bool encontrado = false;
        int contador = 0;

        const size_t W_PROD = 30, W_STOCK = 10, W_MIN = 10, W_FALTA = 9;
        const size_t ANCHO = W_PROD + W_STOCK + W_MIN + W_FALTA + 3 * 3;
        const string linea(ANCHO, '-');

        cout << celda("PRODUCTO", W_PROD) << " | "
             << celda("STOCK ACT.", W_STOCK) << " | "
             << celda("STOCK MIN.", W_MIN) << " | "
             << celda("FALTANTE", W_FALTA) << "\n"
             << linea << "\n";

        while (res->next()) {
            encontrado = true;
            contador++;
            cout << celda(res->getString("NOMBRE"), W_PROD) << " | "
                 << celda(to_string(res->getInt("STOCK_ACTUAL")), W_STOCK) << " | "
                 << celda(to_string(res->getInt("STOCK_MINIMO")), W_MIN) << " | "
                 << celda(to_string(res->getInt("CANTIDAD_FALTANTE")), W_FALTA) << "\n"
                 << linea << "\n";
        }

        if (!encontrado) {
            cout << "\n [✓] ¡Excelente! No hay productos con stock crítico en este momento." << endl;
        } else {
            cout << "\n [!] Alerta: Se encontraron " << contador << " productos que requieren reabastecimiento." << endl;
        }


        drenarResultados(pstmt.get());
    } catch (const sql::SQLException &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS AL GENERAR REPORTE: " << e.what() << endl;
    }
}

// Submenú de productos: muestra el menú, lee la opción y llama a la acción.
// (Antes el menú solo se imprimía y volvía sin hacer nada.)
void ejecutarSubmenuProductos() {
    int opcion = 0;

    while (true) {
        vector<const OpcionProducto*> visibles = opcionesVisibles();
        imprimirMenuProductos(visibles);
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionProducto& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionProducto::Agregar:  registrarProducto(); break;
            case AccionProducto::Actualizar: actualizarProducto(); break;
            case AccionProducto::Estado:   cambiarEstadoProducto(); break;
            case AccionProducto::Buscar:   buscarProducto(); break;
            case AccionProducto::ConsultarInventario: consultarInventario(); break;
            case AccionProducto::ReporteStock: reporteStockCritico(); break;
            case AccionProducto::Volver:   return;
        }
        pausar();
    }
}

