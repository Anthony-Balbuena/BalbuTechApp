# Módulo 42 — CONTRATOS

Registro de contratos de empleados: al firmar, el contrato se sube con
`SP_SUBIR_CONTRATO` y el trigger `TR_ALTA_EMPLEADO` crea o vincula al empleado
en `EMPLEADOS` de forma directa (los datos se piden una vez, en el contrato).

Fuente: `modulos/42- CONTRATOS.sql` · Base: `BALBU_TECH` · Revisado: 18/10/2026.

## Tablas

### CONTRATOS

Una fila por contrato firmado. Los datos de la persona (`NOMBRE` a
`FECHA_INGRESO`) son un **snapshot** de lo que se firmó: no cambian después
aunque cambie el empleado. Motor InnoDB.

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_CONTRATO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador del contrato. |
| `ID_EMPLEADO` | `INT` | FK → `EMPLEADOS(ID_EMPLEADO)`, NOT NULL | Empleado dueño del contrato; lo resuelve el trigger si llega NULL. |
| `TIPO` | `ENUM('TEMPORAL','FIJO')` | NOT NULL | TEMPORAL = término fijo con duración; FIJO = indefinido. |
| `FECHA_INICIO` | `DATE` | NOT NULL | Día de la firma (siempre `CURDATE()` al subir). |
| `FECHA_FIN` | `DATE` | NULL | NULL = contrato FIJO; con valor = vencimiento del TEMPORAL. |
| `SALARIO` | `DECIMAL(10,2)` | NOT NULL | Salario pactado en el contrato (exacto, 2 decimales). |
| `NOMBRE` | `VARCHAR(100)` | NULL | Snapshot del nombre firmado. |
| `CEDULA` | `VARCHAR(20)` | NULL | Snapshot de la cédula (sin UNIQUE acá: la unicidad la maneja `EMPLEADOS`). |
| `CARGO` | `VARCHAR(50)` | NULL | Snapshot del cargo. |
| `TELEFONO` | `VARCHAR(20)` | NULL | Snapshot del teléfono. |
| `EMAIL` | `VARCHAR(100)` | NULL | Snapshot del email. |
| `FECHA_INGRESO` | `DATE` | NULL | Fecha de ingreso de la persona (default: hoy). |
| `RUTA_DOCUMENTO` | `VARCHAR(255)` | NULL | Ruta del HTML del contrato generado por la app. |
| `ESTADO` | `ENUM('ACTIVO','FINALIZADO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo del contrato. |
| `FECHA_REGISTRO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento del registro en BD. |

**Migración idempotente:** el archivo incluye un `ALTER TABLE ... ADD COLUMN IF
NOT EXISTS` que agrega las 6 columnas de snapshot (`NOMBRE` … `FECHA_INGRESO`)
si la tabla ya existía sin ellas. Se puede volver a correr el archivo completo
sin romper nada.

## Procedimientos almacenados

### `SP_SUBIR_CONTRATO(P_NOMBRE, P_CEDULA, P_CARGO, P_SALARIO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO, P_TIPO, P_MESES, P_RUTA)`

Sube (registra) un contrato cuando la persona firma. No recibe ningún ID: los
resuelve el trigger. `P_MESES` solo aplica a TEMPORAL (para FIJO se pasa NULL y
`FECHA_FIN` queda NULL). `FECHA_INICIO` es siempre hoy.

Validaciones (`SIGNAL SQLSTATE '45000'`, la transacción corta):

1. Nombre, cédula y salario obligatorios (salario ≥ 0).
2. Tipo debe ser `TEMPORAL` o `FIJO`; TEMPORAL exige meses ≥ 1.
3. Esa cédula ya tiene un contrato ACTIVO → error (finalizarlo antes).
4. Ese empleado está INACTIVO → error.
5. Persona nueva: teléfono y email reales (no vacíos ni `"-"`) y que no
   pertenezcan a otro empleado (`TELEFONO`/`EMAIL` son UNIQUE en `EMPLEADOS`).

Devuelve un mensaje `EXITO: CONTRATO #<id> …` indicando si el empleado fue
**creado** o **vinculado**.

### `SP_FINALIZAR_CONTRATO(P_ID_CONTRATO)`

Pasa un contrato de `ACTIVO` a `FINALIZADO` (a mano, p. ej. al despedir).
Frena si el ID es inválido, no existe o el contrato ya está finalizado.
`FECHA_FIN`: si era NULL (indefinido) se pone hoy; si el fijo vence a futuro
se corta a hoy; si ya venció, se conserva.

### `SP_CONTRATOS_POR_EMPLEADO(P_ID_EMPLEADO)`

Historial completo de contratos de un empleado, más reciente primero
(`ORDER BY ID_CONTRATO DESC`). Frena si el ID es inválido o el empleado no
existe.

> **Histórico:** el archivo hace `DROP PROCEDURE IF EXISTS SP_INSERTAR_CONTRATO`
> — fue sustituido por `SP_SUBIR_CONTRATO` en el feature de alta automática
> (18/10).

## Triggers

### `TR_ALTA_EMPLEADO` — `BEFORE INSERT ON CONTRATOS FOR EACH ROW`

Resuelve `NEW.ID_EMPLEADO` antes de insertar el contrato (esto habilita la
alta directa sin pasar por "Agregar empleado"):

- Si el contrato ya trae `ID_EMPLEADO`, no toca nada (lo validó el SP y además
  lo cuida la llave foránea).
- Si llega NULL y falta la cédula → error.
- Cédula con **2 o más** empleados → error (ambigüedad; `CEDULA` no tiene
  UNIQUE en `EMPLEADOS`).
- Cédula con **1** empleado → le asigna ese mismo ID (no duplica) y frena si
  ese empleado está INACTIVO.
- Cédula sin empleado → lo **crea** en `EMPLEADOS` con `ESTADO 'ACTIVO'` a
  partir del snapshot del contrato y le asigna `LAST_INSERT_ID()`.

## Reglas de negocio

- **Snapshot inmutable:** los datos de la persona en `CONTRATOS` reflejan lo
  firmado; los cambios posteriores del empleado no alteran el contrato.
- **`FECHA_FIN NULL` = contrato FIJO** (permanente); TEMPORAL siempre vence.
- **Un solo contrato ACTIVO por cédula** (lo valida el SP antes del insert).
- **Alta automática de empleado al firmar:** los datos se piden una vez.
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
   trigger `BEFORE INSERT` está permitido hacer `SET NEW.columna = valor`, que
   es exactamente cómo `TR_ALTA_EMPLEADO` completa `NEW.ID_EMPLEADO` antes del
   insert; en triggers de INSERT solo existe `NEW` (no hay `OLD`). Fuente:
   [MariaDB — CREATE TRIGGER](https://mariadb.com/kb/en/create-trigger/)
