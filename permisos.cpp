#include <iostream>
#include <string>
#include <memory>
#include <vector>
#include <cstdio>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "permisos.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "sesion.h"

using namespace std;

// Modulo 13-PERMISOS_EMPLEADOS. Dos pantallas sobre los mismos SP:
// - misPermisosUI(): el empleado ve su historial y pide permisos nuevos.
// - gestionarPermisosUI(): RRHH/ADMIN resuelve los pendientes.

// El usuario de la sesion no guarda el ID de empleado: se busca en USUARIOS
// por USUARIO (el mismo criterio que usa el login para entrar).
static int empleadoDeSesion() {
    if (!sesionActiva() || globalCon == nullptr) return 0;

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "SELECT ID_EMPLEADO FROM USUARIOS WHERE USUARIO = ?"));
    ps->setString(1, sesionActual.username);

    std::unique_ptr<sql::ResultSet> res(ps->executeQuery());
    int idEmpleado = 0;
    if (res->next()) {
        idEmpleado = res->isNull("ID_EMPLEADO") ? 0 : res->getInt("ID_EMPLEADO");
    }
    res.reset();
    drenarResultados(ps.get());
    return idEmpleado;
}

static bool mensajeDeError(const string& mensaje) {
    return mensaje.rfind("Error DB:", 0) == 0 || mensaje.rfind("ERROR:", 0) == 0;
}

static void mostrarMensaje(const string& mensaje) {
    if (mensajeDeError(mensaje)) {
        cout << ROJO << mensaje << RESET << endl;
    } else {
        cout << VERDE << mensaje << RESET << endl;
    }
}

// Historial propio, del mas reciente al mas antiguo (lo ordena el SP).
static void mostrarHistorialPropio(int idEmpleado) {
    cout << "\n--- MI HISTORIAL DE PERMISOS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_HISTORIAL_PERMISOS_EMPLEADO(?)"));
        ps->setInt(1, idEmpleado);
        std::unique_ptr<sql::ResultSet> res(ps->executeQuery());

        string separator = string(89, '-');
        cout << separator << endl;
        printf("%-11s | %-10s | %-10s | %-10s | %s\n",
               "TIPO", "INICIO", "FIN", "ESTADO", "DESCRIPCION");
        cout << separator << endl;

        bool hay = false;
        while (res->next()) {
            hay = true;
            string estado = res->getString("ESTADO");
            const string& color = (estado == "APROBADO") ? VERDE
                                : (estado == "PENDIENTE") ? AMARILLO : ROJO;
            cout << color;
            printf("%-11.11s | %-10.10s | %-10.10s | %-10.10s | %.45s\n",
                   res->getString("TIPO_PERMISO").c_str(),
                   res->getString("FECHA_INICIO").c_str(),
                   res->getString("FECHA_FIN").c_str(),
                   estado.c_str(),
                   res->isNull("DESCRIPCION") ? "" : res->getString("DESCRIPCION").c_str());
            cout << RESET;
        }

        if (!hay) {
            cout << "[!] Todavia no tienes solicitudes de permiso." << endl;
        }
        cout << separator << endl;

        res.reset();
        drenarResultados(ps.get());
    } catch (const exception &e) {
        cout << ROJO << "No se pudo leer el historial: " << e.what() << RESET << endl;
    }
}

// Alta de una solicitud propia. El SP valida retroactivos y solapamientos;
// aca solo se pide el tipo y las fechas en el formato que espera MariaDB.
static void crearSolicitudPermiso(int idEmpleado) {
    cout << "\n--- NUEVA SOLICITUD DE PERMISO ---" << endl;
    cout << "1. MEDICO" << endl;
    cout << "2. PERSONAL" << endl;
    cout << "3. ESTUDIO" << endl;
    cout << "4. LICENCIA" << endl;
    cout << "5. SIN_SUELDO" << endl;

    static const char* tipos[] = {"MEDICO", "PERSONAL", "ESTUDIO", "LICENCIA", "SIN_SUELDO"};
    int opcionTipo = (int)leerNumeroConIntentos("Tipo de permiso: ", 1, 5);

    string fechaInicio = leerDatoSeguro("Fecha de inicio (YYYY-MM-DD): ");
    string fechaFin = leerDatoSeguro("Fecha de fin (YYYY-MM-DD): ");
    string descripcion = leerDatoSeguro("Descripcion (opcional): ");

    if (fechaInicio.empty() || fechaFin.empty()) {
        cout << ROJO << "[!] La fecha de inicio y la de fin son obligatorias." << RESET << endl;
        return;
    }

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "CALL SP_SOLICITAR_PERMISO(?, ?, ?, ?, ?)"));
    ps->setInt(1, idEmpleado);
    ps->setString(2, tipos[opcionTipo - 1]);
    ps->setString(3, fechaInicio);
    ps->setString(4, fechaFin);
    ps->setString(5, descripcion);

    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

// Pantalla del empleado: historial + alta, en loop para refrescar la lista
// despues de cada solicitud. No edita ni borra.
void misPermisosUI() {
    if (!sesionActiva() || globalCon == nullptr) {
        cout << ROJO << "No hay sesión activa." << RESET << endl;
        return;
    }

    int idEmpleado = 0;
    try {
        idEmpleado = empleadoDeSesion();
    } catch (const exception &e) {
        cout << ROJO << "No se pudo identificar tu empleado: " << e.what() << RESET << endl;
        return;
    }

    if (idEmpleado <= 0) {
        cout << ROJO << "Tu usuario no está vinculado a un empleado. "
             << "Pide a administración que lo asocie en Usuarios." << RESET << endl;
        pausar();
        return;
    }

    int opcion = 0;
    do {
        cout << MAGENTA << "\n=== MIS PERMISOS ===" << RESET << endl;
        mostrarHistorialPropio(idEmpleado);
        cout << "\n1. Nueva solicitud" << endl;
        cout << "0. Volver al Menu Principal" << endl;

        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        switch (opcion) {
            case 1:
                try {
                    crearSolicitudPermiso(idEmpleado);
                } catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                } catch (const exception &e) {
                    cout << ROJO << "No se pudo crear la solicitud: " << e.what() << RESET << endl;
                }
                break;
            case 0:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 0) pausar();
    } while (opcion != 0);
}

struct PermisoPendiente {
    int id;
    string nombre;
    string tipo;
    string fechaInicio;
    string fechaFin;
    string descripcion;
};

static vector<PermisoPendiente> listarPermisosPendientes() {
    vector<PermisoPendiente> pendientes;

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "CALL SP_LISTAR_PERMISOS_PENDIENTES()"));
    std::unique_ptr<sql::ResultSet> res(ps->executeQuery());
    while (res->next()) {
        PermisoPendiente p;
        p.id = res->getInt("ID_PERMISO");
        p.nombre = res->getString("NOMBRE");
        p.tipo = res->getString("TIPO_PERMISO");
        p.fechaInicio = res->getString("FECHA_INICIO");
        p.fechaFin = res->getString("FECHA_FIN");
        p.descripcion = res->isNull("DESCRIPCION") ? "" : res->getString("DESCRIPCION");
        pendientes.push_back(p);
    }
    res.reset();
    drenarResultados(ps.get());
    return pendientes;
}

// Pantalla de RRHH/ADMIN: lista pendientes, resuelve uno y vuelve a listar.
// El SP rechaza cualquier intento de resolver dos veces el mismo permiso.
void gestionarPermisosUI() {
    if (globalCon == nullptr) {
        cout << ROJO << "No hay conexión activa a la base de datos." << RESET << endl;
        return;
    }

    for (;;) {
        vector<PermisoPendiente> pendientes;
        try {
            pendientes = listarPermisosPendientes();
        } catch (const exception &e) {
            cout << ROJO << "No se pudieron listar los permisos pendientes: "
                 << e.what() << RESET << endl;
            return;
        }

        cout << MAGENTA << "\n=== PERMISOS PENDIENTES ===" << RESET << endl;
        if (pendientes.empty()) {
            cout << "[!] No hay solicitudes de permiso pendientes." << endl;
            return;
        }

        string separator = string(96, '-');
        cout << separator << endl;
        printf("%-5s | %-22s | %-11s | %-10s | %-10s | %s\n",
               "ID", "EMPLEADO", "TIPO", "INICIO", "FIN", "DESCRIPCION");
        cout << separator << endl;
        for (const PermisoPendiente& p : pendientes) {
            printf("%-5d | %-22.22s | %-11.11s | %-10.10s | %-10.10s | %.35s\n",
                   p.id, p.nombre.c_str(), p.tipo.c_str(),
                   p.fechaInicio.c_str(), p.fechaFin.c_str(),
                   p.descripcion.c_str());
        }
        cout << separator << endl;

        int idPermiso = 0;
        try {
            idPermiso = (int)leerNumeroConIntentos(
                "ID del permiso a gestionar (0 = volver): ", 0, 2147483647);
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            return;
        }
        if (idPermiso == 0) return;

        const PermisoPendiente* elegido = nullptr;
        for (const PermisoPendiente& p : pendientes) {
            if (p.id == idPermiso) {
                elegido = &p;
                break;
            }
        }
        if (elegido == nullptr) {
            cout << ROJO << "[!] El ID " << idPermiso
                 << " no está en la lista de pendientes." << RESET << endl;
            pausar();
            continue;
        }

        cout << "\nPermiso #" << elegido->id << " de " << elegido->nombre
             << ": " << elegido->tipo << " del " << elegido->fechaInicio
             << " al " << elegido->fechaFin << endl;

        int accion = 0;
        try {
            accion = (int)leerNumeroConIntentos(
                "Accion (1 Aprobar / 2 Rechazar): ", 1, 2);
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            return;
        }

        const char* nuevoEstado = (accion == 1) ? "APROBADO" : "RECHAZADO";
        try {
            std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
                "CALL SP_GESTIONAR_PERMISO(?, ?)"));
            ps->setInt(1, idPermiso);
            ps->setString(2, nuevoEstado);

            string mensaje = Recogermensaje(ps.get());
            drenarResultados(ps.get());
            mostrarMensaje(mensaje);
        } catch (const exception &e) {
            cout << ROJO << "No se pudo gestionar el permiso: "
                 << e.what() << RESET << endl;
        }
        pausar();

        // Vuelve a listar: el permiso resuelto ya no aparece y, si no queda
        // ninguno, el proximo ciclo lo avisa.
    }
}
