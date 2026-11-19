#include <iostream>
#include <string>
#include <memory>
#include <vector>
#include <cstdio>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "bonos.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "tabla.h"
#include "sesion.h"
#include "paginacion.h"

using namespace std;

// Modulo 14-BONOS_EMPLEADOS. Se mantiene separado de empleados.cpp por el mismo
// motivo que vacaciones.cpp: cada modulo tiene sus propios SP y su propia
// pantalla.
//
// (18/11/2026) Por que aparece recien ahora: el modulo existia, los SP tambien,
// pero no habia pantalla. Los bonos los carga solo TR_AUTO_FINALIZAR_VENTA
// (modulo 24) con el 1 % de cada venta cobrada, asi que la tabla crecia sola y
// nadie podia verla ni pagarla. La viva llego a 11 bonos PENDIENTE por $10.330.
//
// Las cuatro acciones de escritura van por SP. SP_ACTUALIZAR_BONO queda sin
// cablear a proposito: corregir el monto de un bono sin dejar rastro es peor que
// anularlo y volver a registrarlo, que si deja historia (y la guarda del modulo
// ya impide tocar un bono que no este PENDIENTE).

static const char* CALL_LISTAR = "CALL SP_LISTAR_BONOS_PAGINADO(?, ?, ?)";
static const char* CALL_CONTAR = "CALL SP_CONTAR_BONOS(?)";

// El driver le pega al mensaje del SIGNAL un sufijo tecnico
// ("... (MySQL error code: 1644, SQLState: 45000 )"). Al operador no le dice
// nada y ocupa media pantalla: se recorta antes de mostrarlo.
static string mensajeLimpio(const string& texto) {
    const string tecnico = " (MySQL error code:";
    const size_t pos = texto.find(tecnico);
    return pos == string::npos ? texto : texto.substr(0, pos);
}

// Los SP de este modulo contestan con tres familias de mensaje: EXITO (se hizo),
// AVISO (no hacia falta, pero no es un error) y ERROR. El color sigue esa
// distincion: un bono que ya estaba pagado no es una falla.
static void mostrarMensaje(const string& mensaje) {
    const string limpio = mensajeLimpio(mensaje);
    if (limpio.rfind("AVISO", 0) == 0) {
        cout << AMARILLO << limpio << RESET << endl;
    } else if (limpio.rfind("ERROR", 0) == 0 || limpio.rfind("Error DB", 0) == 0) {
        cout << ROJO << limpio << RESET << endl;
    } else {
        cout << VERDE << limpio << RESET << endl;
    }
}

// "" es "todos": el SP trata NULL y vacio como sin filtro.
static string nombreFiltro(const string& estado) {
    return estado.empty() ? "TODOS" : estado;
}

// Una pagina de 10 con la cabecera. Devuelve el total de bonos del filtro (0 si
// no hay), igual que las otras pantallas que usan el paginador por SP.
static int listarBonosPaginado(const string& estado) {
    const size_t W_ID = 6, W_NOM = 22, W_FEC = 10, W_TIPO = 14, W_MON = 12, W_EST = 10;
    const size_t ANCHO = W_ID + W_NOM + W_FEC + W_TIPO + W_MON + W_EST + 5 * 3;
    cout << "\n"
         << tablaCelda("ID", W_ID) << " | "
         << tablaCelda("EMPLEADO", W_NOM) << " | "
         << tablaCelda("FECHA", W_FEC) << " | "
         << tablaCelda("TIPO", W_TIPO) << " | "
         << tablaCelda("MONTO", W_MON) << " | "
         << tablaCelda("ESTADO", W_EST) << "\n"
         << tablaLinea(ANCHO) << "\n";

    return mostrarPaginadoSP(
        CALL_LISTAR, CALL_CONTAR, {estado},
        [=](sql::ResultSet* res) {
            char monto[24];
            snprintf(monto, sizeof(monto), "%.2f", (double)res->getDouble("MONTO"));
            string est = res->getString("ESTADO");
            cout << tablaCelda(to_string(res->getInt("ID_BONO")), W_ID) << " | "
                 << tablaCelda(res->getString("NOMBRE_EMPLEADO"), W_NOM) << " | "
                 << tablaCelda(res->getString("FECHA"), W_FEC) << " | "
                 << tablaCelda(res->getString("TIPO_BONO"), W_TIPO) << " | "
                 << tablaCelda(monto, W_MON) << " | "
                 << tablaColorEstado(est) << tablaCelda(est, W_EST) << RESET << "\n"
                 << tablaLinea(ANCHO) << "\n";
        });
}

// Pide un ID y lo devuelve. 0 significa "volver", y es el unico valor que no se
// pasa al SP. El escape de entrada cancela solo esta accion, no la pantalla.
static int pedirId(const char* pregunta) {
    return (int)leerNumeroConIntentos(pregunta, 0, 2147483647);
}

static void pagarBono() {
    cout << "\n--- PAGAR BONO ---" << endl;
    int idBono = pedirId("ID del bono a pagar (0 = volver): ");
    if (idBono == 0) return;

    std::unique_ptr<sql::PreparedStatement> ps(
        globalCon->prepareStatement("CALL SP_PAGAR_BONO(?)"));
    ps->setInt(1, idBono);
    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

static void anularBono() {
    cout << "\n--- ANULAR BONO ---" << endl;
    int idBono = pedirId("ID del bono a anular (0 = volver): ");
    if (idBono == 0) return;

    std::unique_ptr<sql::PreparedStatement> ps(
        globalCon->prepareStatement("CALL SP_ANULAR_BONO(?)"));
    ps->setInt(1, idBono);
    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

// Alta manual. El SP valida que el empleado exista, el tope de 100000 y el tipo;
// TR_VALIDAR_FECHA_BONO corta las fechas de mas de 60 dias. Aca solo se piden
// los datos: repetir esas reglas seria tener dos verdades.
static void registrarBono() {
    cout << "\n--- REGISTRAR BONO ---" << endl;
    cout << "Tipos: 1 DOBLE_SUELDO, 2 HORAS_EXTRA, 3 BONIFICACION" << endl;

    int idEmpleado = pedirId("ID del empleado (0 = volver): ");
    if (idEmpleado == 0) return;

    int tipo = (int)leerNumeroConIntentos("Tipo de bono (1-3): ", 1, 3);
    const char* tipoBono = (tipo == 1) ? "DOBLE_SUELDO"
                         : (tipo == 2) ? "HORAS_EXTRA"
                                       : "BONIFICACION";

    double monto = leerNumeroConIntentos("Monto (mayor a 0, maximo 100000): ", 0.01, 100000);

    string fecha = leerDatoSeguro("Fecha (YYYY-MM-DD, hasta 60 dias atras): ");
    if (fecha.empty()) {
        cout << ROJO << "[!] La fecha es obligatoria." << RESET << endl;
        return;
    }
    string descripcion = leerDatoSeguro("Descripcion (opcional): ");

    std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
        "CALL SP_REGISTRAR_BONO(?, ?, ?, ?, ?)"));
    ps->setInt(1, idEmpleado);
    ps->setString(2, fecha);
    ps->setString(3, tipoBono);
    ps->setDouble(4, monto);
    ps->setString(5, descripcion);

    string mensaje = Recogermensaje(ps.get());
    drenarResultados(ps.get());
    mostrarMensaje(mensaje);
}

// PENDIENTE por defecto: es la unica lista sobre la que se trabaja (pagar o
// anular). Los otros estados estan para consultar el historial.
static void cambiarFiltro(string& estado) {
    cout << "\n--- FILTRO POR ESTADO ---" << endl;
    cout << "1. PENDIENTE (por defecto)" << endl
         << "2. PAGADO" << endl
         << "3. ANULADO" << endl
         << "4. TODOS" << endl
         << "0. Volver" << endl;

    int opcion = 0;
    cout << AZUL << "Seleccione una opcion: " << RESET;
    if (!leerOpcionMenu(opcion)) return;

    switch (opcion) {
        case 1: estado = "PENDIENTE"; break;
        case 2: estado = "PAGADO";    break;
        case 3: estado = "ANULADO";   break;
        case 4: estado = "";          break;
        default: break;  // 0 o cualquier otra cosa: se queda como estaba
    }
}

void gestionarBonosUI() {
    if (!sesionActiva() || globalCon == nullptr) {
        cout << ROJO << "No hay sesión activa." << RESET << endl;
        return;
    }

    string estado = "PENDIENTE";

    for (;;) {
        cout << MAGENTA << "\n=== BONOS DE EMPLEADOS (" << nombreFiltro(estado)
             << ") ===" << RESET << endl;

        int total = 0;
        try {
            total = listarBonosPaginado(estado);
        } catch (const exception& e) {
            cout << ROJO << "No se pudieron listar los bonos: "
                 << mensajeLimpio(e.what()) << RESET << endl;
            return;
        }

        if (total == 0) {
            cout << "[!] No hay bonos " << nombreFiltro(estado) << "." << endl;
        }

        cout << "\n1. Pagar bono" << endl
             << "2. Anular bono" << endl
             << "3. Registrar bono" << endl
             << "4. Cambiar filtro de estado" << endl
             << "0. Volver" << endl;

        int opcion = 0;
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        // El CancelarOperacionException de cualquier accion vuelve al listado:
        // la pantalla sigue viva. Cualquier otra excepcion de SQL se muestra y
        // tambien se vuelve, para no dejar el menu en un estado raro.
        try {
            switch (opcion) {
                case 1: pagarBono();           break;
                case 2: anularBono();          break;
                case 3: registrarBono();       break;
                case 4: cambiarFiltro(estado); break;
                case 0: return;
                default:
                    cout << ROJO << "Opcion no valida." << RESET << endl;
                    continue;
            }
        } catch (const CancelarOperacionException& e) {
            cout << "\n[!] " << e.what() << endl;
            continue;
        } catch (const exception& e) {
            cout << ROJO << "No se pudo completar la operacion: "
                 << mensajeLimpio(e.what()) << RESET << endl;
        }

        // Vuelve a listar (S6): el bono que se pago o anulo cambia de estado y,
        // con el filtro PENDIENTE, desaparece de la lista.
        pausar();
    }
}
