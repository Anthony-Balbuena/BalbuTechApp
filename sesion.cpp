#include "sesion.h"
#include "database.h"
#include <iostream>
#include <memory>

using namespace std;

SesionActual sesionActual = {false, 0, 0, "", "", 0, "", ""};

void inicializarSesion() {
    sesionActual.activa = false;
    sesionActual.idUsuario = 0;
    sesionActual.idEmpleado = 0;
    sesionActual.username = "";
    sesionActual.nombreUsuario = "";
    sesionActual.idRol = 0;
    sesionActual.nombreRol = "";
    sesionActual.estadoCuenta = "";
}

void guardarSesion(int idUsuario, int idEmpleado, const string& username, int idRol, const string& rol, const string& estadoCuenta) {
    sesionActual.activa = true;
    sesionActual.idUsuario = idUsuario;
    sesionActual.idEmpleado = idEmpleado;
    sesionActual.username = username;
    sesionActual.nombreUsuario = username;
    sesionActual.idRol = idRol;
    sesionActual.nombreRol = rol;
    sesionActual.estadoCuenta = estadoCuenta;
}

void cerrarSesion() {
    // (25/10/2026) Limpia el admin de la conexion: despues del logout no
    // queda ningun usuario como autor de un cambio.
    // (29/10/2026) Limpia tambien el empleado y el motivo del historial
    // de estado de producto (modulo 61).
    if (globalCon != nullptr) {
        try {
            std::unique_ptr<sql::PreparedStatement> p(globalCon->prepareStatement(
                "SET @ID_USUARIO_ACTUAL = NULL, @ID_EMPLEADO_ACTUAL = NULL, @MOTIVO_CAMBIO = NULL"
            ));
            p->execute();
            drenarResultados(p.get());
        } catch (...) {
        }
    }
    inicializarSesion();
}

bool sesionActiva() {
    return sesionActual.activa;
}

void mostrarSesionActual() {
    if (!sesionActual.activa) {
        cout << "[!] No hay sesión activa." << endl;
        return;
    }

    cout << "--- SESION ACTIVA ---" << endl;
    cout << "ID Usuario: " << sesionActual.idUsuario << endl;
    cout << "ID Empleado: " << sesionActual.idEmpleado << endl;
    cout << "Usuario: " << sesionActual.username << endl;
    cout << "Rol: " << sesionActual.nombreRol << endl;
    cout << "Estado: " << sesionActual.estadoCuenta << endl;
}
