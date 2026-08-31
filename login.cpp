#include "login.h"
#include "sesion.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include <iostream>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

using namespace std;

bool intentarLogin(const string& usuario, const string& password) {
    if (globalCon == nullptr) {
        cout << "[!] No hay conexión activa a la base de datos." << endl;
        return false;
    }

    try {
        string passwordHash = aplicarHash(password);

        sql::PreparedStatement *pstmt = globalCon->prepareStatement(
            "CALL SP_LOGIN_USUARIO(?, ?)"
        );
        pstmt->setString(1, usuario);
        pstmt->setString(2, passwordHash);

        sql::ResultSet *res = pstmt->executeQuery();

        if (res->next()) {
            string estado = res->getString("ESTADO");
            if (estado == "EXITO") {
                int idUsuario = res->getInt("ID_USUARIO");
                string rol = res->getString("ROL");
                string estadoCuenta = "ACTIVO";

                guardarSesion(idUsuario, usuario, rol, estadoCuenta);

                delete res;
                delete pstmt;
                return true;
            }
        }

        delete res;
        delete pstmt;
        return false;

    } catch (const exception &e) {
        cout << ROJO << "[!] Error al intentar iniciar sesión: " << RESET << e.what() << endl;
        return false;
    }
}
