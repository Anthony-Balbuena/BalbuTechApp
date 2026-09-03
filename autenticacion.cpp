#include "seguridad.h"
#include <iostream>
#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>
#include <cppconn/driver.h>
#include <mysql_driver.h>

using namespace std;

string iniciarSesion() {
    string username, password_input;
    
    cout << "Usuario: ";
    cin >> username;
    cout << "Contraseña: ";
    cin >> password_input;

    string rolObtenido = "ERROR";

    try {
        sql::mysql::MySQL_Driver *driver = sql::mysql::get_mysql_driver_instance();
        sql::Connection *con = driver->connect("tcp://127.0.0.1:3306", "tu_usuario", "tu_clave");
        con->setSchema("BALBU_TECH");

        sql::PreparedStatement *pstmt = con->prepareStatement("CALL SP_GET_USUARIO_LOGIN(?)");
        pstmt->setString(1, username);

        sql::ResultSet *res = pstmt->executeQuery();

        if (res->next()) {
            string hash_guardado = res->getString("CONTRASENA");
            string rol_db = res->getString("NOMBRE_ROL");

            if (verificar_password_pbkdf2(password_input, hash_guardado)) {
                rolObtenido = rol_db;
            } else {
                cout << "\n[!] Contraseña incorrecta." << endl;
            }
        } else {
            cout << "\n[!] Usuario no encontrado o inactivo." << endl;
        }

        delete res;
        delete pstmt;
        delete con;

    } catch (sql::SQLException &e) {
        cout << "\n[ERROR BD] " << e.what() << endl;
    }

    return rolObtenido;
}
