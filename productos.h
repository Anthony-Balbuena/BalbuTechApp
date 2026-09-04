#ifndef PRODUCTOS_H
#define PRODUCTOS_H

#include <mysql_connection.h>

// Declaración de las funciones del módulo de productos
void mostrarMenuProductos();
void registrarProducto();
void actualizarProducto();
void cambiarEstadoProducto();
void buscarProducto();
void consultarInventario();
void reporteStockCritico();

#endif // PRODUCTOS_H