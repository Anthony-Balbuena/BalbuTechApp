#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <limits>
#include <vector>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "roles.h"

using namespace std;

// ---------------------------------------------------------------------------
// Submenu dinamico: cada accion pide su permiso fino. Igual que el menu
// principal (roles.cpp), la lista visible se arma antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionUsuario { Agregar, Actualizar, Estado, Buscar, Clave, Listar, Volver };

struct OpcionUsuario {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionUsuario accion;
};

static const vector<OpcionUsuario>& opcionesUsuarios() {
    static const vector<OpcionUsuario> opciones = {
        {"Agregar Usuario",           "USUARIOS_CREAR",  AccionUsuario::Agregar},
        {"Actualizar Usuario",        "USUARIOS_EDITAR", AccionUsuario::Actualizar},
        {"Cambiar Estado",            "USUARIOS_ESTADO", AccionUsuario::Estado},
        {"Buscar Usuario",            "USUARIOS_VER",    AccionUsuario::Buscar},
        {"Cambiar Clave",             "USUARIOS_CLAVE",  AccionUsuario::Clave},
        {"Listar Usuarios",           "USUARIOS_VER",    AccionUsuario::Listar},
        {"Volver al Menu Principal",  "",                AccionUsuario::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionUsuario& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionUsuario*> opcionesVisibles() {
    vector<const OpcionUsuario*> visibles;
    for (const OpcionUsuario& opcion : opcionesUsuarios()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuUsuarios(const vector<const OpcionUsuario*>& visibles) {
    cout << "\n=== MODULO DE USUARIOS ===" << endl;
    int n = 0;
    for (const OpcionUsuario* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=========================" << endl;
}

}  // namespace


void registrarUsuario() {
    cout << "\n--- REGISTRO DE USUARIO ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_INSERTAR_USUARIOS()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- ROLES DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "| ID: " << RESET << res->getInt("ID_ROL")
                     << CIAN << " | Nombre_rol: " << RESET << res->getString("NOMBRE_ROL") << endl;
            }
        }

        if (pstmt->getMoreResults()) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- EMPLEADOS DISPONIBLES ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "| ID_EMPLEADO: " << RESET << res->getInt("ID_EMPLEADO")
                     << CIAN << " | NOMBRE_EMPLEADO: " << RESET << res->getString("NOMBRE") << endl;
            }
        }

        drenarResultados(pstmt.get());

        string nombre = leerDatoSeguro("Nombre del Usuario: ");
        string clavePlana = leerDatoSeguro("Clave: ");
        string claveHash = aplicarHash(clavePlana);

        string idRolStr = leerDatoSeguro("ID del rol (Numero): ");
        int idRol = stoi(idRolStr);

        string idEmpStr = leerDatoSeguro("ID del empleado (NUMERO): ");
        int idEmpleado = stoi(idEmpStr);

        std::unique_ptr<sql::PreparedStatement> pstmtInsert(globalCon->prepareStatement("CALL SP_INSERTAR_USUARIO(?, ?, ?, ?)"));
        pstmtInsert->setInt(1, idEmpleado);
        pstmtInsert->setInt(2, idRol);
        pstmtInsert->setString(3, nombre);
        pstmtInsert->setString(4, claveHash);

        string respuesta = Recogermensaje(pstmtInsert.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Formato numérico inválido en los campos ID." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void actualizarUsuario() {
    cout << "\n--- ACTUALIZAR USUARIO ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_ACTUALIZAR_USUARIOS()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- LISTADO GENERAL DE ROLES Y EMPLEADOS ---\n" << RESET;
            while (res->next()) {
                cout << CIAN << "\n| ID USUARIO: " << RESET << res->getInt("ID_USUARIO")
                     << CIAN << "\n| NOMBRE DEL USUARIO: " << RESET << res->getString("NOMBRE_USUARIO")
                     << CIAN << "\n| ID ROL: " << RESET << res->getInt("ID_ROL")
                     << CIAN << "\n| NOMBRE ROL: " << RESET << res->getString("NOMBRE_ROL")
                     << CIAN << "\n| ID EMPLEADO: " << RESET << res->getInt("ID_EMPLEADO")
                     << CIAN << "\n| Nombre EMPLEADO: " << RESET << res->getString("NOMBRE_EMPLEADO") << endl;
            }
        }
        drenarResultados(pstmt.get());

        string idStr = leerDatoSeguro("ID del Usuario a Modificar: ");
        int idUsuario = stoi(idStr);

        cout << "Nota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
        string nuevoUsuario = leerDatoSeguro("Nuevo nombre de Usuario: ");
        string idRolStr = leerDatoSeguro("Nuevo ID Rol: ");
        string idEmpStr = leerDatoSeguro("Nuevo ID Empleado: ");

        std::unique_ptr<sql::PreparedStatement> pstmtUpdate(globalCon->prepareStatement("CALL SP_ACTUALIZAR_USUARIO(?, ?, ?, ?)"));
        pstmtUpdate->setInt(1, idUsuario);

        if (nuevoUsuario.empty()) pstmtUpdate->setNull(2, sql::DataType::VARCHAR);
        else pstmtUpdate->setString(2, nuevoUsuario);

        if (idRolStr.empty()) pstmtUpdate->setNull(3, sql::DataType::INTEGER);
        else pstmtUpdate->setInt(3, stoi(idRolStr));

        if (idEmpStr.empty()) pstmtUpdate->setNull(4, sql::DataType::INTEGER);
        else pstmtUpdate->setInt(4, stoi(idEmpStr));

        string respuesta = Recogermensaje(pstmtUpdate.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: Formato numérico inválido en los campos ID." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void cambiarEstadoUsuario() {
    cout << "\n--- DESACTIVAR/ACTIVAR ESTADO DEL USUARIO ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL PARA_ACT_DESAC_USUARIOS()"));
        bool results = pstmt->execute();

        if (results) {
            std::unique_ptr<sql::ResultSet> res(pstmt->getResultSet());
            cout << CIAN << "\n--- LISTADO DE USUARIOS, SU ESTADO Y SU EMPLEADO ---\n" << RESET << endl;
            while (res->next()) {
                cout << CIAN << "\n| ID Usuario: " << RESET << res->getInt("ID_USUARIO")
                     << CIAN << "\n| Nombre: " << RESET << res->getString("USUARIO")
                     << CIAN << "\n| Estado: " << RESET << res->getString("ESTADO")
                     << CIAN << "\n| Empleado: " << RESET << res->getString("EMPLEADO") << endl;
            }
        }
        drenarResultados(pstmt.get());

        string idStr = leerDatoSeguro("Ingrese el ID del usuario: ");
        int idUsuario = stoi(idStr);

        std::unique_ptr<sql::PreparedStatement> pstmtToggle(globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_USUARIO(?)"));
        pstmtToggle->setInt(1, idUsuario);

        string respuesta = Recogermensaje(pstmtToggle.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] Error: El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }
}

void buscarUsuario() {
    cout << "\n--- BUSCAR USUARIO ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre de usuario o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_BUSCAR_USUARIOS(?)"));
        pstmt->setString(1, filtro);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_USUARIO") << " | "
                 << res->getString("NOMBRE_USUARIO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron usuarios con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar usuario: " << e.what() << endl;
    }
}

void cambiarClaveUsuario() {
    cout << "\n--- CAMBIAR CLAVE DE USUARIO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del usuario: ");
        int idUsuario = stoi(idStr);

        string claveNueva = leerDatoSeguro("Nueva clave: ");
        string claveHash = aplicarHash(claveNueva);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_CAMBIAR_CLAVE_USUARIO(?, ?)"));
        pstmt->setInt(1, idUsuario);
        pstmt->setString(2, claveHash);

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
        cout << "\n[!] Error al cambiar clave: " << e.what() << endl;
    }
}

void listarUsuarios() {
    cout << "\n--- LISTADO DE USUARIOS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_USUARIO, USUARIO, ESTADO FROM USUARIOS ORDER BY ID_USUARIO"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        cout << "\nID | USUARIO | ESTADO" << endl;
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            cout << res->getInt("ID_USUARIO") << " | "
                 << res->getString("USUARIO") << " | "
                 << res->getString("ESTADO") << endl;
        }

        if (!encontrado) {
            cout << "\n[!] No hay usuarios registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar usuarios: " << e.what() << endl;
    }
}

// Submenu de usuarios: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion.
void ejecutarSubmenuUsuarios() {
    for (;;) {
        vector<const OpcionUsuario*> visibles = opcionesVisibles();
        imprimirMenuUsuarios(visibles);

        int opcion = 0;
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            return;
        }
        if (opcion == 0) return;

        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionUsuario& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionUsuario::Agregar:    registrarUsuario(); break;
            case AccionUsuario::Actualizar: actualizarUsuario(); break;
            case AccionUsuario::Estado:     cambiarEstadoUsuario(); break;
            case AccionUsuario::Buscar:     buscarUsuario(); break;
            case AccionUsuario::Clave:      cambiarClaveUsuario(); break;
            case AccionUsuario::Listar:     listarUsuarios(); break;
            case AccionUsuario::Volver:     return;
        }
        pausar();
    }
}

