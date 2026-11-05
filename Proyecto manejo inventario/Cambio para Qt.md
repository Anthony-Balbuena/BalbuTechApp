# Cambio para Qt — evaluación y plan

**Fecha:** 05/11/2026
**Estado:** idea evaluada. No iniciada. Va después de cerrar la validación de la viva y el commit de seguridad.
**Relacionado:** [[Realizar en casa]], [[Realizado]], [[PENDIENTES]], [[Auditoria Opus - 03-11-2026]]

## Resumen

La propuesta es migrar la interfaz de la aplicación de consola a **Qt 6 + Qt Quick/QML**, compilado con **CMake**. La conclusión es que **sí es posible** una interfaz moderna como la del render de referencia, y que el costo real no está en Qt sino en separar la lógica de negocio que hoy vive mezclada con los menús de consola.

La recomendación es no reescribir todo de una vez. Primero se extrae la lógica de un módulo chico (`clientes`), después se construye un PoC de Qt sobre esa misma lógica, y recién entonces se migra módulo por módulo.

## Qué propone la imagen

- **Qt 6:** framework para la interfaz gráfica.
- **Qt Quick / QML:** tecnología para interfaces modernas, animaciones y transiciones.
- **CMake:** herramienta para configurar y compilar el proyecto.

El render muestra un dashboard oscuro con tarjetas, sidebar, tablas y gráficos. Es una imagen generada por un modelo: sirve como referencia de estilo, no como diseño funcional ni como alcance.

## ¿Se puede hacer una interfaz moderna en Qt?

**Sí.** La clave es usar **Qt Quick/QML**, no Qt Widgets.

| | Qt Widgets | Qt Quick / QML |
|---|---|---|
| Estética | Escritorio clásico | Moderna, personalizable |
| Animaciones | Limitadas | Nativas (estados, transiciones) |
| Render | CPU | GPU (scene graph) |
| Estilos | QSS (parecido a CSS) | Componentes QML propios |
| Recomendado para | Herramientas internas simples | Dashboards e interfaces modernas |

Con QML se pueden hacer sin problema las tarjetas, el sidebar, las tablas con celdas personalizadas, los temas oscuros, las animaciones y los gráficos del render.

Herramientas útiles:

- **Qt Design Studio:** diseño visual que genera QML.
- **Qt Creator:** IDE y depuración.
- **Live reload de QML:** cambiar el diseño sin recompilar.

### Licencia

- Qt 6 se puede usar bajo **LGPL v3** con enlace dinámico para uso interno.
- **Qt Charts** (gráficos) está bajo **GPL v3 o licencia comercial**, no LGPL.
- Uso interno no constituye distribución a terceros. Si la app se entrega a clientes, hay que revisar licencia comercial o reemplazar los gráficos.

## ¿Por qué es caro?

Porque "pantalla" suena a dibujo, pero el costo está en lo que hay debajo.

Datos medidos del repositorio (05/11/2026):

| Métrica | Valor |
|---|---:|
| Archivos `.cpp` | 24 |
| Líneas de C++ | ~8.600 |
| `cout` (impresión a consola) | 1.028 |
| Llamadas SQL | 322 |

Los archivos más grandes:

| Archivo | Líneas | `cout` | SQL |
|---|---:|---:|---:|
| `ventas.cpp` | 1.584 | 180 | 77 |
| `compras.cpp` | 1.136 | 121 | 63 |
| `contrato.cpp` | 817 | 70 | 12 |
| `empleados.cpp` | 715 | 93 | 27 |

Hoy cada función hace todo: dibuja el menú, lee la opción, valida, ejecuta el SQL, imprime el resultado y pausa. **No hay separación de capas.**

Costos concretos:

1. **Separar lógica de presentación.** Cada función de consola se parte en repositorio, servicio, modelo y pantalla.
2. **Cambia el modelo de ejecución.** La consola es secuencial y bloqueante; la GUI es por eventos (señales, slots, estados).
3. **La sesión vive en la conexión.** `@TOKEN_SESION` es una variable de sesión MySQL sobre la conexión global. Con varias conexiones o hilos, cada una debe setear el token. Perderlo significa `SESION INVALIDA`.
4. **Mostrar datos no es imprimir.** En Qt se necesitan modelos (`QAbstractTableModel`), delegates, refresco, filtros y orden.
5. **Validación y errores cambian de forma.** Formularios, validadores, diálogos, estados de carga.
6. **Los flujos grandes son los caros.** `ventas` y `compras` no son formularios: carrito, pagos, garantías, devoluciones.

### La parte alentadora

No es 24 × el mismo costo. Las primeras 2 o 3 pantallas pagan el esqueleto: capa de datos, sesión, navegación, librería de componentes, manejo de errores. Después, un CRUD simple sale rápido.

Además, la lógica pesada ya está en los stored procedures (bloqueo, permisos, stock, garantías). El C++ mayormente llama SPs y formatea. Extraer la lógica es sobre todo **mover código**, no inventarlo.

## El error de concepto: "backend para terminal"

El backend no es "para la terminal". La terminal es una pantalla. El backend es la lógica y el acceso a datos.

Hoy no existe un backend separado: está mezclado dentro de las funciones de consola. Por eso no hay que "hacer el backend para Qt": hay que **extraer la lógica una sola vez** y que tanto la consola como Qt la consuman.

### Ejemplo real: `clientes.cpp`

Hoy `registrarCliente()` imprime el título, pide cuatro datos, llama al SP, imprime la respuesta y maneja errores. Todo en la misma función.

Separado:

```cpp
// 1) REPOSITORIO: solo habla con MySQL. No sabe que existe una pantalla.
Resultado ClienteRepo::crear(const DatosCliente& d) {
    // CALL SP_INSERTAR_CLIENTES(?,?,?,?)
    return { true, respuesta };
}

// 2) SERVICIO: reglas del negocio. No sabe si es consola o Qt.
Resultado ClienteService::registrar(const DatosCliente& d) {
    if (d.nombre.empty()) return { false, "El nombre es obligatorio" };
    return repo.crear(d);
}

// 3) PANTALLA DE CONSOLA: solo pide datos y muestra el resultado.
void registrarCliente() {
    DatosCliente d = pedirDatos();
    Resultado r = servicio.registrar(d);
    cout << r.mensaje;
}
```

La pantalla Qt hace lo mismo que el punto 3: un formulario que llama a `servicio.registrar(d)`. **La lógica se escribe una sola vez.**

## Plan por fases

### Fase 0 — Cerrar lo abierto (ahora)

- [ ] Validar el mapeo de permisos en la viva con flujos reales.
- [ ] Hacer el commit del trabajo de seguridad pendiente.
- [ ] No iniciar la migración antes de esto.

### Fase 1 — Extraer un módulo (sin Qt)

- [ ] Partir `clientes.cpp` en repositorio + servicio + pantalla de consola.
- [ ] No cambiar el comportamiento.
- [ ] Pasar los tests existentes.
- [ ] Objetivo: aprender el patrón con el módulo más chico (220 líneas).

### Fase 2 — PoC de Qt

- [ ] CMake + Qt 6.8 LTS en Windows (Docker queda solo para la base).
- [ ] Pantalla de login + módulo Clientes.
- [ ] Reusar el mismo servicio de la Fase 1.
- [ ] Medir el esfuerzo real de una pantalla.

### Fase 3 — Migración por módulos

- [ ] Migrar primero los CRUD simples.
- [ ] `ventas` y `compras` al final.
- [ ] Mantener la app de consola viva como respaldo.
- [ ] Priorizar por uso real; evaluar dejar en consola los módulos de poco uso.

## Qué hay que aprender

No hace falta saber todo de software. Tres conceptos:

- **Capas:** datos, reglas y pantalla en lugares distintos.
- **Contrato:** el servicio expone funciones claras (`registrar`, `listar`, `buscar`) y devuelve resultados; no imprime.
- **Dirección de la dependencia:** la pantalla depende del servicio; el servicio depende del repositorio. Nunca al revés. El repositorio no sabe que existe una terminal o una ventana.

Analogía: hoy el cocinero cocina en la mesa del cliente. Separar la cocina permite tener salón, delivery o mostrador; todos piden al mismo lugar. La terminal es un salón; Qt es otro. El menú es el mismo.

## Qué NO hacer

- **Reescritura big-bang:** 8.600 líneas de golpe es la forma más segura de perder el proyecto.
- **Copiar la lógica a la pantalla Qt:** quedan dos versiones que se desincronizan.
- **Dejar que el render fije el alcance:** muestra gráficos y dashboards que hoy no existen en los datos. La primera versión debe ser funcional, no bonita.
- **Correr Qt dentro del contenedor:** la GUI necesita escritorio. Docker se queda para la base; Qt se compila en Windows.
- **Empezar antes de cerrar la seguridad:** no mezclar una reescritura de UI con trabajo sin commitear.

## Decisiones pendientes

- ¿La aplicación se distribuye a terceros o es solo de uso interno? Define la licencia (LGPL vs comercial / Qt Charts).
- ¿Qué módulos se migran y cuáles quedan en consola? Priorizar por uso real.
- ¿Qt 6.8 LTS con MSVC o MinGW en Windows?
- ¿Se mantiene el conector MySQL actual (probado) o se pasa a QtSql? Recomendación inicial: mantener el conector y envolverlo en repositorios.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Perder `@TOKEN_SESION` al abrir varias conexiones | Una conexión por hilo con el token seteado; probar login + operación |
| Duplicar lógica entre consola y Qt | Extraer servicios antes de la UI |
| Alcance inflado por el render | Definir alcance funcional por módulo |
| Migración eterna | Fases chicas, con la consola funcionando |
| Regresiones silenciosas | Tests existentes + pruebas por módulo migrado |

## Referencias

- [[Realizar en casa]] — pendientes priorizados.
- [[Realizado]] — historial de cambios.
- [[PENDIENTES]] — deuda técnica y matriz de pruebas.
- [[Auditoria Opus - 03-11-2026]] — hallazgos de seguridad.
- Código actual: `clientes.cpp`, `main.cpp`, `sesion.cpp`, `login.cpp`, `database.h`, `build.sh`.
