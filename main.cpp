#include <exception>
#include <iostream>
#include <ostream>
#include <stdexcept>
#include <string>
#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>
#include <cppconn/prepared_statement.h>
//#include <iomanip>
//#include <vector>

// Tus archivos de cabecera personalizados
#include "database.h"
#include "seguridad.h"
#include "colores.h"
#include "empleados.h"
#include "clientes.h"
#include "proveedores.h"
#include "productos.h"
#include "metodos_pago.h"
#include "roles.h"
#include "usuarios.h"

using namespace std;


// =========================================================================
// PROGRAMA PRINCIPAL
// ========================================================================
int main() {
    inicializarConexion();
if (globalCon != nullptr) {
    cout << MAGENTA<<  "¡Conexión exitosa a BALBU_TECH!"<<  RESET <<   endl;
}
        
        int opcionPrincipal = 0; // Inicializar variable

        // --- 1. ESTE BUCLE ES EL QUE ARREGLA EL ERROR DEL CONTINUE ---
        while (opcionPrincipal != 11) { 
            // system("clear"); // Opcional: para que el menú siempre salga arriba
            
            cout <<  VERDE<<"\n----------------------------------------" << RESET << endl;
            cout << VERDE << "     Selecione la opcion a realizar: " << RESET << endl;
            cout << VERDE << "----------------------------------------"<< RESET<< endl;
            cout <<AZUL << "1. --- EMPLEADOS ---" << RESET <<endl;
            cout << "2. --- CATEGORIA ---" << endl;
            cout << "3. --- MARCA ---" << endl;
            cout << "4. --- CLIENTE ---" << endl;
            cout << "5. --- PROVEEDORES ---" << endl;
            cout << "6. --- METODOS DE PAGO ---" << endl;
            cout << "7. --- ROLES ---" << endl;
            cout << "8. --- PRODUCTOS ---" << endl;
            cout << "9. --- USUARIOS ---" << endl;
            cout << "10. --- BONO ---" << endl;
            cout << "11. Salir" << endl;

            cout << "--- Opcion --- : ";
            
            // Si el usuario mete una letra, cin falla. 
            // El 'continue' ahora sí sabe que debe volver al inicio del 'while'.
            if (!(cin >> opcionPrincipal)) { 
                cin.clear(); 
                cin.ignore(1000, '\n'); 
                cout << "\n[!] Error: Ingrese un número válido." << endl;
                continue; 
            }
    switch (opcionPrincipal) {

case 1:  { // MODULO DE EMPLEADOS
        
    }

case 4:  { // MODULO CLIENTES
        ;
    }

case 5: { // MODULO PROVEEDORES
        
    }

case 6:  { // MODULO METODOS DE PAGO
        
    }

case 7: { // MODULO ROLES
      
    }

case 8: { // MODULO PRODUCTOS
      
    }

case 9: { // MODULO USUARIOS
      
    }

case 10: { // MODULO

} //CIERRA EL CASE 10










/* PARA Salir del programa hcrear una opcion de salida llamada case como mi proyecto en (C)
case 5:
                printf("\nGuardando datos y saliendo del programa...\n");
                guardarEnArchivo(lista, total);
                break;*/

default: 
            cout << ROJO << "Opción no válida." << RESET<< endl;
            break;
        } // <--- AQUÍ CIERRA EL SWITCH PRINCIPAL

    } // <--- ¡ESTA ES LA QUE TE FALTA! Cierra el bucle WHILE (opcionPrincipal != 11)

    //delete con;  // Se borra la conexión SOLO cuando el usuario decide salir (opción 11)

     
   // else {
      //  cout << "No se pudo conectar a BALBU_TECH." << endl;
   // } 

    return 0;
}

//./programa_db