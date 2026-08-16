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

using namespace std;


// =========================================================================
// PROGRAMA PRINCIPAL
// ========================================================================
int main() {
    inicializarConexion();
if (globalCon != nullptr) {
    cout << MAGENTA<<  "¡Conexión exitosa a BALBU_TECH!"<<  RESET <<   endl;
}
        
       sql::Statement *stmt = globalCon->createStatement();
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

case 1:  { // MÓDULO DE EMPLEADOS
        int subOpcion1 = 0;
        while (subOpcion1 != 9) { 
            system("clear");
            cout << "=== MODULO DE EMPLEADOS ===" << endl;
            cout << "1. Agregar Empleado " << endl;
            cout << "2. Actualizar Datos " << endl;
            cout << "3. Despedir Empleado " << endl;
            cout << "4. Reactivar" << endl;
            cout << "5. Generar recibo " << endl;
            cout << "6. Buscar empleado " << endl;
            cout << "7. Aumento por cargo" << endl;
            cout << "8. Aniversario en la empresa" << endl; // Corregido typo "Universario"
            cout << "9. Volver al Menu Principal" << endl;
            cout << "===========================" << endl;
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";

            if (!(cin >> subOpcion1)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            // =========================================================================
            // 1. AGREGAR EMPLEADO
            // =========================================================================
            if (subOpcion1 == 1) {
                cout << "\n--- REGISTRO DE EMPLEADO ---" << endl;
                
                try {
                    // Usamos la función global de lectura segura
                    string nombre   = leerDatoSeguro("Nombre Completo: ");
                    string cedula   = leerDatoSeguro("Cédula: ");
                    string cargo    = leerDatoSeguro("Cargo: ");
                    string salStr   = leerDatoSeguro("Salario: ");
                    double salario  = stod(salStr); // Convierte string a double
                    string telefono = leerDatoSeguro("Teléfono: ");
                    string email    = leerDatoSeguro("Email: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_EMPLEADO(?, ?, ?, ?, ?, ?)");
                    pstmt->setString(1, nombre);
                    pstmt->setString(2, cedula);
                    pstmt->setString(3, cargo);
                    pstmt->setDouble(4, salario);
                    pstmt->setString(5, telefono);
                    pstmt->setString(6, email);

                    pstmt->execute();
                    cout << "\n¡Empleado '" << nombre << "' guardado con éxito!" << endl;
                    delete pstmt;

                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; // Cae aquí si escribe 'xxx'
                } 
                catch (const exception &e) {
                    cout << "\nError en el proceso: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }

            // =========================================================================
            // 2. ACTUALIZAR DATOS
            // =========================================================================
            else if(subOpcion1 == 2) {
                cout << "\n --- ACTUALIZAR DATOS ---" << endl;
                cout << "Nota: Deje en blanco los campos que NO desee cambiar." << endl;

                try {
                    string idStr    = leerDatoSeguro("ID del empleado (NUMERO): ");
                    int id_empleado = stoi(idStr);
                    
                    string nombre   = leerDatoSeguro("Nombre completo: ");
                    string cedula   = leerDatoSeguro("Cedula: ");
                    string email    = leerDatoSeguro("Email: ");
                    string cargo    = leerDatoSeguro("Cargo: ");
                    string telefono = leerDatoSeguro("Telefono: ");
                    
                    string salStr   = leerDatoSeguro("Salario (0 para no cambiar): ");
                    double salario  = salStr.empty() ? 0 : stod(salStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_EMPLEADO(?, ?, ?, ?, ?, ?, ?)");
                    pstmt->setInt(1, id_empleado);
                    
                    if(nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, nombre);

                    if(cedula.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
                    else pstmt->setString(3, cedula);

                    if(email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR);
                    else pstmt->setString(4, email);

                    if(cargo.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
                    else pstmt->setString(5, cargo);

                    if(telefono.empty()) pstmt->setNull(6, sql::DataType::VARCHAR);
                    else pstmt->setString(6, telefono);

                    if(salario <= 0) pstmt->setNull(7, sql::DataType::DOUBLE);
                    else pstmt->setDouble(7, salario);

                    pstmt->execute();
                    cout << "\n¡Proceso de actualización completado para el ID: " << id_empleado << "!" << endl;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                } 
                catch (const exception &e) {
                    cout << "\nError al actualizar en BALBU_TECH: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menú...";
                cin.get();
            }

            // =========================================================================
            // 3. DESPEDIR EMPLEADO
            // =========================================================================
            else if (subOpcion1 == 3) { 
                cout << "\n --- DESPEDIR EMPLEADO ---" << endl;

                try {
                    string idStr    = leerDatoSeguro("ID del empleado (NUMERO): ");
                    int id_empleado = stoi(idStr);
                    
                    string fechadespido = leerDatoSeguro("Ingrese fecha (YYYY-MM-DD) o presione ENTER para hoy: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_DESPEDIR_EMPLEADO(?, ?)");
                    pstmt->setInt(1, id_empleado);

                    if (fechadespido.empty()) {
                        pstmt->setNull(2, sql::DataType::DATE); 
                    } else {
                        pstmt->setString(2, fechadespido);
                    }

                    pstmt->execute();
                    cout << "\n¡Empleado ID " << id_empleado << " dado de baja con éxito!" << endl;
                    delete pstmt;
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError del Sistema: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 4. REACTIVAR EMPLEADO
            // =========================================================================
            else if (subOpcion1 == 4) { 
                cout << "\n--- REACTIVAR EMPLEADO ---" << endl;
                
                try {
                    string idStr       = leerDatoSeguro("ID del empleado (NUMERO): ");
                    int id_empleado    = stoi(idStr);
                    
                    string salStr      = leerDatoSeguro("Nuevo Salario para la reactivacion: ");
                    double nuevoSalario = stod(salStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_REACTIVAR_EMPLEADO(?, ?)");
                    pstmt->setInt(1, id_empleado);
                    
                    // Usamos Recogermensaje pasándole el statement preparado
                    cout << "\n[+] " << Recogermensaje(pstmt) << endl;
                    delete pstmt;
                }      
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError al reactivar: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 5. GENERAR RECIBO
            // =========================================================================
            else if (subOpcion1 == 5) { 
                cout << "\n --- GENERAR RECIBO ---" << endl;
                
                try {
                    string idStr    = leerDatoSeguro("ID del empleado (NUMERO): ");
                    int id_empleado = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_GENERAR_RECIBO_EMPLEADO(?)");
                    pstmt->setInt(1, id_empleado);

                    sql::ResultSet *res = pstmt->executeQuery();

                    if (res->next()) {
                        cout << "\n================================================" << endl;
                        cout << "       " << res->getString("EMPRESA") << endl;
                        cout << "================================================" << endl;
                        cout << " ID EMPLEADO:   " << res->getInt("ID_EMPLEADO") << endl;
                        cout << " NOMBRE:        " << res->getString("NOMBRE") << endl;
                        cout << " CEDULA:        " << res->getString("CEDULA") << endl;
                        cout << " CARGO:         " << res->getString("CARGO") << endl;
                        cout << "------------------------------------------------" << endl;
                        cout << " SUELDO BRUTO:  $" << res->getDouble("SUELDO_BRUTO") << endl;
                        cout << " DESC. SFS:     -$" << res->getDouble("DESCUENTO_SFS") << endl;
                        cout << " DESC. AFP:     -$" << res->getDouble("DESCUENTO_AFP") << endl;
                        cout << "------------------------------------------------" << endl;
                        cout << " SUELDO NETO:   $" << res->getDouble("SUELDO_NETO") << endl; 
                        cout << "------------------------------------------------" << endl;
                        cout << " FECHA EMISION: " << res->getString("FECHA_EMISION") << endl;
                        cout << "================================================" << endl;
                    }
                    delete res;
                    delete pstmt; 
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError del Sistema: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 6. BUSCAR EMPLEADO
            // =========================================================================
            else if (subOpcion1 == 6) { 
                cout << "\n --- BUSCAR EMPLEADO EN BALBU_TECH ---" << endl;
                
                try {
                    string termino = leerDatoSeguro("Ingrese ID, Nombre o Cargo (O ENTER para ver todos): ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSQUEDA_RAPIDA_EMPLEADOS(?)");
                    
                    if (termino.empty()) {
                        pstmt->setNull(1, sql::DataType::VARCHAR);
                    } else {
                        pstmt->setString(1, termino);
                    }

                    sql::ResultSet *res = pstmt->executeQuery();
                    
                    cout << "\n" << string(80, '-') << endl;
                    printf("%-4s | %-15s | %-10s | %-25s\n", "ID", "CEDULA", "ESTADO", "NOMBRE");
                    cout << string(80, '-') << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-4d | %-15s | %-10s | %-25s\n", 
                            res->getInt("ID_EMPLEADO"),
                            res->getString("CEDULA").c_str(),
                            res->getString("ESTADO").c_str(),
                            res->getString("NOMBRE").c_str());
                    }

                    if (!encontrado) cout << "\n[!] No hay resultados para: " << (termino.empty() ? "TODOS" : termino) << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError DB: " << e.what() << endl;
                }

                cout << "\nPresione ENTER para continuar...";
                cin.get(); 
            }

            // =========================================================================
            // 7. AUMENTO POR CARGO
            // =========================================================================
            else if (subOpcion1 == 7) {
                cout << "\n --- AUMENTO POR CARGO O ID ---" << endl;
                cout << "Nota: Si desea aplicar a todo un cargo, deje el ID en 0." << endl;
                
                try {
                    string idStr    = leerDatoSeguro("ID del empleado (0 para omitir): ");
                    int id_empleado = idStr.empty() ? 0 : stoi(idStr);

                    string cargo    = leerDatoSeguro("Cargo (Deje vacio para omitir): ");
                    
                    string porcStr    = leerDatoSeguro("Porcentaje de aumento (ej: 10.5): ");
                    double porcentaje = stod(porcStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_AUMENTO_POR_CARGO(?, ?, ?)");

                    if (id_empleado <= 0) pstmt->setNull(1, sql::DataType::INTEGER);
                    else pstmt->setInt(1, id_empleado);

                    if (cargo.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, cargo);

                    pstmt->setDouble(3, porcentaje);

                    cout << "\n[+] " << Recogermensaje(pstmt) << endl;
                    delete pstmt;
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError en la operacion: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 8. ANIVERSARIO EMPLEADOS
            // =========================================================================
            else if (subOpcion1 == 8) {
                cout << "\n --- ANIVERSARIOS LABORALES DEL MES ---" << endl;
                try {
                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ANIVERSARIOS_MES()");
                    sql::ResultSet *res = pstmt->executeQuery();

                    if (res->next()) {
                        try {
                            string mensaje = res->getString("MENSAJE");
                            cout << "\n>>> " << mensaje << " <<<" << endl;
                        } 
                        catch (sql::SQLException &) {
                            cout << "\n" << string(70, '-') << endl;
                            printf("%-4s | %-12s | %-5s | %-15s | %-25s\n", "ID", "FECHA ING.", "AÑOS", "CARGO", "NOMBRE");
                            cout << string(70, '-') << endl;
                            do {
                                printf("%-4d | %-12s | %-5d | %-15s | %-25s\n",
                                     res->getInt("ID_EMPLEADO"),
                                     res->getString("FECHA_INGRESO").c_str(),
                                     res->getInt("ANOS_EN_EMPRESA"),
                                     res->getString("CARGO").c_str(),
                                     res->getString("NOMBRE").c_str());
                            } while (res->next());
                            cout << string(70, '-') << endl;
                        }
                    }
                    delete res;
                    delete pstmt;
                }
                catch (sql::SQLException &e) {
                    cout << "\nError del Sistema: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menú...";
                cin.get();
            } 

        } // Cierra el while
        break; 
    } // Cierra el Case 1

case 2: { // MÓDULO DE CATEGORIAS
        int subOpcion2 = 0;
        while (subOpcion2 != 5) {
            system("clear");
            cout << "=== MODULO DE CATEGORIAS ===" << endl;
            cout << "1. Agregar Categoria" << endl;
            cout << "2. Actualizar Datos" << endl;
            cout << "3. Desactivar o Activar Categoria" << endl;
            cout << "4. Buscar Categoria" << endl;
            cout << "5. Volver al menu principal" << endl;
            cout << "============================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";

            if (!(cin >> subOpcion2)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            // =========================================================================
            // 1. AGREGAR CATEGORIA
            // =========================================================================
            if (subOpcion2 == 1) {
                cout << "\n --- AGREGAR CATEGORIA ---" << endl;
                
                try {
                    string nombre      = leerDatoSeguro("Nombre de la Categoria: ");
                    string descripcion = leerDatoSeguro("Descripcion: ");
                    string icono       = leerDatoSeguro("Icono (Presione Enter para dejar vacio): ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_CATEGORIA(?,?,?)");
                    pstmt->setString(1, nombre);
                    pstmt->setString(2, descripcion);

                    if (icono.empty()) {
                        pstmt->setNull(3, sql::DataType::VARCHAR);
                    } else {
                        pstmt->setString(3, icono);
                    }

                    pstmt->execute();
                    cout << "\n¡Categoria '" << nombre << "' guardada con exito!" << endl;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; // Captura el escape global
                } 
                catch (const exception &e) {
                    cout << "\nError al agregar categoria: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 2. ACTUALIZAR DATOS
            // =========================================================================
            else if (subOpcion2 == 2) {
                cout << "\n --- ACTUALIZAR DATOS ---" << endl;
                cout << "Nota: Deje en blanco los campos que NO desee cambiar." << endl;

                try {
                    string idStr = leerDatoSeguro("ID de la categoria (NUMERO): ");
                    int id_categoria = stoi(idStr); // Convierte a entero

                    string nombre      = leerDatoSeguro("Nombre de la categoria: ");
                    string descripcion = leerDatoSeguro("Descripcion: ");
                    string icono       = leerDatoSeguro("Icono: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_CATEGORIA(?, ?, ?, ?)");
                    pstmt->setInt(1, id_categoria);

                    if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, nombre);

                    if (descripcion.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
                    else pstmt->setString(3, descripcion);

                    if (icono.empty()) pstmt->setNull(4, sql::DataType::VARCHAR);
                    else pstmt->setString(4, icono);

                    pstmt->execute();
                    cout << "\n¡Proceso de actualización completado para el ID: " << id_categoria << "!" << endl;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                } 
                catch (const exception &e) {
                    cout << "\n Error al actualizar en BALBU_TECH: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 3. ACTIVAR / DESACTIVAR ESTADO
            // =========================================================================
            else if (subOpcion2 == 3) {
                cout << "\n --- ACTIVAR / DESACTIVAR CATEGORIA ---" << endl;

                try {
                    string idStr = leerDatoSeguro("Ingrese el ID de la categoria (NUMERO): ");
                    int id_categoria = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CATEGORIA(?)");
                    pstmt->setInt(1, id_categoria);

                    sql::ResultSet *res = pstmt->executeQuery();
                    if (res->next()) {
                        cout << "\n>>> " << res->getString("MENSAJE") << " <<<" << endl;
                    }

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                } 
                catch (const exception &e) {
                    cout << "\n[!] Error: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }

            // =========================================================================
            // 4. BUSCAR CATEGORIA
            // =========================================================================
            else if (subOpcion2 == 4) {
                cout << "\n --- BUSCAR CATEGORÍA ---" << endl;

                try {
                    string busqueda = leerDatoSeguro("Ingrese NOMBRE o DESCRIPCION (Enter para ver todas): ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_CATEGORIAS(?)");
                    pstmt->setString(1, busqueda);
                    sql::ResultSet *res = pstmt->executeQuery();

                    string separator = string(95, '-');
                    cout << "\n" << separator << endl;
                    printf("%-4s | %-20s | %-45s | %-10s\n", "ID", "NOMBRE", "DESCRIPCION", "ESTADO");
                    cout << separator << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-4d | %-20.20s | %-45.45s | %-10s\n", 
                               res->getInt("ID_CATEGORIA"), 
                               res->getString("NOMBRE").c_str(), 
                               res->getString("DESCRIPCION").c_str(),
                               res->getString("ESTADO").c_str());
                    }

                    if (!encontrado) {
                        cout << "\n [!] No se hallaron resultados para: [" << busqueda << "]" << endl;
                    }
                    cout << separator << endl;

                    delete res;
                    delete pstmt;
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] Error de sistema: " << e.what() << endl;
                }
                
                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }

        } // Cierra el while
        break;
    } // Cierra el case 2

case 3:  { // MODULO DE MARCAS
        int subOpcion3 = 0;
        while (subOpcion3 != 5) {
            system("clear");
            cout << "=== MODULO DE MARCAS ===" << endl;
            cout << "1. Agregar Marca " << endl;
            cout << "2. Actualizar Datos" << endl;
            cout << "3. Buscar Marca" << endl;
            cout << "4. Activar o Desactivar Marca " << endl;
            cout << "5. Volver al menu principal" << endl;
            cout << "========================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";
            
            if (!(cin >> subOpcion3)) { 
                cin.clear(); 
                cin.ignore(1000, '\n');
                continue; 
            }

            // =========================================================================
            // 1. AGREGAR MARCA
            // =========================================================================
            if (subOpcion3 == 1) {
                cout << "\n --- AGREGAR MARCA ---" << endl;

                try {
                    string nombre = leerDatoSeguro("Nombre de la marca: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_MARCA (?)");
                    pstmt->setString(1, nombre);
                    pstmt->execute();

                    cout << "\n!Marca " << nombre << " guardada con exito!" << endl;
                    delete pstmt;
                }
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; // Captura el aborto con 'xxx'
                }
                catch (const exception &e) {
                    cout << "\nError al agregar marca: " << e.what() << endl;
                }    

                cout << "\nPresione enter para continuar....";
                cin.get();
            }

            // =========================================================================
            // 2. ACTUALIZAR DATOS
            // =========================================================================
            else if (subOpcion3 == 2) {
                cout << "\n--- ACTUALIZAR DATOS ---" << endl;

                try {
                    string idStr = leerDatoSeguro("ID de la marca (NUMERO): ");
                    int id_marca = stoi(idStr);

                    string nombre = leerDatoSeguro("Nombre de la marca: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_MARCA (?,?)");
                    pstmt->setInt(1, id_marca);
                    pstmt->setString(2, nombre);
                    
                    pstmt->execute();
                    cout << "\nProceso de actualizacion completado para el ID " << id_marca << " !" << endl;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError al actualizar: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

            // =========================================================================
            // 3. BUSCAR MARCA
            // =========================================================================
            else if (subOpcion3 == 3) {
                cout << "\n--- BUSCAR MARCA ---" << endl;

                try {
                    string busqueda = leerDatoSeguro("Ingrese Nombre de la marca (Enter para ver todas): ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_BUSCAR_MARCAS(?)");
                    pstmt->setString(1, busqueda);

                    sql::ResultSet *res = pstmt->executeQuery();

                    cout << "\n----------------------------------------------------------------------------" << endl;
                    printf("%-10s %-30s\n", "ID", "NOMBRE");
                    cout << "----------------------------------------------------------------------------" << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-10d %-30s\n", 
                               res->getInt("ID_MARCA"), 
                               res->getString("NOMBRE").c_str());
                    }

                    if (!encontrado) {
                        cout << "\nNo se encontraron marcas que coincidan con: " << busqueda << endl;
                    }
                    cout << "----------------------------------------------------------------------------" << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\nError del sistema: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }

            // =========================================================================
            // 4. ACTIVAR / DESACTIVAR MARCA
            // =========================================================================
            else if (subOpcion3 == 4) {
                cout << "\n --- ACTIVAR / DESACTIVAR MARCA ---" << endl;

                try {
                    string idStr = leerDatoSeguro("Ingrese el ID de la marca para cambiar su estado: ");
                    int id_marca = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_MARCA(?)");
                    pstmt->setInt(1, id_marca);

                    sql::ResultSet *res = pstmt->executeQuery();

                    if (res->next()) {
                        cout << "\n>>> " << res->getString("MENSAJE") << " <<<" << endl;
                    }

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n[!] Error: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

        } // Cierra el while
        break;
    } // Cierra el case 3

case 4:  { // MÓDULO CLIENTES
        int subOpcion4 = 0;
        while (subOpcion4 != 5) { // 5 para volver al menú principal
            system("clear");
            cout << "=== MODULO DE CLIENTES ===" << endl;
            cout << "1. Agregar Cliente" << endl;
            cout << "2. Actualizar Datos" << endl;
            cout << "3. Buscar Cliente" << endl;
            cout << "4. Activar/Desactivar Cliente" << endl;
            cout << "5. Volver al Menu Principal" << endl;
            cout << "==========================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";

            if (!(cin >> subOpcion4)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            // =========================================================================
            // 1. AGREGAR CLIENTE
            // =========================================================================
            if (subOpcion4 == 1) {
                cout << "\n--- REGISTRO DE CLIENTE ---\n";

                try {
                    string nombre    = leerDatoSeguro("Nombre completo: ");
                    string telefono  = leerDatoSeguro("Telefono: ");
                    string email     = leerDatoSeguro("Email: ");
                    string direccion = leerDatoSeguro("Direccion: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_CLIENTES(?, ?, ?, ?)");
                    pstmt->setString(1, nombre);
                    pstmt->setString(2, telefono);
                    pstmt->setString(3, email);

                    if (direccion.empty()) {
                        pstmt->setNull(4, sql::DataType::VARCHAR);
                    } else {
                        pstmt->setString(4, direccion);
                    }

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
            else if (subOpcion4 == 2) {
                cout << "\n --- ACTUALIZAR DATOS ---" << endl;
                cout << "Nota: Deje en blanco los campos que NO desee cambiar." << endl;

                try {
                    string idStr = leerDatoSeguro("ID del cliente a modificar (NUMERO): ");
                    int id_cliente = stoi(idStr);
                    
                    string nombre    = leerDatoSeguro("Nuevo Nombre completo: ");
                    string telefono  = leerDatoSeguro("Nuevo Telefono: ");
                    string email     = leerDatoSeguro("Nuevo Email: ");
                    string direccion = leerDatoSeguro("Nueva Direccion: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_CLIENTES (?, ?, ?, ?, ?)");
                    pstmt->setInt(1, id_cliente);

                    if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, nombre);

                    if (telefono.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
                    else pstmt->setString(3, telefono);

                    if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR);
                    else pstmt->setString(4, email);

                    if (direccion.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
                    else pstmt->setString(5, direccion);

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
                    cout << "\n ERROR DE SISTEMA: " << e.what() << endl;
                }
                
                cout << "\nPresione Enter para volver al menu....";
                cin.get();
            }

            // =========================================================================
            // 3. BUSCAR CLIENTE
            // =========================================================================
            else if (subOpcion4 == 3) {
                cout << "\n --- BUSCAR CLIENTE EN BALBU_TECH ---" << endl;

                try {
                    string filtro = leerDatoSeguro("Ingrese (NOMBRE, TELEFONO o EMAIL) o Enter para ver todos: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_LISTAR_CLIENTES(?)");
                    pstmt->setString(1, filtro);

                    sql::ResultSet *res = pstmt->executeQuery();

                    string separator = string(90, '-');
                    cout << "\n" << separator << endl;
                    printf("%-5s | %-25s | %-30s | %-15s\n", "ID", "NOMBRE", "EMAIL", "TELEFONO");
                    cout << separator << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-5d | %-25.25s | %-30.30s | %-15s\n",
                               res->getInt("ID_CLIENTE"), 
                               res->getString("NOMBRE").c_str(),
                               res->getString("EMAIL").c_str(),
                               res->getString("TELEFONO").c_str());
                    }

                    if (!encontrado) {
                        cout << "\n [!] No se hallaron clientes con el filtro: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
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

            // =========================================================================
            // 4. ACTIVAR / DESACTIVAR CLIENTE
            // =========================================================================
            else if (subOpcion4 == 4) {
                cout << "\n --- CAMBIAR ESTADO (ACTIVO/INACTIVO) ---" << endl;

                try {
                    string idStr = leerDatoSeguro("Ingrese el ID del cliente: ");
                    int id_cliente = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_CLIENTES(?)");
                    pstmt->setInt(1, id_cliente);

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
                    cout << "\nERROR DE CONEXION: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menu...";
                cin.get();
            }
        } // Cierra el while
        break;
    } // Cierra el case 4

case 5:  {// MODULO PROVEEDORES
        int subOpcion5 = 0;
        while (subOpcion5 != 5) {
            system("clear");
            cout << "=== MODULO PROVEEDORES ===" << endl; 
            cout << "1. Agregar proveedor" << endl; 
            cout << "2. Actualizar Datos " << endl; 
            cout << "3. Activar/Desactivar proveedor" << endl; 
            cout << "4. Buscar proveedor" << endl; 
            cout << "5. Volver al menu principal" << endl; 
            cout << "==========================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: "; 
            
            if (!(cin >> subOpcion5)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

            // =========================================================================
            // 1. AGREGAR PROVEEDOR
            // =========================================================================
            if (subOpcion5 == 1) {
                cout << "\n--- REGISTRO DE PROVEEDOR ---\n";

                try {
                    string NOMBRE    = leerDatoSeguro("Nombre Completo: ");
                    string TELEFONO  = leerDatoSeguro("Telefono: ");
                    string EMAIL     = leerDatoSeguro("Email: ");
                    string DIRECCION = leerDatoSeguro("Direccion: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_PROVEEDOR (?,?,?,?)");
                    pstmt->setString(1, NOMBRE);
                    pstmt->setString(2, TELEFONO);
                    pstmt->setString(3, EMAIL);

                    if (DIRECCION.empty()) {
                        pstmt->setNull(4, sql::DataType::VARCHAR);
                    } else {
                        pstmt->setString(4, DIRECCION);
                    }

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
            else if (subOpcion5 == 2) {
                cout << "\n--- ACTUALIZAR DATOS DEL PROVEEDOR ---" << endl;
                cout << "Nota: Deje en blanco los campos que NO desee cambiar." << endl;

                try {
                    string idStr = leerDatoSeguro("ID del proveedor a modificar (NUMERO): ");
                    int id_proveedor = stoi(idStr);

                    string nombre    = leerDatoSeguro("Nuevo Nombre Completo: ");
                    string telefono  = leerDatoSeguro("Nuevo Telefono: ");
                    string email     = leerDatoSeguro("Nuevo Email: ");
                    string direccion = leerDatoSeguro("Nueva Direccion: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_PROVEEDOR(?, ?, ?, ?, ?)");
                    pstmt->setInt(1, id_proveedor);

                    if (nombre.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, nombre);

                    if (telefono.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
                    else pstmt->setString(3, telefono);

                    if (email.empty()) pstmt->setNull(4, sql::DataType::VARCHAR);
                    else pstmt->setString(4, email);

                    if (direccion.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
                    else pstmt->setString(5, direccion);
                    
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
            // 3. ACTIVAR / DESACTIVAR ESTADO
            // =========================================================================
            else if (subOpcion5 == 3) {
                cout << "\n ---  DESACTIVAR/ACTIVAR ESTADO DEL PROVEEDOR ---" << endl;
             
                try {
                    string idStr = leerDatoSeguro("Ingrese el ID del proveedor: ");
                    int id_proveedor = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PROVEEDOR(?)");
                    pstmt->setInt(1, id_proveedor);

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
                    cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menú...";
                cin.get(); 
            }

            // =========================================================================
            // 4. BUSCAR PROVEEDORES
            // =========================================================================
            else if (subOpcion5 == 4) {
                cout << "\n --- BUSCAR PROVEEDOR EN BALBU_TECH ---" << endl;

                try {
                    string filtro = leerDatoSeguro("Ingrese (NOMBRE o TELEFONO) o presione Enter para ver todos: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_LISTAR_PROVEEDORES(?)");
                    pstmt->setString(1, filtro);
                    
                    sql::ResultSet *res = pstmt->executeQuery();

                    string separator = string(85, '-');
                    cout << "\n" << separator << endl;
                    printf("%-5s | %-30s | %-15s | %-25s\n", "ID", "NOMBRE", "TELEFONO", "EMAIL");
                    cout << separator << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-5d | %-30.30s | %-15s | %-25.25s\n",
                               res->getInt("ID_PROVEEDOR"), 
                               res->getString("NOMBRE").c_str(),
                               res->getString("TELEFONO").c_str(),
                               res->getString("EMAIL").c_str());
                    }

                    if (!encontrado) {
                        cout << "\n [!] No se hallaron proveedores con el filtro: [" << (filtro.empty() ? "TODOS" : filtro) << "]" << endl;
                    }
                    cout << separator << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n ERROR DE DB: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get(); 
            }
        } // Cierra el while
        break;
    } // Cierra el case 5


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
            cout << "=== MODULO DE PRODUCTOS ===" << endl;
            cout << "1. Agregar Productos" << endl;
            cout << "2. Actualizar Datos" << endl;
            cout << "3. Activar/Desactivar Producto" << endl;
            cout << "4. Buscar Producto" << endl;
            cout << "5. Consultar Inventario" << endl;
            cout << "6. Reporte De Stock" << endl;
            cout << "7. Volver Al Menu Principal" << endl;
            cout << "===========================\n";
            cout << " (Escriba 'xxx' en cualquier campo para cancelar)" << endl;
            cout << "Seleccione: ";
            
            if (!(cin >> subOpcion8)) {
                cin.clear();
                cin.ignore(1000, '\n');
                continue;
            }

// =========================================================================
// 1. AGREGAR PRODUCTOS
// =========================================================================
            if (subOpcion8 == 1) { 
                cout << "\n---- REGISTRO DE PRODUCTO ---" << endl;

         try {
    // 1. Preparar y ejecutar la llamada al procedimiento almacenado
    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_INSERTAR_PRODUCTO()");
    bool results = pstmt->execute();

    // 2. Procesar el primer conjunto de resultados (Las Categorías)
    if (results) {
        sql::ResultSet *res = pstmt->getResultSet();
        cout << CIAN << "\n--- CATEGORIAS DISPONIBLES ---\n" << RESET;
        while (res->next()) {
            cout << CIAN << " | ID: " << RESET << res->getInt("ID_CATEGORIA") 
                 << CIAN << " | Nombre: " << RESET << res->getString("NOMBRE") << endl;
        }
        delete res; // Liberar memoria del resultado actual
    }
            
    // 3. Procesar el segundo conjunto de resultados (Las Marcas) usando getMoreResults()
    if (pstmt->getMoreResults()) {
        sql::ResultSet *res = pstmt->getResultSet();

        cout << CIAN << "\n--- MARCAS DISPONIBLES ---\n" << RESET;
        while (res->next()) {
            cout << CIAN << "ID: " << RESET << res->getInt("ID_MARCA") 
                 << CIAN << " | Nombre: " << RESET << res->getString("NOMBRE") << endl;
        } 
        delete res; // Liberar memoria del segundo resultado
        }

    // 4. Limpiar el puntero del PreparedStatement
    delete pstmt;

} catch (sql::SQLException &e) {
    cerr << ROJO << "Error al mostrar las listas: " << RESET << e.what() << endl;
}

                try {
                    string NOMBRE      = leerDatoSeguro("\nNombre del Producto: ");
                    string CODIGO      = leerDatoSeguro("\nCodigo del producto (Ej: CPU-001): ");
                    string DESCRIPCION = leerDatoSeguro("\nDescripcion del Producto: ");
                    
                    string marcaStr     = leerDatoSeguro("\nMarca del producto (ID-NUMERO): ");
                    int ID_MARCA        = stoi(marcaStr);

                    string categoriaStr = leerDatoSeguro("\nCategoria del Producto (ID-NUMERO): ");
                    int ID_CATEGORIA    = stoi(categoriaStr);

                    string precioStr    = leerDatoSeguro("\nPrecio del Producto $: ");
                    double PRECIO       = stod(precioStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_INSERTAR_PRODUCTO(?,?,?,?,?,?)");
                    pstmt->setString(1, NOMBRE);
                    pstmt->setString(2, DESCRIPCION);
                    pstmt->setDouble(3, PRECIO);
                    pstmt->setString(4, CODIGO);
                    pstmt->setInt(5, ID_MARCA);
                    pstmt->setInt(6, ID_CATEGORIA);

                    string respuesta = Recogermensaje(pstmt);
                    
                    cout << "\n--------------------------------------------";
                    cout << "\n>>> " << respuesta << " <<<";
                    cout << "\n--------------------------------------------" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl; 
                }
                catch (const invalid_argument&) {
                    cout << "\n[!] Error: Ingresaste letras en campos numéricos (ID o Precio)." << endl;
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
            else if (subOpcion8 == 2) {
                cout << "\n--- ACTUALIZAR DATOS DE PRODUCTO ---" << endl;

            try {
    // 1. Preparar y ejecutar la llamada del procedimiento
    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL PARA_ACTUALIZARDATOS()");
    bool results = pstmt->execute();

    // 2. Procesar el único conjunto de resultados devuelto por el JOIN
    if (results) {
        sql::ResultSet *res = pstmt->getResultSet();
        
        
        cout << CIAN << "\n--- LISTADO GENERAL DE PRODUCTOS, CATEGORÍAS Y MARCAS ---\n" << RESET;
        
        while (res->next()) {
            cout << CIAN << "\n | ID Producto: " << RESET << res->getInt("ID_PRODUCTO") 
                 << CIAN << "\n | Producto: " << RESET << res->getString("PRODUCTO") 
                 << CIAN << "\n | Precio: " << RESET <<"$"<< res->getDouble("PRECIO")
                 << CIAN << "\n | ID CATEGORIA: " << RESET << res->getInt("ID_CATEGORIA")
                 << CIAN << "\n | Categoría: " << RESET << res->getString("CATEGORIA")
                 << CIAN << "\n | ID Marca : " << RESET << res->getInt("ID_MARCA")
                 << CIAN << "\n | Marca: " << RESET << res->getString("MARCA") << endl;
        } 
        delete res; // Liberar memoria del resultado
    }

    // 3. Limpiar el puntero del PreparedStatement
    delete pstmt;

} catch (sql::SQLException &e) {
    cerr << CIAN << "Error al mostrar las listas: " << RESET << e.what() << endl;
}

                try {
                    string idStr = leerDatoSeguro("ID del producto a modificar (NUMERO): ");
                    int ID_PRODUCTO = stoi(idStr);

                    cout << "\nNota: Presione Enter sin escribir nada para conservar el valor actual." << endl;
                    cout << "----------------------------------------------------------------------" << endl;

                    string NOMBRE        = leerDatoSeguro("Nuevo nombre: ");
                    string CODIGO        = leerDatoSeguro("Nuevo codigo: ");
                    string DESCRIPCION   = leerDatoSeguro("Nueva descripcion: ");
                    string precio_raw    = leerDatoSeguro("Nuevo precio $: ");
                    string marca_raw     = leerDatoSeguro("Nueva Marca (ID NUMERO): ");
                    string categoria_raw = leerDatoSeguro("Nueva Categoria (ID NUMERO): ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_ACTUALIZAR_PRODUCTOS(?, ?, ?, ?, ?, ?, ?)");
                    pstmt->setInt(1, ID_PRODUCTO);

                    if (NOMBRE.empty()) pstmt->setNull(2, sql::DataType::VARCHAR);
                    else pstmt->setString(2, NOMBRE);

                    if (DESCRIPCION.empty()) pstmt->setNull(3, sql::DataType::VARCHAR);
                    else pstmt->setString(3, DESCRIPCION);

                    if (precio_raw.empty()) {
                        pstmt->setNull(4, sql::DataType::DOUBLE);
                    } else {
                        pstmt->setDouble(4, stod(precio_raw)); 
                    }

                    if (CODIGO.empty()) pstmt->setNull(5, sql::DataType::VARCHAR);
                    else pstmt->setString(5, CODIGO);

                    if (marca_raw.empty()) {
                        pstmt->setNull(6, sql::DataType::INTEGER);
                    } else {
                        pstmt->setInt(6, stoi(marca_raw)); 
                    }

                    if (categoria_raw.empty()) {
                        pstmt->setNull(7, sql::DataType::INTEGER);
                    } else {
                        pstmt->setInt(7, stoi(categoria_raw));
                    }

                    string respuesta = Recogermensaje(pstmt);
                    
                    cout << "\n--------------------------------------------";
                    cout << "\n>>> " << respuesta << " <<<";
                    cout << "\n--------------------------------------------" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const invalid_argument&) {
                    cout << "\n[!] Error: Formato numérico incorrecto en la entrada." << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE DB: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

// =========================================================================
// 3. CAMBIAR ESTADO
// =========================================================================
            else if (subOpcion8 == 3) {

               //1.Preparar y ejecutar la llamada del sp para ver el estado de los productos

               try {
               sql::PreparedStatement *pstmt = globalCon -> prepareStatement("CALL PARA_ACTIVARODESACTIVAR_PROC()");
               bool results = pstmt -> execute();

               //2. Procesar el conjunto de resultados que devuelve el select

               if (results) {
               sql ::ResultSet *res= pstmt -> getResultSet();

               cout << CIAN << "\n--- LISTADO DE LOS PRODUCTOS Y SU ESTADO ---\n" << RESET << endl;
               // el while maneja la captura de los datos
               while (res -> next()) {
                   
                cout << CIAN << "\n | ID Producto: " << RESET << res -> getInt("ID_PRODUCTO")
                     << CIAN << "\n | Nombre: "      << RESET << res -> getString("Nombre")              
                     << CIAN << "\n | Estado: " << RESET << res -> getString("ESTADO") << endl;

               }
               // libera memoria del resultado
               delete res;
               }
               // limpia el puntero del preparestatement
               delete pstmt;



               } catch (sql:: SQLException &e) {
                  cerr << ROJO << "Error al mostrar la lista: " << RESET << e.what() << endl;
               }



                cout << "\n --- DESACTIVAR/ACTIVAR ESTADO DEL PRODUCTO ---" << endl;

                try {
                    string idStr = leerDatoSeguro("Ingrese el ID del producto (NUMERO): ");
                    int ID_PRODUCTO = stoi(idStr);

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_TOGGLE_ESTADO_PRODUCTOS(?)");
                    pstmt->setInt(1, ID_PRODUCTO);

                    string respuesta = Recogermensaje(pstmt);

                    cout << "\n--------------------------------------------";
                    cout << "\n>>> " << respuesta << " <<<";
                    cout << "\n--------------------------------------------" << endl;

                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const invalid_argument&) {
                    cout << "\n[!] Error: El ID debe ser un número entero." << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
                }

                cout << "\nPresione Enter para volver al menú...";
                cin.get(); 
            }

// =========================================================================
// 4. BUSCAR PRODUCTO
// =========================================================================
            else if (subOpcion8 == 4) {
                cout << "\n--- BUSCAR PRODUCTOS ---" << endl;

                try {
                    string busqueda = leerDatoSeguro("Ingrese (NOMBRE O CODIGO DEL PRODUCTO) o Enter para todos: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CONSULTAR_PRODUCTOS_FILTRADO(?)");
                    pstmt->setString(1, busqueda);

                    sql::ResultSet *res = pstmt->executeQuery();

                    string separator = string(105, '-');
                    cout << "\n" << separator << endl;
                    printf("%-5s | %-12s | %-25s | %-25s | %-20s | %-10s | %-10s\n", 
                           "ID", "CODIGO", "NOMBRE", "MARCA", "CATEGORIA", "PRECIO", "ESTADO");
                    cout << separator << endl;

                    bool encontrado = false;
                    while (res->next()) {
                        encontrado = true;
                        printf("%-5d | %-12s | %-25.25s | %-20.15s | %-15.15s | $%-9.2Lf | %-10s\n",
                               res->getInt("ID_PRODUCTO"),
                               res->getString("CODIGO").c_str(),
                               res->getString("NOMBRE").c_str(),
                               res->getString("MARCA").c_str(),
                               res->getString("CATEGORIA").c_str(),
                               res->getDouble("PRECIO"),
                               res->getString("ESTADO").c_str());
                    }

                    if (!encontrado) {
                        cout << "\n [!] No se encontraron productos con el filtro: [" 
                             << (busqueda.empty() ? "TODOS" : busqueda) << "]" << endl;
                    }
                    cout << separator << endl;

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE BASE DE DATOS: " << e.what() << endl;
                }

                cout << "\nPresione Enter para continuar...";
                cin.get();
            }

// =========================================================================
// 5. CONSULTAR INVENTARIO
// =========================================================================
            else if (subOpcion8 == 5) {
                cout << "\n============================================\n";
                cout << "        CONSULTA DE INVENTARIO BALBU_TECH     \n";
                cout << "============================================\n";

                try {
                    cout << "Ingrese término de búsqueda (Código, Nombre o Categoría)\n";
                    string BUSQUEDA = leerDatoSeguro("[Presione Enter para listar todo el inventario]: ");

                    sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_CONSULTAR_INVENTARIO(?)");
                    pstmt->setString(1, BUSQUEDA);
                    
                    sql::ResultSet *res = pstmt->executeQuery();

                    cout << "\n=========================================================================================================================\n";
                    printf("| %-4s | %-10s | %-25s | %-15s | %-12s | %-6s | %-6s | %-10s | %-12s |\n", 
                           "ID", "CODIGO", "PRODUCTO", "CATEGORIA", "MARCA", "STOCK", "MINIMO", "PRECIO", "ESTATUS");
                    cout << "=========================================================================================================================\n";

                    int cont = 0;
                    while (res->next()) {
                        cont++;
                        int id          = res->getInt("ID_PRODUCTO");
                        string codigo   = res->getString("CODIGO");
                        string nombre   = res->getString("NOMBRE");
                        string cat      = res->getString("CATEGORIA");
                        string marca    = res->getString("MARCA");
                        int stock       = res->getInt("STOCK_ACTUAL");
                        int minimo      = res->getInt("STOCK_MINIMO");
                        double precio   = res->getDouble("PRECIO");
                        string estatus  = res->getString("ESTATUS_STOCK");

                        if (nombre.length() > 25) nombre = nombre.substr(0, 22) + "...";
                        if (cat.length() > 15) cat = cat.substr(0, 12) + "...";
                        if (marca.length() > 12) marca = marca.substr(0, 9) + "...";

                        printf("| %-4d | %-10s | %-25s | %-15s | %-12s | %-6d | %-6d | $%-9.2f | %-12s |\n", 
                               id, codigo.c_str(), nombre.c_str(), cat.c_str(), marca.c_str(), stock, minimo, precio, estatus.c_str());
                    }

                    cout << "=========================================================================================================================\n";

                    if (cont == 0) {
                        cout << "\n[!] No se encontraron registros en el inventario que coincidan con: \"" << BUSQUEDA << "\"\n";
                    } else {
                        cout << "\n[+] Total de filas mostradas: " << cont << "\n";
                    }

                    delete res;
                    delete pstmt;
                } 
                catch (const CancelarOperacionException &e) {
                    cout << "\n[!] " << e.what() << endl;
                }
                catch (const exception &e) {
                    cout << "\n [!] ERROR DE SISTEMA AL CONSULTAR INVENTARIO: " << e.what() << endl;
                }
               
                cout << "\nPresione Enter para volver al menú...";
                cin.get();
            }

           
// =========================================================================
// 6. REPORTE DE STOCK CRÍTICO
// =========================================================================
            else if (subOpcion8 == 6) {
    cout << "\n======================================================\n";
    cout << "        REPORTE DE STOCK CRÍTICO (BALBU_TECH)         \n";
    cout << "======================================================\n";
    cout << " Listando productos que están en o por debajo de su mínimo:\n\n";

    try {
        sql::PreparedStatement *pstmt = globalCon->prepareStatement("CALL SP_REPORTE_STOCK_CRITICO()");
        sql::ResultSet *res = pstmt->executeQuery();

        string separator = string(80, '-');
        cout << separator << endl;
        printf("%-30s | %-12s | %-12s | %-12s\n", "PRODUCTO", "STOCK ACT.", "STOCK MIN.", "FALTANTE");
        cout << separator << endl;

        bool encontrado = false;
        int contador = 0;

        while (res->next()) {
            encontrado = true;
            contador++;

            string nombreProd = res->getString("NOMBRE");
            if (nombreProd.length() > 30) {
                nombreProd = nombreProd.substr(0, 27) + "...";
            }

            printf("%-30s | %-12d | %-12d | %-12d\n",
                   nombreProd.c_str(),
                   res->getInt("STOCK_ACTUAL"),
                   res->getInt("STOCK_MINIMO"),
                   res->getInt("CANTIDAD_FALTANTE"));
        }

        cout << separator << endl;

        if (!encontrado) {
            cout << "\n [✓] ¡Excelente! No hay productos con stock crítico en este momento." << endl;
        } else {
            cout << "\n [!] Alerta: Se encontraron " << contador << " productos que requieren reabastecimiento." << endl;
        }

        delete res;

        // TRUCO VITAL: Limpiar cualquier resultado extra del Stored Procedure
        while (pstmt->getMoreResults()) {
            sql::ResultSet *extra = pstmt->getResultSet();
            delete extra;
        }

        delete pstmt;
    } 
    catch (const sql::SQLException &e) {
        cout << "\n [!] ERROR DE BASE DE DATOS AL GENERAR REPORTE: " << e.what() << endl;
    }

   cout << "\nPresione Enter para continuar...";
    cin.ignore(1000, '\n'); // <-- AÑADE ESTO: Limpia el residuo del menú
    cin.get();
}

        } // Cierra el while
        break;   
    } // Cierra el case 8

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


//===================================================================
//4. CONSULTAR USUARIOS
//===================================================================
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

//===================================================================
//5. CAMBIAR CLAVE
//===================================================================

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
   }

} //CIERRA EL CASE 9   


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