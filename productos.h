#ifndef PRODUCTOS_H
#define PRODUCTOS_H

#include <mysql_connection.h>

// Declaración de las funciones del módulo de productos
// (22/10/2026) El menu se arma por permisos dentro de productos.cpp: el orden y
// la cantidad de opciones dependen del rol, asi que no se declara aca.
void ejecutarSubmenuProductos();
void registrarProducto();
void actualizarProducto();
void cambiarEstadoProducto();
void buscarProducto();
void consultarInventario();
void reporteStockCritico();

#endif // PRODUCTOS_H