#ifndef SESION_H
#define SESION_H

#include <string>

struct SesionActual {
    bool activa;
    int idUsuario;
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
void guardarSesion(int idUsuario, const std::string& username, const std::string& rol, const std::string& estadoCuenta);
void mostrarSesionActual();

#endif
