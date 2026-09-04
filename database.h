#ifndef DATABASE_H
#define DATABASE_H

#include <string>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/connection.h>

// Variable global de conexión accesible en todo el proyecto
extern sql::Connection *globalCon;

// Prototipos de base de datos
void inicializarConexion();
std::string Recogermensaje(sql::PreparedStatement *pstmt);
void mostrarCategoriasYMarcas();

#endif