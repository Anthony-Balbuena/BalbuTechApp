#ifndef SESION_H
#define SESION_H

#include <string>

struct SesionActual {
    bool activa;
    int idUsuario;
    int idEmpleado;
    std::string username;
    std::string nombreUsuario;
    int idRol;
    std::string nombreRol;
    std::string estadoCuenta;
};

extern SesionActual sesionActual;

void inicializarSesion();
void cerrarSesion();
bool sesionActiva();
void guardarSesion(int idUsuario, int idEmpleado, const std::string& username, int idRol, const std::string& rol, const std::string& estadoCuenta);
void mostrarSesionActual();

#endif
