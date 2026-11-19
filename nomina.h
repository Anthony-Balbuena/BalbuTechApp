#ifndef NOMINA_H
#define NOMINA_H

// (18/11/2026) Nomina: recibo del mes y pago de los bonos incluidos.
//
// Por que existe: el modulo 14 carga bonos solos (el 1 % de cada venta cobrada,
// via TR_AUTO_FINALIZAR_VENTA) y SP_GENERAR_RECIBO_EMPLEADO existia sin un solo
// llamador y sin leer BONOS_EMPLEADOS. La decision del dueno es que el bono
// integra el sueldo del mes: el recibo lo muestra y el pago lo marca con fecha y
// usuario. Sin esta pantalla los bonos se podian listar pero no cobrar.
void gestionarNominaUI();

#endif
