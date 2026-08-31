#include <iostream>
#include <string>
#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>
#include <cppconn/prepared_statement.h>

#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "login.h"
#include "sesion.h"
#include "roles.h"

using namespace std;

int main() {
    inicializarConexion();

    if (globalCon == nullptr) {
        cout << ROJO << "No se pudo conectar a BALBU_TECH." << RESET << endl;
        return 1;
    }

    cout << MAGENTA << "\n=== BALBU_TECH ===" << RESET << endl;
    inicializarSesion();

    const int MAX_INTENTOS = 3;
    for (int intento = 1; intento <= MAX_INTENTOS; ++intento) {
        string usuario;
        string password;

        cout << AZUL << "\nUsuario: " << RESET;
        getline(cin, usuario);

        cout << AZUL << "Contraseña: " << RESET;
        getline(cin, password);

        if (intentarLogin(usuario, password)) {
            cout << VERDE << "\nAcceso concedido." << RESET << endl;
            cout << "Bienvenido/a: " << sesionActual.nombreUsuario << endl;
            cout << "Rol activo: " << sesionActual.nombreRol << endl;
            cout << "\nPresione Enter para continuar...";
            cin.get();

            ejecutarMenuSegunRol();
            return 0;
        }

        cout << ROJO << "Credenciales inválidas. Intento " << intento << " de " << MAX_INTENTOS << "." << RESET << endl;

        if (intento == MAX_INTENTOS) {
            cout << ROJO << "Acceso denegado. Saliendo del sistema..." << RESET << endl;
            return 0;
        }
    }

    return 0;
}
