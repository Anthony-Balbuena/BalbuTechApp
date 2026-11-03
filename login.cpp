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

// (03/11/2026) La verificacion de la clave vive en el servidor:
//   SP_LOGIN_PARAMETROS  -> sal e iteraciones (nada secreto)
//   SP_LOGIN_AUTENTICAR  -> compara, aplica el bloqueo y escribe LOG_ACCESOS
// El cliente deriva PBKDF2 y manda solo el derivado; el hash nunca sale de la
// base, asi que un volcado de USUARIOS sin el pepper no sirve para atacar
// offline. El bloqueo tambien es del servidor: llamar al SP desde un cliente
// SQL no lo saltea.
bool intentarLogin(const string& usuario, const string& password, int* minutosBloqueo) {
    if (minutosBloqueo != nullptr) *minutosBloqueo = 0;

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
        // 1) Parametros de derivacion. Si la cuenta no existe, el SP devuelve
        // una sal fija para derivar igual y no delatar por tiempo.
        string sal;
        string formato;
        int iter = 0;
        {
            unique_ptr<sql::PreparedStatement> pPar(globalCon->prepareStatement(
                "CALL SP_LOGIN_PARAMETROS(?)"));
            pPar->setString(1, truncarUtf8(usuario, 50));

            unique_ptr<sql::ResultSet> rp(pPar->executeQuery());
            if (rp->next()) {
                if (!rp->isNull("SAL")) sal = rp->getString("SAL");
                iter = rp->getInt("ITER");
                formato = rp->getString("FORMATO");
            }
            rp.reset();
            drenarResultados(pPar.get());
        }

        // 2) Credencial derivada en el cliente. El formato SHA256 solo existe
        // para una base sembrada con un script viejo; se migra al primer login.
        string credencial;
        if (formato == "SHA256") {
            credencial = aplicarHash(password);
        } else if (!derivarClaveLogin(password, sal, iter, credencial)) {
            cout << ROJO << "[!] No se pudo derivar la clave de acceso." << RESET << endl;
            return false;
        }

        // 3) Verificacion, bloqueo y registro: todo del lado del servidor.
        string resultado;
        string estado;
        string rol;
        string token;
        int idUsuario = 0;
        int idEmpleado = 0;
        int idRol = 0;
        int minutos = 0;
        {
            unique_ptr<sql::PreparedStatement> pAuth(globalCon->prepareStatement(
                "CALL SP_LOGIN_AUTENTICAR(?, ?)"));
            pAuth->setString(1, truncarUtf8(usuario, 50));
            pAuth->setString(2, credencial);

            unique_ptr<sql::ResultSet> ra(pAuth->executeQuery());
            if (ra->next()) {
                resultado = ra->getString("RESULTADO");
                minutos = ra->getInt("MINUTOS");
                if (!ra->isNull("ID_USUARIO")) idUsuario = ra->getInt("ID_USUARIO");
                if (!ra->isNull("ID_EMPLEADO")) idEmpleado = ra->getInt("ID_EMPLEADO");
                if (!ra->isNull("ESTADO_BD")) estado = ra->getString("ESTADO_BD");
                if (!ra->isNull("ID_ROL")) idRol = ra->getInt("ID_ROL");
                if (!ra->isNull("NOMBRE_ROL")) rol = ra->getString("NOMBRE_ROL");
                if (!ra->isNull("TOKEN")) token = ra->getString("TOKEN");
            }
            ra.reset();
            drenarResultados(pAuth.get());
        }

        if (resultado == "BLOQUEADO") {
            if (minutosBloqueo != nullptr) *minutosBloqueo = minutos;
            return false;
        }
        if (resultado != "OK") {
            return false;
        }

        guardarSesion(idUsuario, idEmpleado, usuario, idRol, rol, estado);
        guardarTokenSesion(token);

        // (03/11/2026) El token y el actor de auditoria viajan en la conexion.
        // El token no se puede inventar: solo existen los que emitio el login,
        // y SP_EXIGIR_PERMISO los valida en cada rutina.
        try {
            unique_ptr<sql::PreparedStatement> pSet(globalCon->prepareStatement(
                "SET @ID_USUARIO_ACTUAL = ?, @TOKEN_SESION = ?"));
            pSet->setInt(1, idUsuario);
            pSet->setString(2, token);
            pSet->execute();
            drenarResultados(pSet.get());
        } catch (...) {
            // no fatal: el login sigue aunque no se pueda setear
        }

        return true;

    } catch (const exception &e) {
        cout << ROJO << "[!] Error al intentar iniciar sesión: " << RESET << e.what() << endl;
        return false;
    }
}
