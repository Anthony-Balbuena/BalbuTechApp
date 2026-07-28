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

#endif