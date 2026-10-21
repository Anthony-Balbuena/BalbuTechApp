# Módulo 30 — LOG_AUDITORIA_PERMISOS

Bitácora de los cambios de estado de los permisos de empleados: estado anterior,
estado nuevo y cuándo. La alimenta un trigger sobre `PERMISOS_EMPLEADOS`.

**Depende de:** `PERMISOS_EMPLEADOS` (13).
**Es usado por:** **nadie**: no hay `SP` de consulta ni la lee la app.

> Es el módulo más chico de la casa: una tabla y un trigger. No tiene `SP`,
> vistas ni funciones.

Fuente: `modulos/30- LOG_AUDITORIA_PERMISOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### LOG_AUDITORIA_PERMISOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LOG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_PERMISO` | `INT` | NULL, FK → `PERMISOS_EMPLEADOS` **ON DELETE SET NULL** | Permiso afectado. |
| `ESTADO_ANTERIOR` | `VARCHAR(20)` | NULL | Estado previo. |
| `ESTADO_NUEVO` | `VARCHAR(20)` | NULL | Estado nuevo. |
| `FECHA_CAMBIO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |

> **`ON DELETE SET NULL` a propósito** (cambio del 10/10/2026): borrar un permiso
> **no** debe destruir su bitácora. Antes era `CASCADE`. Es la decisión correcta
> para una tabla de auditoría.
>
> **No guarda quién hizo el cambio**, solo el antes/después y la fecha. Para
> saber quién, hay que cruzar con otra bitácora —y no hay ninguna que registre
> esa acción.
>
> **`VARCHAR(20)` en vez del `ENUM` de origen**: si mañana el estado se alarga,
> acá no rompe, pero tampoco hay validación.

## Triggers

### `TR_LOG_GESTION_PERMISO` (`AFTER UPDATE ON PERMISOS_EMPLEADOS`)

Solo si `OLD.ESTADO <> NEW.ESTADO`, inserta la fila con el estado anterior y el
nuevo.

> **No audita el alta ni el `DELETE` de un permiso**: un permiso nuevo, o uno
> borrado, no deja fila. La bitácora arranca en la primera modificación.
>
> **Sin acceso a la bitácora**, el registro se acumula y nunca se lee desde el
> sistema: sirve solo para consulta manual por SQL.

## Reglas de negocio

- **Cada cambio de estado de un permiso deja una fila.**
- **Cambiar a lo mismo no registra nada.**
- **Borrar el permiso no borra su historial**, solo lo desvincula.
- **El alta y el borrado no se auditan.**
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
