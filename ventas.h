#ifndef VENTAS_H
#define VENTAS_H

// (22/10/2026) El menu se arma por permisos dentro de ventas.cpp: el orden y la
// cantidad de opciones dependen del rol, asi que no se declara aca.
void ejecutarSubmenuVentas();

// (15/11/2026) Barrido de borradores vacios (opcion D de P-4): cancela las
// ventas EN_PROCESO SIN lineas que pasaron el plazo de cobro. Se llama al
// entrar a la app. Nunca toca una venta con lineas.
void limpiarBorradoresVacios();

#endif
