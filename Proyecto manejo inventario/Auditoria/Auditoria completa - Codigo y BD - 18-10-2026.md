# Auditoría completa — Código C++ y Base de Datos (18-10-2026)

**Alcance.** 7.532 líneas de C++ (38 archivos) y 12.552 líneas de SQL (44 módulos), contrastadas contra la base viva `BALBU_TECH` (43 tablas base, 23 vistas, 165 rutinas, 76 triggers). Auditoría de **solo lectura**: no se modificó código ni datos.

> **Carpeta `Auditoria/`.** Lo que quedó **abierto** de la auditoría anterior (08/10) está en el hermano `Auditoría BD general - 08-10-2026.md`; todo lo que ya estaba cerrado de esa auditoría se movió a `../Planes/Realizado.md`.

**Veredicto en una línea.** Las piezas están bien hechas — cero inyección SQL, PBKDF2 correcto, precisión monetaria impecable, transacciones bien construidas donde importan —; el problema no es la calidad del código sino que **la base de datos dejó de ser la fuente de verdad**, el proyecto acumuló una funcionalidad entera construida y nunca cableada, y la seguridad depende de que nadie llegue al servidor.

---

## Resumen numérico

| Severidad | Cantidad |
| --- | --- |
| Crítico | 3 |
| Alto | 26 |
| Medio | 48 |
| Bajo / mejora | 21 |
| **Total** | **98** |

---

## 1. Lo que está bien (con evidencia)

Esto no es relleno: son fortalezas reales, varias por encima del promedio de un proyecto de este tamaño.

| Fortaleza | Evidencia |
| --- | --- |
| **Cero inyección SQL en todo el repositorio** | Las 105 llamadas `CALL` van por `prepareStatement` con parámetros enlazados, incluso los patrones `LIKE` (`clientes.cpp:122-126` pasa `"%" + filtro + "%"` como *valor*). Los `NULL` se pasan con `setNull(...)`, no interpolando `"NULL"`. Ninguna rutina usa SQL dinámico (excepto `10- USUARIOS.sql:181-183`). |
| **PBKDF2 bien implementado** | Salt de `RAND_bytes`, 100.000 iteraciones, el conteo se lee del valor almacenado, comparación con `CRYPTO_memcmp`, y rehash automático del formato legacy en el login (`login.cpp:46`). |
| **Cero errores de precisión monetaria** | No hay un solo `FLOAT`/`DOUBLE` en el esquema y **todos** los `DECIMAL` llevan precisión explícita. El redondeo del carrito coincide al centavo con las columnas generadas de la BD. Sin doble ITBIS en compras. |
| **Transacciones correctas donde importan** | Los SP de escritura múltiple usan consistentemente `IF @@in_transaction = 0 THEN START TRANSACTION` + `DECLARE EXIT HANDLER FOR SQLEXCEPTION ... ROLLBACK` + `SET V_PROPIA_TRANSACCION`. Verificado de forma independiente en las tres rebanadas SQL. |
| **Los frenos van antes de la escritura** | No se encontró ni una validación aplicada después de un `INSERT`/`UPDATE`. |
| **El hueco clásico de `DECIMAL` no está** | `DECIMAL` sin paréntesis (que defaultea a `(10,0)` y trunca centavos en silencio): cero coincidencias. |
| **Estructura de la base impecable** | Las 43 tablas con PK, todo InnoDB + `utf8mb4_unicode_ci`, cero rutinas con SQL dinámico, cero `DEFAULT` ambiguos. |
| **Ninguna vista expone la contraseña** | `CONTRASENA` solo aparece en `10- USUARIOS.sql`; la vista de identidad (`29:79-89`) no la selecciona. |
| **El fix del fin de entrada (EOF) es real** | `leerOpcionMenu` devuelve `bool`, los 15 bucles cortan con `break` y `pausar()` no espera Enter en EOF (`database.cpp:96-102`). Verificado con RED/GREEN en `db/test-menus-eof.sh`. |
| **Frenos de negocio bien puestos** | `SP_DESPEDIR_EMPLEADO` impide doble despido y fecha futura (`8:215-230`); `PERMISOS_EMPLEADOS` frena solapamiento y fechas retroactivas (`13:91-107`); `USUARIOS.ID_EMPLEADO` es `UNIQUE`. |
| **Idempotencia donde se aplicó** | `DROP ... IF EXISTS` antes de cada `CREATE PROCEDURE` en la mayoría de los módulos; `CREATE OR REPLACE VIEW`; semillas con `INSERT IGNORE` / `ON DUPLICATE KEY UPDATE`. |
| **Los 4 bugs de contrato quedaron realmente arreglados** | Verificado: el camino feliz produce stdout + HTML + borrador **idénticos byte a byte** al binario anterior. |

---

## 2. Los 3 críticos

### C-1. La credencial de `root` de la base está en el código, en 12 archivos y en 17 commits

`database.cpp:23` — `envOr("DB_PASSWORD", "linux01")` es el **default de runtime**. Replicado en `docker-compose.yml:28`, `db/import.sh:18`, `db/seed-admin.sh:16`, `db/seed-catalogo.sh:13`, `db/check-app-sps.sh:16`, `.env.example`, `.vscode/tasks.json`, `README-DOCKER.md` y 2 documentos. Además está en **17 commits** del historial.

**Lo bueno:** `.env` **nunca** estuvo versionado (0 commits).

### C-2. La clave del administrador está en el historial público del repositorio

`Pedro0110` aparece en **4 commits, los 4 en `origin/main`**. Se quitó del working tree, pero eso **no alcanza**: el historial es público y la credencial es recuperable. La única reparación es **rotarla**.

### C-3. Un `CHECK` hardcodeado hace inadministrable el sistema de permisos

`modulos/36- PERMISOS_ROLES.sql:38-40`:

```sql
CONSTRAINT CHK_ROL_NOMBRE CHECK (
    ROL_NOMBRE IN ('ADMIN', 'RRHH', 'EMPLEADO')
)
```

`SP_INSERTAR_ROL` permite crear cualquier rol, pero la tabla puente rechaza todo lo que no sea esos tres nombres. Y `SP_ASIGNAR_PERMISO_A_ROL` **no lo llama ningún `.cpp`**. Resultado: todo rol creado desde la app nace inerte. El módulo "Gestión de Roles" promete administración y entrega roles decorativos.

**Hallazgo propio agregado:** la base está expuesta en la red. MariaDB escucha en `0.0.0.0:3306` y `[::]:3306`, y existen `root@localhost`, `root@172.17.0.2` y **`root@%`**. La app se conecta como `root`, que tiene `SUPER`, `GRANT`, `CREATE USER`, `FILE`, `SHUTDOWN` y `PROCESS`; las 165 rutinas y 23 vistas son `SQL SECURITY DEFINER` como `root@localhost`.

---

## 3. Los 7 patrones de fondo

Los 98 hallazgos no son 98 problemas independientes: son 7 causas raíz que se repiten.

### P-1. La credencial y el privilegio están embarrados

Secretos en el código y en el historial (C-1, C-2); la app corre como `root` de la base; el servidor escucha en todas las interfaces; las rutinas se ejecutan como `root@localhost`. **Un solo error = servidor completo.** Y como todo corre como `root`, la auditoría no puede distinguir a nadie (ver P-7).

### P-2. La base no es la fuente de verdad; el C++ la duplica

Tres instancias confirmadas:

- **Permisos:** `roles.cpp:79` consulta **primero** su lista hardcodeada y solo después `FN_TIENE_PERMISO`. Efecto neto: la base puede **agregar** permisos pero **no revocar ninguno**. Ya divergieron: el C++ le da `GESTIONAR_VENTAS` a `RRHH` y a `EMPLEADO`, y ni el módulo ni la viva se lo dan — o sea que **RRHH y EMPLEADO venden solo por el hardcode**.
- **Fechas:** hay tres validadores distintos (`empleados.cpp:288`, `contrato.cpp:207`, y el SP). `empleados.cpp` acepta `2026-99-99`; `contrato.cpp` acepta `2026-02-31`.
- **Reglas de negocio:** el candado de 7 días de `11_SP_BLOQUEAR_EDICION_ANTIGUA` se invoca desde el cliente como llamada **separada y previa**; `11_SP_JUSTIFICAR_ASISTENCIA` por sí solo justifica cualquier fecha.

### P-3. Valido en el lugar equivocado (o después de escribir)

- `SP_REGISTRAR_LIQUIDACION` (`16:99`) calcula `P_SALARIO * P_ANIOS` con datos que **vienen del cliente** y no los contrasta con `EMPLEADOS.SALARIO` ni con `FECHA_INGRESO`. El monto de una obligación laboral es lo que diga quien llama.
- `SP_FINALIZAR_RECLAMO` (`34:171`) usa `CONCAT(OBSERVACIONES, ...)` sobre una columna nullable: la nota final se pierde **en silencio** y el SP igual responde `EXITO`. El mismo bug ya estaba arreglado en `26_SP_RECHAZAR_DEVOLUCION` con `IFNULL`.
- `BONOS_EMPLEADOS`: el alta valida solo el techo (`14:95`) y la edición valida el piso (`14:141`); el piso queda en manos de un `CHECK`.
- **8 lugares imprimen errores de base en VERDE como si fueran éxito** (`ventas.cpp:253-255`, `compras.cpp:609-611`, `compras.cpp:123-125`, `compras.cpp:222-224`; el patrón correcto está en `caja.cpp:57-61`).
- `compras.cpp:500-502` **descarta** la advertencia "PRECIO DE COMPRA IGUAL O MAYOR AL DE VENTA" que el SP devuelve.

### P-4. Atomicidad y orden que dependen de la suerte

El C++ **no tiene una sola transacción** (`autocommit`/`COMMIT`/`ROLLBACK`: cero coincidencias en todo el C++). La atomicidad depende por completo de los SP — que en general lo hacen bien (ver §1) —, pero:

- La venta multi-línea **no es atómica** (`ventas.cpp:321-348`: compensación best-effort con `SP_CANCELAR_VENTA`).
- **El orden de los triggers de `DETALLE_COMPRA` es un artefacto del historial de creación**: ninguno de los cinco declara `FOLLOWS`. Verificado en la viva: el orden actual (stock → auditoría → total → historial → costo) coincide con el comentario de `19.1` pero **no** con el orden en que aparecen los `CREATE TRIGGER` en los archivos. Un rebuild limpio podría desfasar los snapshots `STOCK_ANTERIOR`/`STOCK_NUEVO`.
- "Un contrato ACTIVO por cédula" se prueba con un `IF EXISTS` y no hay constraint que lo garantice (`42:102-108`).
- `FN_TIENE_PERMISO` se declara `P_ACCION VARCHAR(20)` pero hay permisos de 21 y 22 caracteres. **No trunca: revienta.** Verificado: `ERROR 1406 (22001) Data too long for column 'P_ACCION'`. El C++ lo convierte en `Error DB: ...`.

### P-5. El esquema no reproduce la base (el hallazgo estructural de la auditoría)

Comparación medida entre `modulos/*.sql` y la base viva:

| Objeto | Módulos | Viva | |
| --- | --- | --- | --- |
| Tablas | 43 | 43 | ✅ |
| Vistas | 23 | 23 | ✅ |
| Triggers | 76 | 76 | ✅ |
| Funciones | 4 | 4 | ✅ |
| **Procedimientos** | **154** | **161** | ⚠️ |

**7 rutinas viven solo en la base y ningún módulo las declara:** `11_SP_REGISTRAR_ENTRADA`, `3_SP_LISTAR_ROLES_SELECT`, `9_SP_ACTUALIZAR_PRODUCTO`, `SP_BUSCAR_CATEGORIAS`, `SP_BUSCAR_MARCAS`, `SP_CREAR_USUARIO`, `SP_ELIMINAR_BONO`. Un rebuild desde `modulos/` las pierde.

Y el permiso `GESTIONAR_METODOS_PAGO` existe en la viva con **`ID_PERMISO = 100`**, saltándose la secuencia 1..16 del módulo: fue parchado a mano y ningún módulo lo declara.

Peor, en tres frentes:

1. **Los módulos mutan datos al importarse.** `9- PRODUCTOS.sql:566-576` ejecuta `ALTER TABLE PRODUCTOS ADD COLUMN ID_PROVEEDOR` + **`UPDATE PRODUCTOS SET ID_PROVEEDOR = 1 WHERE ID_PROVEEDOR IS NULL OR ID_PROVEEDOR = 0`** + `MODIFY COLUMN`. Importar el módulo reasigna el proveedor 1 a todo producto sin proveedor. También hay `CALL` de semillas con datos de ejemplo (incluido un teléfono y un email de cliente hardcodeados en el esquema, `7:282`) y `SELECT`/`DESCRIBE` de introspección.
2. **`SELECT * FROM USUARIOS;` al final de `10- USUARIOS.sql:471`** vuelca **todos los hashes de contraseña** al log del import.
3. **`DROP PROCEDURE IF EXISTS SP_X` / `CREATE PROCEDURE 6_SP_X`** (`6- AUDITORIA_SISTEMA.sql:48-49`, `72-73`) y cuatro módulos sin `DROP` alguno: como `db/import.sh:53` corre con **`--force`**, el `CREATE` falla con "already exists" y el error **se traga**. Las ediciones al cuerpo de esas rutinas **nunca llegan a la base**.

> Consecuencia: **hoy no se puede reconstruir la base viva desde `modulos/`.** Ese es el hallazgo más importante de la parte de BD.

### P-6. Código construido y nunca cableado

- **61 de las 165 rutinas (37%) no las llama la app.** Son casi todas de RRHH (liquidaciones, vacaciones, bonos manuales, permisos) y de postventa (garantías, reclamos, reparaciones).
- **16 de las 43 tablas están vacías**, y coinciden exactamente con esas features: `LIQUIDACIONES`, `VACACIONES_EMPLEADOS`, `ASIGNACIONES_RECLAMOS`, `DETALLE_REPARACIONES`, `CONTRATOS`, `GARANTIAS`, `RECLAMOS_GARANTIAS`, `LOG_ACCESOS`, `PERMISOS_EMPLEADOS`, etc.
- **Trampa de nombres:** los 6 SP `PARA_*` **no escriben** — son lecturas que llenan selects (`PARA_INSERTAR_PRODUCTO()` devuelve categorías, marcas y proveedores). Van en pareja con el SP real que la app llama después. El nombre dice "insertar"; hacen lo contrario.
- **Gemelos confusos:** `SP_BUSCAR_CATEGORIA` vs `SP_BUSCAR_CATEGORIAS`, `9_SP_ACTUALIZAR_PRODUCTO` vs `SP_ACTUALIZAR_PRODUCTOS`.
- **Duplicación literal entre módulos:** `diasEnMesC`/`nombreMesC`/`fmt2C` son copias byte a byte entre `ventas.cpp` y `compras.cpp`; categorías, marcas y métodos de pago comparten ~180 líneas de esqueleto cada uno.

### P-7. Bitácoras que no sirven para responsabilizar

| Bitácora | Estado real medido |
| --- | --- |
| `MOVIMIENTOS_INVENTARIO` + `HISTORIAL_MOVIMIENTOS_PRODUCTO` | **Dos bitácoras paralelas del mismo evento**, escritas por pares de triggers distintos. Coinciden en contenido (verificado en producto 20: 4 eventos en cada una) pero `HISTORIAL_MOVIMIENTOS_PRODUCTO` **no tiene columna `ID_EMPLEADO`**: no puede decir quién movió el stock. |
| Tipo de movimiento | El `ENUM` es `('ENTRADA','SALIDA','AJUSTE','DEVOLUCION')`: **no hay tipo CANCELACION**. Una cancelación de compra se registra como `SALIDA` y la única marca de qué pasó vive en el texto libre `OBSERVACION` (`'Compra cancelada ID: 426'`). Una consulta que agrupe por `TIPO` cuenta cancelaciones como ventas. |
| `LOG_ACCESOS` | **0 filas.** Sin trigger. Su único escritor (`SP_REGISTRAR_ACCESO`) nunca se llama. El esquema no guarda el usuario intentado ni la IP: cero trazabilidad de logins y de fuerza bruta. |
| `LOG_USUARIOS` | Las **32 filas son `ALERTA_STOCK_BAJO`** y `ID_USUARIO_ADMIN` está **NULL en las 32**. La tabla de auditoría está 100% ocupada por ruido, sin atribución, y no cubre el cambio de nombre de usuario. |
| `AUDITORIA_SISTEMA` | Las 21 filas tienen `USUARIO_SISTEMA = 'root@localhost'`, porque se llena con `USER()`. Solo hay triggers para `PROVEEDORES` y `CLIENTES`: nada de `USUARIOS`, `ROLES`, `PERMISOS` ni `EMPLEADOS`. |
| `AUDITORIA_SISTEMA.USUARIO_SISTEMA` | Documentada como "el usuario de la DB o del App"; guarda la cuenta de conexión. La bitácora de "quién tocó los datos" no identifica a nadie. |

---

## 4. Hallazgos verificados contra la base viva

Todo lo siguiente se comprobó con consultas reales, no por lectura de archivos.

| # | Hallazgo | Evidencia medida |
| --- | --- | --- |
| 1 | **Costo fantasma tras cancelar una compra** | `PRODUCTO FASE I` (ID 20) tiene `P_COMPRA = 10.00` — el precio exacto de las **dos compras canceladas** (426 y 464) y **cero** compras válidas. El trigger que recalcula el costo solo corre en el camino `DELETE`, y `SP_CANCELAR_COMPRA` no borra el detalle. |
| 2 | `FN_TIENE_PERMISO` revienta, no trunca | `ERROR 1406 (22001)` con un permiso de 21 caracteres. |
| 3 | Permisos ejecutables hoy | `PERMISOS` = 17, `ROL_PERMISO` = 26 (ADMIN 17, RRHH 5, EMPLEADO 4), `ROLES` = 3, `USUARIOS` = **1** (`abalbuena`, ADMIN). `FN_TIENE_PERMISO('abalbuena','GESTIONAR_ROLES') = 1`; con un permiso inexistente = 0: **la función funciona**. |
| 4 | `EMPLEADOS.CEDULA` sin `UNIQUE` | `SHOW INDEX` solo devuelve `PRIMARY`, `EMAIL`, `TELEFONO`. **Estado: 9 empleados, 9 cédulas distintas** → riesgo latente, no materializado. |
| 5 | `AUDITORIA_SISTEMA` atribuye todo a `root` | 21 filas con `root@localhost`; `SELECT USER()` = `root@localhost`. |
| 6 | El `DROP` del módulo 6 nunca dropea | En la viva existen **solo** `6_SP_LISTAR_AUDITORIA_GENERAL` y `6_SP_CONSULTAR_HISTORIAL_REGISTRO`; los nombres del `DROP` no existen. |
| 7 | Contraseña almacenada del único usuario real | 83 caracteres, prefijo `pbkdf2$1` (formato fuerte). `CONTRASENA VARCHAR(512)`. |
| 8 | `LOG_USUARIOS` = ruido | 32/32 filas `ALERTA_STOCK_BAJO`; `SUM(ID_USUARIO_ADMIN IS NOT NULL) = 0`. |
| 9 | Bono automático del 1% | 8 bonos, mínimo 105.00, máximo 4.240,00, **cero bonos en 0.00**. El subtotal mínimo de línea es 10.500,00, así que el caso "bono redondea a 0.00" (línea < 0,50) **nunca ocurrió**: riesgo real pero latente. |
| 10 | `CHECK`s de la viva | `CHK_ROL_NOMBRE` (el crítico C-3), `CK_GARANTIA_FECHAS`, `CK_FECHAS_VACACIONES`, `CK_PERMISO_FECHAS`, `CHK_FECHAS_VALIDAS`, `CHK_PAGOS_COMPRA_MONTO`. |
| 11 | Índices duplicados reales | `CATEGORIAS(NOMBRE)`, `PROVEEDORES(EMAIL)`, `PROVEEDORES(TELEFONO)`, `ROLES(NOMBRE_ROL)`, `USUARIOS(USUARIO)`, `ASIGNACIONES_RECLAMOS`. Además `ASISTENCIA_EMPLEADOS.IX_ASISTENCIA_EMPLEADO` es redundante: `UQ_ASISTENCIA_DIA(ID_EMPLEADO, FECHA)` ya lo cubre como prefijo. |
| 12 | Sin duplicados por FK implícita | Se verificó `LIQUIDACIONES`, `BONOS_EMPLEADOS`, `HISTORIAL_LABORAL_EMPLEADO`, `DETALLE_REPARACIONES`, `VACACIONES_EMPLEADOS`, `ASISTENCIA_EMPLEADOS`: InnoDB **reutilizó** el índice existente, no creó uno implícito. *(Esta era una afirmación teórica de un auditor, refutada por la medición.)* |
| 13 | `1- CATEGORIAS.sql` con error de sintaxis | Línea 9: `select * from DETALLES_VENTA` **sin punto y coma**, seguida de `SELECT * FROM \`PAGOS\`;` → `ERROR 1064` en cada import. Línea 279: `select * from PRODUCTOS;;`. |
| 14 | `db/import.sh` tolera errores | Línea 53: `--force`; línea 54 cuenta `^ERROR` y solo imprime un AVISO. Es lo que hace invisible P-5. |

---

## 5. Correcciones a los auditores

Dos afirmaciones de los auditores eran incorrectas y se corrigieron midiendo contra la base. Quedan registradas porque el arreglo es distinto en cada caso.

**Corrección 1 — `GESTIONAR_METODOS_PAGO` sí existe.** Un auditor concluyó que "no existe en la base" (había leído el *seed del módulo*, no el *contenido de la tabla*). Existe, con `ID_PERMISO = 100`. Y esto **es un hallazgo, no una ausencia**: el ID 100 salta la secuencia 1..16, o sea que fue parchado a mano y ningún módulo lo declara. La divergencia real C++ ↔ base es la inversa de la reportada: `GESTIONAR_VENTAS` para `RRHH` y `EMPLEADO` existe **solo** en el hardcode del C++.

**Corrección 2 — Los índices duplicados por FK implícita no existen.** El auditor teorizó que el `CREATE INDEX` posterior al `CONSTRAINT FOREIGN KEY` duplicaba el índice. La medición muestra que InnoDB reutiliza el índice existente. Los duplicados reales son los 6 de la tabla §4.

**Corrección 3 — `FN_TIENE_PERMISO` no trunca: revienta.** El auditor dijo "trunca a 20 y por eso nunca coincide". Devuelve `ERROR 1406`. El arreglo es distinto: no alcanza con comparar distinto, hay que ensanchar el parámetro **y** atajar la excepción en el cliente.

---

## 6. Prioridades sugeridas

**Antes que nada — la puerta.**

1. **Rotar las dos credenciales** (la de `root` de la base y la del administrador). Sacarlas del working tree no alcanza: están en el historial público.
2. **Sacar MariaDB de la red**: que escuche solo en `127.0.0.1`, y eliminar `root@%`.
3. **Dejar de conectar como `root`**: usuario dedicado con solo los privilegios de datos que la app necesita.
4. **`database.cpp:23`**: sin default hardcodeado; si falta la variable de entorno, fallar fuerte y claro.

**Después — lo que rompe funcionalidad.**

5. **P-5 (reproducibilidad)**: agregar los `DROP` que faltan, declarar las 7 rutinas huérfanas y `GESTIONAR_METODOS_PAGO` en sus módulos, y sacar de los módulos el `UPDATE`, los `SELECT *` (el que vuelca hashes primero) y los `CALL` de semilla.
6. **P-4 (atomicidad)**: la venta multi-línea.
7. **P-3 (valido mal)**: los 8 errores pintados en verde, la advertencia de precio descartada, y el monto de la liquidación tomado del cliente.
8. **C-3 / P-2 (permisos)**: elegir **una** fuente de verdad. Lo correcto es que sea la base: borrar la lista hardcodeada y sembrar en SQL.
9. **`FN_TIENE_PERMISO`**: `VARCHAR(80)` en el parámetro.
10. **`LOG_ACCESOS`**: cablearlo en el login (con usuario intentado e IP) y tipar el estado con `ENUM`.

**Después — decisión de producto.**

11. **P-6**: por cada feature sin cablear (liquidaciones, vacaciones, bonos manuales, garantías, reclamos, reparaciones) decidir si se cablea o se retira. Hoy hay que mantener y auditar rutinas que nadie ejecuta, y da la falsa sensación de que la funcionalidad existe.

---

## 7. Anexo — cobertura por rebanada

| Rebanada | Alcance | Crítico | Alto | Medio | Bajo |
| --- | --- | --- | --- | --- | --- |
| C++ núcleo y seguridad | `main.cpp`, `database.*`, `seguridad.*`, `login.cpp`, `usuarios.cpp`, `autenticacion.cpp` | 2 | 5 | 7 | 0 |
| C++ ventas / compras / caja | `ventas.cpp`, `compras.cpp`, `caja.cpp` | 0 | 3 | 6 | 2 |
| C++ CRUD y RRHH | productos, inventario, categorías, marcas, métodos de pago, proveedores, clientes, empleados, roles, contrato, web_export | 0 | 5 | 8 | 6 |
| SQL dinero y stock | módulos 17, 18, 19, 19.1, 19.5, 19.6, 20, 21, 21.5, 22, 23, 24, 26, 32, 38, 39, 41 | 0 | 5 | 9 | 6 |
| SQL identidad y seguridad | módulos 3, 6, 8, 10, 13, 28, 29, 30, 33, 36, 42 | 1 | 4 | 12 | 2 |
| SQL catálogo, RRHH y servicios | módulos 1, 2, 4, 5, 7, 9, 11, 12, 14, 15, 16, 25, 27, 34, 35, 40 | 0 | 4 | 6 | 5 |
| **Total** | | **3** | **26** | **48** | **21** |

---

## 8. Anexo — pendientes ya conocidos, fuera de esta auditoría

- **NCF / comprobante fiscal DGII**: bloqueado por el trámite en la oficina virtual.
- **Drift bidireccional `TEST` ↔ viva** en el módulo de asistencia.
- **Datos de prueba a limpiar**: `Mouse` con el typo "Dispocitivo", `Teclado` con descripción `NULL`, `IPHONE` modelado como marca, y los registros `FASE I` (`CAT FASE I` ID 17, `PRODUCTO FASE I` ID 20, `MARCA FASE I` ID 29, marca `2` ID 19). El costo fantasma del hallazgo §4-1 vive precisamente en `PRODUCTO FASE I`.
- **Compra de prueba** para que los 49 productos entren al inventario con stock.
- **API para la web**: `GET /api/reporte` + adaptar `index.html` a `fetch` + deploy.
- **Higiene**: `tempCodeRunnerFile.cpp` existe (32 bytes) y el glob `*.cpp` de `build.sh` lo compila.
