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
#include "colores.h"

using namespace std;

void mostrarMenuEmpleados() {
    cout << "\n=== MODULO DE EMPLEADOS ===" << endl;
    cout << "1. Agregar Empleado" << endl;
    cout << "2. Actualizar Datos" << endl;
    cout << "3. Despedir Empleado" << endl;
    cout << "4. Reactivar Empleado" << endl;
    cout << "5. Buscar Empleado" << endl;
    cout << "6. Listar Empleados" << endl;
    cout << "7. Marcar asistencia" << endl;
    cout << "8. Ver asistencia" << endl;
    cout << "9. Justificar asistencia" << endl;
    cout << "10. Asistencia del dia" << endl;
    cout << "11. Historial de asistencia" << endl;
    cout << "12. Generar contrato" << endl;
    cout << "13. Subir contrato (al firmar)" << endl;
    cout << "14. Ver contratos" << endl;
    cout << "15. Finalizar contrato" << endl;
    cout << "16. Volver al Menu Principal" << endl;
    cout << "=============================" << endl;
}

void registrarEmpleado() {
    cout << "\n--- REGISTRO DE EMPLEADO ---" << endl;
    try {
        string nombre = leerDatoSeguro("Nombre Completo: ");
        string cedula = leerDatoSeguro("Cedula: ");
        string cargo = leerDatoSeguro("Cargo: ");
        string salStr = leerDatoSeguro("Salario: ");
        double salario = stod(salStr);
        string telefono = leerDatoSeguro("Telefono: ");
        string email = leerDatoSeguro("Email: ");

        std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement("CALL SP_INSERTAR_EMPLEADO(?, ?, ?, ?, ?, ?)"));
        pstmt->setString(1, nombre);
        pstmt->setString(2, cedula);
        pstmt->setString(3, cargo);
        pstmt->setDouble(4, salario);
        pstmt->setString(5, telefono);
        pstmt->setString(6, email);

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

// Submenú de empleados: muestra el menú, lee la opción y llama a la acción.
// (Antes el menú solo se imprimía y volvía sin hacer nada.)
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

void ejecutarSubmenuEmpleados() {    int opcion = 0;

    do {
        mostrarMenuEmpleados();
        cout << AZUL << "Seleccione una opcion: " << RESET;
        if (!leerOpcionMenu(opcion)) {
            cout << "\n[!] Entrada agotada. Saliendo del menu." << endl;
            break;
        }

        switch (opcion) {
            case 1:
                registrarEmpleado();
                break;
            case 2:
                actualizarEmpleado();
                break;
            case 3:
                despedirEmpleado();
                break;
            case 4:
                reactivarEmpleado();
                break;
            case 5:
                buscarEmpleado();
                break;
            case 6:
                listarEmpleados();
                break;
            case 7:
                marcarAsistenciaAuto();
                break;
            case 8:
                verAsistenciaUI();
                break;
            case 9:
                if (tienePermiso("CONSULTAR_REPORTES")) justificarAsistenciaUI();
                else cout << ROJO << "Solo administracion justifica asistencia." << RESET << endl;
                break;
            case 10:
                if (tienePermiso("CONSULTAR_REPORTES")) asistenciaHoyUI();
                else cout << ROJO << "No tienes permiso para ver reportes." << RESET << endl;
                break;
            case 11:
                if (tienePermiso("CONSULTAR_REPORTES")) historialAsistenciaUI();
                else cout << ROJO << "No tienes permiso para ver reportes." << RESET << endl;
                break;
            case 12:
                ejecutarSubmenuContratos();
                break;
            case 13:
                subirContratoUI();
                break;
            case 14:
                consultarContratosUI();
                break;
            case 15:
                finalizarContratoUI();
                break;
            case 16:
                break;
            default:
                cout << ROJO << "Opcion no valida." << RESET << endl;
                break;
        }
        if (opcion != 16) pausar();
    } while (opcion != 16);
}

