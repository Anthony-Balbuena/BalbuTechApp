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
    // (03/11/2026) Token emitido por SP_LOGIN_AUTENTICAR. Va en @TOKEN_SESION
    // y es lo que valida SP_EXIGIR_PERMISO en cada rutina.
    std::string token;
};

extern SesionActual sesionActual;

void inicializarSesion();
void cerrarSesion();
bool sesionActiva();
void guardarSesion(int idUsuario, int idEmpleado, const std::string& username, int idRol, const std::string& rol, const std::string& estadoCuenta);
void guardarTokenSesion(const std::string& token);
void mostrarSesionActual();

#endif
