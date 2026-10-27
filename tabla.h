#ifndef TABLA_H
#define TABLA_H

#include <cstddef>
#include <string>

#include "colores.h"

// (27/10/2026) Helpers para tablas de consola con celdas alineadas.
// printf cuenta bytes, no columnas: un acento UTF-8 ocupa 2 bytes y 1
// columna, asi que "CRÍTICO" desalinea la tabla. Estas funciones recortan y
// rellenan por code point para que los acentos se conserven y las columnas
// queden derechas.

inline size_t tablaAncho(const std::string &s) {
    size_t n = 0;
    for (size_t i = 0; i < s.size(); ) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c < 0x80) i += 1;
        else if ((c & 0xE0) == 0xC0) i += 2;
        else if ((c & 0xF0) == 0xE0) i += 3;
        else if ((c & 0xF8) == 0xF0) i += 4;
        else i += 1;
        ++n;
    }
    return n;
}

inline std::string tablaRecortar(const std::string &s, size_t maxCols) {
    std::string out;
    size_t cols = 0;
    for (size_t i = 0; i < s.size() && cols < maxCols; ) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t len = 1;
        if (c >= 0x80) {
            if ((c & 0xE0) == 0xC0) len = 2;
            else if ((c & 0xF0) == 0xE0) len = 3;
            else if ((c & 0xF8) == 0xF0) len = 4;
            if (i + len > s.size()) break;
        }
        out.append(s, i, len);
        i += len;
        ++cols;
    }
    return out;
}

inline std::string tablaCelda(const std::string &s, size_t width) {
    std::string out = tablaRecortar(s, width);
    size_t n = tablaAncho(out);
    if (n < width) out.append(width - n, ' ');
    return out;
}

inline std::string tablaLinea(size_t width) {
    return std::string(width, '-');
}

// Color por estado. Verde = activo/ok/recibida/realizada; amarillo =
// pendiente/en proceso/stock bajo/abierta; rojo = inactivo/cancelado/
// agotado/critico/rechazado. Un estado desconocido queda sin color.
inline const std::string &tablaColorEstado(const std::string &estado) {
    if (estado == "ACTIVO" || estado == "ACTIVA" || estado == "OK" ||
        estado == "REALIZADA" || estado == "RECIBIDA" ||
        estado == "APROBADO" || estado == "PAGADA") {
        return VERDE;
    }
    if (estado == "INACTIVO" || estado == "INACTIVA" ||
        estado == "CANCELADA" || estado == "CANCELADO" ||
        estado == "AGOTADO" || estado == "CRÍTICO" ||
        estado == "RECHAZADO" || estado == "ANULADA") {
        return ROJO;
    }
    if (estado == "EN_PROCESO" || estado == "PENDIENTE" ||
        estado == "STOCK BAJO" || estado == "ABIERTA" ||
        estado == "PARCIAL") {
        return AMARILLO;
    }
    return RESET;
}

#endif
