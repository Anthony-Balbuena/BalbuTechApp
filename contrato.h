#ifndef CONTRATO_H
#define CONTRATO_H

#include <string>

// Datos de la persona para el documento. Se piden a mano al generar: la BD
// no interviene (el contrato se registra recien cuando la persona firma).
struct DatosPersonaContrato {
    std::string nombre;
    std::string cedula;
    std::string cargo;
    std::string salario;      // ya formateado con 2 decimales
    std::string telefono;
    std::string email;
    std::string fechaIngreso; // ISO YYYY-MM-DD
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

// Pantalla: pide los datos de la persona y genera el HTML (sin registrar nada
// en la BD).
void ejecutarSubmenuContratos();

// Pantalla: historial de contratos de un empleado (SP_CONTRATOS_POR_EMPLEADO).
void consultarContratosUI();

// Pantalla: pasa un contrato de ACTIVO a FINALIZADO (SP_FINALIZAR_CONTRATO).
void finalizarContratoUI();

// Pantalla: sube (registra) un contrato cuando la persona firma, a partir del
// .borrador que dejo la opcion 12. Si la cedula no existe en EMPLEADOS, el
// trigger TR_ALTA_EMPLEADO crea al empleado sola (alta directa).
void subirContratoUI();

#endif
