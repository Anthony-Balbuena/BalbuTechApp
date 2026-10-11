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