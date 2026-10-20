#ifndef CONTRATO_H
#define CONTRATO_H

#include <string>

// Datos de la persona para el documento. Al generar se pide la cedula y se
// consulta EMPLEADOS para precargar nombre/cargo; registrar en la BD sigue
// pasando recien cuando la persona firma (opcion 13).
struct DatosPersonaContrato {
    std::string nombre;
    std::string cedula;
    std::string cargo;
    std::string salario;         // salario impreso en el documento (el ofrecido)
    std::string salarioOfrecido; // mismo valor, como referencia en el .borrador
    std::string telefono;
    std::string email;
    std::string fechaIngreso;    // ISO YYYY-MM-DD
};

// Backend puro: junta los datos y rellena la plantilla. No depende de la
// consola. Solo lee CONFIGURACION (datos de la empresa); no consulta
// EMPLEADOS ni escribe en la BD.
// tipoContrato: "TEMPORAL" (con duracion) | "FIJO" (permanente). Nota: los
// TITULOS legales del HTML son al revés que la UI — la ley llama "termino
// fijo" al temporal y "termino indefinido" al permanente.
// duracionTexto solo aplica al temporal (ej. "1 año").
std::string armarContrato(const DatosPersonaContrato &persona,
                          const std::string &tipoContrato,
                          const std::string &duracionTexto,
                          const std::string &dirEmpleado, const std::string &horario,
                          const std::string &horasSemanales, const std::string &formaPago);

// Escribe el HTML en contratos/ y devuelve la ruta. Unico punto que toca disco
// (al migrar a Qt se reemplaza por QPdfWriter).
std::string escribirContrato(const std::string &html,
                             const std::string &nombrePersona,
                             const std::string &fechaISO);

// Pantalla: pide los datos del empleado (por cedula) y genera el HTML + el
// borrador (sin registrar nada en la BD).
void generarContratoUI();

// Pantalla: historial de contratos de un empleado (SP_CONTRATOS_POR_EMPLEADO).
void consultarContratosUI();

// Pantalla: pasa un contrato de ACTIVO a FINALIZADO (SP_FINALIZAR_CONTRATO).
void finalizarContratoUI();

// Pantalla: sube (registra) un contrato cuando la persona firma, a partir del
// .borrador que dejo la opcion 12. La cedula tiene que existir en EMPLEADOS:
// el contrato vincula, no crea empleados.
void subirContratoUI();

#endif
