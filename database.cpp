#include "database.h"
#include <iostream>
#include <cstdlib>
#include <mysql_driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>

using namespace std;

sql::Connection *globalCon = nullptr;

static string envOr(const char *name, const string &dflt) {
    const char *v = std::getenv(name);
    return (v && *v) ? string(v) : dflt;
}

void inicializarConexion() {
    try {
        // En Docker: DB_HOST=db (ver .env). En Windows local: DB_HOST=127.0.0.1.
        string host = envOr("DB_HOST", "127.0.0.1");
        string port = envOr("DB_PORT", "3306");
        string user = envOr("DB_USER", "root");
        string pass = envOr("DB_PASSWORD", "linux01");
        string name = envOr("DB_NAME", "BALBU_TECH");

        sql::mysql::MySQL_Driver *driver = sql::mysql::get_mysql_driver_instance();
        globalCon = driver->connect("tcp://" + host + ":" + port, user, pass);
        globalCon->setSchema(name);
    } catch (sql::SQLException &e) {
        cout << "Error en la conexion: " << e.what() << endl;
    }
}

string Recogermensaje(sql::PreparedStatement *pstmt) {
    string mensaje = "";
    try {
        sql::ResultSet *res = pstmt->executeQuery();
        if (res && res->next()) {
            mensaje = res->getString("MENSAJE");
        }
        delete res; 
    } catch (sql::SQLException &e) {
        mensaje = "Error DB: " + string(e.what());
    }
    return mensaje;
}

void mostrarCategoriasYMarcas() {
    try {
        sql::Statement *stmt = globalCon->createStatement();
        sql::ResultSet *resCat = stmt->executeQuery("SELECT ID_CATEGORIA, NOMBRE FROM CATEGORIAS;");
        
        cout << "\n--- CATEGORÍAS DISPONIBLES ---" << endl;
        cout << "ID\tNombre" << endl;
        cout << "-----------------------------" << endl;
        while (resCat->next()) {
            cout << resCat->getInt("ID_CATEGORIA") << "\t" << resCat->getString("NOMBRE") << endl;
        }
        delete resCat;

        sql::ResultSet *resMar = stmt->executeQuery("SELECT ID_MARCA, NOMBRE FROM MARCAS;");
        cout << "\n--- MARCAS DISPONIBLES ---" << endl;
        cout << "ID\tNombre" << endl;
        cout << "--------------------------" << endl;
        while (resMar->next()) {
            cout << resMar->getInt("ID_MARCA") << "\t" << resMar->getString("NOMBRE") << endl;
        }
        delete resMar;
        delete stmt;
    } catch (sql::SQLException &e) {
        cout << "Error al cargar categorías o marcas: " << e.what() << endl;
    }
}