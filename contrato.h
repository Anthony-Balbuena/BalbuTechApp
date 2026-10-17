#ifndef CONTRATO_H
#define CONTRATO_H

#include <string>

// Backend puro: junta los datos y rellena la plantilla. No depende de la consola.
// tipoContrato: "fijo" | "indefinido". duracionTexto solo aplica si es fijo.
std::string armarContrato(int idEmpleado, const std::string &tipoContrato,
                          const std::string &duracionTexto,
                          const std::string &dirEmpleado, const std::string &horario,
                          const std::string &horasSemanales, const std::string &formaPago);

// Escribe el HTML en contratos/ y devuelve la ruta. Unico punto que toca disco
// (al migrar a Qt se reemplaza por QPdfWriter).
std::string escribirContrato(const std::string &html,
                             const std::string &nombreEmpleado,
                             const std::string &fechaISO);

// Pantalla: pide datos, arma el contrato y lo abre en el navegador.
void ejecutarSubmenuContratos();

#endif
