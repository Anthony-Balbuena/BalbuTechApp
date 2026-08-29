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
        int subOpcion1 = 0;
        while (subOpcion1 != 7) {
            system("clear");
            mostrarMenuEmpleados();
            cout << "Seleccione: ";

            if (!(cin >> subOpcion1)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            if (subOpcion1 == 1) {
                registrarEmpleado();
            } else if (subOpcion1 == 2) {
                actualizarEmpleado();
            } else if (subOpcion1 == 3) {
                despedirEmpleado();
            } else if (subOpcion1 == 4) {
                reactivarEmpleado();
            } else if (subOpcion1 == 5) {
                buscarEmpleado();
            } else if (subOpcion1 == 6) {
                listarEmpleados();
            }

            if (subOpcion1 >= 1 && subOpcion1 <= 6) {
                cout << "\nPresione Enter para continuar...";
                cin.get();
            }
        }
        break;
    }

case 4:  { // MODULO CLIENTES
        int subOpcion4 = 0;
        while (subOpcion4 != 6) {
            system("clear");
            mostrarMenuClientes();
            cout << "Seleccione: ";

            if (!(cin >> subOpcion4)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            if (subOpcion4 == 1) {
                registrarCliente();
            } else if (subOpcion4 == 2) {
                actualizarCliente();
            } else if (subOpcion4 == 3) {
                cambiarEstadoCliente();
            } else if (subOpcion4 == 4) {
                buscarCliente();
            } else if (subOpcion4 == 5) {
                listarClientes();
            }

            if (subOpcion4 >= 1 && subOpcion4 <= 5) {
                cout << "\nPresione Enter para continuar...";
                cin.get();
            }
        }
        break;
    }

case 5: { // MODULO PROVEEDORES
        int subOpcion5 = 0;
        while (subOpcion5 != 6) {
            system("clear");
            mostrarMenuProveedores();
            cout << "Seleccione: ";

            if (!(cin >> subOpcion5)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            if (subOpcion5 == 1) {
                registrarProveedor();
            } else if (subOpcion5 == 2) {
                actualizarProveedor();
            } else if (subOpcion5 == 3) {
                cambiarEstadoProveedor();
            } else if (subOpcion5 == 4) {
                buscarProveedor();
            } else if (subOpcion5 == 5) {
                listarProveedores();
            }

            if (subOpcion5 >= 1 && subOpcion5 <= 5) {
                cout << "\nPresione Enter para continuar...";
                cin.get();
            }
        }
        break;
    }

case 6:  { // MODULO METODOS DE PAGOS
        int subOpcion6 = 0;
        while (subOpcion6 != 5) {
            system("clear");
            cout << "=== MODULO METODOS DE PAGOS ===" << endl;
            cout << "1. Agregar Metodo" << endl;
            cout << "2. Actualizar datos" << endl;
            cout << "3. Activar/Desactivar metodos" << endl;
            cout << "4. Buscar metodos" << endl;
            cout << "5. Volver al Menu Principal" << endl;
            cout << "===============================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";
            
            if (!(cin >> subOpcion6)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;             
            }

            // =========================================================================
            // 1. AGREGAR MÉTODO
            // =========================================================================
            if (subOpcion6 == 1) {
                cout << "--- REGISTRO DE METODOS ---\n";

                try {
                    string nombre = leerDatoSeguro("Nombre del metodo: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_METODO_PAGO (?)");
                    pstmt->setString(1, nombre);

                    string respuesta = Recogermensaje(pstmt);
                    cout << "\n>>> " << respuesta << " <<<\n";

                    delete pstmt;
                }       
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; // Aborta con 'xxx'
                }
                catch (const exception &e) {
                    cout << "\nERROR DE SISTEMA: " << e.what() << endl;
                }

                cout << "\nPresione enter para volver al menu....";
                cin.get();
            }   

            // =========================================================================
            // 2. ACTUALIZAR DATOS
            // =========================================================================
            else if (subOpcion6 == 2) {
                cout << "\n--- ACTUALIZAR DATOS DEL METODO DE PAGO ---" << endl;
                cout << "Nota: Deje en blanco los campos que NO desee cambiar." << endl;

                try {
                    string idStr = leerDatoSeguro("ID del metodo de pago a modificar (NUMERO): ");
                    int id_metodo = stoi(idStr);

                    string nombre = leerDatoSeguro("Nuevo nombre: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_METODO_PAGO (?,?)");
                    pstmt->setInt(1, id_metodo);

                    if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, nombre);

                    string respuesta = Recogermensaje(pstmt);
                    
                    cout << "\n========================================" << endl;
                    cout << "  " << respuesta << endl;
                    cout << "========================================" << endl;

                    delete pstmt;
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n[!] Error en el proceso: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menu....";
                cin.get();
            }

            // =========================================================================
            // 3. ACTIVAR / DESACTIVAR MÉTODOS
            // =========================================================================
            else if (subOpcion6 == 3) {
                cout << "\n --- ACTIVAR / DESACTIVAR MÉTODO DE PAGO ---" << endl;

                try {
                    string idStr = leerDatoSeguro("Ingrese el ID del método de pago (NÚMERO): ");
                    int id_metodo = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_METODO_PAGO(?)");
                    pstmt->setInt(1, id_metodo);

                    string respuesta = Recogermensaje(pstmt);

                    cout << "\n--------------------------------------------";
                    cout << "\n>>> " << respuesta << " <<<";
                    cout << "\n--------------------------------------------" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE SISTEMA: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }

            // =========================================================================
            // 4. BUSCAR MÉTODOS
            // =========================================================================
            else if (subOpcion6 == 4) {
                cout << "\n --- BUSCAR METODOS DE PAGO ---" << endl;

                try {
                    string busqueda = leerDatoSeguro("Ingrese NOMBRE del metodo o Presione Enter para ver todos: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_METODOS_PAGO(?)");
                    pstmt->setString(1, busqueda);
                    
                    sql::ResultSet *res = pstmt->executeQuery();

                    cout << "\n" << string(50, '-') << endl;
                    printf("%-8s | %-35s\n", "ID", "METODO DE PAGO");
                    cout << string(50, '-') << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-8d | %-35s\n", 
                               res->getInt("ID_METODO_PAGO"), 
                               res->getString("NOMBRE").c_str());
                    } 

                    if (!encontrado) {
                        cout << "\n [!] No se hallaron resultados con: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
                    }
                    cout << string(50, '-') << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE DB: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }                     
        } // Cierra el while
        break;
    } // Cierra el case 6


case 7: { // MODULO ROLES
        int subOpcion7 = 0;
        while (subOpcion7 != 4) {
            system("clear");
            cout << "=== MODULO DE ROLES ===" << endl;
            cout << "1. Agregar Roles" << endl;
            cout << "2. Actualizar Datos" << endl;
            cout << "3. Buscar Roles" << endl;
            cout << "4. Volver al Menu Principal" << endl;
            cout << "=======================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";
            
            if (!(cin >> subOpcion7)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            // =========================================================================
            // 1. AGREGAR ROLES
            // =========================================================================
            if (subOpcion7 == 1) {
                cout << "\n--- REGISTRO DE ROLES ---" << endl;

                try {
                    string nombre_rol = leerDatoSeguro("Nombre del ROL: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_ROL(?)");
                    pstmt->setString(1, nombre_rol);
                    
                    string respuesta = Recogermensaje(pstmt);
                    
                    cout << "\n--------------------------------------------";
                    cout << "\n>>> " << respuesta << " <<<";
                    cout << "\n--------------------------------------------" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; // Aborta de golpe con 'xxx'
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE SISTEMA: " << e.what() << endl;
                }
                
                cout << "\nPresione Enter para volver al menú...";
                cin.get(); 
            }

            // =========================================================================
            // 2. ACTUALIZAR DATOS
            // =========================================================================
            else if (subOpcion7 == 2) {
                cout << "\n--- ACTUALIZAR DATOS DE ROL ---" << endl;
                cout << "Nota: Deje en blanco si no desea cambiar el nombre." << endl;

                try {
                    string idStr = leerDatoSeguro("ID del rol a modificar (NUMERO): ");
                    int id_rol = stoi(idStr);

                    string nombre = leerDatoSeguro("Nuevo nombre del rol: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_ROL(?, ?)");
                    pstmt->setInt(1, id_rol);

                    if (nombre.empty()) {
                        pstmt->setNull(2, sql::DataType::VARCHAR);
                    } else {
                        pstmt->setString(2, nombre);
                    }

                    string respuesta = Recogermensaje(pstmt);

                    cout << "\n========================================" << endl;
                    cout << "  " << respuesta << endl;
                    cout << "========================================" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE SISTEMA: " << e.what() << endl;
                }
                
                cout << "\nPresione Enter para volver al menú...";
                cin.get();
            }

            // =========================================================================
            // 3. BUSCAR ROLES
            // =========================================================================
            else if (subOpcion7 == 3) {
                cout << "\n --- BUSCAR ROLES ---" << endl;

                try {
                    string busqueda = leerDatoSeguro("Ingrese nombre del rol o Enter para ver todos: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_ROLES(?)");
                    pstmt->setString(1, busqueda);

                    sql::ResultSet *res = pstmt->executeQuery();

                    string separator = string(50, '-');
                    cout << "\n" << separator << endl;
                    printf("%-5s | %-30s\n", "ID", "NOMBRE DEL ROL");
                    cout << separator << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-5d | %-30.30s\n", 
                               res->getInt("ID_ROL"), 
                               res->getString("NOMBRE_ROL").c_str());
                    }

                    if (!encontrado) {
                        cout << "\n [!] No se hallaron roles con el filtro: [" << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
                    }
                    cout << separator << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE DB: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }
            
        } // Cierra el while
        break; 
    } // Cierra el case 7

case 8: { // MODULO PRODUCTOS
        int subOpcion8 = 0;
        while (subOpcion8 != 7) {
            system("clear");
            mostrarMenuProductos();
            cout << "Seleccione: ";

            if (!(cin >> subOpcion8)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            if (subOpcion8 == 1) {
                registrarProducto();
            }
            else if (subOpcion8 == 2) {
                actualizarProducto();
            }
            else if (subOpcion8 == 3) {
                cambiarEstadoProducto();
            }
            else if (subOpcion8 == 4) {
                buscarProducto();
            }
            else if (subOpcion8 == 5) {
                consultarInventario();
            }
            else if (subOpcion8 == 6) {
                reporteStockCritico();
            }
            else if (subOpcion8 == 7) {
                cout << "Volviendo al menu principal..." << endl;
            }

            if (subOpcion8 >= 1 && subOpcion8 <= 6) {
                cout << "\nPresione Enter para continuar...";
                cin.get();
            }
        }
        break;
    }

case 9: { //MODULO USUARIOS
   int subOpcion9 =0;
   while (subOpcion9 != 6) {
   system("clear");
   cout << "=== MODULO DE USUARIOS ===" << endl;
   cout << "1. Agregar Usuario"<< endl;
   cout << "2. Actualizar Usuario"<< endl;
   cout << "3. Cambiar Estado del Usuario"<< endl;
   cout << "4. Buscar Usuario"<< endl;
   cout << "5. Cambiar Clave"<< endl;
   cout << "6. Volver al Menu Principal"<< endl;
   cout << "==================================="<< endl;
   cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
   cout << "Seleccione: ";
// Limpia el bullfer del while
   if (!(cin >> subOpcion9)) {
   cin.clear();
   cin.ignore(1000, '\n');
   continue;
   }


// =========================================================================
// 1. INSERTAR USUARIO
// =========================================================================
if (subOpcion9 == 1) {
    cout << "\n --- REGISTRO DE USUARIO ---" << endl;

try {
 //1. Preparar y ejecutar la lalmada del (SP)   
sql:: PreparedStatement *pstmt = globalCon ->prepareStatement("CALL PARA_INSERTAR_USUARIOS()");
bool results = pstmt ->execute();
// Resultaods del primer select los roles
if (results) {
    sql:: ResultSet *res = pstmt ->getResultSet();

    cout << CIAN << "\n--- ROLES DISPONIBLES ---\n" << RESET;
    while (res -> next()) {
        cout << CIAN << "| ID: " << RESET << res -> getInt("ID_ROL") 
             << CIAN <<" | Nombre_rol: " << RESET << res ->getString ("NOMBRE_ROL") << endl;
    }
    delete res;
}
//Resultados del segundo select 
if (pstmt -> getMoreResults()) {

    sql :: ResultSet *res = pstmt ->getResultSet();

    cout << CIAN << "\n--- EMPLEADOS DISPONIBLES ---\n" << RESET;
    while (res -> next()) {
    cout << CIAN << "| ID_EMPLEADO: " << RESET << res ->getInt("ID_EMPLEADO")
         << CIAN << "| NOMBRE_EMPLEADO: " << RESET << res -> getString("NOMBRE") << endl;
    }
    delete res; // LIBERAR MEMORIA DEL SEGUNDO RESULTADO
}
 // LIMPIAR EL PUNTERO DEL PreparedStatement
 delete  pstmt;
} catch (sql::SQLException &e) {
    cerr << ROJO << "Error al mostrar las listas: " << RESET << e.what() << endl;
}

    try {
        string nombre = leerDatoSeguro("\nNombre del Usuario (Se creara automaticamente): ");
        string clavePlana  = leerDatoSeguro("Clave: ");

        // 1. APLICAR HASH A LA CONTRASEÑA AQUÍ
        string claveHash = aplicarHash(clavePlana); // Asegúrate de usar el nombre de tu función de seguridad

        string idRolStr = leerDatoSeguro("ID del rol (Numero): ");
        int id_rol = stoi(idRolStr);

        string idEmpStr = leerDatoSeguro("ID del empleado (NUMERO): ");
        int id_empleado = stoi(idEmpStr);

        // El orden debe ser: P_ID_EMPLEADO, P_ID_ROL, P_USUARIO, P_CONTRASENA
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_USUARIO(?, ?, ?, ?)");
        
        pstmt->setInt(1, id_empleado);
        pstmt->setInt(2, id_rol);
        pstmt->setString(3, nombre);
        pstmt->setString(4, claveHash); // 2. ENVIAR LA CLAVE HASHEADA EN VEZ DE LA PLANA

        // Recogermensaje procesa el SELECT que devuelve el SP
        string respuesta = Recogermensaje(pstmt);

        cout << "\n--------------------------------------------";
        cout << "\n>>> " << respuesta << " <<<";
        cout << "\n--------------------------------------------" << endl;

        delete pstmt;

    } catch (const CancelarOperacionException &e) {
        cout << "\n [!]" << e.what() << endl;
    } catch (const invalid_argument &e) {
        cout << "\n [!] Error: Formato numerico invalido en los campos ID." << endl; 
    } catch (const exception &e) {
        cout << "\n [!] ERROR: " << e.what() << endl;
    }

    cout << "\n Presione Enter para volver al menu....";
    //cin.ignore();
    cin.get();
}
// =========================================================================
// 2. ACTUALIZAR DATOS
// =========================================================================
else if (subOpcion9 == 2) {
    cout << "\n--- ACTUALIZAR DATOS DE USUARIO ---" << endl;

    try {
    // Preparar y ejecutar la llamada del procedimiento
    sql::PreparedStatement *pstmt = globalCon ->prepareStatement("CALL PARA_ACTUALIZAR_USUARIOS()");
    bool results = pstmt ->execute();

    //Procesar los datos del SP DEL JOIN
    if (results) {
    
        //Llamada al sql
        sql::ResultSet *res= pstmt ->getResultSet();
        cout << CIAN << "\n--- LISTADO GENERAL DE PRODUCTOS, ROLES Y EMPLEADOS\n" << RESET;

        while (res->next()) {
        cout << CIAN <<"\n| ID USUARIO: " << RESET << res -> getInt("ID_USUARIO")
             << CIAN <<"\n| NOMBRE DEL USUARIO: " << RESET << res -> getString("NOMBRE_USUARIO")
             << CIAN <<"\n| ID ROL: " << RESET << res-> getInt("ID_ROL")
             << CIAN <<"\n| NOMBRE ROL: " << RESET << res -> getString("NOMBRE_ROL")
             << CIAN <<"\n| ID EMPLEADO: " << RESET << res-> getInt("ID_EMPLEADO")
             << CIAN <<"\n| Nombre EMPLEADO: " << RESET << res -> getString("NOMBRE_EMPLEADO") << endl;
        } 
        delete res; // Liberar memoria del resultado 
    }
      delete pstmt; // Limpiar el puntero del PreparedStatement

    } catch (sql::SQLException &e)  {
       cerr << ROJO << "Error al mostrar las listas: " << RESET << e.what() << endl;   
    }

    
    try {
        string idStr = leerDatoSeguro("\nID del Usuario a Modificar (NUMERO): ");
        int id_usuario = stoi(idStr);

        cout << "\nNota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
        string nuevo_usuario = leerDatoSeguro("Nuevo nombre de Usuario (Enter para omitir): ");
        string id_rol_str    = leerDatoSeguro("Nuevo ID Rol (Enter para omitir): ");
        string id_emp_str    = leerDatoSeguro("Nuevo ID Empleado (Enter para omitir): ");

        // Ajustado a 4 parámetros: P_ID_USUARIO, P_USUARIO, P_ID_ROL, P_ID_EMPLEADO
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_USUARIO(?, ?, ?, ?)");
        
        // 1. ID de usuario (Obligatorio)
        pstmt->setInt(1, id_usuario);

        // 2. Nuevo nombre de usuario
        if (nuevo_usuario.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
        else pstmt->setString(2, nuevo_usuario);

        // 3. Nuevo ID de rol
        if (id_rol_str.empty()) pstmt->setNull(3, sql::DataType::INTEGER);
        else pstmt->setInt(3, stoi(id_rol_str));

        // 4. Nuevo ID de empleado
        if (id_emp_str.empty()) pstmt->setNull(4, sql::DataType::INTEGER);
        else pstmt->setInt(4, stoi(id_emp_str));

        string respuesta = Recogermensaje(pstmt);
        cout << "\n--------------------------------------------";
        cout << "\n>>> " << respuesta << " <<<";
        cout << "\n--------------------------------------------" << endl;

        delete pstmt;
    } 
    catch (const CancelarOperacionException &e) {
        cout << "\n [!]" << e.what() << endl;
    } catch (const invalid_argument &e) {
        cout << "\n [!] Error: Formato numerico invalido en los campos ID." << endl; 
    } catch (const exception &e) {
        cout << "\n[!] ERROR: " << e.what() << endl;
    }

    cout << "\nPresione Enter para continuar...";
    //cin.ignore(); 
    cin.get();
}
// =========================================================================
// 3. CAMBIAR ESTADO
// =========================================================================
else if (subOpcion9 == 3) {

 cout << "--- DESACTIVAR/ACTIVAR ESTADO DEL  USUARIO --- "  << endl;

try {

//1. Preparar y ejecutar la llamada del sp para ver el estado de los usuarios
sql :: PreparedStatement *pstmt = globalCon -> prepareStatement("CALL PARA_ACT_DESAC_USUARIOS()");

bool results = pstmt -> execute();

//2. Procesar el conjunto de resultados que devuelve el join

if (results) {
    sql :: ResultSet *res= pstmt -> getResultSet();

    cout << CIAN << "\n--- LISTADO DE LOS USUARIOS, SU ESTADO Y EL NOBRE DE SU EMPLEADO ---\n" << RESET << endl;
    // el while maneja la captura de los datos
    while (res -> next()) {
        
     cout << CIAN << "\n| ID Usuario: " << RESET << res -> getInt("ID_USUARIO")
          << CIAN << "\n| Nombre: "      << RESET << res -> getString("USUARIO")              
          << CIAN << "\n| Estado: " << RESET << res -> getString("ESTADO") 
          << CIAN << "\n| Empleado: " << RESET << res -> getString("EMPLEADO") << endl;
    }
    // libera memoria del resultado
    delete res;
}
delete pstmt; // limpia el puntero del preparestatement
} catch (sql:: SQLException &e) {
   cerr << ROJO << "Error al mostrar la lista: " << RESET << e.what() << endl;

}

try {
string idStr = leerDatoSeguro("\nIngrese el ID del usuario (NUMERO): ");
int id_usuario = stoi(idStr);

sql:: PreparedStatement *pstmt = globalCon -> prepareStatement(" CALL SP_TOGGLE_ESTADO_USUARIO (?)");
 pstmt -> setInt(1,id_usuario);

 string respuesta = Recogermensaje(pstmt);

cout << "\n-----------------------------------------------";
cout << "\n>>> " << respuesta << " <<<";
cout << "-------------------------------------------------";

delete pstmt;

} catch (const CancelarOperacionException &e) {
          cout << "\n[!]" << e.what() << endl;
}

catch (const invalid_argument&) {
          cout <<"\n[!] Error: EL ID debe de ser un numero entero" << endl;
}

catch (const exception &e) {
   cout <<"\n [!] ERRROR DE BASE DE DATOS: "<< e.what() << endl;
}          
cout <<"\nPresione Enter para volver al menu....";
cin.get();

}// Cierra opcion 3 
//==========================================================================
//4. CONSULTAR USUARIOS
//==========================================================================
else if (subOpcion9 == 4) {

cout << "\n--- BUSCAR USUARIO ---" <<endl;

try {
string busqueda = leerDatoSeguro("Ingrese Nombre del Usuario (Enter para ver todos): ");


sql ::PreparedStatement *pstmt =globalCon ->prepareStatement(" CALL SP_BUSCAR_USUARIOS_FILTRADO (?)" );
pstmt ->setString(1, busqueda);

sql :: ResultSet *res= pstmt ->executeQuery();

string separator = string (75, '_');
cout << "\n" << separator << endl;
printf("%-5s | %-20s | %-20s | %-15s | %-10s\n", "ID", "USUARIO", "EMPLEADO", "ROL", "ESTADO");
cout << separator << endl;

bool encontrado = false;
while (res->next()) {
    encontrado = true;
    printf("%-5d | %-20.20s | %-20.20s | %-15.15s | %-10.10s\n",
            res->getInt(1),                    // ID_USUARIO
            res->getString(2).c_str(),         // USUARIO
            res->getString(3).c_str(),         // EMPLEADO
            res->getString(4).c_str(),         // ROL
            res->getString(5).c_str()          // ESTADO
    );


} 
if (!encontrado) {
      cout << "\n [!] No se encontraron usuarios  con el filtro : [ "
        << (busqueda.empty() ? "TODOS" : busqueda ) << "]" << endl;
}
cout << separator << endl;

delete res;
delete pstmt;


} catch (const CancelarOperacionException &e) {
     cout <<"\n [!] " << e.what() << endl;
}


 catch (const exception &e) {
         cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
                }

          cout << "\nPresione Enter para continuar...";
                cin.get();
 } // CIERRA OPCION 4

//==========================================================================
//5. CAMBIAR CLAVE
//==========================================================================

else if (subOpcion9 == 5) {

   cout << "\n--- CAMBIAR CLAVE DEL USUARIO ---" << endl;
 
   try {
       string idStr = leerDatoSeguro("ID del Usuario a Modificar la clave (NUMERO): ");
       int id_usuario = stoi(idStr);
     
       string clave_actual_plana = leerDatoSeguro("Ingrese su clave actual: ");
       cout << "Espere......" << endl;
       string clave_nueva_plana = leerDatoSeguro("Ingrese Su nueva clave: ");

       // APLICAR HASH A AMBAS CLAVES ANTES DE ENVIARLAS AL SP
       string clave_actual_hash = aplicarHash(clave_actual_plana);
       string clave_nueva_hash  = aplicarHash(clave_nueva_plana);

       // LLAMADA A SQL PARA USAR EL PROCEDURE (Asegúrate de que tu SP reciba los hashes)
       sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CAMBIAR_CONTRASENA(?, ?, ?)");

       // 1. ID del usuario (OBLIGATORIO)
       pstmt->setInt(1, id_usuario);

       // 2. LA CLAVE ACTUAL (YA HASHEADA)
       pstmt->setString(2, clave_actual_hash);

       // 3. NUEVA CLAVE (YA HASHEADA)
       pstmt->setString(3, clave_nueva_hash);

       string respuesta = Recogermensaje(pstmt);
       cout << "\n-----------------------------------------";
       cout << "\n>>> " << respuesta << " <<<";
       cout << "\n-----------------------------------------" << endl;

       delete pstmt;
   } 
   catch (const CancelarOperacionException &e) {
       cout << "\n [!] " << e.what() << endl;
   }
   catch (const invalid_argument &e){
       cout << "\n [!] Error: Formato numerico invalido en los campos ID." << endl;
   }
   catch (const exception &e){
       cout << "\n [!] ERROR: " << e.what() << endl;
   }
 
   cout << "\n Presione ENTER para continuar....";
   cin.ignore();
   cin.get();      
}
   } //CIERRA OPCION 5

} //CIERRA EL CASE 9

break;

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