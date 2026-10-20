#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <filesystem>
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
// tipoContrato: "TEMPORAL" (con duracion) | "FIJO" (permanente). Nota: los
// TITULOS legales son al revés que la UI — la ley llama "termino fijo" al
// temporal y "termino indefinido" al permanente. duracionTexto solo aplica
// al temporal (ej. "1 año").
string armarContrato(const DatosPersonaContrato &persona, const string &tipoContrato,
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

    // Datos de la persona (los pide la app al generar; no se consulta la BD)
    string nombre   = persona.nombre;
    string cedula   = persona.cedula;
    string cargo    = persona.cargo;
    string salario  = persona.salario;
    string telefono = persona.telefono;
    string email    = persona.email;
    string fIngreso = persona.fechaIngreso;

    // Datos de la empresa: todo sale de CONFIGURACION (BALBU_TECH es la
    // empresa). Las claves RNC/CIUDAD/DIRECCION_EMPRESA/REPRESENTANTE/
    // CEDULA_REPRESENTANTE existen vacias hasta que se carguen; mientras
    // tanto el documento muestra el placeholder para completar a mano.
    map<string, string> cfg = leerConfiguracion();
    string nomEmpresa = cfgO(cfg, "NOMBRE_TIENDA", "BALBU_TECH");
    string rnc        = cfgO(cfg, "RNC", "____________");
    string ciudad     = cfgO(cfg, "CIUDAD", "____________");
    string dirEmpresa = cfgO(cfg, "DIRECCION_EMPRESA", "____________");
    string repres     = cfgO(cfg, "REPRESENTANTE", "____________");
    string cedRepres  = cfgO(cfg, "CEDULA_REPRESENTANTE", "____________");

    // Tipo y duracion
    bool esTemporal = (tipoContrato == "TEMPORAL");
    string tipoTit  = esTemporal ? "CONTRATO DE TRABAJO A TERMINO FIJO"
                                 : "CONTRATO DE TRABAJO A TERMINO INDEFINIDO";
    string duracion = esTemporal ? duracionTexto : "indefinido";
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

// Valida una fecha ISO (AAAA-MM-DD) sin dejar que stoi explote con basura.
static bool esFechaISO(const string &f) {
    if (f.size() != 10 || f[4] != '-' || f[7] != '-') return false;
    for (size_t i = 0; i < f.size(); i++) {
        if (i == 4 || i == 7) continue;
        if (f[i] < '0' || f[i] > '9') return false;
    }
    int mes = stoi(f.substr(5, 2));
    int dia = stoi(f.substr(8, 2));
    return mes >= 1 && mes <= 12 && dia >= 1 && dia <= 31;
}

// Convierte la duracion en meses al texto del contrato (12 -> "1 año",
// 6 -> "6 meses"). Asi el HTML y la BD hablan de lo mismo.
static string textoDuracion(long meses) {
    if (meses > 0 && meses % 12 == 0) {
        long anios = meses / 12;
        return to_string(anios) + (anios == 1 ? " año" : " años");
    }
    return to_string(meses) + (meses == 1 ? " mes" : " meses");
}

// Recorta espacios de los extremos (seguridad.cpp no las exporta).
static string recortar(const string &s) {
    size_t i = s.find_first_not_of(" \t\r\n");
    if (i == string::npos) return "";
    size_t f = s.find_last_not_of(" \t\r\n");
    return s.substr(i, f - i + 1);
}

void generarContratoUI() {
    try {
        cout << "\n=== GENERAR CONTRATO DE TRABAJO ===" << endl;
        cout << "(Solo genera el documento: nada se registra en la BD hasta la firma.)" << endl;

        // --- DATOS DEL EMPLEADO ---
        // La 12 es la OFERTA: la persona todavia no esta en EMPLEADOS (acaba de
        // firmar o ni siquiera firmo). La cedula se escribe en el contrato, pero
        // no se busca en la base: no hace falta que exista.
        cout << "\n--- DATOS DEL EMPLEADO ---" << endl;
        auto requerido = [](const string &etiqueta) {
            while (true) {
                string v = recortar(leerDatoSeguro(etiqueta));
                if (!v.empty()) return v;
                // (18/10/2026) Con la entrada agotada leerDatoSeguro() devuelve
                // "" para siempre: sin esto el bucle gira sin fin (misma clase
                // de bug que el de los menus con EOF).
                if (cin.eof()) throw CancelarOperacionException();
                cout << ROJO << "No puede quedar vacio." << RESET << endl;
            }
        };

        string cedula;
        while (true) {
            cedula = requerido("Cedula del empleado (11 digitos): ");
            if (cedula.size() == 11 &&
                all_of(cedula.begin(), cedula.end(),
                       [](char c) { return c >= '0' && c <= '9'; })) break;
            cout << ROJO << "La cedula debe tener 11 digitos, sin guiones ni espacios."
                 << RESET << endl;
        }

        DatosPersonaContrato p;
        p.cedula = cedula;
        p.nombre = requerido("Nombre completo: ");
        p.cargo  = requerido("Cargo que se le ofrece: ");

        // (20/10/2026) La opcion 12 es la OFERTA: solo pide el salario
        // ofrecido. El salario pactado se define al subir el contrato
        // (opcion 13), cuando se coteja contra el papel firmado.
        auto pedirMonto = [](const string &etiqueta, double defecto) {
            while (true) {
                string s = recortar(leerDatoSeguro(etiqueta));
                if (s.empty()) {
                    if (cin.eof()) throw CancelarOperacionException();
                    if (defecto > 0) return defecto;
                    cout << ROJO << "Este monto es obligatorio." << RESET << endl;
                    continue;
                }
                try {
                    size_t usado = 0;
                    double v = stod(s, &usado);
                    if (usado != s.size() || v <= 0) throw invalid_argument("rango");
                    return v;
                } catch (const exception &) {
                    if (cin.eof()) throw CancelarOperacionException();
                    cout << ROJO << "Monto invalido (ej. 15000 o 15000.50)." << RESET << endl;
                }
            }
        };

        {
            double ofrecido = pedirMonto("Salario ofrecido: ", 0);
            ostringstream so;
            so << fixed << setprecision(2) << ofrecido;
            p.salarioOfrecido = so.str();
            // El documento se imprime con el ofrecido; el pactado se confirma
            // en la opcion 13 antes de registrar.
            p.salario = p.salarioOfrecido;
        }

        p.telefono = recortar(leerDatoSeguro("Telefono (Enter = -): "));
        if (p.telefono.empty()) p.telefono = "-";
        p.email = recortar(leerDatoSeguro("Email (Enter = -): "));
        if (p.email.empty()) p.email = "-";

        while (true) {
            p.fechaIngreso = recortar(leerDatoSeguro("Fecha de ingreso (AAAA-MM-DD, Enter = hoy): "));
            if (p.fechaIngreso.empty()) { p.fechaIngreso = fechaHoyISO(); break; }
            if (esFechaISO(p.fechaIngreso)) break;
            cout << ROJO << "Formato invalido: use AAAA-MM-DD (ej. 2026-10-17)." << RESET << endl;
        }

        // --- CONTRATO ---
        cout << "\n--- CONTRATO ---" << endl;
        cout << "Tipo de contrato:" << endl;
        cout << "  1. Temporal (con duracion: 1 mes, 1 año, etc.)" << endl;
        cout << "  2. Fijo" << endl;
        int op = (int)leerNumeroConIntentos("Opcion: ", 1, 2);
        bool esTemporal = (op == 1);

        long meses = 0;
        string duracion;
        if (esTemporal) {
            meses = (long)leerNumeroConIntentos("Duracion en meses (12 = 1 año): ", 1, 1200);
            duracion = textoDuracion(meses);
        }

        // Condiciones que no estan en ningun lado: se piden a generar.
        string dirEmp = requerido("Direccion del empleado: ");
        string horario = leerDatoSeguro("Horario (ej. 8:00 AM - 5:00 PM): ");
        if (horario.empty()) horario = "9:00 AM - 6:00 PM";
        string horasSem = leerDatoSeguro("Horas semanales (ej. 44): ");
        if (horasSem.empty()) horasSem = "44";
        string formaPago = leerDatoSeguro("Forma de pago (ej. transferencia bancaria): ");
        if (formaPago.empty()) formaPago = "transferencia bancaria";

        string html = armarContrato(p, esTemporal ? "TEMPORAL" : "FIJO", duracion,
                                    dirEmp, horario, horasSem, formaPago);

        string ruta = escribirContrato(html, p.nombre, fechaHoyISO());
        cout << "\nContrato generado: " << ruta << endl;

        // Borrador (clave=valor) junto al HTML: lo lee la opcion 13 Subir
        // cuando la persona firma, asi no hay que volver a pedir los datos.
        // (18/10/2026) La ruta del borrador sale SOLO si el documento termina
        // en ".html". Antes se hacia rfind(".html") y, si no aparecia, la ruta
        // quedaba IGUAL a la del documento: el ofstream de abajo lo abria en
        // modo truncado y lo pisaba con el borrador. Hoy escribirContrato()
        // siempre devuelve .html, pero el dia que deje de hacerlo esto borraba
        // el contrato recien generado sin decir una palabra.
        const string sufijoHtml = ".html";
        string rutaBorrador;
        if (ruta.size() > sufijoHtml.size() &&
            ruta.compare(ruta.size() - sufijoHtml.size(), sufijoHtml.size(),
                         sufijoHtml) == 0) {
            rutaBorrador = ruta.substr(0, ruta.size() - sufijoHtml.size()) + ".borrador";
        }

        if (rutaBorrador.empty()) {
            cout << AMARILLO << "[Aviso] El documento no termina en .html: no "
                    "genere el borrador para no pisarlo. La opcion 13 Subir no "
                    "va a ver este contrato." << RESET << endl;
        } else {
            ofstream fb(rutaBorrador);
            if (fb) {
                fb << "nombre=" << p.nombre << "\n"
                   << "cedula=" << p.cedula << "\n"
                   << "cargo=" << p.cargo << "\n"
                   << "salario=" << p.salario << "\n"
                   << "salario_ofrecido=" << p.salarioOfrecido << "\n"
                   << "telefono=" << p.telefono << "\n"
                   << "email=" << p.email << "\n"
                   << "fecha_ingreso=" << p.fechaIngreso << "\n"
                   << "tipo=" << (esTemporal ? "TEMPORAL" : "FIJO") << "\n"
                   << "meses=" << (esTemporal ? to_string(meses) : "0") << "\n"
                   << "dir=" << dirEmp << "\n"
                   << "horario=" << horario << "\n"
                   << "horas=" << horasSem << "\n"
                   << "forma_pago=" << formaPago << "\n"
                   << "html=" << ruta << "\n"
                   << "generado=" << fechaHoyISO() << "\n";
                fb.close();
                if (fb) {
                    cout << "Borrador guardado: " << rutaBorrador << endl;
                } else {
                    cout << AMARILLO << "[Aviso] El borrador " << rutaBorrador
                         << " quedo incompleto (se lleno el disco?). La opcion 13 "
                            "Subir puede no verlo." << RESET << endl;
                }
            } else {
                cout << AMARILLO << "[Aviso] No se pudo guardar el borrador "
                     << rutaBorrador << ": la opcion 13 Subir no va a ver este "
                        "contrato. Revisa permisos y espacio en disco, y genera "
                        "el contrato de nuevo." << RESET << endl;
            }
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

// ---------------------------------------------------------------------------
// Registro del contrato firmado (19/10/2026)
// ---------------------------------------------------------------------------

// Cedula dominicana: 11 digitos, sin guiones ni espacios.
static bool esCedulaValida(const string &c) {
    if (c.size() != 11) return false;
    for (char ch : c) if (ch < '0' || ch > '9') return false;
    return true;
}

// Pregunta un campo con el valor del borrador como default. Enter lo deja.
static string cotejarCampo(const string &etiqueta, const string &actual) {
    string v = recortar(leerDatoSeguro(etiqueta + " [" + actual + "]: "));
    if (cin.eof()) throw CancelarOperacionException();
    return v.empty() ? actual : v;
}

// S/N. Con la entrada agotada corta (no gira).
static bool confirmarSiNo(const string &pregunta) {
    while (true) {
        string r = recortar(leerDatoSeguro(pregunta + " (S/N): "));
        if (cin.eof()) throw CancelarOperacionException();
        if (r == "S" || r == "s") return true;
        if (r == "N" || r == "n") return false;
        cout << ROJO << "Responda S o N." << RESET << endl;
    }
}

// Monto obligatorio con default visible. Con EOF corta.
static double pedirMontoObligatorio(const string &etiqueta, const string &porDefecto) {
    while (true) {
        string s = recortar(leerDatoSeguro(etiqueta + " [" + porDefecto + "]: "));
        if (cin.eof()) throw CancelarOperacionException();
        if (s.empty()) s = porDefecto;
        try {
            size_t usado = 0;
            double v = stod(s, &usado);
            if (usado != s.size() || v <= 0) throw invalid_argument("rango");
            return v;
        } catch (const exception &) {
            cout << ROJO << "Monto invalido (ej. 18000 o 18000.50)." << RESET << endl;
        }
    }
}

// Copia el escaneo del papel a contratos/firmados/ y devuelve la ruta.
// Enter = sin escaneo (devuelve ""). La app no guarda el archivo en la base.
static string copiarEscaneo(const string &cedula, const string &fechaISO) {
    namespace fs = std::filesystem;
    while (true) {
        string ruta = recortar(leerDatoSeguro("Ruta del PDF firmado (Enter = sin escaneo): "));
        if (cin.eof()) throw CancelarOperacionException();
        if (ruta.empty()) return "";

        error_code ec;
        if (!fs::is_regular_file(ruta, ec)) {
            cout << ROJO << "No existe ese archivo. Proba de nuevo o Enter para "
                 << "seguir sin escaneo." << RESET << endl;
            continue;
        }
        string ext = fs::path(ruta).extension().string();
        for (char &c : ext) c = (char)tolower((unsigned char)c);
        if (ext != ".pdf" && ext != ".jpg" && ext != ".jpeg" && ext != ".png") {
            cout << ROJO << "Tiene que ser un PDF, JPG o PNG." << RESET << endl;
            continue;
        }
        if (fs::file_size(ruta, ec) > 20u * 1024u * 1024u) {
            cout << ROJO << "El archivo pasa de 20 MB." << RESET << endl;
            continue;
        }

        fs::create_directories("contratos/firmados", ec);
        string destino = "contratos/firmados/FIRMADO_" + cedula + "_" + fechaISO + ext;
        int n = 2;
        while (fs::exists(destino, ec)) {
            destino = "contratos/firmados/FIRMADO_" + cedula + "_" + fechaISO +
                      "_" + to_string(n) + ext;
            ++n;
        }
        fs::copy_file(ruta, destino, fs::copy_options::none, ec);
        if (ec) {
            cout << ROJO << "No se pudo copiar el escaneo: " << ec.message() << RESET << endl;
            continue;
        }
        cout << "Escaneo guardado en: " << destino << endl;
        return destino;
    }
}

// Historial de contratos de una persona. Busca por cedula: funciona antes y
// despues del alta (ID_EMPLEADO puede ser NULL).
void consultarContratosUI() {
    try {
        cout << "\n=== CONTRATOS DE LA PERSONA ===" << endl;

        string cedula;
        while (true) {
            cedula = recortar(leerDatoSeguro("Cedula (11 digitos): "));
            if (cin.eof()) throw CancelarOperacionException();
            if (esCedulaValida(cedula)) break;
            cout << ROJO << "La cedula debe tener 11 digitos, sin guiones ni espacios."
                 << RESET << endl;
        }

        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_CONTRATOS_POR_CEDULA(?)"));
        ps->setString(1, cedula);
        std::unique_ptr<sql::ResultSet> r(ps->executeQuery());

        struct Fila {
            int id;
            string nombre, cargo, tipo, inicio, fin, estado, vinculo, doc;
            double salario;
        };
        vector<Fila> filas;
        while (r->next()) {
            Fila f;
            f.id = r->getInt("ID_CONTRATO");
            f.nombre = r->isNull("NOMBRE") ? "-" : r->getString("NOMBRE");
            f.cargo = r->isNull("CARGO") ? "-" : r->getString("CARGO");
            f.tipo = r->getString("TIPO");
            f.inicio = r->getString("FECHA_INICIO");
            f.fin = r->isNull("FECHA_FIN") ? "indefinido" : r->getString("FECHA_FIN");
            f.salario = r->getDouble("SALARIO");
            f.estado = r->getString("ESTADO");
            f.vinculo = r->getString("VINCULO");
            f.doc = r->isNull("RUTA_DOCUMENTO") ? "-" : r->getString("RUTA_DOCUMENTO");
            filas.push_back(f);
        }
        drenarResultados(ps.get());

        if (filas.empty()) {
            cout << "Esa cedula no tiene contratos registrados." << endl;
            return;
        }

        // El nombre y el cargo salen del contrato: puede que el empleado
        // todavia no exista en EMPLEADOS (contrato firmado antes del alta).
        cout << "\nPersona: " << filas.front().nombre << " - " << filas.front().cargo << endl;
        printf("%-4s | %-9s | %-10s | %-10s | %10s | %-10s | %-10s | %s\n",
               "ID", "TIPO", "INICIO", "FIN", "SALARIO", "ESTADO", "VINCULO", "DOCUMENTO");
        printf("%s\n", string(108, '-').c_str());
        for (const Fila &f : filas) {
            printf("%-4d | %-9s | %-10s | %-10s | %10.2f | %-10s | %-10s | %s\n",
                   f.id, f.tipo.c_str(), f.inicio.c_str(), f.fin.c_str(),
                   f.salario, f.estado.c_str(), f.vinculo.c_str(), f.doc.c_str());
        }

        // El papel se escanea cuando se puede: se adjunta despues.
        if (!confirmarSiNo("\n¿Adjuntar el escaneo firmado a un contrato?")) return;

        int idCont = (int)leerNumeroConIntentos("Contrato (ID): ", 1, 999999999);

        string fechaInicio;
        {
            std::unique_ptr<sql::PreparedStatement> pf(globalCon->prepareStatement(
                "SELECT FECHA_INICIO FROM CONTRATOS "
                "WHERE ID_CONTRATO = ? AND CEDULA = ?"));
            pf->setInt(1, idCont);
            pf->setString(2, cedula);
            std::unique_ptr<sql::ResultSet> rf(pf->executeQuery());
            if (rf->next()) fechaInicio = rf->getString("FECHA_INICIO");
            drenarResultados(pf.get());
        }
        if (fechaInicio.empty()) {
            cout << ROJO << "Ese contrato no es de esa cedula." << RESET << endl;
            return;
        }

        string ruta = copiarEscaneo(cedula, fechaInicio);
        if (ruta.empty()) {
            cout << "No se adjunto nada." << endl;
            return;
        }

        std::unique_ptr<sql::PreparedStatement> pu(globalCon->prepareStatement(
            "UPDATE CONTRATOS SET RUTA_DOCUMENTO = ? WHERE ID_CONTRATO = ?"));
        pu->setString(1, ruta);
        pu->setInt(2, idCont);
        pu->executeUpdate();
        drenarResultados(pu.get());
        cout << VERDE << "Escaneo adjuntado al contrato #" << idCont << "." << RESET << endl;

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudieron ver los contratos: " << e.what() << RESET << endl;
    }
}

// Finaliza el contrato ACTIVO de una persona (a mano, p.ej. al despedir).
void finalizarContratoUI() {
    try {
        cout << "\n=== FINALIZAR CONTRATO ===" << endl;
        cout << "(Al despedir a un empleado, finaliza aqui su contrato.)" << endl;

        string cedula;
        while (true) {
            cedula = recortar(leerDatoSeguro("Cedula (11 digitos): "));
            if (cin.eof()) throw CancelarOperacionException();
            if (esCedulaValida(cedula)) break;
            cout << ROJO << "La cedula debe tener 11 digitos, sin guiones ni espacios."
                 << RESET << endl;
        }

        int idCont = 0;
        {
            std::unique_ptr<sql::PreparedStatement> pb(globalCon->prepareStatement(
                "SELECT ID_CONTRATO FROM CONTRATOS "
                "WHERE CEDULA = ? AND ESTADO = 'ACTIVO' "
                "ORDER BY ID_CONTRATO DESC LIMIT 1"));
            pb->setString(1, cedula);
            std::unique_ptr<sql::ResultSet> rb(pb->executeQuery());
            if (rb->next()) idCont = rb->getInt("ID_CONTRATO");
            drenarResultados(pb.get());
        }
        if (idCont == 0) {
            cout << "Esa cedula no tiene un contrato ACTIVO." << endl;
            return;
        }

        cout << "Contrato activo: #" << idCont << endl;
        if (!confirmarSiNo("¿Finalizarlo?")) return;

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

// Lee un .borrador (clave=valor) a un mapa. False si no se abre o esta vacio.
static bool leerBorrador(const string &ruta, map<string, string> &datos) {
    ifstream fb(ruta);
    if (!fb) return false;
    string linea;
    while (getline(fb, linea)) {
        size_t igual = linea.find('=');
        if (igual == string::npos || igual == 0) continue;
        datos[linea.substr(0, igual)] = linea.substr(igual + 1);
    }
    return !datos.empty();
}

// Registra el contrato firmado: coteja el borrador contra el papel, guarda lo
// que se firmo y deja la evidencia. No da de alta empleados.
void subirContratoUI() {
    try {
        namespace fs = std::filesystem;
        cout << "\n=== REGISTRAR CONTRATO FIRMADO ===" << endl;

        // 1. Borradores pendientes (los ya registrados quedan como .subido)
        vector<pair<string, map<string, string>>> pendientes;
        if (fs::exists("contratos")) {
            vector<string> rutas;
            for (const auto &entrada : fs::directory_iterator("contratos")) {
                if (entrada.is_regular_file() && entrada.path().extension() == ".borrador")
                    rutas.push_back(entrada.path().string());
            }
            sort(rutas.begin(), rutas.end());
            for (const string &r : rutas) {
                map<string, string> datos;
                if (leerBorrador(r, datos)) pendientes.push_back({r, datos});
            }
        }

        if (pendientes.empty()) {
            cout << "No hay borradores pendientes. Genere el contrato con la opcion 12." << endl;
            return;
        }

        cout << "\nBorradores pendientes:" << endl;
        for (size_t i = 0; i < pendientes.size(); i++) {
            const auto &d = pendientes[i].second;
            string nombre = d.count("nombre") ? d.at("nombre") : "?";
            string ced = d.count("cedula") ? d.at("cedula") : "?";
            string car = d.count("cargo") ? d.at("cargo") : "?";
            string fec = d.count("fecha_ingreso") ? d.at("fecha_ingreso") : "?";
            cout << "  " << (i + 1) << ". " << nombre << " - " << ced
                 << " - " << car << " - ingreso " << fec << endl;
        }
        // (18/10/2026) Salida para el borrador que ya no sirve. Sin esto, uno
        // que no se pudo marcar como .subido quedaba en esta lista para
        // siempre y no habia forma de sacarlo.
        const int opDescartar = (int)pendientes.size() + 1;
        cout << "  " << opDescartar << ". Descartar un borrador (no registra nada)" << endl;
        cout << "  0. Volver" << endl;

        int op = (int)leerNumeroConIntentos("Elegir: ", 0, (double)opDescartar);
        if (op == 0) return;

        if (op == opDescartar) {
            int cual = (int)leerNumeroConIntentos(
                "Cual descarto? (0 = cancelar): ", 0, (double)pendientes.size());
            if (cual == 0) return;

            const string origen = pendientes[cual - 1].first;
            string destino = origen;
            size_t corte = destino.rfind(".borrador");
            if (corte != string::npos) destino.replace(corte, 9, ".descartado");
            else destino += ".descartado";

            // No se borra: se renombra, igual que .subido, para no perder el
            // registro de lo que se genero.
            if (std::rename(origen.c_str(), destino.c_str()) == 0)
                cout << VERDE << "Borrador descartado (queda como " << destino
                     << ")." << RESET << endl;
            else
                cout << ROJO << "No se pudo descartar " << origen
                     << ". Borralo a mano si ya no sirve." << RESET << endl;
            return;
        }

        const string rutaBorrador = pendientes[op - 1].first;
        map<string, string> b = pendientes[op - 1].second;

        // 2. Campos que el borrador tiene que traer
        for (const char *clave : {"nombre", "cedula", "cargo", "salario",
                                   "fecha_ingreso", "tipo"}) {
            if (!b.count(clave) || b.at(clave).empty()) {
                cout << ROJO << "El borrador esta incompleto (falta '" << clave
                     << "'). Genere el contrato de nuevo con la opcion 12." << RESET << endl;
                return;
            }
        }
        if (b.at("tipo") != "TEMPORAL" && b.at("tipo") != "FIJO") {
            cout << ROJO << "El borrador tiene un tipo invalido: '" << b.at("tipo")
                 << "'. Debe ser TEMPORAL o FIJO. Genere el contrato de nuevo con "
                    "la opcion 12." << RESET << endl;
            return;
        }

        const map<string, string> original = b;

        // 3. Cotejo contra el papel firmado
        cout << "\n--- COTEJO CONTRA EL PAPEL FIRMADO ---" << endl;
        cout << "(Enter deja el valor del borrador; escribi el valor si el papel "
                "dice otra cosa.)" << endl;

        string nombre = cotejarCampo("Nombre", b.at("nombre"));

        string cedula;
        while (true) {
            cedula = cotejarCampo("Cedula", b.at("cedula"));
            if (esCedulaValida(cedula)) break;
            cout << ROJO << "La cedula debe tener 11 digitos, sin guiones ni espacios."
                 << RESET << endl;
        }

        string cargo = cotejarCampo("Cargo", b.at("cargo"));

        double salario = 0;
        {
            double originalMonto = 0;
            try {
                originalMonto = stod(b.at("salario"));
            } catch (const exception &) {
                cout << ROJO << "El borrador tiene un salario invalido: '"
                     << b.at("salario") << "'." << RESET << endl;
                return;
            }
            ostringstream porDef;
            porDef << fixed << setprecision(2) << originalMonto;
            salario = pedirMontoObligatorio("Salario pactado", porDef.str());
        }

        string tipo;
        while (true) {
            tipo = cotejarCampo("Tipo (FIJO/TEMPORAL)", b.at("tipo"));
            for (char &c : tipo) c = (char)toupper((unsigned char)c);
            if (tipo == "FIJO" || tipo == "TEMPORAL") break;
            cout << ROJO << "El tipo debe ser FIJO o TEMPORAL." << RESET << endl;
        }

        long meses = 0;
        if (tipo == "TEMPORAL") {
            string porDef = (b.count("meses") && !b.at("meses").empty()) ? b.at("meses") : "12";
            while (true) {
                string s = cotejarCampo("Duracion en meses", porDef);
                try {
                    size_t usado = 0;
                    long v = stol(s, &usado);
                    if (usado != s.size() || v < 1) throw invalid_argument("rango");
                    meses = v;
                    break;
                } catch (const exception &) {
                    cout << ROJO << "Duracion invalida: use meses (12 = 1 año)." << RESET << endl;
                }
            }
        }

        string fecha;
        while (true) {
            fecha = cotejarCampo("Fecha de ingreso (AAAA-MM-DD)", b.at("fecha_ingreso"));
            if (esFechaISO(fecha)) break;
            cout << ROJO << "Formato invalido: use AAAA-MM-DD (ej. 2026-11-01)." << RESET << endl;
        }

        string telefono = cotejarCampo(
            "Telefono", (b.count("telefono") && !b.at("telefono").empty()) ? b.at("telefono") : "-");
        string email = cotejarCampo(
            "Email", (b.count("email") && !b.at("email").empty()) ? b.at("email") : "-");

        // 4. Resumen de diferencias
        vector<string> cambios;
        auto comparar = [&cambios](const string &campo, const string &antes,
                                   const string &despues) {
            if (antes != despues)
                cambios.push_back("  - " + campo + ": " + antes + " -> " + despues);
        };
        comparar("nombre", original.at("nombre"), nombre);
        comparar("cedula", original.at("cedula"), cedula);
        comparar("cargo", original.at("cargo"), cargo);
        {
            ostringstream a, d;
            a << fixed << setprecision(2) << stod(original.at("salario"));
            d << fixed << setprecision(2) << salario;
            comparar("salario", a.str(), d.str());
        }
        comparar("tipo", original.at("tipo"), tipo);
        comparar("meses", (original.count("meses") ? original.at("meses") : "0"),
                 tipo == "TEMPORAL" ? to_string(meses) : "0");
        comparar("fecha de ingreso", original.at("fecha_ingreso"), fecha);
        comparar("telefono", (original.count("telefono") ? original.at("telefono") : "-"),
                 telefono);
        comparar("email", (original.count("email") ? original.at("email") : "-"), email);

        if (cambios.empty()) {
            cout << "\nEl papel coincide con el borrador." << endl;
        } else {
            cout << "\nCambios detectados:" << endl;
            for (const string &c : cambios) cout << c << endl;
        }

        if (!confirmarSiNo("\n¿Registrar el contrato con estos valores?")) {
            cout << "No se registro nada." << endl;
            return;
        }

        // 5. Escaneo opcional (lo archiva RRHH; la app solo guarda la ruta)
        string rutaDoc = copiarEscaneo(cedula, fecha);
        if (rutaDoc.empty()) rutaDoc = b.count("html") ? b.at("html") : "";

        // 6. Registrar: el SP vincula si el empleado ya existe; si no, deja
        //    ID_EMPLEADO NULL y el alta lo engancha despues.
        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_SUBIR_CONTRATO(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        ps->setString(1, nombre);
        ps->setString(2, cedula);
        ps->setString(3, cargo);
        ps->setDouble(4, salario);
        ps->setString(5, telefono);
        ps->setString(6, email);
        ps->setString(7, fecha);
        ps->setString(8, tipo);
        if (tipo == "TEMPORAL") ps->setInt(9, (int)meses);
        else ps->setNull(9, sql::DataType::INTEGER);
        ps->setString(10, rutaDoc);
        string msg = Recogermensaje(ps.get());
        cout << "\n" << msg << endl;

        // 7. Si salio bien, el borrador deja de estar pendiente
        if (msg.rfind("EXITO", 0) == 0) {
            string destino = rutaBorrador;
            size_t punto = destino.rfind(".borrador");
            if (punto != string::npos) destino.replace(punto, 9, ".subido");
            if (std::rename(rutaBorrador.c_str(), destino.c_str()) == 0) {
                cout << "Borrador marcado: " << destino << endl;
            } else {
                cout << AMARILLO
                     << "[Aviso] No se pudo marcar el borrador; el contrato ya "
                        "quedo registrado." << endl
                     << "        Siguio pendiente en: " << rutaBorrador << endl
                     << "        Ya no sirve: descartalo desde este mismo menu "
                        "(opcion \"Descartar un borrador\") o borra el archivo."
                     << RESET << endl;
            }
        }

    } catch (const CancelarOperacionException &e) {
        cout << "\n[!] " << e.what() << endl;
    } catch (const exception &e) {
        cout << ROJO << "No se pudo registrar el contrato: " << e.what() << RESET << endl;
    }
}
