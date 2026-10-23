#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <limits>
#include <vector>
#include <utility>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"
#include "roles.h"
#include "contrato.h"
#include "permisos.h"
#include "vacaciones.h"
#include "colores.h"

using namespace std;

// ---------------------------------------------------------------------------
// Submenu dinamico: cada accion pide su permiso fino. Igual que el menu
// principal (roles.cpp) y el submenu de Usuarios, la lista visible se arma
// antes de imprimir/numerar.
// ---------------------------------------------------------------------------
namespace {

enum class AccionEmpleado {
    Agregar, Actualizar, Despedir, Reactivar, Buscar, Listar,
    MarcarAsistencia, VerAsistencia, Justificar, AsistenciaHoy, Historial,
    GenerarContrato, SubirContrato, VerContratos, FinalizarContrato,
    Permisos, Vacaciones, Volver
};

struct OpcionEmpleado {
    const char* etiqueta;
    const char* permiso;   // vacio = siempre visible
    AccionEmpleado accion;
};

static const vector<OpcionEmpleado>& opcionesEmpleados() {
    static const vector<OpcionEmpleado> opciones = {
        {"Agregar Empleado",             "EMPLEADOS_CREAR",                 AccionEmpleado::Agregar},
        {"Actualizar Datos",             "EMPLEADOS_EDITAR",                AccionEmpleado::Actualizar},
        {"Despedir Empleado",            "EMPLEADOS_BAJA",                  AccionEmpleado::Despedir},
        {"Reactivar Empleado",           "EMPLEADOS_BAJA",                  AccionEmpleado::Reactivar},
        {"Buscar Empleado",              "EMPLEADOS_VER",                   AccionEmpleado::Buscar},
        {"Listar Empleados",             "EMPLEADOS_VER",                   AccionEmpleado::Listar},
        {"Marcar asistencia",            "REGISTRAR_ASISTENCIA",            AccionEmpleado::MarcarAsistencia},
        {"Ver asistencia",               "CONSULTAR_REPORTES",              AccionEmpleado::VerAsistencia},
        {"Justificar asistencia",        "JUSTIFICAR_ASISTENCIA",           AccionEmpleado::Justificar},
        {"Asistencia del dia",           "CONSULTAR_REPORTES",              AccionEmpleado::AsistenciaHoy},
        {"Historial de asistencia",      "CONSULTAR_REPORTES",              AccionEmpleado::Historial},
        {"Generar contrato",             "GESTIONAR_CONTRATOS",             AccionEmpleado::GenerarContrato},
        {"Subir contrato (al firmar)",   "GESTIONAR_CONTRATOS",             AccionEmpleado::SubirContrato},
        {"Ver contratos",                "GESTIONAR_CONTRATOS",             AccionEmpleado::VerContratos},
        {"Finalizar contrato",           "GESTIONAR_CONTRATOS",             AccionEmpleado::FinalizarContrato},
        {"Gestionar permisos",           "GESTIONAR_PERMISOS_EMPLEADO",     AccionEmpleado::Permisos},
        {"Gestionar vacaciones",         "GESTIONAR_VACACIONES_EMPLEADO",   AccionEmpleado::Vacaciones},
        {"Volver al Menu Principal",     "",                                AccionEmpleado::Volver}
    };
    return opciones;
}

static bool puedeVerOpcion(const OpcionEmpleado& opcion) {
    if (opcion.permiso == nullptr || opcion.permiso[0] == '\0') return true;
    return tienePermiso(opcion.permiso);
}

static vector<const OpcionEmpleado*> opcionesVisibles() {
    vector<const OpcionEmpleado*> visibles;
    for (const OpcionEmpleado& opcion : opcionesEmpleados()) {
        if (puedeVerOpcion(opcion)) visibles.push_back(&opcion);
    }
    return visibles;
}

// Numera sobre lo visible: si un rol no tiene una accion, no queda hueco.
static void imprimirMenuEmpleados(const vector<const OpcionEmpleado*>& visibles) {
    cout << "\n=== MODULO DE EMPLEADOS ===" << endl;
    int n = 0;
    for (const OpcionEmpleado* opcion : visibles) {
        cout << ++n << ". " << opcion->etiqueta << endl;
    }
    cout << "=============================" << endl;
}

}  // namespace

void registrarEmpleado() {
    cout << "\n--- REGISTRO DE EMPLEADO ---" << endl;
    try {
        string nombre, cedula, cargo, telefono, email, fechaIngreso;
        double salario = 0.0;
        bool precargado = false;

        // (19/10/2026) Contratos firmados sin empleado: el alta se precarga con
        // lo que dice el papel. El vinculo del contrato lo hace TR_VINCULAR_CONTRATO.
        struct Pendiente { int id; string nombre, cedula, cargo, telefono, email, fecha; double salario; };
        vector<Pendiente> pend;
        {
            std::unique_ptr<sql::PreparedStatement> pp(globalCon->prepareStatement(
                "SELECT ID_CONTRATO, NOMBRE, CEDULA, CARGO, TELEFONO, EMAIL, "
                "FECHA_INGRESO, SALARIO FROM CONTRATOS "
                "WHERE ID_EMPLEADO IS NULL AND ESTADO = 'ACTIVO' "
                "ORDER BY ID_CONTRATO"));
            std::unique_ptr<sql::ResultSet> rp(pp->executeQuery());
            while (rp->next()) {
                Pendiente p;
                p.id = rp->getInt("ID_CONTRATO");
                p.nombre = rp->getString("NOMBRE");
                p.cedula = rp->getString("CEDULA");
                p.cargo = rp->getString("CARGO");
                p.telefono = rp->isNull("TELEFONO") ? "" : rp->getString("TELEFONO");
                p.email = rp->isNull("EMAIL") ? "" : rp->getString("EMAIL");
                p.fecha = rp->isNull("FECHA_INGRESO") ? "" : rp->getString("FECHA_INGRESO");
                p.salario = rp->getDouble("SALARIO");
                pend.push_back(p);
            }
            drenarResultados(pp.get());
        }

        if (!pend.empty()) {
            cout << "\nContratos firmados sin empleado:" << endl;
            for (size_t i = 0; i < pend.size(); i++) {
                printf("  %zu. %s - %s - %s - %.2f - ingreso %s\n",
                       i + 1, pend[i].nombre.c_str(), pend[i].cedula.c_str(),
                       pend[i].cargo.c_str(), pend[i].salario,
                       pend[i].fecha.c_str());
            }
            cout << "  0. Dar de alta a alguien sin contrato" << endl;
            int op = (int)leerNumeroConIntentos("Elegir: ", 0, (double)pend.size());
            if (op > 0) {
                const Pendiente &p = pend[op - 1];
                nombre = p.nombre;
                cedula = p.cedula;
                cargo = p.cargo;
                telefono = p.telefono;
                email = p.email;
                fechaIngreso = p.fecha;
                salario = p.salario;
                precargado = true;
                cout << "\nDatos cargados del contrato #" << p.id << "." << endl;
            }
        }

        // Enter deja el valor del contrato. Un "-" del borrador no sirve como
        // dato real: se vuelve a pedir.
        auto pedirConDefault = [](const string &etiqueta, const string &actual) {
            if (actual.empty() || actual == "-") return leerDatoSeguro(etiqueta);
            string v = leerDatoSeguro(etiqueta + " [" + actual + "]: ");
            return v.empty() ? actual : v;
        };

        if (!precargado) {
            nombre = leerDatoSeguro("Nombre Completo: ");
            cedula = leerDatoSeguro("Cedula: ");
            cargo = leerDatoSeguro("Cargo: ");
            string salStr = leerDatoSeguro("Salario: ");
            salario = stod(salStr);
        }

        telefono = pedirConDefault("Telefono: ", telefono);
        email = pedirConDefault("Email: ", email);
        if (fechaIngreso.empty()) {
            fechaIngreso = leerDatoSeguro("Fecha de ingreso (AAAA-MM-DD, Enter = hoy): ");
        } else {
            fechaIngreso = pedirConDefault("Fecha de ingreso (AAAA-MM-DD): ", fechaIngreso);
        }

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL SP_INSERTAR_EMPLEADO(?, ?, ?, ?, ?, ?, ?)"));
        pstmt->setString(1, nombre);
        pstmt->setString(2, cedula);
        pstmt->setString(3, cargo);
        pstmt->setDouble(4, salario);
        pstmt->setString(5, telefono);
        pstmt->setString(6, email);
        if (fechaIngreso.empty()) pstmt->setNull(7, sql::DataType::DATE);
        else pstmt->setString(7, fechaIngreso);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El salario debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al registrar empleado: " << e.what() << endl;
    }
}

void actualizarEmpleado() {
    cout << "\n--- ACTUALIZAR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);

        string nombre = leerDatoSeguro("Nuevo nombre (Enter para omitir): ");
        string cedula = leerDatoSeguro("Nueva cédula (Enter para omitir): ");
        string email = leerDatoSeguro("Nuevo email (Enter para omitir): ");
        string cargo = leerDatoSeguro("Nuevo cargo (Enter para omitir): ");
        string telefono = leerDatoSeguro("Nuevo telefono (Enter para omitir): ");
        string salStr = leerDatoSeguro("Nuevo salario (0 para omitir): ");
        double salario = salStr.empty() ? 0 : stod(salStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_ACTUALIZAR_EMPLEADO(?, ?, ?, ?, ?, ?, ?)"));
        pstmt->setInt(1, idEmpleado);

        if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR); else pstmt->setString(2, nombre);
        if (cedula.empty()) pstmt->setNull(3, sql::DataType::VARCHAR); else pstmt->setString(3, cedula);
        if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR); else pstmt->setString(4, email);
        if (cargo.empty()) pstmt->setNull(5, sql::DataType::VARCHAR); else pstmt->setString(5, cargo);
        if (telefono.empty()) pstmt->setNull(6, sql::DataType::VARCHAR); else pstmt->setString(6, telefono);
        if (salario <= 0) pstmt->setNull(7, sql::DataType::DOUBLE); else pstmt->setDouble(7, salario);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID o el salario deben ser numéricos." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al actualizar empleado: " << e.what() << endl;
    }
}

void despedirEmpleado() {
    cout << "\n--- DESPEDIR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);

        string fecha = leerDatoSeguro("Fecha (YYYY-MM-DD) o Enter para hoy: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_DESPEDIR_EMPLEADO(?, ?)"));
        pstmt->setInt(1, idEmpleado);

        if (fecha.empty()) {
            pstmt->setNull(2, sql::DataType::DATE);
        } else {
            pstmt->setString(2, fecha);
        }

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID debe ser numérico." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al despedir empleado: " << e.what() << endl;
    }
}

void reactivarEmpleado() {
    cout << "\n--- REACTIVAR EMPLEADO ---" << endl;
    try {
        string idStr = leerDatoSeguro("ID del empleado: ");
        int idEmpleado = stoi(idStr);
        string salStr = leerDatoSeguro("Nuevo salario: ");
        double nuevoSalario = stod(salStr);

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_REACTIVAR_EMPLEADO(?, ?)"));
        pstmt->setInt(1, idEmpleado);
        pstmt->setDouble(2, nuevoSalario);

        string respuesta = Recogermensaje(pstmt.get());
        cout << "\n--------------------------------------------" << endl;
        cout << ">>> " << respuesta << " <<<" << endl;
        cout << "--------------------------------------------" << endl;

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const invalid_argument&) {
        cout << "\n[!] El ID y el salario deben ser numéricos." << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al reactivar empleado: " << e.what() << endl;
    }
}

void buscarEmpleado() {
    cout << "\n--- BUSCAR EMPLEADO ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese nombre, cédula o cargo o Enter para ver todos: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_EMPLEADO, NOMBRE, CEDULA, CARGO, ESTADO FROM EMPLEADOS WHERE (? = '' OR NOMBRE LIKE ? OR CEDULA LIKE ? OR CARGO LIKE ?) ORDER BY ID_EMPLEADO"));
        pstmt->setString(1, filtro);
        pstmt->setString(2, "%" + filtro + "%");
        pstmt->setString(3, "%" + filtro + "%");
        pstmt->setString(4, "%" + filtro + "%");

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        bool encontrado = false;

        printf("\n%-4s | %-22s | %-12s | %-28s | %-8s\n", "ID", "NOMBRE", "CEDULA", "CARGO", "ESTADO");
        printf("%s\n", string(86, '-').c_str());
        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-28.28s | %-8s\n",
                   res->getInt("ID_EMPLEADO"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("CEDULA").c_str(),
                   res->getString("CARGO").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(86, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No se encontraron empleados con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << "\n[!] Error al buscar empleado: " << e.what() << endl;
    }
}

void listarEmpleados() {
    cout << "\n--- LISTADO DE EMPLEADOS ---" << endl;
    try {
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("SELECT ID_EMPLEADO, NOMBRE, CEDULA, CARGO, ESTADO FROM EMPLEADOS ORDER BY ID_EMPLEADO"));
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());

        printf("\n%-4s | %-22s | %-12s | %-28s | %-8s\n", "ID", "NOMBRE", "CEDULA", "CARGO", "ESTADO");
        printf("%s\n", string(86, '-').c_str());
        bool encontrado = false;
        while (res->next()) {
            encontrado = true;
            printf("%-4d | %-22.22s | %-12.12s | %-28.28s | %-8s\n",
                   res->getInt("ID_EMPLEADO"),
                   res->getString("NOMBRE").c_str(),
                   res->getString("CEDULA").c_str(),
                   res->getString("CARGO").c_str(),
                   res->getString("ESTADO").c_str());
            printf("%s\n", string(86, '-').c_str());
        }

        if (!encontrado) {
            cout << "\n[!] No hay empleados registrados." << endl;
        }

        drenarResultados(pstmt.get());
    } catch (const exception &e) {
        cout << "\n[!] Error al listar empleados: " << e.what() << endl;
    }
}

static int identificarEmpleado() {
    // EL CORTE: hoy pide el ID; manana la huella entra aqui sin tocar lo demas.
    return (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
}

static void marcarAsistenciaAuto() {
    cout << "\n--- MARCAR ASISTENCIA ---" << endl;
    try {
        int idEmp = identificarEmpleado();
        std::unique_ptr<sql::PreparedStatement> ph(globalCon->prepareStatement("SELECT CURTIME() AS HORA"));
        std::unique_ptr<sql::ResultSet> rh(ph->executeQuery());
        string hora = "12:00:00";
        if (rh->next()) hora = rh->getString("HORA");
        drenarResultados(ph.get());
        string tipo = (hora < "12:00:00") ? "ENTRADA" : "SALIDA";
        cout << "Hora BD: " << hora << " -> " << tipo << endl;
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_REGISTRAR_ASISTENCIA(?, ?)"));
        pstmt->setInt(1, idEmp);
        pstmt->setString(2, tipo);
        string msg = Recogermensaje(pstmt.get());
        drenarResultados(pstmt.get());
        bool espejo = (msg.find("YA TIENE REGISTRO DE ENTRADA") != string::npos ||
                        msg.find("NO TIENE REGISTRO DE ENTRADA") != string::npos);
        if (msg.rfind("Error DB:", 0) == 0 || msg.rfind("ERROR:", 0) == 0) {
            cout << ROJO << msg << RESET << endl;
            if (!espejo) return;
            string otro = (tipo == "ENTRADA") ? "SALIDA" : "ENTRADA";
            string r = leerDatoSeguro(("Marcar " + otro + " en su lugar? (s/n): ").c_str());
            if (r != "s" && r != "S") return;
            std::unique_ptr<sql::PreparedStatement> p2(globalCon->prepareStatement("CALL SP_REGISTRAR_ASISTENCIA(?, ?)"));
            p2->setInt(1, idEmp);
            p2->setString(2, otro);
            cout << ">>> " << Recogermensaje(p2.get()) << " <<<" << endl;
            drenarResultados(p2.get());
            return;
        }
        cout << VERDE << msg << RESET << endl;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo marcar asistencia." << RESET << endl;
    }
}

static bool fechaValidaEmpleados(const string &s) {
    // AAAA-MM-DD simple, igual que en ventas (sin bisiestos finos: la BD valida).
    if (s.size() != 10 || s[4] != '-' || s[7] != '-') return false;
    for (size_t i = 0; i < s.size(); i++) {
        if (i == 4 || i == 7) continue;
        if (!isdigit(static_cast<unsigned char>(s[i]))) return false;
    }
    return true;
}

static void verAsistenciaUI() {    cout << "\n--- VER ASISTENCIA ---" << endl;
    try {
        int idEmp = (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        string ini = leerDatoSeguro("Desde (AAAA-MM-DD): ");
        string fin = leerDatoSeguro("Hasta (AAAA-MM-DD): ");
        if (!fechaValidaEmpleados(ini) || !fechaValidaEmpleados(fin) || ini > fin) {
            cout << ROJO << "Rango invalido. Use AAAA-MM-DD." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL 11_SP_REPORTE_ASISTENCIA_INDIVIDUAL(?, ?, ?)"));
        pstmt->setInt(1, idEmp);
        pstmt->setString(2, ini);
        pstmt->setString(3, fin);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-12s | %-8s | %-8s | %-6s | %-10s\n", "FECHA", "ENTRADA", "SALIDA", "HORAS", "ESTADO");
        bool hay = false;
        while (res->next()) {
            hay = true;
            string ent("--:--:--"), sal("--:--:--"), est("?");
            try { ent = res->getString("HORA_ENTRADA").c_str(); } catch (...) {}
            try { sal = res->getString("HORA_SALIDA").c_str(); } catch (...) {}
            double hs = 0.0;
            try { hs = res->getDouble("HORAS_TRABAJADAS"); } catch (...) {}
            try { est = res->getString("ESTADO").c_str(); } catch (...) {}
            printf("%-12.12s | %-8.8s | %-8.8s | %-6.2f | %-10.10s\n",
                   res->getString("FECHA").c_str(), ent.c_str(), sal.c_str(), hs, est.c_str());
        }
        if (!hay) cout << "[!] Sin registros." << endl;
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver la asistencia." << RESET << endl;
    }
}

// (17/10/2026) Asistencia v2 - justificar: cambia el estado de UN dia ya
// marcado (AUSENTE/TARDE/PERMISO) con motivo. Bloquea fechas > 7 dias via
// 11_SP_BLOQUEAR_EDICION_ANTIGUA. Solo admin.
static void justificarAsistenciaUI() {
    cout << "\n--- JUSTIFICAR ASISTENCIA ---" << endl;
    try {
        int idEmp = (int)leerNumeroConIntentos("ID empleado: ", 1, 999999999);
        string fecha = leerDatoSeguro("Fecha (AAAA-MM-DD): ");
        if (!fechaValidaEmpleados(fecha)) {
            cout << ROJO << "Fecha invalida. Use AAAA-MM-DD." << RESET << endl;
            return;
        }
        cout << "Nuevo estado: 1. AUSENTE  2. TARDE  3. PERMISO" << endl;
        int opEst = (int)leerNumeroConIntentos("Opcion: ", 1, 3);
        string estado = (opEst == 1) ? "AUSENTE" : (opEst == 2) ? "TARDE" : "PERMISO";
        string motivo = leerDatoSeguro("Motivo: ");
        if (motivo.empty()) {
            cout << ROJO << "El motivo es obligatorio." << RESET << endl;
            return;
        }
        // Freno 1: la BD bloquea ediciones de mas de 7 dias.
        std::unique_ptr<sql::PreparedStatement> pb(globalCon->prepareStatement(
            "CALL 11_SP_BLOQUEAR_EDICION_ANTIGUA(?, ?)"));
        pb->setInt(1, idEmp);
        pb->setString(2, fecha);
        std::unique_ptr<sql::ResultSet> rb(pb->executeQuery());
        bool permitido = false;
        while (rb->next()) {
            string est;
            try { est = rb->getString("ESTADO"); } catch (...) {}
            if (est == "ACCESO PERMITIDO") permitido = true;
        }
        drenarResultados(pb.get());
        if (!permitido) {
            cout << ROJO << "Fecha bloqueada: no se puede justificar mas de 7 dias atras." << RESET << endl;
            return;
        }
        // Freno 2: el SP falla si ese dia no tiene registro.
        std::unique_ptr<sql::PreparedStatement> p(globalCon->prepareStatement(
            "CALL 11_SP_JUSTIFICAR_ASISTENCIA(?, ?, ?, ?)"));
        p->setInt(1, idEmp);
        p->setString(2, fecha);
        p->setString(3, estado);
        p->setString(4, motivo);
        string msg = Recogermensaje(p.get());
        drenarResultados(p.get());
        if (msg.rfind("Error DB:", 0) == 0 || msg.rfind("ERROR:", 0) == 0)
            cout << ROJO << msg << RESET << endl;
        else
            cout << VERDE << msg << RESET << endl;
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo justificar la asistencia: " << e.what() << RESET << endl;
    }
}

// (17/10/2026) Asistencia v2 - reporte del dia: todos los activos con su
// estado (AUSENTE si no marco). Cuenta presentes/tardes/ausentes/permisos.
static void asistenciaHoyUI() {
    cout << "\n--- ASISTENCIA DEL DIA ---" << endl;
    try {
        string fecha = leerDatoSeguro("Fecha (AAAA-MM-DD, Enter = hoy): ");
        if (!fecha.empty() && !fechaValidaEmpleados(fecha)) {
            cout << ROJO << "Fecha invalida. Use AAAA-MM-DD." << RESET << endl;
            return;
        }
        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
            "CALL 11_SP_ASISTENCIA_HOY(?)"));
        if (fecha.empty()) pstmt->setNull(1, sql::DataType::DATE);
        else pstmt->setString(1, fecha);
        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        printf("\n%-5s | %-22s | %-12s | %-10s | %-10s | %-6s\n",
               "ID", "NOMBRE", "CARGO", "ESTADO", "ENTRADA", "HORAS");
        int nPres = 0, nTarde = 0, nAus = 0, nPerm = 0;
        bool hay = false;
        while (res->next()) {
            hay = true;
            string est; try { est = res->getString("ESTADO"); } catch (...) {}
            string ent("--:--:--"); try { ent = res->getString("HORA_ENTRADA"); } catch (...) {}
            double hs = 0.0; try { hs = res->getDouble("HORAS"); } catch (...) {}
            if (est == "PRESENTE") nPres++;
            else if (est == "TARDE") nTarde++;
            else if (est == "PERMISO") nPerm++;
            else nAus++;
            printf("%-5d | %-22.22s | %-12.12s | ", res->getInt("ID_EMPLEADO"),
                   res->getString("NOMBRE").c_str(), res->getString("CARGO").c_str());
            const string &c = (est == "PRESENTE") ? VERDE
                            : (est == "TARDE") ? AMARILLO
                            : (est == "PERMISO") ? CIAN : ROJO;
            string estCelda = est;
            estCelda.resize(10, ' ');  // ancho fijo 10: mantiene alineadas las columnas siguientes
            cout << c << estCelda << RESET;
            printf(" | %-10.10s | %-6.2f\n", ent.c_str(), hs);
        }
        if (!hay) cout << "[!] Sin empleados activos." << endl;
        else {
            cout << "\nResumen: " << VERDE << nPres << " presentes" << RESET
                 << " | " << AMARILLO << nTarde << " tardes" << RESET
                 << " | " << CIAN << nPerm << " permisos" << RESET
                 << " | " << ROJO << nAus << " ausentes" << RESET << endl;
        }
        drenarResultados(pstmt.get());
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver la asistencia del dia." << RESET << endl;
    }
}

// (17/10/2026) Asistencia v2 - historial de asistencia de UN empleado.
static void historialAsistenciaUI() {
    cout << "\n--- HISTORIAL DE ASISTENCIA ---" << endl;
    try {
        string filtro = leerDatoSeguro("Ingrese ID, nombre o cedula o Enter para ver todos: ");
        vector<pair<int,string>> empleados;
        std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
            "SELECT ID_EMPLEADO, NOMBRE, CEDULA FROM EMPLEADOS "
            "WHERE (? = '' OR NOMBRE LIKE CONCAT('%', ?, '%') "
            "       OR CEDULA LIKE CONCAT('%', ?, '%') "
            "       OR ID_EMPLEADO = CAST(? AS UNSIGNED)) "
            "ORDER BY ID_EMPLEADO"));
        pe->setString(1, filtro); pe->setString(2, filtro);
        pe->setString(3, filtro); pe->setString(4, filtro);
        std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
        while (re->next()) {
            empleados.push_back({re->getInt("ID_EMPLEADO"), (string)re->getString("NOMBRE")});
        }
        drenarResultados(pe.get());
        if (empleados.empty()) {
            cout << "[!] Ningun empleado coincide con: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
            return;
        }
        for (auto &e : empleados) {
            string mes = leerDatoSeguro("Mes para " + to_string(e.first) + " - " + e.second + " (AAAA-MM): ");
            if (mes.size() != 7 || mes[4] != '-') {
                cout << ROJO << "Mes invalido. Use AAAA-MM." << RESET << endl;
                continue;
            }
            std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(
                "CALL 11_SP_RESUMEN_ASISTENCIA_MES(?, ?)"));
            pstmt->setInt(1, e.first);
            pstmt->setString(2, mes);
            std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
            printf("\n%-22.22s | %-5s\n", e.second.c_str(), mes.c_str());
            printf("%s\n", string(36, '-').c_str());
            if (res->next()) {
                printf("%-16s: %d\n", "Dias marcados", res->getInt("DIAS_MARCADOS"));
                printf("%-16s: %.2f\n", "Horas totales", (double)res->getDouble("HORAS_TOTALES"));
                printf("%-16s: %d\n", "Presencias", res->getInt("PRESENCIAS"));
                printf("%-16s: %d\n", "Tardanzas", res->getInt("TARDANZAS"));
                printf("%-16s: %d\n", "Ausencias", res->getInt("AUSENCIAS"));
                printf("%-16s: %d\n", "Permisos", res->getInt("PERMISOS"));
            } else {
                cout << "[!] Ese empleado no marco asistencia en " << mes << "." << endl;
            }
            drenarResultados(pstmt.get());
        }
    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &) {
        cout << ROJO << "No se pudo ver el historial." << RESET << endl;
    }
}

// Submenu de empleados: arma la lista visible con los permisos de la sesion,
// numera sobre lo visible y despacha por accion.
void ejecutarSubmenuEmpleados() {
    for (;;) {
        vector<const OpcionEmpleado*> visibles = opcionesVisibles();
        imprimirMenuEmpleados(visibles);

        int opcion = 0;
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            return;
        }
        if (opcion < 1 || opcion > (int)visibles.size()) {
            cout << ROJO << "Opcion no valida." << RESET << endl;
            continue;
        }

        const OpcionEmpleado& elegido = *visibles[opcion - 1];
        switch (elegido.accion) {
            case AccionEmpleado::Agregar:           registrarEmpleado(); break;
            case AccionEmpleado::Actualizar:        actualizarEmpleado(); break;
            case AccionEmpleado::Despedir:          despedirEmpleado(); break;
            case AccionEmpleado::Reactivar:         reactivarEmpleado(); break;
            case AccionEmpleado::Buscar:            buscarEmpleado(); break;
            case AccionEmpleado::Listar:            listarEmpleados(); break;
            case AccionEmpleado::MarcarAsistencia:  marcarAsistenciaAuto(); break;
            case AccionEmpleado::VerAsistencia:     verAsistenciaUI(); break;
            case AccionEmpleado::Justificar:        justificarAsistenciaUI(); break;
            case AccionEmpleado::AsistenciaHoy:     asistenciaHoyUI(); break;
            case AccionEmpleado::Historial:         historialAsistenciaUI(); break;
            case AccionEmpleado::GenerarContrato:   generarContratoUI(); break;
            case AccionEmpleado::SubirContrato:     subirContratoUI(); break;
            case AccionEmpleado::VerContratos:      consultarContratosUI(); break;
            case AccionEmpleado::FinalizarContrato: finalizarContratoUI(); break;
            case AccionEmpleado::Permisos:          gestionarPermisosUI(); break;
            case AccionEmpleado::Vacaciones:        gestionarVacacionesUI(); break;
            case AccionEmpleado::Volver:            return;
        }
        pausar();
    }
}

