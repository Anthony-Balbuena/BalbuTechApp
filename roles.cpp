#include <iostream>
#include <string>
#include <stdexcept>
#include <limits>
#include <vector>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "roles.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "sesion.h"
#include "categorias.h"
#include "marcas.h"
#include "productos.h"
#include "proveedores.h"
#include "empleados.h"
#include "clientes.h"
#include "usuarios.h"

using namespace std;

// Obtiene la lista de permisos que tiene un rol concreto dentro del sistema.
vector<std::string> obtenerPermisosPorRol(const std::string& rol) {
    std::vector<std::string> permisos;

    if (rol == "ADMIN") {
        permisos = {
            "GESTIONAR_ROLES",
            "GESTIONAR_USUARIOS",
            "GESTIONAR_EMPLEADOS",
            "GESTIONAR_CLIENTES",
            "GESTIONAR_PROVEEDORES",
            "GESTIONAR_CATEGORIAS",
            "GESTIONAR_MARCAS",
            "GESTIONAR_PRODUCTOS",
            "GESTIONAR_INVENTARIO",
            "GESTIONAR_VENTAS",
            "GESTIONAR_COMPRAS",
            "CONSULTAR_REPORTES"
        };
    } else if (rol == "RRHH") {
        permisos = {
            "GESTIONAR_EMPLEADOS",
            "GESTIONAR_ROLES",
            "GESTIONAR_USUARIOS",
            "GESTIONAR_CLIENTES",
            "CONSULTAR_REPORTES"
        };
    } else if (rol == "EMPLEADO") {
        permisos = {
            "CONSULTAR_PRODUCTOS",
            "CONSULTAR_CLIENTES",
            "REGISTRAR_ASISTENCIA",
            "SOLICITAR_PERMISO"
        };
    }

    return permisos;
}

// Verifica si el usuario autenticado tiene permiso para ejecutar una acción concreta.
bool tienePermiso(const string& accion) {
    if (!sesionActiva()) {
        return false;
    }

    vector<string> permisos = obtenerPermisosPorRol(sesionActual.nombreRol);
    for (const string& permiso : permisos) {
        if (permiso == accion) {
            return true;
        }
    }

    if (globalCon != nullptr) {
        try {
            sql::PreparedStatement *pstmt = globalCon->prepareStatement(
                "SELECT IFNULL(FN_TIENE_PERMISO(?, ?), 0) AS PERMISO"
            );
            pstmt->setString(1, sesionActual.username);
            pstmt->setString(2, accion);

            sql::ResultSet *res = pstmt->executeQuery();
            bool permitido = false;

            if (res->next()) {
                permitido = res->getInt("PERMISO") == 1;
            }

            delete res;
            delete pstmt;
            return permitido;
        } catch (const exception&) {
            return false;
        }
    }

    return false;
}

// Muestra todos los permisos disponibles para el rol actual de la sesión activa.
void mostrarPermisosActuales() {
    if (!sesionActiva()) {
        cout << ROJO << "No hay sesión activa." << RESET << endl;
        return;
    }

    cout << AZUL << "\nPermisos para: " << sesionActual.nombreRol << RESET << endl;
    vector<string> permisos = obtenerPermisosPorRol(sesionActual.nombreRol);
    for (const string& permiso : permisos) {
        cout << "- " << permiso << endl;
    }
}

// Genera el menú principal según el rol activo del usuario autenticado.
void mostrarMenuSegunRol() {
    cout << MAGENTA << "\n=== MENU PRINCIPAL BALBU_TECH ===" << RESET << endl;
    cout << AZUL << "Usuario activo: " << sesionActual.username << RESET << endl;
    cout << AZUL << "Rol: " << sesionActual.nombreRol << RESET << endl;
    cout << "----------------------------------------" << endl;

    if (sesionActual.nombreRol == "ADMIN") {
        cout << "1. Roles" << endl;
        cout << "2. Usuarios" << endl;
        cout << "3. Empleados" << endl;
        cout << "4. Clientes" << endl;
        cout << "5. Proveedores" << endl;
        cout << "6. Categorias" << endl;
        cout << "7. Marcas" << endl;
        cout << "8. Productos" << endl;
        cout << "9. Ver permisos" << endl;
        cout << "10. Cerrar sesión" << endl;
    } else if (sesionActual.nombreRol == "RRHH") {
        cout << "1. Empleados" << endl;
        cout << "2. Roles" << endl;
        cout << "3. Usuarios" << endl;
        cout << "4. Clientes" << endl;
        cout << "5. Ver permisos" << endl;
        cout << "6. Cerrar sesión" << endl;
    } else {
        cout << "1. Productos" << endl;
        cout << "2. Clientes" << endl;
        cout << "3. Ver permisos" << endl;
        cout << "4. Cerrar sesión" << endl;
    }

    cout << "----------------------------------------" << endl;
}

// Ejecuta la navegación del sistema, validando permisos antes de abrir cada módulo.
void ejecutarMenuSegunRol() {
    int opcion = 0;

    do {
        mostrarMenuSegunRol();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        cin >> opcion;
        cin.ignore(numeric_limits<streamsize>::max(), '\n');

        if (sesionActual.nombreRol == "ADMIN") {
            switch (opcion) {
                case 1:
                    if (tienePermiso("GESTIONAR_ROLES")) {
                        mostrarMenuRoles();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar roles." << RESET << endl;
                    }
                    break;
                case 2:
                    if (tienePermiso("GESTIONAR_USUARIOS")) {
                        mostrarMenuUsuarios();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar usuarios." << RESET << endl;
                    }
                    break;
                case 3:
                    if (tienePermiso("GESTIONAR_EMPLEADOS")) {
                        mostrarMenuEmpleados();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar empleados." << RESET << endl;
                    }
                    break;
                case 4:
                    if (tienePermiso("GESTIONAR_CLIENTES")) {
                        mostrarMenuClientes();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar clientes." << RESET << endl;
                    }
                    break;
                case 5:
                    if (tienePermiso("GESTIONAR_PROVEEDORES")) {
                        mostrarMenuProveedores();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar proveedores." << RESET << endl;
                    }
                    break;
                case 6:
                    if (tienePermiso("GESTIONAR_CATEGORIAS")) {
                        mostrarMenuCategorias();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar categorias." << RESET << endl;
                    }
                    break;
                case 7:
                    if (tienePermiso("GESTIONAR_MARCAS")) {
                        mostrarMenuMarcas();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar marcas." << RESET << endl;
                    }
                    break;
                case 8:
                    if (tienePermiso("GESTIONAR_PRODUCTOS")) {
                        mostrarMenuProductos();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar productos." << RESET << endl;
                    }
                    break;
                case 9:
                    mostrarPermisosActuales();
                    break;
                case 10:
                    cerrarSesion();
                    cout << VERDE << "Sesión cerrada correctamente." << RESET << endl;
                    opcion = 0;
                    break;
                default:
                    cout << ROJO << "Opcion no valida." << RESET << endl;
                    break;
            }
        } else if (sesionActual.nombreRol == "RRHH") {
            switch (opcion) {
                case 1:
                    if (tienePermiso("GESTIONAR_EMPLEADOS")) {
                        mostrarMenuEmpleados();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar empleados." << RESET << endl;
                    }
                    break;
                case 2:
                    if (tienePermiso("GESTIONAR_ROLES")) {
                        mostrarMenuRoles();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar roles." << RESET << endl;
                    }
                    break;
                case 3:
                    if (tienePermiso("GESTIONAR_USUARIOS")) {
                        mostrarMenuUsuarios();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar usuarios." << RESET << endl;
                    }
                    break;
                case 4:
                    if (tienePermiso("GESTIONAR_CLIENTES")) {
                        mostrarMenuClientes();
                    } else {
                        cout << ROJO << "No tienes permiso para gestionar clientes." << RESET << endl;
                    }
                    break;
                case 5:
                    mostrarPermisosActuales();
                    break;
                case 6:
                    cerrarSesion();
                    cout << VERDE << "Sesión cerrada correctamente." << RESET << endl;
                    opcion = 0;
                    break;
                default:
                    cout << ROJO << "Opcion no valida." << RESET << endl;
                    break;
            }
        } else {
            switch (opcion) {
                case 1:
                    if (tienePermiso("CONSULTAR_PRODUCTOS")) {
                        mostrarMenuProductos();
                    } else {
                        cout << ROJO << "No tienes permiso para consultar productos." << RESET << endl;
                    }
                    break;
                case 2:
                    if (tienePermiso("CONSULTAR_CLIENTES")) {
                        mostrarMenuClientes();
                    } else {
                        cout << ROJO << "No tienes permiso para consultar clientes." << RESET << endl;
                    }
                    break;
                case 3:
                    mostrarPermisosActuales();
                    break;
                case 4:
                    cerrarSesion();
                    cout << VERDE << "Sesión cerrada correctamente." << RESET << endl;
                    opcion = 0;
                    break;
                default:
                    cout << ROJO << "Opcion no valida." << RESET << endl;
                    break;
            }
        }

    } while (opcion != 0);
}

// Muestra las opciones del módulo de roles para administración del sistema.
void mostrarMenuRoles() {
    cout << "\n=== MODULO DE ROLES ===" << endl;
    cout << "1. Agregar Rol" << endl;
    cout << "2. Actualizar Rol" << endl;
    cout << "3. Buscar Rol" << endl;
    cout << "4. Listar Roles" << endl;
    cout << "5. Volver al Menu Principal" << endl;
    cout << "=======================" << endl;
}

// Registra un nuevo rol en la base de datos con validación básica de entrada.
void registrarRol() {
    cout << "\n--- REGISTRO DE ROL ---" << endl;
    try {
        string nombreRol = leerDatoSeguro("Nombre del rol: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_ROL(?)");
        pstmt->setString(1, nombreRol);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar rol: " << e.what() << endl;
    }
}

// Actualiza el nombre de un rol existente verificando que el ID sea válido.
void actualizarRol() {
    cout << "\n--- ACTUALIZAR ROL ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del rol: ");
        int idRol = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre del rol: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_ROL(?, ?)");
        pstmt->setInt(1, idRol);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al actualizar rol: " << e.what() << endl;
    }
}

// Busca roles por coincidencia de nombre y muestra los resultados encontrados.
void buscarRol() {
    cout << "\n--- BUSCAR ROLES ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre del rol o Enter para ver todos: ");

        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_ROLES(?)");
        pstmt->setString(1, busqueda);

        sql::ResultSet *res = pstmt->executeQuery();
        string separator = string(50, '-');
        cout << "\n" << separator << endl;
        printf("%-5s | %-30s\n", "ID", "NOMBRE DEL ROL");
        cout << separator << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s\n",
                   res->getInt("ID_ROL"),
                   res->getString("NOMBRE_ROL").c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se hallaron roles con el filtro: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }
        cout << separator << endl;

        delete res;
        delete pstmt;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar rol: " << e.what() << endl;
    }
}

// Lista todos los roles registrados en el sistema para consulta rápida.
void listarRoles() {
    cout << "\n--- LISTADO DE ROLES ---" << endl;
    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL");
        sql::ResultSet *res = pstmt->executeQuery();

        cout << "\nID | NOMBRE DEL ROL" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_ROL") << " | "
                 << res->getString("NOMBRE_ROL") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay roles registrados." << endl;
        }

        delete res;
        delete pstmt;
    } catch (const exception &e) {
        cout << "\n[!] Error al listar roles: " << e.what() << endl;
    }
}
