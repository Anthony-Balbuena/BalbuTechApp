# Módulo 29 — LOG_USUARIOS

Bitácora de los cambios de **rol** y **estado** de un usuario, con el valor
anterior y el nuevo. Se alimenta sola desde un trigger sobre `USUARIOS`.

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
| `ACCION` | `VARCHAR(50)` | NULL | `CAMBIO_ROL` o `CAMBIO_ESTADO`. |
| `VALOR_ANTERIOR` | `VARCHAR(255)` | NULL | Antes. |
| `VALOR_NUEVO` | `VARCHAR(255)` | NULL | Después. |
| `FECHA_CAMBIO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ID_USUARIO_ADMIN` | `INT` | NULL, FK → `USUARIOS` | Quién hizo el cambio. |

> **`ID_USUARIO_ADMIN` queda siempre en `NULL`.** La columna existe, el
> comentario del archivo dice "quién realizó el cambio", pero el trigger **no la
> escribe**. El `SP` de alta de usuarios (10) no deja rastro del admin en ninguna
> variable, así que no hay de dónde sacarlo.
>
> **`ACCION` no está acotada** y el comentario promete `CAMBIO_USUARIO`, que
> **nunca se genera**: cambiar el nombre de usuario no deja fila.
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

- si `OLD.ID_ROL <> NEW.ID_ROL` → fila `CAMBIO_ROL` con los dos IDs como texto.
- si `OLD.ESTADO <> NEW.ESTADO` → fila `CAMBIO_ESTADO` con los dos estados.

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
`VALOR_NUEVO`, `FECHA_CAMBIO`, del más nuevo al más viejo.

> El `INNER JOIN` **oculta** los cambios de usuarios borrados. Como el `FK` sin
> `ON DELETE` impide borrar, en la práctica no hay caso, pero la vista depende de
> eso.

## Reglas de negocio

- **Cada cambio de rol o de estado deja una fila.**
- **El rol se guarda por ID, no por nombre.**
- **No se registra quién hizo el cambio** (`ID_USUARIO_ADMIN` siempre `NULL`).
- **Cambiar el nombre de usuario no deja rastro.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
