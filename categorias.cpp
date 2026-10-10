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
    cout << "5. Listar Categorias" << endl;
    cout << "6. Volver al Menu Principal" << endl;
    cout << "=============================" << endl;
}

void registrarCategoria() {
    cout << "\n--- REGISTRO DE CATEGORIA ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre de la categoria: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_CATEGORIA(?)"));
        pstmt->setString(1, nombre);

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

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_CATEGORIA(?, ?)"));
        pstmt->setInt(1, idCategoria);

        if (nombre.empty()) {
            pstmt->setNull(2, sql::DataType::VARCHAR);
        } else {
            pstmt->setString(2, nombre);
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

        cout << "\nID | NOMBRE | ESTADO" << endl;
        bool encontrado = false;

        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_CATEGORIA") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("ESTADO") << endl;
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

void listarCategorias() {
    cout << "\n--- LISTADO DE CATEGORIAS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_LISTAR_CATEGORIAS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        cout << "\nID | NOMBRE | ESTADO" << endl;
        while (res->next()) {
            cout << res->getInt("ID_CATEGORIA") << " | "
                 << res->getString("NOMBRE") << " | "
                 << res->getString("ESTADO") << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar categorias: " << e.what() << endl;
    }
}

// Submenú de categorías: muestra el menú, lee la opción y llama a la acción.
// (Antes el menú solo se imprimía y volvía sin hacer nada.)
void ejecutarSubmenuCategorias() {
    int opcion = 0;

    do {
        mostrarMenuCategorias();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        cin.ignore(numeric_limits<streamsize>::max(), '\n');

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
            case 5:
                listarCategorias();
                break;
            case 6:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
    } while (opcion != 6);
}

