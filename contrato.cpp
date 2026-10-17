#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <limits>
#include <mysql_connection.h>
#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "contrato.h"
#include "database.h"
#include "seguridad.h"
#include "colores.h"

using namespace std;

// Modulo de contratos de empleados (17/10/2026).
// Idea: al contratar a alguien, la app rellena plantillas/contrato.html con
// los datos del empleado y los de la empresa (tabla CONFIGURACION), y deja el
// archivo HTML listo para imprimir a PDF desde el navegador.
//
// Diseno pensado para migrar a Qt despues: armarContrato() es backend puro
// (lee la BD, no depende de la consola), escribirContrato() es el unico punto
// que toca un archivo. Cuando la app pase a Qt, solo se cambia esta ultima
// para usar QPdfWriter y generar PDF nativo.

// ---------------------------------------------------------------------------
// Utilidades internas
// ---------------------------------------------------------------------------

// Lee TODA la tabla CONFIGURACION a un mapa CLAVE -> VALOR.
static map<string, string> leerConfiguracion() {
    map<string, string> cfg;
    std::unique_ptr<sql::Statement> st(globalCon->createStatement());
    std::unique_ptr<sql::ResultSet> res(st->executeQuery(
        "SELECT CLAVE, VALOR FROM CONFIGURACION"));
    while (res->next()) {
        cfg[res->getString("CLAVE")] = res->getString("VALOR");
    }
    drenarResultados(st.get());
    return cfg;
}

// Valor de CONFIGURACION o un texto por defecto si la clave no existe o esta
// vacia (los campos de empresa pueden no estar cargados aun).
static string cfgO(const map<string, string> &cfg, const string &clave,
                   const string &porDefecto) {
    auto it = cfg.find(clave);
    if (it == cfg.end() || it->second.empty()) return porDefecto;
    return it->second;
}

// Fecha de hoy desde la BD ('AAAA-MM-DD').
static string fechaHoyISO() {
    std::unique_ptr<sql::Statement> st(globalCon->createStatement());
    std::unique_ptr<sql::ResultSet> res(st->executeQuery("SELECT CURDATE() AS HOY"));
    string hoy = "";
    if (res->next()) hoy = res->getString("HOY");
    drenarResultados(st.get());
    return hoy;
}

// Fecha 'AAAA-MM-DD' -> 'DD de MES de AAAA' para el contrato.
static string fechaLarga(const string &fechaISO) {
    static const char *meses[] = {"enero", "febrero", "marzo", "abril", "mayo",
                                  "junio", "julio", "agosto", "septiembre",
                                  "octubre", "noviembre", "diciembre"};
    if (fechaISO.size() < 10) return fechaISO;
    int dia = stoi(fechaISO.substr(8, 2));
    int mes = stoi(fechaISO.substr(5, 2)) - 1;
    string anio = fechaISO.substr(0, 4);
    if (mes < 0 || mes > 11) return fechaISO;
    return to_string(dia) + " de " + meses[mes] + " de " + anio;
}

// Reemplaza TODAS las ocurrencias de un placeholder {{X}} en el texto.
static void reemplazar(string &texto, const string &clave, const string &valor) {
    string marca = "{{" + clave + "}}";
    size_t pos = 0;
    while ((pos = texto.find(marca, pos)) != string::npos) {
        texto.replace(pos, marca.size(), valor);
        pos += valor.size();
    }
}

// ---------------------------------------------------------------------------
// Backend puro: junta los datos del contrato (no depende de la consola)
// ---------------------------------------------------------------------------

// Dado un ID de empleado, devuelve el HTML del contrato ya relleno.
// Lanza runtime_error si el empleado no existe.
// tipoContrato: "fijo" | "indefinido".  duracionTexto: solo para fijo (ej. "1 año").
string armarContrato(int idEmpleado, const string &tipoContrato,
                     const string &duracionTexto,
                     const string &dirEmpleado, const string &horario,
                     const string &horasSemanales, const string &formaPago) {
    // Plantilla
    ifstream fin("plantillas/contrato.html");
    if (!fin) throw runtime_error("No se encontro plantillas/contrato.html");
    stringstream ss;
    ss << fin.rdbuf();
    string html = ss.str();
    fin.close();

    // Datos del empleado
    std::unique_ptr<sql::PreparedStatement> pe(globalCon->prepareStatement(
        "SELECT NOMBRE, CEDULA, CARGO, SALARIO, TELEFONO, EMAIL, FECHA_INGRESO "
        "FROM EMPLEADOS WHERE ID_EMPLEADO = ?"));
    pe->setInt(1, idEmpleado);
    std::unique_ptr<sql::ResultSet> re(pe->executeQuery());
    if (!re->next()) {
        drenarResultados(pe.get());
        throw runtime_error("No existe el empleado ID " + to_string(idEmpleado));
    }
    string nombre   = re->getString("NOMBRE");
    string cedula   = re->getString("CEDULA");
    string cargo    = re->getString("CARGO");
    string salario  = re->getString("SALARIO");
    string telefono = re->getString("TELEFONO");
    string email    = re->getString("EMAIL");
    string fIngreso = re->getString("FECHA_INGRESO");
    drenarResultados(pe.get());

    // Datos de la empresa (CONFIGURACION)
    map<string, string> cfg = leerConfiguracion();
    string nomEmpresa = cfgO(cfg, "NOMBRE_TIENDA", "BALBU_TECH");
    string rnc        = cfgO(cfg, "RNC", "____________");
    string ciudad     = cfgO(cfg, "CIUDAD", "____________");
    string dirEmpresa = cfgO(cfg, "DIRECCION_EMPRESA", "____________");
    string repres     = cfgO(cfg, "REPRESENTANTE", "____________");
    string cedRepres  = cfgO(cfg, "CEDULA_REPRESENTANTE", "____________");

    // Tipo y duracion
    bool esFijo = (tipoContrato == "fijo");
    string tipoTit  = esFijo ? "CONTRATO DE TRABAJO A TERMINO FIJO"
                             : "CONTRATO DE TRABAJO A TERMINO INDEFINIDO";
    string duracion = esFijo ? duracionTexto : "indefinido";
    string pruebas  = "90";  // dias de prueba por defecto

    // Relleno de placeholders
    reemplazar(html, "NOMBRE_EMPLEADO", nombre);
    reemplazar(html, "CEDULA", cedula);
    reemplazar(html, "CARGO", cargo);
    reemplazar(html, "SALARIO", salario);
    reemplazar(html, "TELEFONO", telefono);
    reemplazar(html, "EMAIL", email);
    reemplazar(html, "FECHA_INGRESO", fechaLarga(fIngreso));

    // Fechas (hoy) y datos que se piden al generar
    string hoyISO = fechaHoyISO();
    reemplazar(html, "FECHA_FIRMA", fechaLarga(hoyISO));
    reemplazar(html, "FECHA_GENERACION", fechaLarga(hoyISO));
    reemplazar(html, "DIRECCION_EMPLEADO", dirEmpleado);
    reemplazar(html, "HORARIO", horario);
    reemplazar(html, "HORAS_SEMANALES", horasSemanales);
    reemplazar(html, "FORMA_PAGO", formaPago);

    reemplazar(html, "TIPO_CONTRATO", tipoTit);
    reemplazar(html, "DURACION", duracion);
    reemplazar(html, "DIAS_PRUEBA", pruebas);

    reemplazar(html, "NOMBRE_EMPRESA", nomEmpresa);
    reemplazar(html, "RNC_EMPRESA", rnc);
    reemplazar(html, "CIUDAD", ciudad);
    reemplazar(html, "DIRECCION_EMPRESA", dirEmpresa);
    reemplazar(html, "REPRESENTANTE", repres);
    reemplazar(html, "CEDULA_REPRESENTANTE", cedRepres);

    return html;
}

// ---------------------------------------------------------------------------
// Consola: escribe el HTML a disco (unica parte que cambia al migrar a Qt)
// ---------------------------------------------------------------------------

// Escribe el HTML en un archivo dentro de contratos/ y devuelve la ruta.
// (AQUI es donde, al migrar a Qt, se generara el PDF con QPdfWriter.)
string escribirContrato(const string &html, const string &nombreEmpleado,
                        const string &fechaISO) {
    // carpeta contratos/
#ifdef _WIN32
    system("if not exist contratos mkdir contratos");
#else
    system("mkdir -p contratos");
#endif

    // nombre de archivo legible (sin espacios raros)
    string base = nombreEmpleado;
    for (char &c : base) {
        if (!isalnum((unsigned char)c)) c = '_';
    }
    string ruta = "contratos/CONTRATO_" + base + "_" + fechaISO + ".html";

    ofstream fout(ruta);
    if (!fout) throw runtime_error("No se pudo crear el archivo " + ruta);
    fout << html;
    fout.close();
    return ruta;
}

// ---------------------------------------------------------------------------
// Pantalla principal del modulo
// ---------------------------------------------------------------------------

// Convierte la duracion en meses al texto del contrato (12 -> "1 año",
// 6 -> "6 meses"). Asi el HTML y la BD hablan de lo mismo.
static string textoDuracion(long meses) {
    if (meses > 0 && meses % 12 == 0) {
        long anios = meses / 12;
        return to_string(anios) + (anios == 1 ? " año" : " años");
    }
    return to_string(meses) + (meses == 1 ? " mes" : " meses");
}

void ejecutarSubmenuContratos() {
    try {
        cout << "\n=== GENERAR CONTRATO DE TRABAJO ===" << endl;
        cout << "Empleado (ID): ";
        int idEmp = (int)leerNumeroConIntentos("", 1, 999999999);

        cout << "Tipo de contrato:" << endl;
        cout << "  1. Fijo (con duracion: 1 mes, 1 año, etc.)" << endl;
        cout << "  2. Indefinido" << endl;
        int op = (int)leerNumeroConIntentos("Opcion: ", 1, 2);
        bool esFijo = (op == 1);

        long meses = 0;
        string duracion;
        if (esFijo) {
            meses = (long)leerNumeroConIntentos("Duracion en meses (12 = 1 año): ", 1, 1200);
            duracion = textoDuracion(meses);
        }

        // Registrar ANTES de pedir todo lo demas: si ya tiene un contrato
        // activo, aqui frena sin gastar los demas datos. La ruta del documento
        // se completa despues de escribir el HTML.
        {
            std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
                "CALL SP_INSERTAR_CONTRATO(?, ?, ?, ?)"));
            ps->setInt(1, idEmp);
            ps->setString(2, esFijo ? "FIJO" : "INDEFINIDO");
            if (esFijo) ps->setInt(3, (int)meses);
            else ps->setNull(3, sql::DataType::INTEGER);
            ps->setNull(4, sql::DataType::VARCHAR);
            string msg = Recogermensaje(ps.get());
            cout << "\n" << msg << endl;
            if (msg.rfind("Error DB:", 0) == 0) return;  // freno: no sigue
        }

        // Datos que no estan en la tabla EMPLEADOS: se piden al generar.
        string dirEmp = leerDatoSeguro("Direccion del empleado: ");
        string horario = leerDatoSeguro("Horario (ej. 8:00 AM - 5:00 PM): ");
        if (horario.empty()) horario = "9:00 AM - 6:00 PM";
        string horasSem = leerDatoSeguro("Horas semanales (ej. 44): ");
        if (horasSem.empty()) horasSem = "44";
        string formaPago = leerDatoSeguro("Forma de pago (ej. transferencia bancaria): ");
        if (formaPago.empty()) formaPago = "transferencia bancaria";

        string html = armarContrato(idEmp, esFijo ? "fijo" : "indefinido", duracion,
                                    dirEmp, horario, horasSem, formaPago);

        // nombre del empleado para el nombre del archivo
        std::unique_ptr<sql::Statement> st(globalCon->createStatement());
        std::unique_ptr<sql::ResultSet> r(st->executeQuery("SELECT NOMBRE FROM EMPLEADOS WHERE ID_EMPLEADO=" + to_string(idEmp)));
        string nomEmp = "";
        if (r->next()) nomEmp = r->getString("NOMBRE");
        drenarResultados(st.get());

        string ruta = escribirContrato(html, nomEmp, fechaHoyISO());
        cout << "\nContrato generado: " << ruta << endl;

        // Dejar la ruta del documento en el registro que abrimos antes
        {
            std::unique_ptr<sql::PreparedStatement> pu(globalCon->prepareStatement(
                "UPDATE CONTRATOS SET RUTA_DOCUMENTO=? "
                "WHERE ID_EMPLEADO=? AND ESTADO='ACTIVO'"));
            pu->setString(1, ruta);
            pu->setInt(2, idEmp);
            pu->executeUpdate();
        }

        // abrir en el navegador (imprimir a PDF desde ahi)
        cout << "Abriendo en el navegador para imprimir a PDF..." << endl;
#ifdef _WIN32
        string cmd = "start \"\" \"" + ruta + "\"";
        system(cmd.c_str());
#else
        string cmd = "xdg-open \"" + ruta + "\" >/dev/null 2>&1 &";
        system(cmd.c_str());
#endif

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo generar el contrato: " << e.what() << RESET << endl;
    }
}

// Historial de contratos de un empleado, mas reciente primero.
void consultarContratosUI() {
    try {
        cout << "\n=== CONTRATOS DEL EMPLEADO ===" << endl;
        int idEmp = (int)leerNumeroConIntentos("Empleado (ID): ", 1, 999999999);

        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_CONTRATOS_POR_EMPLEADO(?)"));
        ps->setInt(1, idEmp);
        std::unique_ptr<sql::ResultSet> r(ps->executeQuery());

        bool hay = false;
        printf("\n%-4s | %-11s | %-10s | %-10s | %-10s | %-11s | %s\n",
               "ID", "TIPO", "INICIO", "FIN", "SALARIO", "ESTADO", "DOCUMENTO");
        printf("%s\n", string(95, '-').c_str());
        while (r->next()) {
            hay = true;
            string fin = r->isNull("FECHA_FIN") ? "indefinido" : r->getString("FECHA_FIN");
            string doc = r->isNull("RUTA_DOCUMENTO") ? "-" : r->getString("RUTA_DOCUMENTO");
            printf("%-4d | %-11s | %-10s | %-10s | %10.2f | %-11s | %s\n",
                   r->getInt("ID_CONTRATO"),
                   r->getString("TIPO").c_str(),
                   r->getString("FECHA_INICIO").c_str(),
                   fin.c_str(),
                   (double)r->getDouble("SALARIO"),
                   r->getString("ESTADO").c_str(),
                   doc.c_str());
        }
        drenarResultados(ps.get());
        if (!hay) cout << "El empleado no tiene contratos registrados." << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudieron ver los contratos: " << e.what() << RESET << endl;
    }
}

// Pasa un contrato de ACTIVO a FINALIZADO (a mano, p.ej. al despedir).
void finalizarContratoUI() {
    try {
        cout << "\n=== FINALIZAR CONTRATO ===" << endl;
        cout << "(Al despedir a un empleado, finaliza aqui su contrato.)" << endl;
        int idCont = (int)leerNumeroConIntentos("Contrato (ID): ", 1, 999999999);

        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_FINALIZAR_CONTRATO(?)"));
        ps->setInt(1, idCont);
        cout << "\n" << Recogermensaje(ps.get()) << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo finalizar el contrato: " << e.what() << RESET << endl;
    }
}
