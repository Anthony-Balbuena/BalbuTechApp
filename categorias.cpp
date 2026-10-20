#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <limits>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

void mostrarMenuCategorias() {
    cout << "\n=== MODULO DE CATEGORIAS ===" << endl;
    cout << "1. Agregar Categoria" << endl;
    cout << "2. Actualizar Categoria" << endl;
    cout << "3. Activar/Desactivar Categoria" << endl;
    cout << "4. Buscar Categoria" << endl;
    // (11/10/2026) Listar comentado: buscar-con-Enter cubre lo mismo.
    // cout << "5. Listar Categorias" << endl;
    cout << "5. Volver al Menu Principal" << endl;
    cout << "=============================" << endl;
}

void registrarCategoria() {
    cout << "\n--- REGISTRO DE CATEGORIA ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre de la categoria: ");
        string descripcion = leerDatoSeguro("Descripcion (Enter para omitir): ");
        string icono = leerDatoSeguro("Icono (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_CATEGORIA(?, ?, ?)"));
        pstmt->setString(1, nombre);

        if (descripcion.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, descripcion);
        }

        if (icono.empty()) {
            pstmt->setNull(3, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(3, icono);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar categoria: " << e.what() << endl;
    }
}

void actualizarCategoria() {
    cout << "\n--- ACTUALIZAR CATEGORIA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la categoria: ");
        int idCategoria = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string descripcion = leerDatoSeguro("Nueva descripcion (Enter para omitir): ");
        string icono = leerDatoSeguro("Nuevo icono (Enter para omitir): ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_CATEGORIA(?, ?, ?, ?)"));
        pstmt->setInt(1, idCategoria);

        if (nombre.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, nombre);
        }

        if (descripcion.empty()) {
            pstmt->setNull(3, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(3, descripcion);
        }

        if (icono.empty()) {
            pstmt->setNull(4, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(4, icono);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al actualizar categoria: " << e.what() << endl;
    }
}

void cambiarEstadoCategoria() {
    cout << "\n--- ACTIVAR/DESACTIVAR CATEGORIA ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID de la categoria: ");
        int idCategoria = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CATEGORIA(?)"));
        pstmt->setInt(1, idCategoria);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al cambiar estado de categoria: " << e.what() << endl;
    }
}

void buscarCategoria() {
    cout << "\n--- BUSCAR CATEGORIA ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre de la categoria o Enter para ver todas: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_CATEGORIA(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_CATEGORIA"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar categoria: " << e.what() << endl;
    }
}

// (11/10/2026) Función comentada: buscar-con-Enter cubre lo mismo.
#if 0
void listarCategorias() {
    cout << "\n--- LISTADO DE CATEGORIAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_CATEGORIAS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-5s | %-30s | %-8s\n", "ID", "NOMBRE", "ESTADO");
        printf("%-5s-+-%-30s-+-%-8s\n", "-----", "------------------------------", "--------");
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s | %-8s\n",
                   res->getInt("ID_CATEGORIA"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("ESTADO").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No hay categorias registradas." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar categorias: " << e.what() << endl;
    }
}
#endif

// Submenú de categorías: muestra el menú, lee la opción y llama a la acción.
// (Antes el menú solo se imprimía y volvía sin hacer nada.)
void ejecutarSubmenuCategorias() {
    int opcion = 0;

    do {
        mostrarMenuCategorias();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        switch (opcion) {
            case 1:
                registrarCategoria();
                break;
            case 2:
                actualizarCategoria();
                break;
            case 3:
                cambiarEstadoCategoria();
                break;
            case 4:
                buscarCategoria();
                break;
            // (11/10/2026) Listar comentado: ver arriba.
            // case 5:
            //     listarCategorias();
            //     break;
            case 5:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 5) pausar();
    } while (opcion != 5);
}

