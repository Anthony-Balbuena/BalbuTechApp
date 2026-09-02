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

        // 1) Intentar autenticación en la tabla USUARIOS (esquema unificado)
        sql::PreparedStatement *pSelect = globalCon->prepareStatement(
            "SELECT U.ID_USUARIO, U.USUARIO, U.CONTRASENA, U.ESTADO, R.NOMBRE_ROL "
            "FROM USUARIOS U LEFT JOIN ROLES R ON U.ID_ROL = R.ID_ROL "
            "WHERE U.USUARIO = ?"
        );
        pSelect->setString(1, usuario);
        sql::ResultSet *rsel = pSelect->executeQuery();

        if (rsel->next()) {
            string storedHash = rsel->getString("CONTRASENA");
            string estadoCuenta = rsel->getString("ESTADO");
            if (storedHash == passwordHash && estadoCuenta == "ACTIVO") {
                int idUsuario = rsel->getInt("ID_USUARIO");
                string rol = rsel->getString("NOMBRE_ROL");
                guardarSesion(idUsuario, usuario, rol, estadoCuenta);
                delete rsel;
                delete pSelect;
                return true;
            }
        }

        delete rsel;
        delete pSelect;

        // 2) Fallback: llamar al SP antiguo (por compatibilidad)
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
