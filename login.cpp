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

            string rehash;
            bool ok = verificarPassword(password, storedHash, &rehash);
            if (ok && estadoCuenta == "ACTIVO") {
                int idUsuario = rsel->getInt("ID_USUARIO");
                string rol = rsel->getString("NOMBRE_ROL");

                // Si hubo rehash, actualizamos la BD al formato PBKDF2
                if (!rehash.empty()) {
                    try {
                        sql::PreparedStatement *pUpd = globalCon->prepareStatement(
                            "UPDATE USUARIOS SET CONTRASENA = ? WHERE ID_USUARIO = ?"
                        );
                        pUpd->setString(1, rehash);
                        pUpd->setInt(2, idUsuario);
                        pUpd->executeUpdate();
                        delete pUpd;
                    } catch (...) {
                        // no fatales: continuamos con la sesión aun si no se pudo actualizar
                    }
                }

                guardarSesion(idUsuario, usuario, rol, estadoCuenta);
                delete rsel;
                delete pSelect;
                return true;
            }
        }

        delete rsel;
        delete pSelect;

        // No fallback SP: autenticación manejada por PBKDF2/legacy rehash arriba
        delete rsel;
        delete pSelect;
        return false;

    } catch (const exception &e) {
        cout << ROJO << "[!] Error al intentar iniciar sesión: " << RESET << e.what() << endl;
        return false;
    }
}
