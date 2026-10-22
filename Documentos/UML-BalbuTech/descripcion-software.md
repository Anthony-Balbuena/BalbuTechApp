# BalbuTechApp — Descripción del software seleccionado

## Descripción general

BalbuTechApp es un sistema de punto de venta e inventario desarrollado para
gestionar las operaciones de una tienda de tecnología. Es una aplicación de
consola escrita en C++ que interactúa con una base de datos MariaDB, donde
reside la mayor parte de la lógica de negocio en forma de procedimientos
almacenados, triggers y vistas (43 tablas y más de 150 procedimientos
almacenados). El acceso al sistema se realiza mediante autenticación por
usuario, y cada usuario obtiene un rol que determina —a través de permisos
individuales— qué menús y operaciones puede utilizar. El software se encuentra
en desarrollo: el alcance cubierto por el modelo incluye las funcionalidades
implementadas hasta la fecha.

## Funcionalidades destacadas

- **Catálogo**: alta, edición, búsqueda y activación/desactivación de
  productos, categorías, marcas, proveedores, clientes y métodos de pago.
- **Inventario**: control de stock con nivel mínimo y ubicación, registro de
  movimientos de stock (entradas, salidas, ajustes y devoluciones) en un kardex
  consultable, y reporte de productos con stock crítico.
- **Compras**: carga de compras a proveedores con carrito de líneas, cálculo de
  subtotal e ITBIS, pagos al proveedor con seguimiento de saldo, devoluciones
  de mercancía, reportes por rango de fechas y consulta de precios por suplidor.
- **Ventas y postventa**: venta rápida con carrito, cobro con distintos
  métodos de pago, anulación de ventas y de pagos, emisión de garantías
  asociadas a la venta, reclamos sobre garantías con seguimiento de su
  estado, devoluciones de clientes, reportes de ventas y ganancias,
  historial de ventas y exportación de datos hacia la página web del negocio.
- **Caja**: apertura de turno con saldo inicial, consulta del estado del turno
  y cierre con cuadre de caja.
- **Recursos humanos**: gestión de empleados (alta, edición, baja y
  reactivación), control de asistencia diaria con justificaciones, solicitudes
  de vacaciones y permisos laborales con aprobación por parte de RRHH, y
  generación de contratos de trabajo en formato HTML.
- **Seguridad**: inicio de sesión con contraseñas protegidas mediante hashing
  PBKDF2 (con migración automática desde el esquema legacy SHA256), gestión de
  roles y permisos por módulo, menú principal dinámico que se construye según
  los permisos efectivos del usuario, y registro de intentos de acceso.

## Roles del sistema

El sistema define roles como ADMIN, RRHH y VENDEDOR (y otros como GERENTE o
SUBGERENTE gestionables desde el módulo de roles). Cada usuario tiene un único
rol, y los permisos se asignan a los roles; en tiempo de ejecución, el menú y
las operaciones visibles se filtran según los permisos efectivos, de modo que
cada rol presenta una vista del sistema distinta.

## Modelo de clases

El diagrama adjunto (`diagrama-clases.drawio`) modela las entidades de dominio
del sistema —aquellas que representan información del negocio— junto con sus
atributos, operaciones y relaciones de asociación, composición y dependencia,
agrupadas según el paquete funcional a la que pertenecen (catálogo, inventario,
ventas, compras, caja, RRHH y seguridad).
