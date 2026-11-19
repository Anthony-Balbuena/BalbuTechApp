# Módulo 8 — EMPLEADOS

Maestro de empleados: nombre, cédula, cargo, salario, teléfono, email y
fechas de ingreso/despido. Todo empleado arranca `ACTIVO`; el despido lo pasa
a `INACTIVO` y el reingreso lo devuelve a `ACTIVO`.

Es la base de RRHH: asistencia (11), vacaciones (12), permisos (13), bonos
(14), historial laboral (15), liquidaciones (16) y contratos (esta misma
sección, al final) cuelgan de este ID.

> **Absorbe el `42` (14/11/2026):** el registro de contratos vive ahora **en este
> mismo archivo**, al final, en la sección «CONTRATOS (ex módulo 42)». Su trigger
> `TR_VINCULAR_CONTRATO` es `AFTER INSERT ON EMPLEADOS` y es el único de ese
> tipo, así que no hay orden que cuidar.

Fuente: `modulos/8- EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 18/11/2026.

## Tablas

### EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_EMPLEADO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL, CHECK trim `> 0` | Nombre completo. |
| `CEDULA` | `VARCHAR(20)` | NOT NULL | Cédula. **Sin UNIQUE en la tabla**: la unicidad la controla el SP. |
| `CARGO` | `VARCHAR(50)` | NOT NULL | Cargo. Los triggers lo guardan en **MAYÚSCULAS**. |
| `SALARIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Salario mensual. |
| `TELEFONO` | `VARCHAR(20)` | NOT NULL, **UNIQUE** | Teléfono. |
| `EMAIL` | `VARCHAR(100)` | NOT NULL, **UNIQUE** | Email. |
| `FECHA_INGRESO` | `DATE` | NOT NULL | Alta original. El reingreso la **sobrescribe**. |
| `FECHA_DESPIDO` | `DATE` | NULL | Baja; `NULL` mientras está activo. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta del registro. |

> **Nota:** `CEDULA` no es única a nivel de tabla (sí lo es `TELEFONO` y
> `EMAIL`). Un `INSERT` directo puede duplicar cédula; la protección real está
> en `SP_INSERTAR_EMPLEADO`.

## Procedimientos almacenados

### `SP_INSERTAR_EMPLEADO(P_NOMBRE, P_CEDULA, P_CARGO, P_SALARIO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO)`

**Usada por la app** (`empleados.cpp`).

**Limpieza:** nombre con colapso de espacios; cédula sin espacios ni guiones;
teléfono sin espacios/paréntesis/guiones; email en minúsculas y sin espacios.
El cargo **no** se limpia acá: lo pasa a mayúsculas el trigger de inserción.

**Validaciones (`SIGNAL 45000`):**
- nombre o cédula vacíos → `ERROR: NOMBRE Y CÉDULA SON OBLIGATORIOS.`
- cédula repetida → `ERROR: YA EXISTE UN EMPLEADO CON ESTA CÉDULA.`
- email repetido → `ERROR: ESTE EMAIL YA ESTÁ REGISTRADO.`
- teléfono repetido → `ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.`
- salario `<= 0` → `ERROR: EL SALARIO DEBE SER MAYOR A CERO.`

`FECHA_INGRESO` nula → usa `CURDATE()`. Devuelve
`EXITO: EMPLEADO "<nombre>" INSERTADO. ID: <id>`.

> **Nota:** un salario `NULL` **no** cae en la validación (`NULL <= 0` es
> `NULL`, no verdadero) y termina en el error técnico `1048` de la columna
> `NOT NULL`.

### `SP_ACTUALIZAR_EMPLEADO(P_ID_EMPLEADO, P_NOMBRE, P_CEDULA, P_EMAIL, P_CARGO, P_TELEFONO, P_SALARIO)`

**Usada por la app.** Los parámetros van en el **orden que manda el C++**
(email, cargo, teléfono, salario); hubo un bug histórico de parámetros
permutados que corrompía datos, por eso el orden está comentado en el archivo.
Actualización parcial: `NULL` conserva.

- ID inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
- Cédula vacía → `ERROR: LA CÉDULA NO PUEDE ESTAR VACÍA.`
- Cédula de otro → `ERROR: LA CÉDULA YA PERTENECE A OTRO EMPLEADO.`
- Teléfono de otro → `ERROR: EL TELÉFONO YA PERTENECE A OTRO EMPLEADO.`
- Email de otro → `ERROR: EL EMAIL YA PERTENECE A OTRO EMPLEADO.`
- Salario: solo se aplica si `P_SALARIO > 0`; si viene `NULL`, 0 o negativo
  se **conserva** el actual (no hay mensaje de error).
- Devuelve `EXITO: EMPLEADO "<nombre>" ACTUALIZADO CON ÉXITO.`

> El nombre no se valida vacío: un `''` lo corta el CHECK de tabla con error
> técnico.

### `SP_DESPEDIR_EMPLEADO(P_ID_EMPLEADO, P_FECHA_DESPIDO)`

**Usada por la app.** Marca `INACTIVO` y setea `FECHA_DESPIDO`.

- ID inexistente → `ERROR: EL EMPLEADO NO EXISTE EN LA BASE DE DATOS.`
- Ya inactivo → `AVISO: ESTE EMPLEADO YA CONSTA COMO INACTIVO.`
- Fecha nula → hoy; fecha futura →
  `ERROR: LA FECHA DE DESPIDO NO PUEDE SER FUTURA.`
- Devuelve `EXITO: EL EMPLEADO ID <id> HA SIDO DADO DE BAJA.`

> (08/11/2026) Si el empleado tenía cuenta, el mensaje agrega
> `SU USUARIO QUEDO INACTIVO Y SUS SESIONES CERRADAS.`: el trigger
> `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` (módulo 10) pone la cuenta en
> `INACTIVO` y `TR_INVALIDAR_SESION_EMPLEADO_INACTIVO` (módulo 66) borra sus
> sesiones abiertas.

### `SP_REACTIVAR_EMPLEADO(P_ID_EMPLEADO, P_NUEVO_SALARIO)`

**Usada por la app.** Devuelve a `ACTIVO`, limpia `FECHA_DESPIDO`, **setea
`FECHA_INGRESO = CURRENT_DATE`** y aplica el salario nuevo si viene.

- ID inexistente → `ERROR: EL ID DE EMPLEADO NO EXISTE.`
- Ya activo → `AVISO: EL EMPLEADO YA SE ENCUENTRA ACTIVO.`
- Salario no nulo y `<= 0` → `ERROR: EL NUEVO SALARIO DEBE SER MAYOR A CERO.`
- Devuelve `EXITO: EMPLEADO ID <id> REINGRESADO CORRECTAMENTE.`

> (08/11/2026) **No reactiva la cuenta**: si el empleado tiene su usuario en
> `INACTIVO`, el mensaje agrega `SU USUARIO SIGUE INACTIVO: ACTIVELO EN EL
> MODULO USUARIOS.` Se prefiere que alguien lo decida a mano antes que devolver
> el acceso solo.

> El reingreso **pierde la fecha de ingreso original**: la antigüedad pasa a
> contar desde el reingreso. Es el comportamiento documentado en el código.

### `SP_REPORTE_NOMINA_TOTAL()`

**La app no la llama.** Devuelve **2 result sets**: resumen de activos
(`TOTAL_EMPLEADOS`, `GASTO_MENSUAL_NOMINA`, `SUELDO_MINIMO`, `SUELDO_MAXIMO`,
`SUELDO_PROMEDIO`) y desglose `CARGO / EMPLEADOS_POR_CARGO / TOTAL_POR_CARGO`.
Si no hay activos, un único result set con
`AVISO: NO HAY EMPLEADOS ACTIVOS PARA GENERAR NÓMINA.`

### `SP_CONSULTAR_EMPLEADOS(P_ID_EMPLEADO, P_FILTRO_NOMBRE)`

**La app no la llama.** Si llega ID, filtra por ID; si no, por nombre parcial;
si ambos vacíos, lista todo. Devuelve 10 columnas (sin `FECHA_REGISTRO`),
ordenado por ID **descendente**.

### `SP_AUMENTO_POR_CARGO(P_ID_EMPLEADO, P_CARGO, P_PORCENTAJE)`

**La app no la llama.** Aplica aumento porcentual a los activos, por ID o por
cargo. Trabaja en transacción explícita: si no hay ID ni cargo →
`ERROR: ESPECIFIQUE ID O CARGO.` (rollback); si el `UPDATE` no toca filas →
`ERROR: NO SE ENCONTRARON EMPLEADOS ACTIVOS PARA EL FILTRO DADO.`
(rollback); si actualiza, `COMMIT` y
`EXITO: SE APLICÓ EL AUMENTO A <n> EMPLEADO(S).` Redondea a 2 decimales.

> No valida el signo ni el tope del porcentaje: un valor negativo **baja** el
> salario. Uso interno, no expuesto en la app.

### `SP_ANIVERSARIOS_MES()`

**La app no la llama.** Lista activos que cumplen años de ingreso en el mes
actual, con `ANOS_EN_EMPRESA`, ordenados por día. Sin activos →
`ERROR: NO HAY EMPLEADOS ACTIVOS EN LA BASE DE DATOS.`; sin aniversarios →
`INFORMATIVO: NO HAY ANIVERSARIOS LABORALES EN EL MES ACTUAL.`

### `SP_BUSQUEDA_RAPIDA_EMPLEADOS(P_TERMINO)`

**La app no la llama.** Término obligatorio (si no,
`ERROR: DEBE INGRESAR UN DATO PARA BUSCAR.`). Busca por ID exacto, cédula,
nombre o cargo; devuelve `ID, CEDULA, NOMBRE, CARGO, ESTADO`, con los
`ACTIVO` primero y luego alfabético.

### `SP_GENERAR_RECIBO_EMPLEADO(P_ID_EMPLEADO)`

**Usada por la app** (`nomina.cpp`, 18/11/2026). Volante de pago: sueldo bruto,
`DESCUENTO_SFS` (3.04%), `DESCUENTO_AFP` (2.87%), `SUELDO_NETO` (bruto menos
5.91%), el `ESTADO` del empleado, los bonos pendientes y el total, con la fecha
de emisión `dd/mm/yyyy`.

Columnas: `EMPRESA`, `ID_EMPLEADO`, `NOMBRE`, `CEDULA`, `CARGO`, `ESTADO`,
`SUELDO_BRUTO`, `DESCUENTO_SFS`, `DESCUENTO_AFP`, `SUELDO_NETO`,
`CANTIDAD_BONOS_PENDIENTES`, `TOTAL_BONOS_PENDIENTES`, `TOTAL_A_PAGAR`,
`FECHA_EMISION`.

- ID nulo → `ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.`
- Inexistente → `ERROR: EL EMPLEADO NO EXISTE.`

> **(18/11/2026)** Tres cosas que este SP hace y dos que no:
> - Los bonos (14) son **arrastre**: toma **todos** los `PENDIENTE` del
>   empleado, de cualquier mes. La nómina de octubre nunca se corrió y esos
>   bonos no los levantaría ningún mes.
> - `TOTAL_A_PAGAR = SUELDO_NETO + TOTAL_BONOS_PENDIENTES`.
> - Ya **no exige `ACTIVO`**: un despedido con bonos pendientes igual cobra lo
>   que trabajó; el estado va como columna para que se vea en el recibo.
> - **No marca nada.** Es consulta pura: un recibo no es un pago, y marcar al
>   imprimir dejaría bonos `PAGADO` sin que salga plata.
> - **No cambia la base de los descuentos.** `SUELDO_BRUTO` sigue siendo
>   `SALARIO` y SFS/AFP se calculan sobre `SALARIO`: si el bono cotiza, es
>   gravable o integra el bruto lo define el contador. El bono se suma después
>   del neto y el recibo no afirma nada previsional.

> Los porcentajes de SFS/AFP están **hardcodeados** en el SP.

### `SP_PAGAR_NOMINA_EMPLEADO(P_ID_EMPLEADO)` — nuevo (18/11/2026)

**Usada por la app.** El acto de pagar: marca `PAGADO` **todos** los bonos
`PENDIENTE` del empleado con `FECHA_PAGO = CURRENT_DATE` y `PAGADO_POR`
resuelto con `FN_USUARIO_SESION()`, y devuelve cuántos y cuánto.

- ID nulo → `ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.`
- Inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
- Sin bonos pendientes → `AVISO: EL EMPLEADO CON ID <id> NO TIENE BONOS
  PENDIENTES. NO SE PAGO NADA.` (no es un error: puede que ya se le pagó).
- Con bonos → `EXITO: SE PAGARON <n> BONO(S) POR $<monto>. EL SUELDO BASE SE
  PAGA FUERA DEL SISTEMA.`

> Existe separado del recibo a propósito: el recibo se mira cuantas veces se
> quiera; esto escribe. Si marcara al emitir, dos consultas pagarían dos veces.
>
> **El sistema no paga sueldos:** no hay tabla de nómina. Lo que queda
> registrado son los bonos; el sueldo base se paga fuera y el mensaje lo dice
> para que nadie crea que la nómina quedó asentada.
>
> No exige `ACTIVO`, igual que el recibo.

## Pantalla (app C++)

`nomina.cpp` / `nomina.h`, colgada del submenú de Empleados como
«Nómina (recibo y pago)» (18/11/2026).

| Acción | SP |
|---|---|
| Listar empleados (10 por página, con `ID`, `NOMBRE` y `ESTADO`) | `SELECT` directo paginado |
| Recibo del mes | `SP_GENERAR_RECIBO_EMPLEADO` |
| Detalle de los bonos incluidos | `SP_LISTAR_BONOS_PENDIENTES_EMPLEADO` (14) |
| Pagar la nómina | `SP_PAGAR_NOMINA_EMPLEADO` |

- Abre con el permiso **`GESTIONAR_NOMINA`** (36: ADMIN, GERENTE y RRHH;
  SUBGERENTE no). Las tres rutinas exigen ese mismo permiso: pantalla y rutina
  con permisos distintos dejarían al rol legítimo en `SIN_PERMISO`. El ítem
  «Empleados» del menú principal también lo incluye; sin eso la pantalla existe
  pero nadie llega.
- Dos mitades separadas a propósito: el recibo es consulta y el pago es el acto.
  El pago pide confirmación explícita (`s/n`) antes de tocar la base.
- El pago es **por empleado**, no masivo: un botón que paga a toda la plantilla
  de una vez no se deshace.
- Si el empleado no tiene pendientes, la pantalla lo dice y no llama al SP: no
  hay nada que pagar y eso no es una falla.

> **Ojo al leer un `CALL` en C++:** el `ResultSet` de un procedimiento hay que
> soltarlo (`res.reset()`) y después llamar a `drenarResultados(ps.get())` antes
> de la consulta siguiente. Si no, la conexión queda con un resultado abierto y
> la próxima consulta muere con `Commands out of sync`.

## Triggers

### `TRG_CARGO_UPPER`

`BEFORE INSERT ON EMPLEADOS`: guarda `NEW.CARGO = UPPER(NEW.CARGO)`.

### `TRG_CARGO_UPPER_UPDATE`

`BEFORE UPDATE ON EMPLEADOS`: mismo uppercase del cargo en cada update.

> Por esto los cargos quedan siempre en mayúsculas; los reportes que agrupan
> por cargo dependen de eso.

## Reglas de negocio

- **Nombre y cédula obligatorios**; cédula única **por lógica de SP** (sin
  UNIQUE en la tabla).
- **Teléfono y email obligatorios y únicos** (UNIQUE real).
- **Salario > 0** (CHECK + validaciones de SP).
- **Cargo en mayúsculas** por triggers.
- **Despido** = `INACTIVO` + `FECHA_DESPIDO` (no se borra); **reingreso** =
  `ACTIVO`, fecha de despido `NULL` y fecha de ingreso = hoy.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.

---

## EMPLEADOS_CEDULA_UNICA (ex módulo 59)

Parche absorbido dentro del `8` el 14/11/2026 (ver el `## Log` de
`odd/tasks/consolidacion-modulos.md`). El texto viaja verbatim; solo se
degradaron los encabezados un nivel.

### Que hace

Agrega el indice unico `UQ_EMPLEADOS_CEDULA` sobre `EMPLEADOS.CEDULA`.

### Por que

El comentario del modulo 8 decia que la cedula era obligatoria y unica, y
la app confiaba en eso, pero el esquema solo tenia `UNIQUE` en `TELEFONO`
y `EMAIL`. Dos empleados con la misma cedula entraban sin error y despues
rompian la busqueda de contratos, que asume una cedula = una persona.

### Como aplicarlo

Ya no es un archivo: vive al final del módulo `8` y se aplica reimportando el
`8`. Es idempotente: se puede correr dos veces.

### Que preserva

- No toca datos, empleados, contratos ni usuarios.
- Si hay duplicados, el modulo no aplica y los lista para limpiarlos.

### Que no hace

- No fusiona empleados duplicados.
- No cambia los SPs de alta o edicion; el error de la base se propaga.


## CONTRATOS (ex módulo 42)

Registro del contrato firmado: absorbido dentro del `8` el 14/11/2026 (ver
«Estado de la documentación» y el `## Log` de
`odd/tasks/consolidacion-modulos.md`). El cuerpo del ex `42` viaja **verbatim**:
acá solo se degradaron los encabezados un nivel.

Registro del **papel firmado**. El contrato nace antes que el empleado: la
opción 12 arma la oferta, la 13 coteja el borrador contra el papel y lo registra
con `SP_SUBIR_CONTRATO`. Subir un contrato **no crea empleados**: el alta se
hace después en el módulo de `EMPLEADOS` y ahí `TR_VINCULAR_CONTRATO` completa
`ID_EMPLEADO`.

La **cédula** es la llave real del contrato: existe desde la oferta y no cambia.
`ID_EMPLEADO` puede ser `NULL` (contrato huérfano, persona todavía sin alta).

**Es usado por:** `contrato.cpp` (borrador, subida, finalización y consulta por
cédula).

Fuente: `modulos/8- EMPLEADOS.sql`, sección del ex módulo `42` · Base:
`BALBU_TECH` · Revisado: 19/10/2026 · Fusionado: 14/11/2026.

### Tablas

#### CONTRATOS

Una fila por contrato firmado. Los datos de la persona (`NOMBRE` a
`FECHA_INGRESO`) son un **snapshot** de lo que se firmó: no cambian después
aunque cambie el empleado. Motor InnoDB.

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_CONTRATO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador del contrato. |
| `ID_EMPLEADO` | `INT` | FK → `EMPLEADOS(ID_EMPLEADO)`, **NULL** | Empleado dueño del contrato. `NULL` = contrato firmado antes del alta; lo completa `TR_VINCULAR_CONTRATO`. |
| `TIPO` | `ENUM('TEMPORAL','FIJO')` | NOT NULL | TEMPORAL = término fijo con duración; FIJO = indefinido. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Fecha de ingreso pactada en el contrato (no el día en que se sube). |
| `FECHA_FIN` | `DATE` | NULL | NULL = contrato FIJO; con valor = vencimiento del TEMPORAL. |
| `SALARIO` | `DECIMAL(10,2)` | NOT NULL | Salario pactado en el contrato (exacto, 2 decimales). |
| `NOMBRE` | `VARCHAR(100)` | NULL | Snapshot del nombre firmado. |
| `CEDULA` | `VARCHAR(20)` | NULL | Snapshot de la cédula. Sin UNIQUE a propósito: una persona acumula varios contratos (temporal → renovación → fijo) y ese historial es justamente lo que se quiere conservar. |
| `CARGO` | `VARCHAR(50)` | NULL | Snapshot del cargo. |
| `TELEFONO` | `VARCHAR(20)` | NULL | Snapshot del teléfono. |
| `EMAIL` | `VARCHAR(100)` | NULL | Snapshot del email. |
| `FECHA_INGRESO` | `DATE` | NULL | Fecha de ingreso de la persona (la misma de `FECHA_INICIO`). |
| `RUTA_DOCUMENTO` | `VARCHAR(255)` | NULL | Ruta del HTML generado o del escaneo firmado (`contratos/firmados/...`). |
| `ESTADO` | `ENUM('ACTIVO','FINALIZADO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo del contrato. |
| `FECHA_REGISTRO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento del registro en BD. |

**Migración idempotente:** el bloque incluye, y se puede volver a correr
completo sin romper nada:

- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` de las 6 columnas de snapshot
  (`NOMBRE` … `FECHA_INGRESO`).
- `ALTER TABLE ... MODIFY ID_EMPLEADO INT NULL` (19/10/2026: el contrato ya no
  exige empleado).
- `IX_CONTRATOS_CEDULA`: la búsqueda normal pasa a ser por cédula. Se crea solo
  si falta (chequeo en `INFORMATION_SCHEMA.STATISTICS`).

### Procedimientos almacenados

#### `SP_SUBIR_CONTRATO(P_NOMBRE, P_CEDULA, P_CARGO, P_SALARIO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO, P_TIPO, P_MESES, P_RUTA)`

Registra un contrato cuando la persona firma. No recibe ningún ID: lo resuelve
por cédula. `P_MESES` solo aplica a TEMPORAL (para FIJO se pasa NULL y
`FECHA_FIN` queda NULL). `FECHA_INICIO` y `FECHA_FIN` salen de
`P_FECHA_INGRESO` (no de `CURDATE()`).

- Si la cédula **ya existe** en `EMPLEADOS`, vincula `ID_EMPLEADO` en el acto.
- Si **no existe** (lo normal), guarda `ID_EMPLEADO = NULL`: el contrato queda
  huérfano hasta el alta.
- Si hay **más de un** empleado con esa cédula, frena por ambigüedad.

Validaciones (`SIGNAL SQLSTATE '45000'`, la transacción corta):

1. Nombre, cédula y salario obligatorios (salario > 0).
2. Tipo debe ser `TEMPORAL` o `FIJO`; TEMPORAL exige meses ≥ 1.
3. Esa cédula ya tiene un contrato ACTIVO → error (finalizarlo antes).
4. Si el empleado ya existe y está INACTIVO → error (reactivarlo antes).

Devuelve `EXITO: CONTRATO #<id> REGISTRADO. EMPLEADO PENDIENTE DE ALTA.` o
`... EMPLEADO VINCULADO.` según el caso.

#### `SP_FINALIZAR_CONTRATO(P_ID_CONTRATO)`

Pasa un contrato de `ACTIVO` a `FINALIZADO` (a mano, p. ej. al despedir).
Frena si el ID es inválido, no existe o el contrato ya está finalizado.
`FECHA_FIN`: si era NULL (indefinido) se pone hoy; si el fijo vence a futuro
se corta a hoy; si ya venció, se conserva.

#### `SP_CONTRATOS_POR_CEDULA(P_CEDULA)`

Historial completo de contratos de una persona, más reciente primero
(`ORDER BY ID_CONTRATO DESC`). Devuelve `NOMBRE` y `CARGO` del contrato (pueden
no estar en `EMPLEADOS` todavía) y una columna `VINCULO`
(`PENDIENTE` / `VINCULADO`). No frena si no hay contratos: devuelve 0 filas.
Frena si la cédula viene vacía.

> **Histórico:** hasta el 19/10/2026 existía `SP_CONTRATOS_POR_EMPLEADO`, que
> pedía `ID_EMPLEADO`; el contrato ahora se busca por cédula.

> **Histórico:** el bloque hace `DROP PROCEDURE IF EXISTS SP_INSERTAR_CONTRATO`
> — fue sustituido por `SP_SUBIR_CONTRATO` en el feature de alta automática
> (18/10).

### Triggers

#### `TR_VINCULAR_CONTRATO` (AFTER INSERT en `EMPLEADOS`)

Cuando se da de alta a un empleado, completa `ID_EMPLEADO` en sus contratos
huérfanos de esa cédula (`WHERE CEDULA = NEW.CEDULA AND ID_EMPLEADO IS NULL`).
No crea ni modifica nada más: **el alta sigue siendo del módulo de empleados**;
el trigger solo cierra el vínculo que faltaba.

Es el **único `AFTER INSERT` de `EMPLEADOS`**, así que no hay orden que cuidar
ni `FOLLOWS` que respetar.

#### `TR_ALTA_EMPLEADO` (eliminado)

Existió hasta el 19/10/2026: era un `BEFORE INSERT` sobre `CONTRATOS` que creaba
al empleado si la cédula no existía. Se eliminó porque un contrato es un
documento, no el origen de un registro maestro: crear empleados desde ahí dejaba
altas sin control (sin usuario, sin revisión de RRHH) y dependía del
`AUTO_INCREMENT`. El bloque conserva un `DROP TRIGGER IF EXISTS` para limpiar
las bases donde todavía exista.

### Reglas de negocio

- **Snapshot inmutable:** los datos de la persona en `CONTRATOS` reflejan lo
  firmado; los cambios posteriores del empleado no alteran el contrato.
- **`FECHA_FIN NULL` = contrato FIJO** (permanente); TEMPORAL siempre vence.
- **Un solo contrato ACTIVO por cédula** (lo valida el SP antes del insert).
- **El contrato no crea empleados:** subir un contrato solo registra el papel.
  El alta se hace después y el trigger completa el vínculo.
- **La cédula es la llave:** buscar, listar y finalizar se hacen por cédula, no
  por `ID_EMPLEADO` ni por `ID_CONTRATO`.
- **El escaneo es opcional:** RRHH decide dónde archiva el papel; la app solo
  copia el archivo a `contratos/firmados/` si se lo indican (PDF/JPG/PNG, hasta
  20 MB). No se guarda en la base.
- **El contrato no actualiza al empleado:** si cambió el cargo o el salario, se corrige en el módulo de empleados. El contrato guarda el snapshot de lo firmado.
- **Al despedir se finaliza a mano** (opción del menú de empleados).
- Todos los frenos usan `SIGNAL SQLSTATE '45000'` con mensaje en mayúsculas
  para la UI.

### Notas de buenas prácticas (referencias externas)

1. **Errores personalizados con `SIGNAL '45000'`.** La KB de MariaDB recomienda
   exactamente el SQLSTATE `45000` para errores definidos por el usuario; si
   nadie lo captura con un `HANDLER`, el programa almacenado termina con ese
   error y **la sentencia que lo provocó no se ejecuta** — por eso un freno
   saltado deja la BD sin cambios. Fuente:
   [MariaDB — SIGNAL](https://mariadb.com/kb/en/signal/)
2. **`ENUM` se guarda como índice numérico** (1 o 2 bytes según la lista), y en
   modo *strict* (`sql_mode` por defecto en instalaciones actuales) insertar un
   valor fuera de la lista **falla** con `ERROR 1265 (Data truncated)` en vez de
   meter un vacío silencioso: conviene porque los frenos de `TIPO`/`ESTADO`
   son estrictos. Además, una columna `NOT NULL` sin `DEFAULT` explícito toma
   como default el **primer** valor de la lista (por eso `ESTADO` declara
   `DEFAULT 'ACTIVO'` de forma explícita). Fuente:
   [MariaDB — ENUM](https://mariadb.com/kb/en/enum/)
3. **`BEFORE` triggers pueden modificar la fila que va a insertarse.** En un
   trigger `BEFORE INSERT` está permitido hacer `SET NEW.columna = valor`, y en
   uno posterior ya no: en `AFTER INSERT` la fila está escrita y `NEW` es de
   solo lectura. Por eso un `AFTER` no puede completar una FK obligatoria; en
   triggers de INSERT solo existe `NEW` (no hay `OLD`). Fuente:
   [MariaDB — CREATE TRIGGER](https://mariadb.com/kb/en/create-trigger/)
