#include <iostream>
#include <string>
#include <memory>
#include <vector>
#include <cstdio>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "accesos.h"
#include "database.h"
#include "seguridad.h"
#include "roles.h"
#include "colores.h"

using namespace std;

// Modulo 28-LOG_ACCESOS: bitacora de los intentos de login. La llena
// login.cpp en cada intento; aca solo se consulta y se limpia. Entra
// unicamente ADMIN, por el permiso GESTIONAR_ROLES del menu principal.

// Ultimos 50 intentos, del mas reciente al mas viejo.
static void listarAccesos() {
    cout << "\n--- ULTIMOS 50 ACCESOS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_REPORTAR_ACCESOS()"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        string separator = string(54, '-');
        cout << "\n" << separator << endl;
        printf("%-19s | %-20s | %s\n", "FECHA", "USUARIO", "RESULTADO");
        cout << separator << endl;

        bool hay = false;
        while (res->next()) {
            hay = true;
            string estado = res->getString("ESTADO_INTENTO");
            const string& color = (estado == "EXITOSO") ? VERDE
                                : (estado == "INACTIVO") ? AMARILLO : ROJO;
            cout << color;
            printf("%-19.19s | %-20.20s | %s\n",
                   res->getString("FECHA_ACCESO").c_str(),
                   res->getString("USUARIO_INTENTADO").c_str(),
                   estado.c_str());
            cout << RESET;
        }

        if (!hay) {
            cout << "[!] No hay accesos registrados." << endl;
        }
        cout << separator << endl;

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << ROJO << "No se pudieron listar los accesos: " << e.what() << RESET << endl;
    }
}

// Borra los intentos de mas de N dias (Enter = 120, el valor historico).
static void limpiarAccesos() {
    cout << "\n--- LIMPIAR ACCESOS ANTIGUOS ---" << endl;
    try {
        double cientoVeinte = 120;
        double dias = leerNumeroConIntentos("Dias a conservar (Enter = 120): ", 1, 3650, &cientoVeinte);

        string r = leerDatoSeguro("Confirma la limpieza? (s/n): ");
        if (r != "s" && r != "S") {
            cout << "Cancelado." << endl;
            return;
        }

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_LIMPIAR_LOGS_ANTIGUOS(?)"));
        pstmt->setInt(1, (int)dias);

        string msg = Recogermensaje(pstmt.get());
        drenarResultados(pstmt.get());
        if (msg.rfind("Error DB:", 0) == 0 || msg.rfind("ERROR:", 0) == 0) {
            cout << ROJO << msg << RESET << endl;
        } else {
            cout << VERDE << msg << RESET << endl;
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo limpiar el log: " << e.what() << RESET << endl;
    }
}

namespace {

enum class AccionAccesos {
    Ver, Limpiar, Volver
};

struct OpcionAccesos {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionAccesos accion;
};

// (24/10/2026) Mismo patron que el resto de los submenus: lista visible
// numerada y Volver como opcion. El item del menu principal ya pide
// GESTIONAR_ROLES, asi que hoy las tres opciones se ven siempre.
static const vector<OpcionAccesos>& opcionesAccesos() {
    static const vector<OpcionAccesos> opciones = {
        {"Ver ultimos accesos",      "GESTIONAR_ROLES", AccionAccesos::Ver},
        {"Limpiar accesos antiguos", "GESTIONAR_ROLES", AccionAccesos::Limpiar},
        {"Volver al Menu Principal", "",                AccionAccesos::Volver}
    };
    return opciones;
}

static bool puedeVerOpcionAccesos(const OpcionAccesos& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionAccesos*> opcionesAccesosVisibles() {
    vector<const OpcionAccesos*> visibles;
    for (const OpcionAccesos& opcion : opcionesAccesos()) {
        if (puedeVerOpcionAccesos(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuAccesos(const vector<const OpcionAccesos*>& visibles) {
    cout << "\n=== MODULO DE ACCESOS ===" << endl;
    int n = 0;
    for (const OpcionAccesos* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=========================" << endl;
}

}  // namespace

void ejecutarSubmenuAccesos() {
    int opcion = 0;

    while (true) {
        vector<const OpcionAccesos*> visibles = opcionesAccesosVisibles();
        imprimirMenuAccesos(visibles);
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionAccesos& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionAccesos::Ver:     listarAccesos(); break;
            case AccionAccesos::Limpiar: limpiarAccesos(); break;
            case AccionAccesos::Volver:  return;
        }
        pausar();
    }
}
