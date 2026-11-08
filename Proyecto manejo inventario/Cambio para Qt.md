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

#### Lecturas directas: se mudan, no se reescriben (08/11/2026)

Las pantallas que hoy listan antes de pedir un ID usan `SELECT` directo, no un
`SP`:

| Pantalla | Consulta actual |
|---|---|
| Clientes → Actualizar | `SELECT ID_CLIENTE, NOMBRE, TELEFONO, EMAIL, ESTADO FROM CLIENTES` |
| Clientes → Cambiar Estado | `SELECT ID_CLIENTE, NOMBRE, ESTADO FROM CLIENTES` |
| Proveedores → Actualizar | `SELECT ID_PROVEEDOR, NOMBRE FROM PROVEEDORES` |
| Proveedores → Cambiar Estado | `SELECT ID_PROVEEDOR, NOMBRE, ESTADO FROM PROVEEDORES` |
| Marcas → Actualizar | `SELECT ID_MARCA, NOMBRE FROM MARCAS` |
| Marcas → Cambiar Estado | `SELECT ID_MARCA, NOMBRE, ESTADO FROM MARCAS` |
| Empleados → Actualizar / Despedir | `SELECT ID_EMPLEADO, NOMBRE FROM EMPLEADOS` |
| Empleados → Reactivar | igual, con `WHERE ESTADO = 'INACTIVO'` |

**El SQL está bien: no se cambia para Qt.** Lo que cambia es dónde vive. Hoy el
`SELECT` está adentro de la función de pantalla, junto a `cout` y a `globalCon`.
En Qt esa pantalla no existe: no puede usar `globalCon` ni `cout`. En la Fase 1
el `SELECT` se **muda al repositorio** (`ClienteRepo::listar()`), que es quien
habla con MySQL; la pantalla de consola y después la de Qt solo consumen. Mudar
la consulta no es cambiar comportamiento: el `ORDER BY` y las columnas quedan
iguales. Lo único que se le agrega es la paginación (`LIMIT`/`OFFSET`), que se
decide más abajo.

#### No reusar `SP_LISTAR_*` desde esas pantallas

`SP_LISTAR_CLIENTES`, `SP_LISTAR_PROVEEDORES` y `SP_LISTAR_MARCAS` existen,
pero exigen el permiso de **consulta** con `EXIGIR = 1`:

| Rutina | Permiso | EXIGIR |
|---|---|---|
| `SP_LISTAR_CLIENTES` | `CLIENTES_VER` | 1 |
| `SP_LISTAR_PROVEEDORES` | `PROVEEDORES_VER` | 1 |
| `SP_LISTAR_MARCAS` | `MARCAS_VER` | 1 |

La matriz real de Clientes:

```
ROL           VER  EDITAR  ESTADO
ADMIN          1     1       1
CONTABILIDAD   1     0       0
GERENTE        1     1       1
SUBGERENTE     1     1       1
VENDEDOR       0     1       1   ← tiene EDITAR y ESTADO, no VER
```

`VENDEDOR` llega a "Actualizar Cliente" y "Cambiar Estado" sin tener
`CLIENTES_VER`. Si esas pantallas pasaran a llamar `SP_LISTAR_CLIENTES`, el
vendedor recibiría `ERROR: SIN PERMISO PARA ESTA OPERACION.` y se le rompería
una pantalla que hoy funciona. Hoy funciona porque la lectura directa no lleva
guarda.

Es la misma regla que gobierna el mapeo de todo el proyecto: **el permiso que
exige un `SP` tiene que ser uno que todos los roles capaces de abrir la pantalla
llamadora tengan.** Acá el denominador común es `CLIENTES_EDITAR`, no
`CLIENTES_VER`.

En Proveedores no hay riesgo (todos los que tienen `PROVEEDORES_EDITAR` tienen
`PROVEEDORES_VER`), pero se mantiene el mismo patrón para no mezclar.

En Marcas tampoco hay riesgo **hoy**: los cuatro roles con `MARCAS_EDITAR` o
`MARCAS_ESTADO` (ADMIN, GERENTE, SUBGERENTE, ALMACEN) tienen además
`MARCAS_VER`, así que `SP_LISTAR_MARCAS` funcionaría. Igual se dejó el `SELECT`
directo, por dos motivos: mantiene el mismo patrón que los otros módulos y no
queda atado a que `MARCAS_VER` siga siendo universal. El día que alguien reciba
`MARCAS_EDITAR` sin `MARCAS_VER`, la pantalla no se rompe.

Ojo con el enum: `MARCAS.ESTADO` es `ENUM('ACTIVA','INACTIVA')`, no
`ACTIVO/INACTIVO` como Clientes, Proveedores y Empleados. `tablaColorEstado`
contempla los dos, pero cualquier filtro nuevo tiene que usar los valores
correctos.

Si más adelante se quiere que las lecturas queden auditadas por permiso, la vía
es un `SP` nuevo con el permiso de la pantalla (`CLIENTES_EDITAR`,
`PROVEEDORES_EDITAR`, `MARCAS_EDITAR`, `EMPLEADOS_EDITAR`), **nunca** reusar
`SP_LISTAR_*` desde la pantalla de edición.

#### Paginación: 10 filas por página (08/11/2026)

Decisión del dueño: los listados de selección van **paginados de 10**.

Esto **no es solo UI**. Paginar obliga a cambiar la consulta y el contrato del
repositorio:

```sql
-- 1) La página
SELECT ID_CLIENTE, NOMBRE, ESTADO
  FROM CLIENTES
 ORDER BY ID_CLIENTE
 LIMIT 10 OFFSET 20;   -- página 3

-- 2) El total, con el mismo filtro, para saber cuántas páginas hay
SELECT COUNT(*) FROM CLIENTES;
```

Y en el repositorio:

```cpp
struct PaginaClientes {
    std::vector<Cliente> filas;  // como máximo 10
    int total;                   // para "Página 1 de 3"
};

PaginaClientes ClienteRepo::listar(int pagina, int porPagina = 10);
```

Con `total` se calculan las páginas y se deshabilitan los botones: sin el
`COUNT` la pantalla no sabe si hay una página más hasta que llega vacía.

**Ojo con la sección anterior.** Ahí dice que el `SELECT` no se reescribe. Sigue
siendo cierto *por Qt*: cambia por paginar, no por migrar. Pero hay que decidirlo
en la **Fase 1**, cuando se arma el repositorio, y no en la Fase 2: si la consola
y Qt no comparten el contrato, el repositorio termina con dos formas de leer y se
pierde justo lo que la Fase 1 busca.

**Decidido (08/11/2026): la consola también pagina.** La pantalla de consola usa
`[N]` siguiente / `[P]` anterior y muestra "Página 1 de 3". No hay dos formas de
leer: consola y Qt piden la misma página al mismo método del repositorio y cada
una la dibuja a su manera.

Condición para que esto sirva de verdad: **el `LIMIT`/`OFFSET` y el `COUNT`
viven en el repositorio, no en la pantalla.** Si la paginación se implementa
dentro de la función de consola (como está hoy `imprimirClientesParaEstado`),
Qt no hereda nada: tendría que repetir la consulta. Lo que se comparte es el
contrato (`listar(pagina)` que devuelve filas + total), no el `cout` ni los
botones.

Ventaja práctica de hacerlo primero en consola: se diseña y se prueba el
contrato barato (compilar y correr en segundos) antes de meter Qt. Cuando llegue
la PoC, la consulta paginada ya está resuelta y solo falta dibujarla.

##### Implementación en consola (08/11/2026): `paginacion.h`

Ya está hecho, genérico y compartido: `paginacion.h` expone `mostrarPaginado`
y `mostrarPaginadoSP`, y las pantallas solo aportan **cómo se dibuja una fila**.
No hay paginación copiada por módulo.

| Función | Cuándo |
|---|---|
| `mostrarPaginado(ConsultaPaginada, fila)` | la pantalla puede leer la tabla con `SELECT` directo |
| `mostrarPaginadoSP(callPagina, callTotal, filtros, fila)` | la tabla solo se lee por `SP` `DEFINER` |

El segundo caso no es capricho: `balbu_app` tiene `SELECT` sobre 16 tablas
nomas (recorte del 03/11). `PRODUCTOS` e `INVENTARIO` **no** están entre ellas,
así que ahí el `LIMIT` tiene que vivir dentro del procedimiento
(`SP_CONSULTAR_PRODUCTOS_PAGINADO` + `SP_CONTAR_PRODUCTOS_FILTRADOS`, módulo 9).

Pantallas ya paginadas: Clientes (Actualizar, Cambiar Estado, Buscar, Listar),
Proveedores (Actualizar, Cambiar Estado, Listar), Marcas (Actualizar, Cambiar
Estado), Empleados (Actualizar, Despedir, Reactivar), Productos (Buscar,
Actualizar, Consultar Inventario, Reporte de Stock), Compras (Ver compra con
IVA, Devolución, Pagar, Cancelar), Ventas (Cobrar, Anular pago, Devolución) e
Inventario (Ajuste de stock, Ajustar p.compra, Movimientos/Kardex).

Pendientes de paginar, todas por la misma razón (lectura por `SP`, sin `SELECT`
directo): Proveedores → Buscar, Marcas → Buscar/Listar y los reportes por
periodo de Ventas y Compras. Cada una necesita su par de `SP`s paginados.

> **Ojo con las búsquedas puntuales:** `buscarPorId`, `buscarPorCodigo` y
> `resolverProducto` de `ventas.cpp` también usan
> `SP_CONSULTAR_PRODUCTOS_FILTRADO`, pero **no** se paginan a propósito: no son
> listados, son resolución exacta de un código o ID para el carrito. Paginarlas
> haría que un producto que cae en la página 2 no se encuentre.

Consecuencia práctica: la Fase 1 deja de ser "mudar el SQL tal cual" y pasa a ser
"mudar el SQL y agregarle `LIMIT`/`OFFSET`". El comportamiento visible de la
consola cambia (10 por pantalla) y eso hay que aceptarlo explícitamente, porque
choca con el "no cambiar el comportamiento" del plan original.

##### ¿Se puede hacer en Qt? Sí

Paginar en Qt es de las cosas fáciles:

- `QTableView` + un modelo propio que guarde **solo la página actual** (o, más
  simple todavía, un `QTableWidget` que se rellena con las 10 filas que devolvió
  el servicio).
- Dos botones (anterior / siguiente) y un `QLabel` con "Página 2 de 5",
  habilitados según `pagina > 1` y `pagina < totalPaginas`.
- La pantalla **no hace SQL**: llama a `servicio.listar(pagina)` y muestra lo que
  llega. Toda la consulta sigue viviendo en el repositorio.

Lo que **no** conviene: usar `QSqlQueryModel::fetchMore()` para esto. Eso carga
filas de a poco sobre una única consulta abierta; no sabe cuántas páginas hay ni
te deja saltar a la última. Para paginación real, `LIMIT`/`OFFSET` en el
repositorio y un modelo que solo tiene la página.

Costo real: una pantalla paginada tiene dos consultas (página + total) y tres
piezas de UI (tabla, botones, etiqueta). No cambia el esfuerzo de la migración;
solo hay que preverlo en el contrato del repositorio desde el principio.

### Fase 2 — PoC de Qt

- [ ] CMake + Qt 6.8 LTS en Windows (Docker queda solo para la base).
- [ ] Pantalla de login + módulo Clientes.
- [ ] Reusar el mismo servicio de la Fase 1.
- [ ] Medir el esfuerzo real de una pantalla.
- [ ] Incluir la paginación de 10 en la pantalla de Clientes: es la pieza que más
      cambia el contrato del repositorio y conviene medirla en la PoC.

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
