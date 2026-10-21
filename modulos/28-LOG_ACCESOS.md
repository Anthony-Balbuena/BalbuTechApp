# Módulo 28 — LOG_ACCESOS

Registro de intentos de login: quién, cuándo y si salió bien. Es la bitácora de
seguridad del sistema.

**Depende de:** `USUARIOS` (10).
**Es usado por:** el login (`login.cpp`), que anota cada intento, y el menú
principal (`roles.cpp`), que abre la pantalla **Accesos** solo para quien tiene el
permiso `GESTIONAR_ROLES` (ADMIN).

> Módulo de los "archivos vacíos": el encabezado anuncia secciones de *store
> procedures*, *triggers*, *views* y *functions*, pero solo hay `SP`.

Fuente: `modulos/28-LOG_ACCESOS.sql` · Base: `BALBU_TECH` · Revisado: 21/10/2026.

## Tablas

### LOG_ACCESOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_LOG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_USUARIO` | `INT` | NULL, FK → `USUARIOS` **ON DELETE SET NULL** | Cuenta que intentó; `NULL` si el nombre no existe o la cuenta se borró. |
| `USUARIO_INTENTADO` | `VARCHAR(50)` | NOT NULL | Nombre tecleado en el login. |
| `FECHA_ACCESO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ESTADO_INTENTO` | `ENUM('EXITOSO', 'FALLIDO', 'INACTIVO')` | NOT NULL | Resultado del intento. |

> **`ON DELETE SET NULL` es la decisión correcta**: borrar el usuario no borra el
> intento de acceso, solo lo deja sin `ID_USUARIO`. El nombre sobrevive en
> `USUARIO_INTENTADO`, así que la fila no queda anónima.

> **`ESTADO_INTENTO` es un catálogo cerrado** de tres valores. Antes era
> `VARCHAR(50)` libre, sin catálogo: entraba cualquier texto, incluido `NULL`.

> **No hay índice por fecha.** El `FK` crea uno sobre `ID_USUARIO`, pero
> `FECHA_ACCESO` —la columna por la que se ordena y se borra— se recorre entera.

## Procedimientos almacenados

### `SP_REGISTRAR_ACCESO(P_ID_USUARIO, P_USUARIO_INTENTADO, P_ESTADO)`

Inserta el intento. Valida:

- `P_USUARIO_INTENTADO` nulo o vacío →
  `ERROR: EL USUARIO ES OBLIGATORIO.`
- `P_ESTADO` fuera de `EXITOSO`, `FALLIDO`, `INACTIVO` →
  `ERROR: ESTADO DE INTENTO INVALIDO.`

> **No valida que el usuario exista**: `P_ID_USUARIO` se guarda tal cual. Con un
> ID inexistente responde la FK (`1452`); para anotar un nombre desconocido se
> pasa `NULL` en el ID y el nombre en `P_USUARIO_INTENTADO`, que es lo que hace
> el login cuando no encuentra la cuenta.

> **La app nunca deja que este `SP` corte el acceso**: `login.cpp` envuelve el
> `CALL` en un `try` que ignora cualquier error del log.

### `SP_REPORTAR_ACCESOS()`

Los últimos **50** intentos: `FECHA_ACCESO`, `USUARIO_INTENTADO`,
`ESTADO_INTENTO`, del más reciente al más viejo
(`FECHA_ACCESO DESC, ID_LOG DESC`).

> **Sin `LEFT JOIN`**: el nombre no se toma de `USUARIOS`, vive en el propio log.
> Los intentos de cuentas borradas siguen mostrando el nombre tecleado.

### `SP_LIMPIAR_LOGS_ANTIGUOS(P_DIAS)`

Borra lo anterior a `CURDATE() - P_DIAS` días y devuelve
`LIMPIEZA COMPLETADA: <n> REGISTROS DE MAS DE <días> DIAS ELIMINADOS.`

- `P_DIAS` es **obligatorio** y debe ser `> 0`; nulo, `0` o negativo →
  `ERROR: LOS DIAS DEBEN SER MAYORES A CERO.`

> **No hay valor por defecto**: `CALL SP_LIMPIAR_LOGS_ANTIGUOS()` falla. La
> pantalla propone 120 días, pero el número viaja siempre en el `CALL`.
>
> Usa `CURDATE()` (día) y el de auditoría (6) usa `NOW()` (instante): no son
> equivalentes al borde del día.

## Reglas de negocio

- **Cada intento de login deja una fila**: usuario inexistente o clave
  incorrecta → `FALLIDO`; clave correcta pero cuenta inactiva → `INACTIVO`;
  acceso correcto → `EXITOSO`.
- **El log nunca bloquea el login**: si el `SP` falla, la app ignora el error y
  el acceso sigue su curso.
- **Borrar un usuario no borra sus intentos**: queda el nombre en
  `USUARIO_INTENTADO` y `ID_USUARIO` en `NULL`.
- **La limpieza conserva los últimos N días** y exige `N > 0`.
- **Solo ADMIN consulta la bitácora**: la pantalla Accesos se habilita con
  `GESTIONAR_ROLES`.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
