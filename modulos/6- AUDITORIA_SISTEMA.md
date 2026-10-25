# Módulo 6 — AUDITORIA_SISTEMA

Bitácora genérica del sistema: qué tabla se tocó, qué registro, qué acción, quién
y con qué valores antes y después. Es la tabla donde escriben los triggers de
auditoría de otros módulos (`27` y `40`, además de los tres de este archivo).

**Depende de:** `PROVEEDORES` (5) para sus tres triggers.
**Es usada por:** `27_SP_FINALIZAR_RECLAMO_TOTAL` (27) y `TR_MAPA_COMPRA_RECIBIDA`
(40); los módulos de UI **no** la consultan.

> **La app no lee ni llama nada de este módulo**: ni los dos `SP` de consulta, ni
> el de limpieza. La tabla solo recibe filas.

Fuente: `modulos/6- AUDITORIA_SISTEMA.sql` · Base: `BALBU_TECH` · Revisado: 25/10/2026.

## Tablas

### AUDITORIA_SISTEMA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_AUDITORIA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `TABLA_AFECTADA` | `VARCHAR(50)` | NOT NULL | Nombre de la tabla tocada (`PROVEEDORES`, `RECLAMOS_GARANTIAS`, `COMPRAS`…). |
| `ID_REGISTRO_AFECTADO` | `INT` | NOT NULL | ID del registro. **Sin FK**: es genérico, apunta a tablas distintas. |
| `ACCION` | `ENUM('INSERT','UPDATE','DELETE')` | NOT NULL | Acción. |
| `USUARIO_SISTEMA` | `VARCHAR(50)` | NOT NULL | Nombre del usuario de la app (`@ID_USUARIO_ACTUAL`); si no está, el de la base. |
| `FECHA_HORA` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `VALOR_ANTERIOR` | `TEXT` | NULL | Texto libre (los triggers arman un `CONCAT`, no JSON). |
| `VALOR_NUEVO` | `TEXT` | NULL | Texto libre. |

**Índices:** `IX_AUDITORIA_FECHA` (`FECHA_HORA`) e `IX_AUDITORIA_TABLA`
(`TABLA_AFECTADA`).

> **`USUARIO_SISTEMA` ya distingue a la persona.** La app deja su id en
> `@ID_USUARIO_ACTUAL` al iniciar sesión y el trigger busca el nombre en
> `USUARIOS`. Si no hay variable (un cambio por consola), cae a `USER()`, el
> usuario de MySQL. Ver módulo 57.
>
> **No hay FK ni `ON DELETE`**: borrar un proveedor o un reclamo deja su auditoría
> huérfana, que es justamente lo que se busca en una bitácora.

## Procedimientos almacenados

### `6_SP_LISTAR_AUDITORIA_GENERAL(P_TABLA, P_FECHA_INICIO, P_FECHA_FIN)`

Lista la bitácora con `SELECT *`, filtrando por tabla exacta y rango de fechas;
sin filtros trae todo desde 1900 hasta hoy, de lo más nuevo a lo más viejo.

> **Rango indexable.** El filtro usa `FECHA_HORA >= inicio` y
> `FECHA_HORA < fin + 1 día`, así `IX_AUDITORIA_FECHA` sirve y el día final entra
> completo. Antes era `DATE(FECHA_HORA) BETWEEN …`, que anulaba el índice.
>
> **Tope de 500 filas** para no tragarse la tabla entera.

> **Nombre.** El `DROP` ahora borra las dos variantes (con y sin `6_`), así un
> reimport no deja una versión vieja viva. Ver módulo 57.

### `6_SP_CONSULTAR_HISTORIAL_REGISTRO(P_TABLA, P_ID_REGISTRO)`

El historial de **un** registro concreto: `ID_AUDITORIA`, `ACCION`,
`USUARIO_SISTEMA`, `FECHA_HORA`, `VALOR_ANTERIOR`, `VALOR_NUEVO`, del más nuevo al
más viejo.

> El `DROP` borra las dos variantes (con y sin `6_`). Ver módulo 57.

### `SP_LIMPIAR_AUDITORIA(P_DIAS_ANTIGUEDAD)`

Borra lo más viejo que `P_DIAS_ANTIGUEDAD` días y devuelve
`LIMPIEZA COMPLETADA: <n> REGISTROS DE MAS DE <días> DIAS ELIMINADOS.`

- días nulos, `0` o negativos → `ERROR: LOS DIAS DEBEN SER MAYORES A CERO.`

> **Cuenta las filas borradas** con `ROW_COUNT()`, igual que
> `SP_LIMPIAR_LOGS_ANTIGUOS` en 28.
>
> **Es el único camino que borra auditoría** y no valida permisos: cualquiera que
> pueda ejecutar procedimientos puede vaciar la bitácora.
>
> El contraste con el comentario de la tabla ("nada se borra solo") es real: nada
> se borra **solo**, pero este `SP` existe para hacerlo a mano.

## Triggers

### `TR_AUDIT_PROVEEDORES_INSERT` (`AFTER INSERT ON PROVEEDORES`)

Anota `INSERT` con `VALOR_NUEVO = 'Nombre: <n>, Tel: <t>, Email: <e>'`.

### `TR_AUDIT_PROVEEDORES_UPDATE` (`AFTER UPDATE ON PROVEEDORES`)

Anota `UPDATE` con el mismo formato en `VALOR_ANTERIOR` y `VALOR_NUEVO`.

### `TR_AUDIT_PROVEEDORES_DELETE` (`AFTER DELETE ON PROVEEDORES`)

Anota `DELETE` con los datos que tenía el proveedor en `VALOR_ANTERIOR`. Es el
único `DELETE` auditado del sistema: la fila sobrevive aunque el proveedor ya no
exista.

> **Solo auditan tres columnas.** Si cambia la dirección u otro campo, la fila se
> escribe igual pero **no muestra qué cambió**.
>
> **`AFTER UPDATE` sin comparar**: se escribe una fila en **cada** `UPDATE`, aunque
> no haya cambiado nada. Un `UPDATE` que actualiza lo mismo deja ruido.
>
> **`DELETE` auditado solo en proveedores.** `CLIENTES`, `PRODUCTOS` y
> `RECLAMOS_GARANTIAS` todavía no tienen trigger de `DELETE`; el `ENUM` lo admite.

### Triggers mudados

`TR_AUDITORIA_PRODUCTOS_UPDATE` (cambio de precio) **se movió al módulo 9**, con
su tabla. Acá queda solo el comentario.

## Reglas de negocio

- **Toda fila de auditoría apunta a una tabla y un registro** por nombre + ID.
- **El "quién" es el nombre del usuario de la app** (`@ID_USUARIO_ACTUAL`); si no está, el usuario de MySQL.
- **Los valores se guardan como texto**, no como JSON.
- **Borrar la tabla auditada no borra su auditoría.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
