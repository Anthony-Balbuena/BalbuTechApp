#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <algorithm>
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

    // Datos de la empresa (CONFIGURACION)
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

void ejecutarSubmenuContratos() {
    try {
        cout << "\n=== GENERAR CONTRATO DE TRABAJO ===" << endl;
        cout << "(Solo genera el documento: nada se registra en la BD hasta la firma.)" << endl;

        // --- DATOS DE LA PERSONA ---
        // Sin ID: puede ser alguien que aun no esta registrado como empleado.
        cout << "\n--- DATOS DE LA PERSONA ---" << endl;
        auto requerido = [](const string &etiqueta) {
            while (true) {
                string v = leerDatoSeguro(etiqueta);
                if (!v.empty()) return v;
                // (18/10/2026) Con la entrada agotada leerDatoSeguro() devuelve
                // "" para siempre: sin esto el bucle gira sin fin (misma clase
                // de bug que el de los menus con EOF).
                if (cin.eof()) throw CancelarOperacionException();
                cout << ROJO << "No puede quedar vacio." << RESET << endl;
            }
        };
        DatosPersonaContrato p;
        p.nombre = requerido("Nombre completo: ");
        p.cedula = requerido("Cedula: ");
        p.cargo  = requerido("Cargo: ");

        double sal = leerNumeroConIntentos("Salario: ", 0, 999999999);
        {
            ostringstream ss;
            ss << fixed << setprecision(2) << sal;
            p.salario = ss.str();
        }

        p.telefono = leerDatoSeguro("Telefono (Enter = -): ");
        if (p.telefono.empty()) p.telefono = "-";
        p.email = leerDatoSeguro("Email (Enter = -): ");
        if (p.email.empty()) p.email = "-";

        while (true) {
            p.fechaIngreso = leerDatoSeguro("Fecha de ingreso (AAAA-MM-DD, Enter = hoy): ");
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

// Sube (registra) el contrato cuando la persona firma. Usa el .borrador de la
// opcion 12 para no repetir datos; el trigger crea o vincula al empleado.
void subirContratoUI() {
    try {
        namespace fs = std::filesystem;
        cout << "\n=== SUBIR CONTRATO (AL FIRMAR) ===" << endl;

        // 1. Borradores pendientes (los ya subidos quedan como .subido)
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
            string tipo = d.count("tipo") ? d.at("tipo") : "?";
            string meses = d.count("meses") ? d.at("meses") : "0";
            cout << "  " << (i + 1) << ". " << nombre << " - " << tipo;
            if (tipo == "TEMPORAL" && meses != "0") cout << " " << meses << " meses";
            cout << "  (" << pendientes[i].first << ")" << endl;
        }
        // (18/10/2026) Salida para el borrador que ya no sirve. Sin esto, uno
        // que no se pudo marcar como .subido (falla el rename de mas abajo)
        // quedaba en esta lista para siempre: el SP lo frena con "ESA CEDULA
        // YA TIENE UN CONTRATO ACTIVO" y no habia forma de sacarlo de aca.
        const int opDescartar = (int)pendientes.size() + 1;
        cout << "  " << opDescartar << ". Descartar un borrador (no sube nada)" << endl;
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
            // registro de quien lo genero.
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

        // 2. Campos que el SP necesita a toda costa
        for (const char *clave : {"nombre", "cedula", "cargo", "salario",
                                   "telefono", "email", "fecha_ingreso", "tipo"}) {
            if (!b.count(clave) || b.at(clave).empty()) {
                cout << ROJO << "El borrador esta incompleto (falta '" << clave
                     << "'). Genere el contrato de nuevo con la opcion 12." << RESET << endl;
                return;
            }
        }

        // (18/10/2026) Antes esto era "== TEMPORAL" y todo lo demas caia como
        // FIJO sin avisar: un borrador corrupto registraba un contrato fijo
        // que nadie pidio, y el freno del SP ("EL TIPO DEBE SER TEMPORAL O
        // FIJO") era inalcanzable desde aca. Se valida antes de tocar la BD.
        if (b.at("tipo") != "TEMPORAL" && b.at("tipo") != "FIJO") {
            cout << ROJO << "El borrador tiene un tipo invalido: '" << b.at("tipo")
                 << "'. Debe ser TEMPORAL o FIJO. Genere el contrato de nuevo con "
                    "la opcion 12." << RESET << endl;
            return;
        }

        double salario = 0;
        try {
            salario = stod(b.at("salario"));
        } catch (const exception &) {
            cout << ROJO << "El borrador tiene un salario invalido: '"
                 << b.at("salario") << "'." << RESET << endl;
            return;
        }

        // 3. Si la cedula aun no es de nadie, es un empleado NUEVO: EMPLEADOS
        //    guarda su telefono y email unicos, asi que "-" no entra.
        string telefono = b.at("telefono");
        string email = b.at("email");
        {
            std::unique_ptr<sql::PreparedStatement> pc(globalCon->prepareStatement(
                "SELECT COUNT(*) FROM EMPLEADOS WHERE CEDULA = ?"));
            pc->setString(1, b.at("cedula"));
            std::unique_ptr<sql::ResultSet> rc(pc->executeQuery());
            bool esNuevo = true;
            if (rc->next()) esNuevo = (rc->getInt(1) == 0);
            drenarResultados(pc.get());

            if (esNuevo) {
                while (telefono.empty() || telefono == "-") {
                    telefono = leerDatoSeguro("Telefono real del empleado nuevo (unico en la BD): ");
                    // (18/10/2026) Entrada agotada -> leerDatoSeguro() devuelve
                    // "" y este bucle giraba sin fin.
                    if (cin.eof()) throw CancelarOperacionException();
                    if (telefono.empty() || telefono == "-")
                        cout << ROJO << "El empleado nuevo necesita un telefono real." << RESET << endl;
                }
                while (email.empty() || email == "-") {
                    email = leerDatoSeguro("Email real del empleado nuevo (unico en la BD): ");
                    if (cin.eof()) throw CancelarOperacionException();
                    if (email.empty() || email == "-")
                        cout << ROJO << "El empleado nuevo necesita un email real." << RESET << endl;
                }
            }
        }

        // 4. Registrar: el SP frena lo que haga falta y el trigger resuelve
        //    el empleado (lo crea o lo vincula).
        bool esTemporal = (b.at("tipo") == "TEMPORAL");
        long meses = 0;
        if (esTemporal && b.count("meses") && !b.at("meses").empty()) {
            try { meses = stol(b.at("meses")); } catch (const exception &) { meses = 0; }
        }

        std::unique_ptr<sql::PreparedStatement> ps(globalCon->prepareStatement(
            "CALL SP_SUBIR_CONTRATO(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        ps->setString(1, b.at("nombre"));
        ps->setString(2, b.at("cedula"));
        ps->setString(3, b.at("cargo"));
        ps->setDouble(4, salario);
        ps->setString(5, telefono);
        ps->setString(6, email);
        ps->setString(7, b.at("fecha_ingreso"));
        ps->setString(8, esTemporal ? "TEMPORAL" : "FIJO");
        if (esTemporal) ps->setInt(9, (int)meses);
        else ps->setNull(9, sql::DataType::INTEGER);
        ps->setString(10, b.count("html") ? b.at("html") : "");
        string msg = Recogermensaje(ps.get());
        cout << "\n" << msg << endl;

        // 5. Si salio bien, el borrador deja de estar pendiente
        if (msg.rfind("EXITO", 0) == 0) {
            string destino = rutaBorrador;
            size_t punto = destino.rfind(".borrador");
            if (punto != string::npos) destino.replace(punto, 9, ".subido");
            if (std::rename(rutaBorrador.c_str(), destino.c_str()) == 0) {
                cout << "Borrador marcado: " << destino << endl;
            } else {
                // El contrato YA quedo en la BD: reintentar la subida la frena
                // el SP ("esa cedula ya tiene un contrato activo"). El borrador
                // se queda en la lista, asi que hay que decir donde esta y como
                // sacarlo, o es una trampa para siempre.
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
        cout << ROJO << "No se pudo subir el contrato: " << e.what() << RESET << endl;
    }
}
