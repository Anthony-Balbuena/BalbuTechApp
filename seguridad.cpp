#include "seguridad.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <cstdlib>
#include <cctype>
#include <limits>
#include "colores.h"
#include <openssl/evp.h>
#include <string>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#ifdef _WIN32
#include <conio.h>
#include <cstdio>
#include <io.h>
#else
#include <termios.h>
#include <unistd.h>
#endif

using namespace std;

string leerDatoSeguro(const string& mensaje) {
    string entrada;
    cout << mensaje;
    cin.clear();
    // (10/10/2026) Sin peek/ignore: se comía la línea vacía y el Enter
    // para "ver todos/omitir" pedía dos veces. Los menús ya limpian solos.
    getline(cin, entrada);

    if (entrada == "xxx") {
        throw CancelarOperacionException();
    }

    return entrada;
}

// (03/11/2026) Lee una contraseña sin mostrarla en pantalla. Si stdin no es
// una terminal (pipe/test), cae a getline. Devuelve false si la entrada se
// agotó (Ctrl+D en Linux, Ctrl+Z en Windows).
bool leerPassword(const string& mensaje, string& out) {
    out.clear();
    cout << mensaje;
#ifdef _WIN32
    if (!_isatty(_fileno(stdin))) {
        return static_cast<bool>(getline(cin, out));
    }
    int c;
    while ((c = _getch()) != '\r' && c != '\n') {
        if (c == 3 || c == 26) {  // Ctrl+C / Ctrl+Z
            cout << endl;
            return false;
        }
        if (c == 0 || c == 224) {  // teclas extendidas (flechas, F1...)
            _getch();
            continue;
        }
        if (c == '\b') {
            if (!out.empty()) out.pop_back();
        } else {
            out.push_back(static_cast<char>(c));
        }
    }
    cout << endl;
    return true;
#else
    if (!isatty(STDIN_FILENO)) {
        return static_cast<bool>(getline(cin, out));
    }
    termios oldt{};
    if (tcgetattr(STDIN_FILENO, &oldt) != 0) {
        return static_cast<bool>(getline(cin, out));
    }
    termios noEcho = oldt;
    noEcho.c_lflag &= ~static_cast<tcflag_t>(ECHO);
    if (tcsetattr(STDIN_FILENO, TCSANOW, &noEcho) != 0) {
        return static_cast<bool>(getline(cin, out));
    }
    bool ok = static_cast<bool>(getline(cin, out));
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    cout << endl;
    return ok;
#endif
}

// (18/10/2026) Opcion de menu a prueba de EOF.
// El molde anterior (cin >> opcion; if (cin.fail()) { cin.clear(); ... })
// giraba para siempre con la entrada agotada: clear() limpia el flag pero el
// buffer sigue en EOF, asi que el siguiente ">>" falla al instante y opcion
// nunca llega a valer la opcion de salida. Aqui se detecta el EOF ANTES de
// limpiar nada y se avisa al llamador para que corte el bucle.
bool leerOpcionMenu(int &opcion) {
    if (!(cin >> opcion)) {
        if (cin.eof()) return false;   // entrada agotada: que el menu corte
        cin.clear();
        cin.ignore(numeric_limits<streamsize>::max(), '\n');
        opcion = -1;                   // fuera de rango -> "Opcion no valida"
        return true;
    }
    cin.ignore(numeric_limits<streamsize>::max(), '\n');
    return true;
}

// --- Entrada numerica con reintentos (15/10/2026) ---
static string recortarEspacios(const string& texto) {
    size_t ini = texto.find_first_not_of(" \t\r\n");
    if (ini == string::npos) return "";
    size_t fin = texto.find_last_not_of(" \t\r\n");
    return texto.substr(ini, fin - ini + 1);
}

// Acepta enteros y decimales con punto o coma (ej: 75.50 / 75,5).
static bool parsearDecimal(const string& texto, double &valor) {
    string limpio = recortarEspacios(texto);
    if (limpio.empty()) return false;
    for (char &c : limpio) {
        if (c == ',') c = '.';
    }
    char* fin = nullptr;
    valor = strtod(limpio.c_str(), &fin);
    return fin != limpio.c_str() && *fin == '\0';
}

bool esNumerico(const string& texto) {
    if (texto.empty()) return false;
    for (char c : texto) {
        if (!isdigit(static_cast<unsigned char>(c))) return false;
    }
    return true;
}

string dinero(double v) {
    // Formato monetario fijo: siempre dos decimales (ej: $75.50, $0.00).
    ostringstream o;
    o << "$" << fixed << setprecision(2) << v;
    return o.str();
}

double leerNumeroConIntentos(const string& mensaje, double minimo, double maximo,
                             const double* porDefecto, int maxIntentos) {
    for (int intento = 1; intento <= maxIntentos; ++intento) {
        string texto = recortarEspacios(leerDatoSeguro(mensaje));
        if (texto.empty() && porDefecto != nullptr) {
            return *porDefecto;
        }
        double valor = 0.0;
        if (parsearDecimal(texto, valor)) {
            if (valor >= minimo && valor <= maximo) {
                return valor;
            }
            cout << ROJO << "Fuera de rango: debe estar entre " << minimo
                 << " y " << maximo << " (intento " << intento << " de "
                 << maxIntentos << ")." << RESET << endl;
        } else {
            cout << ROJO << "Valor invalido: escriba un numero (intento "
                 << intento << " de " << maxIntentos << ")." << RESET << endl;
        }
    }
    cout << ROJO << "Se agotaron los intentos. Regresando al menu principal..."
         << RESET << endl;
    throw CancelarOperacionException();
}

string aplicarHash(const string& input) {
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int length = 0;

    if (mdctx == nullptr) {
        return "";
    }

    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestUpdate(mdctx, input.c_str(), input.size()) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestFinal_ex(mdctx, hash, &length) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    EVP_MD_CTX_free(mdctx);

    stringstream ss;
    for (unsigned int i = 0; i < length; ++i) {
        ss << hex << setw(2) << setfill('0') << static_cast<int>(hash[i]);
    }
    return ss.str();
}

// Base64 helpers using OpenSSL BIO
static string base64_encode(const unsigned char* input, int length) {
    BIO *bmem = nullptr;
    BIO *b64 = nullptr;
    BUF_MEM *bptr = nullptr;

    b64 = BIO_new(BIO_f_base64());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bmem = BIO_new(BIO_s_mem());
    b64 = BIO_push(b64, bmem);
    BIO_write(b64, input, length);
    BIO_flush(b64);
    BIO_get_mem_ptr(b64, &bptr);

    string out(bptr->data, bptr->length);
    BIO_free_all(b64);
    return out;
}

 vector<unsigned char> base64_decode(const string &input) {
    BIO *b64 = BIO_new(BIO_f_base64());
    BIO *bmem = BIO_new_mem_buf(input.data(), input.size());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bmem = BIO_push(b64, bmem);

    vector<unsigned char> out(input.size());
    int decoded_len = BIO_read(bmem, out.data(), input.size());
    if (decoded_len <= 0) {
        out.clear();
    } else {
        out.resize(decoded_len);
    }
    BIO_free_all(bmem);
    return out;
}

// wrapper expected name
bool verificar_password_pbkdf2(const std::string &password, const std::string &stored) {
    return verificarPassword(password, stored, nullptr);
}

bool generar_hash_pbkdf2(const std::string &password, std::string &out_serializado) {
    const int SALT_LEN = 16;
    const int ITER = 100000;
    const int DK_LEN = 32;

    unsigned char salt[SALT_LEN];
    if (RAND_bytes(salt, SALT_LEN) != 1) return false;

    vector<unsigned char> dk(DK_LEN);
    if (!PKCS5_PBKDF2_HMAC(password.c_str(), password.size(), salt, SALT_LEN, ITER, EVP_sha256(), DK_LEN, dk.data())) {
        return false;
    }

    string salt_b64 = base64_encode(salt, SALT_LEN);
    string dk_b64 = base64_encode(dk.data(), DK_LEN);

    out_serializado = "pbkdf2$" + to_string(ITER) + "$" + salt_b64 + "$" + dk_b64;
    return true;
}

bool verificarPassword(const std::string &password, const std::string &stored, std::string *out_rehash) {
    if (stored.rfind("pbkdf2$", 0) == 0) {
        // formato: pbkdf2$iter$salt_b64$hash_b64
        vector<string> parts;
        string tmp;
        std::istringstream iss(stored);
        while (std::getline(iss, tmp, '$')) parts.push_back(tmp);
        if (parts.size() != 4) return false;
        int iter = stoi(parts[1]);
        vector<unsigned char> salt = base64_decode(parts[2]);
        vector<unsigned char> hash = base64_decode(parts[3]);
        if (salt.empty() || hash.empty()) return false;

        vector<unsigned char> dk(hash.size());
        if (!PKCS5_PBKDF2_HMAC(password.c_str(), password.size(), salt.data(), salt.size(), iter, EVP_sha256(), dk.size(), dk.data())) {
            return false;
        }

        // tiempo-constante comparison
        if (CRYPTO_memcmp(dk.data(), hash.data(), dk.size()) == 0) return true;
        return false;
    } else {
        // legacy: stored is hex of SHA256(password)
        string legacy = aplicarHash(password);
        if (legacy == stored) {
            if (out_rehash) {
                string newhash;
                if (generar_hash_pbkdf2(password, newhash)) {
                    *out_rehash = newhash;
                }
            }
            return true;
        }
        return false;
    }
}

// (03/11/2026) Derivacion con sal impuesta por el servidor. La sal y las
// iteraciones no son secretas (viajan en SP_LOGIN_PARAMETROS); lo que se
// protege es el resultado almacenado, que solo el servidor puede comparar.
bool derivarClaveLogin(const string &password, const string &saltB64, int iter, string &outB64) {
    if (iter <= 0) return false;
    vector<unsigned char> salt = base64_decode(saltB64);
    if (salt.empty()) return false;

    const int DK_LEN = 32;
    vector<unsigned char> dk(DK_LEN);
    if (!PKCS5_PBKDF2_HMAC(password.c_str(), static_cast<int>(password.size()),
                           salt.data(), static_cast<int>(salt.size()),
                           iter, EVP_sha256(), DK_LEN, dk.data())) {
        return false;
    }
    outB64 = base64_encode(dk.data(), DK_LEN);
    return true;
}