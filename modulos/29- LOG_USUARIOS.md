# Módulo 29 — LOG_USUARIOS

Bitácora de los cambios de **rol**, **estado** y **nombre de usuario**, con el
valor anterior y el nuevo, y **quién** lo hizo. Se alimenta sola desde un trigger
sobre `USUARIOS`.

**Depende de:** `USUARIOS` (10).
**Es usado por:** **la app no la consulta**. `SP_OBTENER_LOG_USUARIOS` y la vista
no aparecen en el código C++.

Fuente: `modulos/29- LOG_USUARIOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### LOG_USUARIOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LOG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_USUARIO` | `INT` | NULL, FK → `USUARIOS` | Usuario afectado. |
| `ACCION` | `VARCHAR(50)` | NULL | `CAMBIO_ROL`, `CAMBIO_ESTADO` o `CAMBIO_USUARIO`. |
| `VALOR_ANTERIOR` | `VARCHAR(255)` | NULL | Antes. |
| `VALOR_NUEVO` | `VARCHAR(255)` | NULL | Después. |
| `FECHA_CAMBIO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ID_USUARIO_ADMIN` | `INT` | NULL, FK → `USUARIOS` | Quién hizo el cambio. |

> **`ID_USUARIO_ADMIN` guarda al autor desde el 12/11/2026.** Sale de
> `@ID_USUARIO_ACTUAL`, que la app deja en la conexión al iniciar sesión: el
> trigger lo resuelve con un `SELECT` y, si no hay sesión o el usuario ya no
> existe, queda `NULL` —nunca aborta el cambio de usuario—. Antes la columna
> existía pero no se escribía nunca.
>
> **`ACCION` no está acotada**: `VARCHAR(50)` sin `CHECK` ni `ENUM`, para que
> agregar una acción nueva no requiera un `ALTER`.
>
> **Sin `ON DELETE`** en los dos FK: con una sola fila de log, el usuario ya no
> se puede borrar. Es un candado implícito, no declarado.
>
> El archivo tiene un **`DESCRIBE USUARIOS;` suelto** que se ejecuta en cada
> import (ruido en el log).

## Procedimientos almacenados

### `SP_OBTENER_LOG_USUARIOS()`

`SELECT * FROM VIEW_HISTORIAL_CAMBIOS_USUARIOS LIMIT 100`.

> **No ordena: la vista ya trae `ORDER BY`**, y `SELECT *` sobre una vista
> conserva el orden de su definición en MySQL. Funciona, pero el orden vive a
> dos saltos de distancia y es frágil.
>
> **100 filas sin paginación.**

## Triggers

### `TRG_AUDITORIA_USUARIOS` (`AFTER UPDATE ON USUARIOS`)

- si cambia `ID_ROL` → fila `CAMBIO_ROL` con los dos IDs como texto.
- si cambia `ESTADO` → fila `CAMBIO_ESTADO` con los dos estados.
- si cambia `USUARIO` → fila `CAMBIO_USUARIO` con el nombre anterior y el nuevo.

Las tres comparaciones usan `<=>` para tratar `NULL` sin sorpresas, y todas
escriben `ID_USUARIO_ADMIN` con el autor de la sesión.

> **Un solo `UPDATE` que cambie rol y estado deja dos filas**, no una. La
> bitácora se lee como eventos, no como versiones del registro.
>
> **Guarda IDs de rol, no nombres** (`CAST(OLD.ID_ROL AS CHAR)`): si el rol se
> renombra, el log sigue diciendo `3`.
>
> **No audita `INSERT` ni `DELETE` de usuarios**: solo cambios.

## Vistas

### `VIEW_HISTORIAL_CAMBIOS_USUARIOS`

`ID_LOG`, `USUARIO_AFECTADO` (el nombre, no el ID), `ACCION`, `VALOR_ANTERIOR`,
`VALOR_NUEVO`, `FECHA_CAMBIO`, `ID_USUARIO_ADMIN` y `USUARIO_ADMIN` (el nombre
del que hizo el cambio), del más nuevo al más viejo.

> Usa `LEFT JOIN` en los dos usuarios: si una cuenta se borra, el registro no
> desaparece, solo se queda sin nombre.

## Reglas de negocio

- **Cada cambio de rol, de estado o de nombre de usuario deja una fila.**
- **El rol se guarda por ID, no por nombre.**
- **Se registra quién hizo el cambio** cuando hay sesión; sin sesión queda
  `NULL` y el cambio se aplica igual.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
