# Módulo 42 — CONTRATOS

Registro del **papel firmado**. El contrato nace antes que el empleado: la
opción 12 arma la oferta, la 13 coteja el borrador contra el papel y lo registra
con `SP_SUBIR_CONTRATO`. Subir un contrato **no crea empleados**: el alta se
hace después en el módulo de `EMPLEADOS` y ahí `TR_VINCULAR_CONTRATO` completa
`ID_EMPLEADO`.

La **cédula** es la llave real del contrato: existe desde la oferta y no cambia.
`ID_EMPLEADO` puede ser `NULL` (contrato huérfano, persona todavía sin alta).

Fuente: `modulos/42- CONTRATOS.sql` · Base: `BALBU_TECH` · Revisado: 19/10/2026.

## Tablas

### CONTRATOS

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

**Migración idempotente:** el archivo incluye, y se puede volver a correr
completo sin romper nada:

- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` de las 6 columnas de snapshot
  (`NOMBRE` … `FECHA_INGRESO`).
- `ALTER TABLE ... MODIFY ID_EMPLEADO INT NULL` (19/10/2026: el contrato ya no
  exige empleado).
- `IX_CONTRATOS_CEDULA`: la búsqueda normal pasa a ser por cédula. Se crea solo
  si falta (chequeo en `INFORMATION_SCHEMA.STATISTICS`).

## Procedimientos almacenados

### `SP_SUBIR_CONTRATO(P_NOMBRE, P_CEDULA, P_CARGO, P_SALARIO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO, P_TIPO, P_MESES, P_RUTA)`

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

### `SP_FINALIZAR_CONTRATO(P_ID_CONTRATO)`

Pasa un contrato de `ACTIVO` a `FINALIZADO` (a mano, p. ej. al despedir).
Frena si el ID es inválido, no existe o el contrato ya está finalizado.
`FECHA_FIN`: si era NULL (indefinido) se pone hoy; si el fijo vence a futuro
se corta a hoy; si ya venció, se conserva.

### `SP_CONTRATOS_POR_CEDULA(P_CEDULA)`

Historial completo de contratos de una persona, más reciente primero
(`ORDER BY ID_CONTRATO DESC`). Devuelve `NOMBRE` y `CARGO` del contrato (pueden
no estar en `EMPLEADOS` todavía) y una columna `VINCULO`
(`PENDIENTE` / `VINCULADO`). No frena si no hay contratos: devuelve 0 filas.
Frena si la cédula viene vacía.

> **Histórico:** hasta el 19/10/2026 existía `SP_CONTRATOS_POR_EMPLEADO`, que
> pedía `ID_EMPLEADO`; el contrato ahora se busca por cédula.

> **Histórico:** el archivo hace `DROP PROCEDURE IF EXISTS SP_INSERTAR_CONTRATO`
> — fue sustituido por `SP_SUBIR_CONTRATO` en el feature de alta automática
> (18/10).

## Triggers

### `TR_VINCULAR_CONTRATO` (AFTER INSERT en `EMPLEADOS`)

Cuando se da de alta a un empleado, completa `ID_EMPLEADO` en sus contratos
huérfanos de esa cédula (`WHERE CEDULA = NEW.CEDULA AND ID_EMPLEADO IS NULL`).
No crea ni modifica nada más: **el alta sigue siendo del módulo de empleados**;
el trigger solo cierra el vínculo que faltaba.

### `TR_ALTA_EMPLEADO` (eliminado)

Existió hasta el 19/10/2026: era un `BEFORE INSERT` sobre `CONTRATOS` que creaba
al empleado si la cédula no existía. Se eliminó porque un contrato es un
documento, no el origen de un registro maestro: crear empleados desde ahí dejaba
altas sin control (sin usuario, sin revisión de RRHH) y dependía del
`AUTO_INCREMENT`. El archivo conserva un `DROP TRIGGER IF EXISTS` para limpiar
las bases donde todavía exista.

## Reglas de negocio

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

## Notas de buenas prácticas (referencias externas)

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
