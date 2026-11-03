#ifndef LOGIN_H
#define LOGIN_H

#include <string>

// (03/11/2026) Los umbrales del bloqueo por fuerza bruta viven ahora del lado
// del servidor (SP_LOGIN_AUTENTICAR: 5 fallos en 15 minutos). El cliente solo
// informa cuantos minutos faltan, asi que no hay dos fuentes de verdad.

// Devuelve true solo si el acceso fue concedido. Si la cuenta esta bloqueada,
// devuelve false y, cuando minutosBloqueo no es nullptr, deja ahi la espera
// estimada en minutos (0 cuando no hay bloqueo).
bool intentarLogin(const std::string& usuario, const std::string& password,
                   int* minutosBloqueo = nullptr);

#endif
