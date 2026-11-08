#ifndef PAGINACION_H
#define PAGINACION_H

#include <cctype>
#include <functional>
#include <memory>
#include <string>
#include <vector>
#include <iostream>

#include <cppconn/prepared_statement.h>
#include <cppconn/resultset.h>

#include "database.h"
#include "seguridad.h"

// ---------------------------------------------------------------------------
// (08/11/2026) Paginacion generica de listados para la consola.
//
// Por que existe: las pantallas que listan para elegir un ID traian todas las
// filas de una. Con 50 o 200 registros eso es una pared de texto y obliga a
// traer todo de la base. Aca cada pantalla aporta sus dos consultas y como se
// dibuja una fila; la navegacion, el LIMIT/OFFSET y el COUNT los pone esto.
//
// De aca sale el mismo contrato que va a consumir Qt: pagina + total, con la
// consulta en un solo lugar. Ninguna pantalla arma el LIMIT a mano.
//
// Uso tipico (pantalla de consola):
//
//   ConsultaPaginada c{
//       "SELECT ID_CLIENTE, NOMBRE, ESTADO FROM CLIENTES ORDER BY ID_CLIENTE",
//       "SELECT COUNT(*) FROM CLIENTES",
//       {}
//   };
//   int total = mostrarPaginado(c, [&](sql::ResultSet *res) {
//       cout << tablaCelda(std::to_string(res->getInt("ID_CLIENTE")), W_ID) ...
//   });
//
// Con filtro, los dos SQL llevan el mismo WHERE y los valores van en
// `parametros`, en el mismo orden. Un solo juego de parametros para las dos
// consultas: si se agrega un WHERE a una hay que agregarlo a la otra.
// ---------------------------------------------------------------------------

struct ConsultaPaginada {
    std::string sqlFilas;                 // SELECT ... ORDER BY ... (sin LIMIT)
    std::string sqlTotal;                 // SELECT COUNT(*) ...
    std::vector<std::string> parametros;  // valores de los ? de ambos SQL
};

// Ejecuta el COUNT. Devuelve -1 si no pudo leerlo (la pantalla lo trata como 0).
inline int paginarTotal(const ConsultaPaginada &consulta) {
    std::unique_ptr<sql::PreparedStatement> pstmt(
        globalCon->prepareStatement(consulta.sqlTotal));
    for (size_t i = 0; i < consulta.parametros.size(); ++i) {
        pstmt->setString(static_cast<unsigned int>(i + 1), consulta.parametros[i]);
    }
    std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
    int total = -1;
    if (res->next()) total = res->getInt(1);
    res.reset();
    drenarResultados(pstmt.get());
    return total;
}

// Muestra una pagina: ejecuta sqlFilas + LIMIT/OFFSET y llama a `fila` por cada
// registro. Devuelve el total de registros de la pagina (0 si no hay).
inline int paginarFila(const ConsultaPaginada &consulta, int porPagina, int pagina,
                       const std::function<void(sql::ResultSet *)> &fila) {
    const int offset = (pagina - 1) * porPagina;

    std::unique_ptr<sql::PreparedStatement> pstmt(
        globalCon->prepareStatement(consulta.sqlFilas + " LIMIT ? OFFSET ?"));
    unsigned int n = 1;
    for (const std::string &valor : consulta.parametros) {
        pstmt->setString(n++, valor);
    }
    pstmt->setInt(n++, porPagina);
    pstmt->setInt(n++, offset);

    std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
    int vistos = 0;
    while (res->next()) {
        ++vistos;
        fila(res.get());
    }
    res.reset();
    drenarResultados(pstmt.get());
    return vistos;
}

// Recorre las paginas dibujando cada una con `dibujar` y ofreciendo
// siguiente/anterior. Vuelve cuando el usuario elige (Enter) para que la
// pantalla pida el ID. Devuelve el total de registros.
inline int navegarPaginas(int total, int porPagina,
                          const std::function<void(int pagina)> &dibujar) {
    if (porPagina < 1) porPagina = 10;
    if (total <= 0) return 0;

    const int paginas = (total + porPagina - 1) / porPagina;
    int pagina = 1;

    for (;;) {
        dibujar(pagina);

        std::cout << "\nPagina " << pagina << " de " << paginas
                  << "  (" << total << " registros)" << std::endl;
        if (paginas > 1) {
            std::cout << "[N] siguiente   [P] anterior   [Enter] elegir" << std::endl;
            std::string tecla = leerDatoSeguro("Opcion: ");
            if (!tecla.empty()) {
                const char c = static_cast<char>(
                    std::tolower(static_cast<unsigned char>(tecla[0])));
                if (c == 'n' && pagina < paginas) { ++pagina; continue; }
                if (c == 'p' && pagina > 1)       { --pagina; continue; }
                continue;  // tecla desconocida: redibuja la misma pagina
            }
        }
        break;
    }
    return total;
}

// Recorre las paginas de una consulta SELECT: dibuja una, ofrece
// siguiente/anterior y vuelve cuando el usuario elige (Enter). Devuelve el
// total de registros, para que quien llama sepa si hay algo o no.
inline int mostrarPaginado(const ConsultaPaginada &consulta,
                           const std::function<void(sql::ResultSet *)> &fila,
                           int porPagina = 10) {
    const int total = paginarTotal(consulta);
    return navegarPaginas(total, porPagina, [&](int pagina) {
        paginarFila(consulta, porPagina, pagina, fila);
    });
}

// ---------------------------------------------------------------------------
// (08/11/2026) Variante para listados que NO se pueden leer con SELECT directo
// porque el usuario de la app no tiene privilegios sobre la tabla (recorte de
// balbu_app del 03/11): la lectura pasa por SPs DEFINER con P_PAGINA y
// P_POR_PAGINA. Mismo contrato (pagina + total) y misma navegacion; lo unico
// que cambia es que el LIMIT vive dentro del procedimiento.
// ---------------------------------------------------------------------------

// Ejecuta el SP de conteo y devuelve el total (0 si no pudo leerlo).
inline int paginarTotalSP(const std::string &callTotal,
                          const std::vector<std::string> &filtros) {
    std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(callTotal));
    unsigned int n = 1;
    for (const std::string &valor : filtros) {
        pstmt->setString(n++, valor);
    }
    std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
    int total = 0;
    if (res->next()) total = res->getInt(1);
    res.reset();
    drenarResultados(pstmt.get());
    return total;
}

// Muestra una pagina llamando al SP: filtros, despues pagina y porPagina.
inline int paginarFilaSP(const std::string &callPagina,
                         const std::vector<std::string> &filtros,
                         int porPagina, int pagina,
                         const std::function<void(sql::ResultSet *)> &fila) {
    std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(callPagina));
    unsigned int n = 1;
    for (const std::string &valor : filtros) {
        pstmt->setString(n++, valor);
    }
    pstmt->setInt(n++, pagina);
    pstmt->setInt(n++, porPagina);

    std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
    int vistos = 0;
    while (res->next()) {
        ++vistos;
        fila(res.get());
    }
    res.reset();
    drenarResultados(pstmt.get());
    return vistos;
}

// Igual que mostrarPaginado, pero con SPs: recorre, navega y devuelve el total.
inline int mostrarPaginadoSP(const std::string &callPagina,
                             const std::string &callTotal,
                             const std::vector<std::string> &filtros,
                             const std::function<void(sql::ResultSet *)> &fila,
                             int porPagina = 10) {
    const int total = paginarTotalSP(callTotal, filtros);
    return navegarPaginas(total, porPagina, [&](int pagina) {
        paginarFilaSP(callPagina, filtros, porPagina, pagina, fila);
    });
}

// ---------------------------------------------------------------------------
// (08/11/2026) Variante con filtro ENTERO, para SPs del estilo
// SP_KARDEX_PAGINADO(P_ID_PRODUCTO, P_PAGINA, P_POR_PAGINA), donde 0 = todos.
// Las funciones de arriba solo saben bindear strings; aca el que llama arma el
// binding con un lambda y el paginador le agrega pagina y porPagina al final.
// ---------------------------------------------------------------------------
using BinderSP = std::function<void(sql::PreparedStatement *, unsigned int &)>;

inline int paginarTotalSPCon(const std::string &callTotal, const BinderSP &bind) {
    std::unique_ptr<sql::PreparedStatement> pstmt(globalCon->prepareStatement(callTotal));
    unsigned int n = 1;
    bind(pstmt.get(), n);
    std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
    int total = 0;
    if (res->next()) total = res->getInt(1);
    res.reset();
    drenarResultados(pstmt.get());
    return total;
}

inline int mostrarPaginadoSPCon(const std::string &callPagina,
                                const std::string &callTotal,
                                const BinderSP &bind,
                                const std::function<void(sql::ResultSet *)> &fila,
                                int porPagina = 10) {
    const int total = paginarTotalSPCon(callTotal, bind);
    return navegarPaginas(total, porPagina, [&](int pagina) {
        std::unique_ptr<sql::PreparedStatement> pstmt(
            globalCon->prepareStatement(callPagina));
        unsigned int n = 1;
        bind(pstmt.get(), n);
        pstmt->setInt(n++, pagina);
        pstmt->setInt(n++, porPagina);

        std::unique_ptr<sql::ResultSet> res(pstmt->executeQuery());
        while (res->next()) {
            fila(res.get());
        }
        res.reset();
        drenarResultados(pstmt.get());
    });
}

#endif
