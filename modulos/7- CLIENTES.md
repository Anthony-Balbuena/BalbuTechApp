# Módulo 7 — CLIENTES

Maestro de clientes: nombre, teléfono y email **obligatorios y únicos**;
dirección opcional. El email tiene un chequeo de formato a nivel de tabla. No
se borran: se desactivan con toggle. Cada alta y cada cambio queda en la
bitácora `AUDITORIA_SISTEMA` por dos triggers.

Es el dueño lógico de las ventas (`VENTAS.ID_CLIENTE`).

Fuente: `modulos/7- CLIENTES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### CLIENTES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_CLIENTE` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador del cliente. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL | Nombre / razón social. |
| `TELEFONO` | `VARCHAR(20)` | NOT NULL, **UNIQUE** | Teléfono. Obligatorio. |
| `EMAIL` | `VARCHAR(100)` | NOT NULL, **UNIQUE** | Email. Obligatorio. |
| `DIRECCION` | `VARCHAR(150)` | NULL | Dirección. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado operativo. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Momento del alta. |

**Restricciones de tabla:**
- `CK_CLIENTE_NOMBRE`: `CHAR_LENGTH(TRIM(NOMBRE)) > 0`.
- `CK_CLIENTE_EMAIL`: `EMAIL LIKE '%@%.%'` — formato mínimo (arroba y punto
  después). No valida dominios reales.

## Procedimientos almacenados

### `SP_INSERTAR_CLIENTES(P_NOMBRE, P_TELEFONO, P_EMAIL, P_DIRECCION)`

**Usada por la app** (`clientes.cpp`).

**Limpieza:** nombre y dirección `TRIM` + colapso de espacios; teléfono solo
`TRIM`; email `LOWER(TRIM(...))`.

**Validaciones (`SIGNAL 45000`):**
- cualquiera de nombre/teléfono/email vacío →
  `ERROR: NOMBRE, TELÉFONO Y EMAIL SON OBLIGATORIOS.`
- teléfono ya registrado → `ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.`
- email ya registrado → `ERROR: ESTE EMAIL YA ESTÁ REGISTRADO.`

Inserta y devuelve `EXITO: CLIENTE "<nombre>" INSERTADO. ID: <id>`.

> **Nota:** el SP **no** valida el formato del email; si no cumple
> `CK_CLIENTE_EMAIL`, la base corta con el error técnico de CHECK
> (`ERROR 3819`), no con un mensaje amigable.

### `SP_ACTUALIZAR_CLIENTES(P_ID_CLIENTE, P_NOMBRE, P_TELEFONO, P_EMAIL, P_DIRECCION)`

**Usada por la app.** Actualización parcial: `NULL` conserva el valor
(`COALESCE`).

- ID inexistente → `ERROR: EL CLIENTE NO EXISTE.`
- Nombre vacío → `ERROR: EL NOMBRE NO PUEDE ESTAR VACÍO.`
- Teléfono de otro cliente → `ERROR: EL TELÉFONO YA PERTENECE A OTRO CLIENTE.`
- Email de otro cliente → `ERROR: EL EMAIL YA PERTENECE A OTRO CLIENTE.`
- Devuelve `EXITO: EL CLIENTE "<nombre>" FUE ACTUALIZADO. (EMAIL: <email>)`.

> **Inconsistencia de normalización:** el alta guarda el teléfono solo con
> `TRIM`, pero la actualización le quita espacios, paréntesis y guiones
> (`REGEXP_REPLACE(... '[[:space:]()\-]', '')`). El mismo número escrito con
> guiones puede entrar dos veces por el alta. El email sí se normaliza igual
> en ambos (minúsculas, sin espacios).

### `SP_LISTAR_CLIENTES(P_FILTRO)`

**La app no la llama.** Con filtro vacío/`NULL` devuelve todos; con texto
busca `LIKE` en nombre, teléfono **o** email. Devuelve las 7 columnas y
ordena **por nombre**.

> La app lista y busca clientes con `SELECT` directo en `clientes.cpp` (dos
> consultas), no con este SP. La rutina existe pero quedó sin uso.

### `SP_TOGGLE_ESTADO_CLIENTES(P_ID_CLIENTE)`

**Usada por la app.** Invierte `ACTIVO` ↔ `INACTIVO`. ID inexistente →
`ERROR: EL ID DEL CLIENTE NO EXISTE.` Devuelve
`SISTEMA: CLIENTE ACTIVADO|DESACTIVADO EXITOSAMENTE.`

> **Nota:** el mensaje usa el prefijo `SISTEMA:` (no `EXITO:` como el resto
> del módulo) y no incluye nombre ni ID. La UI lo muestra tal cual.

## Triggers

### `TR_AUDIT_CLIENTES_INSERT`

`AFTER INSERT ON CLIENTES`. Escribe en `AUDITORIA_SISTEMA`
(`TABLA_AFECTADA = 'CLIENTES'`, `ACCION = 'INSERT'`, `CURRENT_USER()`) y
guarda en `VALOR_NUEVO`: `Nombre: <nombre>, Email: <email>`.

### `TR_AUDIT_CLIENTES_UPDATE`

`AFTER UPDATE ON CLIENTES`. Misma bitácora con `ACCION = 'UPDATE'`, guardando
`VALOR_ANTERIOR` y `VALOR_NUEVO` con nombre y email de antes y después.

> La auditoría **no** guarda teléfono ni dirección; solo nombre y email.
> `AUDITORIA_SISTEMA` se crea en el módulo 6, anterior en el orden de import.

## Datos iniciales (seed)

Un `CALL SP_INSERTAR_CLIENTES('Jose Perez', '8097282431',
'perez01@gmail.com', 'Villa carmen')`.

> **No idempotente:** al reimportar sobre una base que ya lo tiene, el `CALL`
> responde `ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.` (o el de email) y el
> import lo reporta como sentencia con error.

## Reglas de negocio

- **Nombre, teléfono y email obligatorios**; teléfono y email **únicos**.
- **Email con formato mínimo** (`%@%.%`) garantizado por CHECK de tabla.
- **No hay borrado físico:** solo toggle de estado.
- **Auditoría automática** de altas y cambios vía triggers a
  `AUDITORIA_SISTEMA`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
