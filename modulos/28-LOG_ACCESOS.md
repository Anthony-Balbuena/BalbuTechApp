# Módulo 28 — LOG_ACCESOS

Registro de intentos de login: quién, cuándo y si salió bien. Es la bitácora de
seguridad del sistema.

**Depende de:** `USUARIOS` (10).
**Es usado por:** **nadie**. El login (`seguridad.cpp` / `login.cpp`) **no llama a
ningún `SP` de este módulo**, así que la tabla queda vacía en la práctica.

> Módulo de los "archivos vacíos": el encabezado anuncia secciones de *store
> procedures*, *triggers*, *views* y *functions*, pero solo hay `SP`.

Fuente: `modulos/28-LOG_ACCESOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### LOG_ACCESOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LOG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_USUARIO` | `INT` | NULL, FK → `USUARIOS` **ON DELETE SET NULL** | Quién intentó. |
| `FECHA_ACCESO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ESTADO_INTENTO` | `VARCHAR(50)` | NULL | Resultado, **texto libre**. |

> **`ON DELETE SET NULL` es la decisión correcta**: borrar el usuario no borra el
> intento de acceso, solo lo deja anónimo.
>
> **`ESTADO_INTENTO` no está acotado**: sin `ENUM`, sin `CHECK` y sin `NOT NULL`,
> así que conviven `EXITOSO`, `FALLIDO`, `fallido`, `FALLO` y `NULL` según quién
> lo escriba. Ninguna consulta puede agrupar con confianza.
>
> **No hay índice por fecha.** El `FK` crea uno sobre `ID_USUARIO`, pero
> `FECHA_ACCESO` —la columna por la que se filtra y se borra— se recorre entera.

## Procedimientos almacenados

### `SP_REGISTRAR_ACCESO(P_ID_USUARIO, P_ESTADO)`

Inserta el intento. **No valida nada**: ni que el usuario exista, ni el estado.

> **Con un usuario inexistente revienta por FK** (`1452`), no con un mensaje
> amable. Para anotar un intento con un nombre que no existe hay que pasar
> `NULL`, porque la columna lo admite.
>
> Es el único `SP` de la casa sin una sola validación.

### `SP_REPORTAR_ACCESOS()`

Los últimos **50** intentos: `FECHA_ACCESO`, `USUARIO`, `ESTADO_INTENTO`, del más
reciente al más viejo, con `LEFT JOIN` a `USUARIOS`.

> El `LEFT JOIN` es correcto: los intentos de usuarios borrados siguen
> apareciendo, con `USUARIO` en `NULL`.

### `SP_LIMPIAR_LOGS_ANTIGUOS(P_DIAS)`

Borra lo anterior a `CURDATE() - P_DIAS` días y devuelve
`LIMPIEZA COMPLETADA: <n> REGISTROS DE MAS DE <días> DIAS ELIMINADOS.`

- días nulos, `0` o negativos → `ERROR: LOS DIAS DEBEN SER MAYORES A CERO.`

> **El comentario dice "sin parámetro usa 120" y es falso**: `P_DIAS` no tiene
> valor por defecto, así que `CALL SP_LIMPIAR_LOGS_ANTIGUOS()` **falla**. Siempre
> hay que pasarle el número.
>
> Usa `CURDATE()` (día) y el de auditoría (6) usa `NOW()` (instante): no son
> equivalentes al borde del día.

## Reglas de negocio

- **Cada intento de acceso deja una fila** (siempre que alguien llame al `SP`).
- **Borrar un usuario no borra sus intentos.**
- **El resultado es texto libre**, sin catálogo cerrado.
- **La limpieza conserva los últimos N días** y exige `N > 0`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
