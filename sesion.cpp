#include "sesion.h"
#include <iostream>

using namespace std;

SesionActual sesionActual = {false, 0, "", "", 0, "", ""};

void inicializarSesion() {
    sesionActual.activa = false;
    sesionActual.idUsuario = 0;
    sesionActual.username = "";
    sesionActual.nombreUsuario = "";
    sesionActual.idRol = 0;
    sesionActual.nombreRol = "";
    sesionActual.estadoCuenta = "";
}

void guardarSesion(int idUsuario, const string& username, const string& rol, const string& estadoCuenta) {
    sesionActual.activa = true;
    sesionActual.idUsuario = idUsuario;
    sesionActual.username = username;
    sesionActual.nombreUsuario = username;
    sesionActual.idRol = 0;
    sesionActual.nombreRol = rol;
    sesionActual.estadoCuenta = estadoCuenta;
}

void cerrarSesion() {
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
    cout << "Usuario: " << sesionActual.username << endl;
    cout << "Rol: " << sesionActual.nombreRol << endl;
    cout << "Estado: " << sesionActual.estadoCuenta << endl;
}
