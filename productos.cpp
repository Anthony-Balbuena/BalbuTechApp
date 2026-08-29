#include <iostream>
#include <string>
#include <stdexcept>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

void mostrarMenuProductos() {
    cout << "\n=== MODULO DE PRODUCTOS ===" << endl;
    cout << "1. Agregar Productos" << endl;
    cout << "2. Actualizar Datos" << endl;
    cout << "3. Activar/Desactivar Producto" << endl;
    cout << "4. Buscar Producto" << endl;
    cout << "5. Consultar Inventario" << endl;
    cout << "6. Reporte De Stock" << endl;
    cout << "7. Volver Al Menu Principal" << endl;
    cout << "===========================" << endl;
}

void registrarProducto() {
    cout << "\n---- REGISTRO DE PRODUCTO ---" << endl;

    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_INSERTAR_PRODUCTO()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- CATEGORIAS DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << " | ID: " << RESET << res->getInt("ID_CATEGORIA")
                     << CIAN << " | Nombre: " << RESET << res->getString("NOMBRE") << endl;
            }
            delete res;
        }

        if (pstmt->getMoreResults()) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- MARCAS DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "ID: " << RESET << res->getInt("ID_MARCA")
                     << CIAN << " | Nombre: " << RESET << res->getString("NOMBRE") << endl;
            }
            delete res;
        }

        if (pstmt->getMoreResults()) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- PROVEEDORES DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "ID: " << RESET << res->getInt("ID_PROVEEDOR")
                     << CIAN << " | Nombre: " << RESET << res->getString("NOMBRE") << endl;
            }
            delete res;
        }

        delete pstmt;
    } catch (const sql::SQLException &e) {
        cerr << ROJO << "Error al mostrar las listas: " << RESET << e.what() << endl;
    }

    try {
        string nombre = leerDatoSeguro("\nNombre del Producto: ");
        string codigo = leerDatoSeguro("\nCodigo del producto (Ej: CPU-001): ");
        string descripcion = leerDatoSeguro("\nDescripcion del Producto: ");

        string marcaStr = leerDatoSeguro("\nMarca del producto (ID-NUMERO): ");
        int idMarca = stoi(marcaStr);

        string categoriaStr = leerDatoSeguro("\nCategoria del Producto (ID-NUMERO): ");
        int idCategoria = stoi(categoriaStr);

        string precioStr = leerDatoSeguro("\nPrecio del Producto $: ");
        double precio = stod(precioStr);

        string proveedorStr = leerDatoSeguro("\nID del Proveedor (ID-NUMERO): ");
        int idProveedor = stoi(proveedorStr);

        string imagen = leerDatoSeguro("\nImagen (ruta o URL, presione Enter para omitir): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_PRODUCTO(?,?,?,?,?,?,?,?)");
        pstmt->setString(1, nombre);
        pstmt->setString(2, descripcion);
        pstmt->setDouble(3, precio);
        pstmt->setString(4, codigo);
        pstmt->setInt(5, idMarca);
        pstmt->setInt(6, idCategoria);
        pstmt->setInt(7, idProveedor);

        if (imagen.empty()) {
            pstmt->setNull(8, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(8, imagen);
        }

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_ACTUALIZARDATOS()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
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
            delete res;
        }

        delete pstmt;
    } catch (const sql::SQLException &e) {
        cerr << CIAN << "Error al mostrar las listas: " << RESET << e.what() << endl;
    }

    try {
        string idStr = leerDatoSeguro("ID del producto a modificar (NUMERO): ");
        int idProducto = stoi(idStr);

        cout << "\nNota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
        cout << "----------------------------------------------------------------------" << endl;

        string nombre = leerDatoSeguro("Nuevo nombre: ");
        string codigo = leerDatoSeguro("Nuevo codigo: ");
        string descripcion = leerDatoSeguro("Nueva descripcion: ");
        string precioRaw = leerDatoSeguro("Nuevo precio $: ");
        string marcaRaw = leerDatoSeguro("Nueva Marca (ID NUMERO): ");
        string categoriaRaw = leerDatoSeguro("Nueva Categoria (ID NUMERO): ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_PRODUCTOS(?, ?, ?, ?, ?, ?, ?, ?, ?)");
        pstmt->setInt(1, idProducto);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

        if (descripcion.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
        else pstmt->setString(3, descripcion);

        if (precioRaw.empty()) pstmt->setNull(4, sql::DataType::DOUBLE);
        else pstmt->setDouble(4, stod(precioRaw));

        if (codigo.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
        else pstmt->setString(5, codigo);

        if (marcaRaw.empty()) pstmt->setNull(6, sql::DataType::INTEGER);
        else pstmt->setInt(6, stoi(marcaRaw));

        if (categoriaRaw.empty()) pstmt->setNull(7, sql::DataType::INTEGER);
        else pstmt->setInt(7, stoi(categoriaRaw));

        string proveedorRaw = leerDatoSeguro("Nuevo Proveedor (ID NUMERO, Enter para omitir): ");
        if (proveedorRaw.empty()) pstmt->setNull(8, sql::DataType::INTEGER);
        else pstmt->setInt(8, stoi(proveedorRaw));

        string imagenRaw = leerDatoSeguro("Nueva Imagen (ruta o URL, Enter para omitir): ");
        if (imagenRaw.empty()) pstmt->setNull(9, sql::DataType::VARCHAR);
        else pstmt->setString(9, imagenRaw);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_ACTIVARODESACTIVAR_PROC()");
        bool results = pstmt->execute();

        if (results) {
            sql::ResultSet *res = pstmt->getResultSet();
            cout << CIAN << "\n--- LISTADO DE LOS PRODUCTOS Y SU ESTADO ---\n" << RESET << endl;
            while (res->next()) {
                cout << CIAN << "\n | ID Producto: " << RESET << res->getInt("ID_PRODUCTO")
                     << CIAN << "\n | Nombre: " << RESET << res->getString("Nombre")
                     << CIAN << "\n | Estado: " << RESET << res->getString("ESTADO") << endl;
            }
            delete res;
        }

        delete pstmt;
    } catch (const sql::SQLException &e) {
        cerr << ROJO << "Error al mostrar la lista: " << RESET << e.what() << endl;
    }

    try {
        string idStr = leerDatoSeguro("Ingrese el ID del producto (NUMERO): ");
        int idProducto = stoi(idStr);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PRODUCTOS(?)");
        pstmt->setInt(1, idProducto);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
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

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)");
        pstmt->setString(1, busqueda);

        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\n----------------------------------------------------------------------------------------------------" << endl;
        cout << "ID | CODIGO | NOMBRE | MARCA | CATEGORIA | PRECIO | ESTADO" << endl;
        cout << "----------------------------------------------------------------------------------------------------" << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_PRODUCTO") << " | "
                 << res->getString("CODIGO") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("MARCA") << " | "
                 << res->getString("CATEGORIA") << " | $"
                 << res->getDouble("PRECIO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n [!] No se encontraron productos con el filtro: ["
                 << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
        cout << "----------------------------------------------------------------------------------------------------" << endl;

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
    }
}

void consultarInventario() {
    cout << "\n============================================\n";
    cout << "        CONSULTA DE INVENTARIO BALBU_TECH     \n";
    cout << "============================================\n";

    try {
        cout << "Ingrese término de búsqueda (Código, Nombre o Categoría)\n";
        string busqueda = leerDatoSeguro("[Presione Enter para listar todo el inventario]: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CONSULTAR_INVENTARIO(?)");
        pstmt->setString(1, busqueda);

        sql::ResultSet *res = pstmt->executeQuery();

        int cont = 0;
        cout << "\nID | CODIGO | PRODUCTO | CATEGORIA | MARCA | STOCK | MINIMO | PRECIO | ESTATUS" << endl;

        while (res->next()) {
            cont++;
            cout << res->getInt("ID_PRODUCTO") << " | "
                 << res->getString("CODIGO") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("CATEGORIA") << " | "
                 << res->getString("MARCA") << " | "
                 << res->getInt("STOCK_ACTUAL") << " | "
                 << res->getInt("STOCK_MINIMO") << " | $"
                 << res->getDouble("PRECIO") << " | "
                 << res->getString("ESTATUS_STOCK") << endl;
        }

        if (cont == 0) {
            cout << "\n[!] No se encontraron registros en el inventario que coincidan con: \"" << busqueda << "\"\n";
        } else {
            cout << "\n[+] Total de filas mostradas: " << cont << "\n";
        }

        delete res;
        delete pstmt;
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
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_REPORTE_STOCK_CRITICO()");
        sql::ResultSet *res = pstmt->executeQuery();

        bool encontrado = false;
        int contador = 0;

        cout << "PRODUCTO | STOCK ACT. | STOCK MIN. | FALTANTE" << endl;

        while (res->next()) {
            encontrado = true;
            contador++;
            cout << res->getString("NOMBRE") << " | "
                 << res->getInt("STOCK_ACTUAL") << " | "
                 << res->getInt("STOCK_MINIMO") << " | "
                 << res->getInt("CANTIDAD_FALTANTE") << endl;
        }

        if (!encontrado) {
            cout << "\n [✓] ¡Excelente! No hay productos con stock crítico en este momento." << endl;
        } else {
            cout << "\n [!] Alerta: Se encontraron " << contador << " productos que requieren reabastecimiento." << endl;
        }

        delete res;

        while (pstmt->getMoreResults()) {
            sql::ResultSet *extra = pstmt->getResultSet();
            delete extra;
        }

        delete pstmt;
    } catch (const sql::SQLException &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS AL GENERAR REPORTE: " << e.what() << endl;
    }
}
