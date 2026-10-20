#ifndef SEGURIDAD_H
#define SEGURIDAD_H
using namespace std;
#include <string>
#include <vector>
#include <exception>

// Excepción global para cancelar operaciones con 'xxx'
class CancelarOperacionException : public exception {
public:
    const char* what() const noexcept override {
        return "Operación cancelada. Regresando al menú principal...";
    }
};

// Prototipos de funciones de seguridad y entrada
string leerDatoSeguro(const string& mensaje);

// (18/10/2026) Lee la opcion de un menu. Devuelve false si la entrada se
// agoto (EOF: Ctrl+D o pipe corto): el bucle del menu debe cortar, porque
// cin.clear() borra el flag pero NO el EOF del buffer, asi que el siguiente
// "cin >>" vuelve a fallar al instante (de ahi el bucle de "Opcion no valida").
// Si la lectura falla por otra razon, deja opcion = -1 (fuera de rango).
bool leerOpcionMenu(int &opcion);

// (15/10/2026) Entrada numerica con reintentos (hermana de leerDatoSeguro):
// pide un numero en [minimo, maximo] con hasta maxIntentos intentos; si el
// usuario cancela ('xxx') o se agotan los intentos lanza CancelarOperacionException.
// porDefecto (opcional): entrada vacia devuelve *porDefecto (casos "Enter = exacto").
constexpr int MAX_INTENTOS = 3;
bool esNumerico(const string& texto);
double leerNumeroConIntentos(const string& mensaje, double minimo, double maximo,
                             const double* porDefecto = nullptr,
                             int maxIntentos = MAX_INTENTOS);

// (16/10/2026) Formato "$" + valor igual que cout << double (prompts "Enter = $X").
string dinero(double v);

string aplicarHash(const string& input);

// Necesitarás implementar o incluir utilidades para Base64
// (09/10/2026) Se quitó base64_encode(buffer, size_t): no existía (la del
// .cpp es static con int); dejarla mentía al linker.
std::vector<unsigned char> base64_decode(const std::string& input);

// PBKDF2 helpers
// Genera un hash serializado con formato: pbkdf2$<iter>$<salt_b64>$<hash_b64>
bool generar_hash_pbkdf2(const string &password, string &out_serializado);

// Nombre solicitado por el snippet: verificar_password_pbkdf2
// (implementación delega a la función interna que soporta rehash-on-login)
bool verificar_password_pbkdf2(const string &password, const string &stored);

// Verifica la contraseña contra el valor almacenado. Si el valor almacenado
// es un hash legacy (SHA256 hex) y coincide, genera un nuevo hash PBKDF2 y 
// lo devuelve en `out_rehash` (si no es nullptr) para actualizar la BD.
bool verificarPassword(const string &password, const string &stored, string *out_rehash = nullptr);

#endif