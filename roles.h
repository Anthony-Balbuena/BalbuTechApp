#ifndef ROLES_H
#define ROLES_H

#include <string>
#include <vector>

std::vector<std::string> obtenerPermisosPorRol(const std::string& rol);
bool tienePermiso(const std::string& accion);
void mostrarPermisosActuales();
void mostrarMenuSegunRol();
void ejecutarMenuSegunRol();

void mostrarMenuRoles();
void registrarRol();
void actualizarRol();
void buscarRol();
void listarRoles();

#endif
