#include <iostream>
#include <string>
#include <memory>
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
#include "metodos_pago.h"
#include "empleados.h"
#include "permisos.h"
#include "vacaciones.h"
#include "caja.h"
#include "clientes.h"
#include "usuarios.h"
#include "ventas.h"
#include "compras.h"
#include "inventario.h"
#include "accesos.h"

using namespace std;

// ---------------------------------------------------------------------------
// Permisos: la base es la unica fuente de verdad (C-3, 20/10/2026).
// ---------------------------------------------------------------------------

// Recorta espacios de los extremos.
static string recortar(const string& s) {
    size_t i = s.find_first_not_of(" \t\r\n");
    if (i == string::npos) return "";
    size_t f = s.find_last_not_of(" \t\r\n");
    return s.substr(i, f - i + 1);
}

// Obtiene la lista de permisos que tiene un rol concreto (consulta la base).
vector<std::string> obtenerPermisosPorRol(const std::string& rol) {
    std::vector<std::string> permisos;
    if (globalCon == nullptr) return permisos;

    try {
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "SELECT P.NOMBRE_PERMISO FROM ROL_PERMISO RP "
            "INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO "
            "WHERE RP.ROL_NOMBRE = ? ORDER BY P.NOMBRE_PERMISO"));
        ps->setString(1, rol);

        std::unique_ptr<sql::ResultSet> res(ps->executeQuery());
        while (res->next()) {
            permisos.push_back(res->getString("NOMBRE_PERMISO"));
        }
        drenarResultados(ps.get());
    } catch (const exception&) {
        permisos.clear();
    }

    return permisos;
}

// Verifica si el usuario autenticado tiene permiso para ejecutar una accion.
// Sin atajo local: la funcion de la base es la unica respuesta.
bool tienePermiso(const string& accion) {
    if (!sesionActiva() || globalCon == nullptr) {
        return false;
    }

    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "SELECT IFNULL(FN_TIENE_PERMISO(?, ?), 0) AS PERMISO"
        ));
        pstmt->setString(1, sesionActual.username);
        pstmt->setString(2, accion);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool permitido = false;

        if (res->next()) {
            permitido = res->getInt("PERMISO") == 1;
        }

        drenarResultados(pstmt.get());
        return permitido;
    } catch (const exception&) {
        return false;
    }
}

// Permisos efectivos del usuario logueado. Se consulta por USUARIO (no por
// nombre de rol): si el rol se renombra, la sesion sigue mostrando lo correcto.
static vector<string> permisosDelUsuario(const string& usuario) {
    vector<string> permisos;
    if (globalCon == nullptr) return permisos;

    try {
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "SELECT P.NOMBRE_PERMISO FROM USUARIOS U "
            "INNER JOIN ROLES R ON R.ID_ROL = U.ID_ROL "
            "INNER JOIN ROL_PERMISO RP ON RP.ROL_NOMBRE = R.NOMBRE_ROL "
            "INNER JOIN PERMISOS P ON P.ID_PERMISO = RP.ID_PERMISO "
            "WHERE U.USUARIO = ? ORDER BY P.NOMBRE_PERMISO"));
        ps->setString(1, usuario);

        std::unique_ptr<sql::ResultSet> res(ps->executeQuery());
        while (res->next()) {
            permisos.push_back(res->getString("NOMBRE_PERMISO"));
        }
        drenarResultados(ps.get());
    } catch (const exception&) {
        permisos.clear();
    }

    return permisos;
}

// Muestra todos los permisos efectivos del usuario de la sesion activa.
void mostrarPermisosActuales() {
    if (!sesionActiva()) {
        cout << ROJO << "No hay sesión activa." << RESET << endl;
        return;
    }

    cout << AZUL << "\nPermisos para: " << sesionActual.username
         << " (" << sesionActual.nombreRol << ")" << RESET << endl;

    vector<string> permisos = permisosDelUsuario(sesionActual.username);
    if (permisos.empty()) {
        cout << "Sin permisos asignados." << endl;
        return;
    }

    for (const string& permiso : permisos) {
        cout << "- " << permiso << endl;
    }
}

// ---------------------------------------------------------------------------
// Menu principal dinamico: se arma con los permisos reales de la base.
// ---------------------------------------------------------------------------

enum class AccionMenu {
    Asistencia, Roles, Usuarios, Empleados, MisPermisos, MisVacaciones, Clientes, Proveedores, Categorias, Marcas,
    Productos, MetodosPago, Ventas, Compras, Inventario, Caja,
    LogAccesos, VerPermisos, CerrarSesion
};

struct ItemMenu {
    const char* etiqueta;
    vector<string> permisos;  // cualquiera de estos habilita; vacio = siempre
    AccionMenu accion;
};

// Orden fijo (el del menu historico de ADMIN): cada rol ve el subconjunto que
// le permiten sus permisos. Agregar un modulo = agregar un item aca.
static const vector<ItemMenu>& itemsMenuPrincipal() {
    static const vector<ItemMenu> items = {
        {"Asistencia",       {"REGISTRAR_ASISTENCIA", "CONSULTAR_ASISTENCIA",
                              "JUSTIFICAR_ASISTENCIA"},                     AccionMenu::Asistencia},
        {"Roles",            {"GESTIONAR_ROLES"},                          AccionMenu::Roles},
        {"Usuarios",         {"USUARIOS_VER", "USUARIOS_CREAR", "USUARIOS_EDITAR", "USUARIOS_ESTADO", "USUARIOS_CLAVE"}, AccionMenu::Usuarios},
        {"Empleados",        {"EMPLEADOS_VER", "EMPLEADOS_CREAR", "EMPLEADOS_EDITAR", "EMPLEADOS_BAJA",
                              "GESTIONAR_PERMISOS_EMPLEADO", "GESTIONAR_VACACIONES_EMPLEADO",
                              "GESTIONAR_CONTRATOS"}, AccionMenu::Empleados},
        {"Mis permisos",     {"SOLICITAR_PERMISO"},                        AccionMenu::MisPermisos},
        {"Mis vacaciones",   {"SOLICITAR_PERMISO"},                        AccionMenu::MisVacaciones},
        {"Clientes",         {"CLIENTES_VER", "CLIENTES_CREAR", "CLIENTES_EDITAR", "CLIENTES_ESTADO"}, AccionMenu::Clientes},
        {"Proveedores",      {"PROVEEDORES_VER", "PROVEEDORES_CREAR",
                              "PROVEEDORES_EDITAR", "PROVEEDORES_ESTADO"},  AccionMenu::Proveedores},
        {"Categorias",       {"GESTIONAR_CATEGORIAS"},                     AccionMenu::Categorias},
        {"Marcas",           {"GESTIONAR_MARCAS"},                         AccionMenu::Marcas},
        {"Productos",        {"GESTIONAR_PRODUCTOS", "CONSULTAR_PRODUCTOS"}, AccionMenu::Productos},
        {"Metodos de pago",  {"GESTIONAR_METODOS_PAGO"},                   AccionMenu::MetodosPago},
        {"Ventas",           {"GESTIONAR_VENTAS"},                         AccionMenu::Ventas},
        {"Compras",          {"GESTIONAR_COMPRAS"},                        AccionMenu::Compras},
        {"Inventario",       {"GESTIONAR_INVENTARIO"},                     AccionMenu::Inventario},
        {"Caja (turnos)",    {"GESTIONAR_VENTAS"},                         AccionMenu::Caja},
        {"Accesos",          {"GESTIONAR_ROLES"},                          AccionMenu::LogAccesos},
        {"Ver permisos",     {},                                           AccionMenu::VerPermisos},
        {"Cerrar sesión",    {},                                           AccionMenu::CerrarSesion}
    };
    return items;
}

static bool puedeVerItem(const ItemMenu& item) {
    if (item.permisos.empty()) return true;
    for (const string& permiso : item.permisos) {
        if (tienePermiso(permiso)) return true;
    }
    return false;
}

// Arma una sola vez la lista visible (evita una consulta por item dos veces).
static vector<const ItemMenu*> menuVisible() {
    vector<const ItemMenu*> visibles;
    for (const ItemMenu& item : itemsMenuPrincipal()) {
        if (puedeVerItem(item)) visibles.push_back(&item);
    }
    return visibles;
}

static void imprimirMenu(const vector<const ItemMenu*>& visibles) {
    cout << MAGENTA << "\n=== MENU PRINCIPAL BALBU_TECH ===" << RESET << endl;
    cout << AZUL << "Usuario activo: " << sesionActual.username << RESET << endl;
    cout << AZUL << "Rol: " << sesionActual.nombreRol << RESET << endl;
    cout << "----------------------------------------" << endl;

    int n = 0;
    for (const ItemMenu* item : visibles) {
        cout << ++n << ". " << item->etiqueta << endl;
    }

    cout << "----------------------------------------" << endl;
}

// Genera el menú principal según los permisos del usuario autenticado.
void mostrarMenuSegunRol() {
    imprimirMenu(menuVisible());
}

// Ejecuta la navegación del sistema con la misma lista visible del menú.
void ejecutarMenuSegunRol() {
    int opcion = 0;

    do {
        vector<const ItemMenu*> visibles = menuVisible();
        imprimirMenu(visibles);

        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const ItemMenu& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionMenu::Asistencia:  ejecutarSubmenuAsistencia(); break;
            case AccionMenu::Roles:       ejecutarSubmenuRoles(); break;
            case AccionMenu::Usuarios:    ejecutarSubmenuUsuarios(); break;
            case AccionMenu::Empleados:   ejecutarSubmenuEmpleados(); break;
            case AccionMenu::MisPermisos: misPermisosUI(); break;
            case AccionMenu::MisVacaciones: misVacacionesUI(); break;
            case AccionMenu::Clientes:    ejecutarSubmenuClientes(); break;
            case AccionMenu::Proveedores: ejecutarSubmenuProveedores(); break;
            case AccionMenu::Categorias:  ejecutarSubmenuCategorias(); break;
            case AccionMenu::Marcas:      ejecutarSubmenuMarcas(); break;
            case AccionMenu::Productos:   ejecutarSubmenuProductos(); break;
            case AccionMenu::MetodosPago: ejecutarSubmenuMetodosPago(); break;
            case AccionMenu::Ventas:      ejecutarSubmenuVentas(); break;
            case AccionMenu::Compras:     ejecutarSubmenuCompras(); break;
            case AccionMenu::Inventario:  ejecutarSubmenuInventario(); break;
            case AccionMenu::Caja:        ejecutarSubmenuCaja(); break;
            case AccionMenu::LogAccesos:  ejecutarSubmenuAccesos(); break;
            case AccionMenu::VerPermisos: mostrarPermisosActuales(); break;
            case AccionMenu::CerrarSesion:
                cerrarSesion();
                cout << VERDE << "Sesión cerrada correctamente." << RESET << endl;
                return;
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
    cout << "5. Asignar permiso a rol" << endl;
    cout << "6. Quitar permiso a rol" << endl;
    cout << "7. Ver permisos de un rol" << endl;
    cout << "8. Volver al Menu Principal" << endl;
    cout << "=======================" << endl;
}

// Registra un nuevo rol en la base de datos con validación básica de entrada.
void registrarRol() {
    cout << "\n--- REGISTRO DE ROL ---" << endl;
    try {
        string nombreRol = leerDatoSeguro("Nombre del rol: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_ROL(?)"));
        pstmt->setString(1, nombreRol);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
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

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_ROL(?, ?)"));
        pstmt->setInt(1, idRol);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nombre);

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
        cout << "\n[!] Error al actualizar rol: " << e.what() << endl;
    }
}

// Busca roles por coincidencia de nombre y muestra los resultados encontrados.
void buscarRol() {
    cout << "\n--- BUSCAR ROLES ---" << endl;
    try {
        string busqueda = leerDatoSeguro("Ingrese nombre del rol o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_ROLES(?)"));
        pstmt->setString(1, busqueda);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        string separator = string(38, '-');
        cout << "\n" << separator << endl;
        printf("%-5s | %-30s\n", "ID", "NOMBRE DEL ROL");
        cout << separator << endl;

        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s\n",
                   res->getInt("ID_ROL"),
                   res->getString("NOMBRE_ROL").c_str());
            cout << separator << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se hallaron roles con el filtro: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
        }

        drenarResultados(pstmt.get());
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
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        string separator = string(38, '-');
        cout << "\n" << separator << endl;
        printf("%-5s | %-30s\n", "ID", "NOMBRE DEL ROL");
        cout << separator << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-5d | %-30.30s\n",
                   res->getInt("ID_ROL"),
                   res->getString("NOMBRE_ROL").c_str());
            cout << separator << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay roles registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar roles: " << e.what() << endl;
    }
}

// Muestra los roles con su ID (para elegir en las acciones de permisos).
static void mostrarRolesDisponibles() {
    try {
        std::unique_ptr<sql::Statement> st(globalCon->createStatement());
        std::unique_ptr<sql::ResultSet> res(st->executeQuery(
            "SELECT ID_ROL, NOMBRE_ROL FROM ROLES ORDER BY ID_ROL"));
        cout << "\nRoles:" << endl;
        while (res->next()) {
            cout << "  " << res->getInt("ID_ROL") << ". "
                 << res->getString("NOMBRE_ROL") << endl;
        }
        drenarResultados(st.get());
    } catch (const exception&) {
        cout << ROJO << "No se pudieron listar los roles." << RESET << endl;
    }
}

// Muestra los permisos disponibles (los que existen en la tabla).
static void mostrarPermisosDisponibles() {
    try {
        std::unique_ptr<sql::Statement> st(globalCon->createStatement());
        std::unique_ptr<sql::ResultSet> res(st->executeQuery(
            "SELECT NOMBRE_PERMISO FROM PERMISOS ORDER BY NOMBRE_PERMISO"));
        cout << "\nPermisos disponibles:" << endl;
        while (res->next()) {
            cout << "  - " << res->getString("NOMBRE_PERMISO") << endl;
        }
        drenarResultados(st.get());
    } catch (const exception&) {
        cout << ROJO << "No se pudieron listar los permisos." << RESET << endl;
    }
}

// Pide rol y permiso por nombre exacto y llama al SP de asignar o quitar.
static void cambiarPermisoDeRol(bool asignar) {
    try {
        mostrarRolesDisponibles();
        string rol = recortar(leerDatoSeguro("Rol (nombre exacto): "));
        if (rol.empty()) {
            cout << "Cancelado." << endl;
            return;
        }

        mostrarPermisosDisponibles();
        string permiso = recortar(leerDatoSeguro("Permiso (nombre exacto): "));
        if (permiso.empty()) {
            cout << "Cancelado." << endl;
            return;
        }

        const char* sql = asignar
            ? "CALL SP_ASIGNAR_PERMISO_A_ROL(?, ?)"
            : "CALL SP_QUITAR_PERMISO_A_ROL(?, ?)";
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(sql));
        ps->setString(1, rol);
        ps->setString(2, permiso);

        cout << "\n" << Recogermensaje(ps.get()) << endl;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo cambiar el permiso: " << e.what() << RESET << endl;
    }
}

// Lista los permisos actuales de un rol.
static void verPermisosDeRol() {
    try {
        mostrarRolesDisponibles();
        string rol = recortar(leerDatoSeguro("Rol (nombre exacto): "));
        if (rol.empty()) {
            cout << "Cancelado." << endl;
            return;
        }

        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_LISTAR_PERMISOS_POR_ROL(?)"));
        ps->setString(1, rol);
        std::unique_ptr<sql::ResultSet> res(ps->executeQuery());

        string separator = string(78, '-');
        cout << "\n" << separator << endl;
        printf("%-5s | %-30s | %s\n", "ID", "PERMISO", "DESCRIPCION");
        cout << separator << endl;

        bool hay = false;
        while (res->next()) {
            hay = true;
            printf("%-5d | %-30.30s | %.50s\n",
                   res->getInt("ID_PERMISO"),
                   res->getString("NOMBRE_PERMISO").c_str(),
                   res->isNull("DESCRIPCION") ? "" : res->getString("DESCRIPCION").c_str());
        }
        if (!hay) {
            cout << "[!] Ese rol no tiene permisos asignados." << endl;
        }
        cout << separator << endl;

        drenarResultados(ps.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudieron ver los permisos: " << e.what() << RESET << endl;
    }
}

// Submenú de roles: lee la opción y llama a la acción.
void ejecutarSubmenuRoles() {
    int opcion = 0;

    do {
        mostrarMenuRoles();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        switch (opcion) {
            case 1:
                registrarRol();
                break;
            case 2:
                actualizarRol();
                break;
            case 3:
                buscarRol();
                break;
            case 4:
                listarRoles();
                break;
            case 5:
                cambiarPermisoDeRol(true);
                break;
            case 6:
                cambiarPermisoDeRol(false);
                break;
            case 7:
                verPermisosDeRol();
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

