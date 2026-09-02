#ifndef SEGURIDAD_H
#define SEGURIDAD_H
using namespace std;
#include <string>
#include <exception>

// Excepción global para cancelar operaciones con 'xxx'
class CancelarOperacionException : public std::exception {
public:
    const char* what() const noexcept override {
        return "Operación cancelada. Regresando al menú principal...";
    }
};

// Prototipos de funciones de seguridad y entrada
string leerDatoSeguro(const std::string& mensaje);
string aplicarHash(const std::string& input);

// PBKDF2 helpers
// Genera un hash serializado con formato: pbkdf2$<iter>$<salt_b64>$<hash_b64>
bool generar_hash_pbkdf2(const std::string &password, std::string &out_serializado);

// Verifica la contraseña contra el valor almacenado. Si el valor almacenado
// es un hash legacy (SHA256 hex) y coincide, genera un nuevo hash PBKDF2 y 
// lo devuelve en `out_rehash` (si no es nullptr) para actualizar la BD.
bool verificarPassword(const std::string &password, const std::string &stored, std::string *out_rehash = nullptr);

#endif