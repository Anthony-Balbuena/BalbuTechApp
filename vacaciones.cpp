#include <iostream>
#include <string>
#include <memory>
#include <vector>
#include <cstdio>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "vacaciones.h"
#include "database.h"
#include "seguridad.h"
#include "roles.h"
#include "colores.h"
#include "sesion.h"

using namespace std;

// Modulo 12-VACACIONES_EMPLEADOS. Se mantiene separado de permisos.cpp para
// no mezclar dos modulos: cada uno tiene sus propios SP y su propia pantalla.
// Dos pantallas sobre los mismos SP:
// - misVacacionesUI(): el empleado ve su historial y pide vacaciones nuevas.
// - gestionarVacacionesUI(): RRHH/ADMIN aprueba o rechaza las pendientes.

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

// Historial propio, de la solicitud mas reciente a la mas antigua (lo ordena
// el SP). Una solicitud PENDIENTE todavia no es una ausencia firme.
static void mostrarHistorialPropio(int idEmpleado) {
    cout << "\n--- MI HISTORIAL DE VACACIONES ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_HISTORIAL_VACACIONES_EMPLEADO(?)"));
        ps->setInt(1, idEmpleado);
        std::unique_ptr<sql::ResultSet> res(ps->executeQuery());

        string separator = string(66, '-');
        cout << separator << endl;
        printf("%-10s | %-10s | %-10s | %s\n",
               "INICIO", "FIN", "ESTADO", "REGISTRO");
        cout << separator << endl;

        bool hay = false;
        while (res->next()) {
            hay = true;
            string estado = res->getString("ESTADO");
            const string& color = (estado == "APROBADO") ? VERDE
                                : (estado == "PENDIENTE") ? AMARILLO : ROJO;
            cout << color;
            printf("%-10.10s | %-10.10s | %-10.10s | %.19s\n",
                   res->getString("FECHA_INICIO").c_str(),
                   res->getString("FECHA_FIN").c_str(),
                   estado.c_str(),
                   res->getString("FECHA_REGISTRO").c_str());
            cout << RESET;
        }

        if (!hay) {
            cout << "[!] Todavia no tienes solicitudes de vacaciones." << endl;
        }
        cout << separator << endl;

        res.reset();
        drenarResultados(ps.get());
    } catch (const exception &e) {
        cout << ROJO << "No se pudo leer el historial: " << e.what() << RESET << endl;
    }
}

// Alta de una solicitud propia. El SP valida retroactivos, solapamiento y el
// tope de 15 dias; aca solo se piden las fechas en el formato de MariaDB.
static void crearSolicitudVacaciones(int idEmpleado) {
    cout << "\n--- NUEVA SOLICITUD DE VACACIONES ---" << endl;
    cout << "Las fechas se piden como YYYY-MM-DD (pueden ser futuras)." << endl;

    string fechaInicio = leerDatoSeguro("Fecha de inicio (YYYY-MM-DD): ");
    string fechaFin = leerDatoSeguro("Fecha de fin (YYYY-MM-DD): ");

    if (fechaInicio.empty() || fechaFin.empty()) {
        cout << ROJO << "[!] La fecha de inicio y la de fin son obligatorias." << RESET << endl;
        return;
    }

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "CALL SP_SOLICITAR_VACACIONES(?, ?, ?)"));
    ps->setInt(1, idEmpleado);
    ps->setString(2, fechaInicio);
    ps->setString(3, fechaFin);

    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

// Pantalla del empleado: historial + alta, en loop para refrescar la lista
// despues de cada solicitud. No edita ni borra.
namespace {

enum class AccionMisVacaciones {
    NuevaSolicitud, Volver
};

struct OpcionMisVacaciones {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionMisVacaciones accion;
};

// (24/10/2026) Mismo patron que el resto de los submenus: lista visible
// numerada y Volver como opcion. El item del menu principal ya pide
// SOLICITAR_PERMISO, asi que hoy las dos opciones se ven siempre.
static const vector<OpcionMisVacaciones>& opcionesMisVacaciones() {
    static const vector<OpcionMisVacaciones> opciones = {
        {"Nueva solicitud",          "SOLICITAR_PERMISO", AccionMisVacaciones::NuevaSolicitud},
        {"Volver al Menu Principal", "",                 AccionMisVacaciones::Volver}
    };
    return opciones;
}

static bool puedeVerOpcionMisVacaciones(const OpcionMisVacaciones& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionMisVacaciones*> opcionesMisVacacionesVisibles() {
    vector<const OpcionMisVacaciones*> visibles;
    for (const OpcionMisVacaciones& opcion : opcionesMisVacaciones()) {
        if (puedeVerOpcionMisVacaciones(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuMisVacaciones(const vector<const OpcionMisVacaciones*>& visibles) {
    int n = 0;
    for (const OpcionMisVacaciones* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
}

}  // namespace

void misVacacionesUI() {
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
    while (true) {
        vector<const OpcionMisVacaciones*> visibles = opcionesMisVacacionesVisibles();
        cout << MAGENTA << "\n=== MIS VACACIONES ===" << RESET << endl;
        mostrarHistorialPropio(idEmpleado);
        cout << endl;
        imprimirMenuMisVacaciones(visibles);

        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionMisVacaciones& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionMisVacaciones::NuevaSolicitud:
                try {
                    crearSolicitudVacaciones(idEmpleado);
                } catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                } catch (const exception &e) {
                    cout << ROJO << "No se pudo crear la solicitud: " << e.what() << RESET << endl;
                }
                break;
            case AccionMisVacaciones::Volver:
                return;
        }
        pausar();
    }
}

struct VacacionPendiente {
    int id;
    string nombre;
    string fechaInicio;
    string fechaFin;
    string fechaRegistro;
};

static vector<VacacionPendiente> listarVacacionesPendientes() {
    vector<VacacionPendiente> pendientes;

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "CALL SP_LISTAR_VACACIONES_PENDIENTES()"));
    std::unique_ptr<sql::ResultSet> res(ps->executeQuery());
    while (res->next()) {
        VacacionPendiente v;
        v.id = res->getInt("ID_VACACION");
        v.nombre = res->getString("NOMBRE");
        v.fechaInicio = res->getString("FECHA_INICIO");
        v.fechaFin = res->getString("FECHA_FIN");
        v.fechaRegistro = res->getString("FECHA_REGISTRO");
        pendientes.push_back(v);
    }
    res.reset();
    drenarResultados(ps.get());
    return pendientes;
}

// Pantalla de RRHH/ADMIN: lista pendientes, resuelve una y vuelve a listar.
// El SP rechaza cualquier intento de resolver dos veces la misma solicitud.
void gestionarVacacionesUI() {
    if (globalCon == nullptr) {
        cout << ROJO << "No hay conexión activa a la base de datos." << RESET << endl;
        return;
    }

    for (;;) {
        vector<VacacionPendiente> pendientes;
        try {
            pendientes = listarVacacionesPendientes();
        } catch (const exception &e) {
            cout << ROJO << "No se pudieron listar las vacaciones pendientes: "
                 << e.what() << RESET << endl;
            return;
        }

        cout << MAGENTA << "\n=== VACACIONES PENDIENTES ===" << RESET << endl;
        if (pendientes.empty()) {
            cout << "[!] No hay solicitudes de vacaciones pendientes." << endl;
            return;
        }

        string separator = string(82, '-');
        cout << separator << endl;
        printf("%-5s | %-22s | %-10s | %-10s | %s\n",
               "ID", "EMPLEADO", "INICIO", "FIN", "REGISTRO");
        cout << separator << endl;
        for (const VacacionPendiente& v : pendientes) {
            printf("%-5d | %-22.22s | %-10.10s | %-10.10s | %.19s\n",
                   v.id, v.nombre.c_str(), v.fechaInicio.c_str(),
                   v.fechaFin.c_str(), v.fechaRegistro.c_str());
        }
        cout << separator << endl;

        int idVacacion = 0;
        try {
            idVacacion = (int)leerNumeroConIntentos(
                "ID de la vacacion a gestionar (0 = volver): ", 0, 2147483647);
        } catch (const CancelarOperacionException &e) {
            cout << "\n[!] " << e.what() << endl;
            return;
        }
        if (idVacacion == 0) return;

        const VacacionPendiente* elegida = nullptr;
        for (const VacacionPendiente& v : pendientes) {
            if (v.id == idVacacion) {
                elegida = &v;
                break;
            }
        }
        if (elegida == nullptr) {
            cout << ROJO << "[!] El ID " << idVacacion
                 << " no está en la lista de pendientes." << RESET << endl;
            pausar();
            continue;
        }

        cout << "\nVacacion #" << elegida->id << " de " << elegida->nombre
             << " del " << elegida->fechaInicio << " al " << elegida->fechaFin << endl;

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
                "CALL SP_GESTIONAR_VACACION(?, ?)"));
            ps->setInt(1, idVacacion);
            ps->setString(2, nuevoEstado);

            string mensaje = Recogermensaje(ps.get());
            drenarResultados(ps.get());
            mostrarMensaje(mensaje);
        } catch (const exception &e) {
            cout << ROJO << "No se pudo gestionar la vacacion: "
                 << e.what() << RESET << endl;
        }
        pausar();

        // Vuelve a listar: la solicitud resuelta ya no aparece y, si no queda
        // ninguna, el proximo ciclo lo avisa.
    }
}
