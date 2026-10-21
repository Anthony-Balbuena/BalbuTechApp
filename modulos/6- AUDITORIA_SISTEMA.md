# Módulo 6 — AUDITORIA_SISTEMA

Bitácora genérica del sistema: qué tabla se tocó, qué registro, qué acción, quién
y con qué valores antes y después. Es la tabla donde escriben los triggers de
auditoría de otros módulos (`27` y `40`, además de los dos de este archivo).

**Depende de:** `PROVEEDORES` (5) para sus dos triggers.
**Es usada por:** `27_SP_FINALIZAR_RECLAMO_TOTAL` (27) y `TR_MAPA_COMPRA_RECIBIDA`
(40); los módulos de UI **no** la consultan.

> **La app no lee ni llama nada de este módulo**: ni los dos `SP` de consulta, ni
> el de limpieza. La tabla solo recibe filas.

Fuente: `modulos/6- AUDITORIA_SISTEMA.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### AUDITORIA_SISTEMA

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_AUDITORIA` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `TABLA_AFECTADA` | `VARCHAR(50)` | NOT NULL | Nombre de la tabla tocada (`PROVEEDORES`, `RECLAMOS_GARANTIAS`, `COMPRAS`…). |
| `ID_REGISTRO_AFECTADO` | `INT` | NOT NULL | ID del registro. **Sin FK**: es genérico, apunta a tablas distintas. |
| `ACCION` | `ENUM('INSERT','UPDATE','DELETE')` | NOT NULL | Acción. |
| `USUARIO_SISTEMA` | `VARCHAR(50)` | NOT NULL | **Usuario de la base** (`balbu_app`), no el de la app. |
| `FECHA_HORA` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `VALOR_ANTERIOR` | `TEXT` | NULL | Texto libre (los triggers arman un `CONCAT`, no JSON). |
| `VALOR_NUEVO` | `TEXT` | NULL | Texto libre. |

**Índices:** `IX_AUDITORIA_FECHA` (`FECHA_HORA`) e `IX_AUDITORIA_TABLA`
(`TABLA_AFECTADA`).

> **`USUARIO_SISTEMA` no dice quién hizo el cambio en la app.** Los triggers usan
> `USER()`, que devuelve el usuario de MySQL: todas las filas de una sesión
> quedan como `balbu_app`. Para saber *qué persona* lo hizo haría falta que la app
> pasara su usuario, y no lo hace.
>
> **No hay FK ni `ON DELETE`**: borrar un proveedor o un reclamo deja su auditoría
> huérfana, que es justamente lo que se busca en una bitácora.

## Procedimientos almacenados

### `6_SP_LISTAR_AUDITORIA_GENERAL(P_TABLA, P_FECHA_INICIO, P_FECHA_FIN)`

Lista la bitácora con `SELECT *`, filtrando por tabla exacta y rango de fechas;
sin filtros trae todo desde 1900 hasta hoy, de lo más nuevo a lo más viejo.

> **El `DROP` no coincide con el `CREATE`**: se borra
> `SP_LISTAR_AUDITORIA_GENERAL` (sin el `6_`) y se crea
> `6_SP_LISTAR_AUDITORIA_GENERAL`. Si una base vieja tiene la versión sin prefijo,
> **queda viva para siempre** y conviven las dos.
>
> **`DATE(FECHA_HORA)` anula el índice**: la función sobre la columna impide que
> `IX_AUDITORIA_FECHA` se use para el rango. Con la bitácora grande, el filtro por
> fecha recorre la tabla completa.
>
> **Sin `LIMIT`**: la pantalla se traga la tabla entera.

### `6_SP_CONSULTAR_HISTORIAL_REGISTRO(P_TABLA, P_ID_REGISTRO)`

El historial de **un** registro concreto: `ID_AUDITORIA`, `ACCION`,
`USUARIO_SISTEMA`, `FECHA_HORA`, `VALOR_ANTERIOR`, `VALOR_NUEVO`, del más nuevo al
más viejo.

> Mismo defecto de nombre: el `DROP` es sin `6_` y el `CREATE` con prefijo.

### `SP_LIMPIAR_AUDITORIA(P_DIAS_ANTIGUEDAD)`

Borra lo más viejo que `P_DIAS_ANTIGUEDAD` días y devuelve
`LIMPIEZA COMPLETADA: SE HAN ELIMINADO REGISTROS CON MÁS DE <días> DÍAS.`

- días nulos, `0` o negativos → `ERROR: LOS DIAS DEBEN SER MAYORES A CERO.`

> **El mensaje miente un poco**: dice cuántos días, no cuántas filas borró (a
> diferencia de `SP_LIMPIAR_LOGS_ANTIGUOS` en 28, que sí cuenta).
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

> **Solo auditan tres columnas.** Si cambia la dirección u otro campo, la fila se
> escribe igual pero **no muestra qué cambió**.
>
> **`AFTER UPDATE` sin comparar**: se escribe una fila en **cada** `UPDATE`, aunque
> no haya cambiado nada. Un `UPDATE` que actualiza lo mismo deja ruido.
>
> **No hay auditoría de `DELETE`** en ningún módulo: el `ENUM` admite `DELETE`
> pero ningún trigger lo usa.

### Triggers mudados

`TR_AUDITORIA_PRODUCTOS_UPDATE` (cambio de precio) **se movió al módulo 9**, con
su tabla. Acá queda solo el comentario.

## Reglas de negocio

- **Toda fila de auditoría apunta a una tabla y un registro** por nombre + ID.
- **El "quién" es el usuario de la base**, no la persona de la app.
- **Los valores se guardan como texto**, no como JSON.
- **Borrar la tabla auditada no borra su auditoría.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
