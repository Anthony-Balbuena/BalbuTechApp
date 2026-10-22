#include "login.h"
#include "sesion.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include <iostream>
#include <memory>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

using namespace std;

// (21/10/2026) Corta a maxBytes sin partir un caracter UTF-8: si el byte
// siguiente es de continuacion (10xxxxxx), retrocede hasta el inicio del caracter.
static string truncarUtf8(const string& texto, size_t maxBytes) {
    if (texto.size() <= maxBytes) return texto;
    size_t corte = maxBytes;
    while (corte > 0 && (static_cast<unsigned char>(texto[corte]) & 0xC0) == 0x80) {
        --corte;
    }
    return texto.substr(0, corte);
}

// (21/10/2026) Deja el intento en LOG_ACCESOS. Nunca debe tumbar el login:
// si el log falla, se ignora y el acceso sigue su curso.
static void registrarAcceso(int idUsuario, const string& usuario, const char* estado) {
    if (globalCon == nullptr) return;
    try {
        unique_ptr<sql::PreparedStatement> p(globalCon->prepareStatement(
            "CALL SP_REGISTRAR_ACCESO(?, ?, ?)"));
        if (idUsuario > 0) p->setInt(1, idUsuario);
        else p->setNull(1, sql::DataType::INTEGER);
        p->setString(2, usuario.empty() ? "(vacio)" : truncarUtf8(usuario, 50));
        p->setString(3, estado);
        p->execute();
        drenarResultados(p.get());
    } catch (...) {
    }
}

bool intentarLogin(const string& usuario, const string& password) {
    if (globalCon == nullptr) {
        cout << "[!] No hay conexión activa a la base de datos." << endl;
        return false;
    }

    // (21/10/2026) Un Enter en blanco no es un intento de acceso: no consulta
    // ni escribe en LOG_ACCESOS. Antes dejaba una fila '(vacio) / FALLIDO'.
    if (usuario.empty()) {
        return false;
    }

    try {
        // 1) Intentar autenticación en la tabla USUARIOS (esquema unificado)
        std::unique_ptr<sql::PreparedStatement> pSelect(globalCon->prepareStatement(
            "SELECT U.ID_USUARIO, U.USUARIO, U.CONTRASENA, U.ESTADO, R.ID_ROL, R.NOMBRE_ROL "
            "FROM USUARIOS U LEFT JOIN ROLES R ON U.ID_ROL = R.ID_ROL "
            "WHERE U.USUARIO = ?"
        ));
        pSelect->setString(1, usuario);
        std::unique_ptr<sql::ResultSet> rsel(pSelect->executeQuery());

        if (rsel->next()) {
            string storedHash = rsel->getString("CONTRASENA");
            string estadoCuenta = rsel->getString("ESTADO");
            int idUsuario = rsel->getInt("ID_USUARIO");
            string rol;
            try { rol = rsel->getString("NOMBRE_ROL"); } catch (...) { rol = ""; }
            int idRol = 0;
            try { idRol = rsel->isNull("ID_ROL") ? 0 : rsel->getInt("ID_ROL"); } catch (...) { idRol = 0; }

            // Cerrar el SELECT antes de cualquier otra query: si el UPDATE
            // de rehash corre con esto abierto, la conexion queda
            // desincronizada ("Commands out of sync") y todo lo posterior falla.
            rsel.reset();
            drenarResultados(pSelect.get());

            string rehash;
            bool ok = verificarPassword(password, storedHash, &rehash);
            if (ok && estadoCuenta == "ACTIVO") {
                // Si hubo rehash, actualizamos la BD al formato PBKDF2
                if (!rehash.empty()) {
                    try {
                        std::unique_ptr<sql::PreparedStatement> pUpd(globalCon->prepareStatement(
                            "UPDATE USUARIOS SET CONTRASENA = ? WHERE ID_USUARIO = ?"
                        ));
                        pUpd->setString(1, rehash);
                        pUpd->setInt(2, idUsuario);
                        pUpd->executeUpdate();
                    } catch (...) {
                        // no fatales: continuamos con la sesión aun si no se pudo actualizar
                    }
                }

                registrarAcceso(idUsuario, usuario, "EXITOSO");
                guardarSesion(idUsuario, usuario, idRol, rol, estadoCuenta);
                return true;
            }

            registrarAcceso(idUsuario, usuario, ok ? "INACTIVO" : "FALLIDO");
            return false;
        }

        // No encontrado: el SELECT ya no hace falta y el intento queda en el log.
        rsel.reset();
        drenarResultados(pSelect.get());
        registrarAcceso(0, usuario, "FALLIDO");
        return false;

    } catch (const exception &e) {
        cout << ROJO << "[!] Error al intentar iniciar sesión: " << RESET << e.what() << endl;
        return false;
    }
}

