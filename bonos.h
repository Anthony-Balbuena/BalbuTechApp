#ifndef BONOS_H
#define BONOS_H

// Modulo 14-BONOS_EMPLEADOS: pantalla de gestion de bonos.
//
// (18/11/2026) El modulo existia desde siempre pero no tenia pantalla: sus SP
// quedaron sin uso mientras TR_AUTO_FINALIZAR_VENTA (modulo 24) llenaba la tabla
// con el 1 % de cada venta cobrada. La viva llego a 11 bonos PENDIENTE por
// $10.330 que nadie podia ver ni pagar.
void gestionarBonosUI();

#endif
