# Módulo 28 — LOG_ACCESOS

Registro de intentos de login: quién, cuándo y si salió bien. Es la bitácora de
seguridad del sistema.

**Depende de:** `USUARIOS` (10).
**Es usado por:** el login (`login.cpp`), que anota cada intento, y el menú
principal (`roles.cpp`), que abre la pantalla **Accesos** solo para quien tiene el
permiso `GESTIONAR_ROLES` (ADMIN).

> Módulo de los "archivos vacíos": el encabezado anuncia secciones de *store
> procedures*, *triggers*, *views* y *functions*, pero solo hay `SP`.

> **Absorbe el `64` (14/11/2026):** el bloqueo por fuerza bruta —el índice de
> `LOG_ACCESOS` y `SP_ESTADO_BLOQUEO_LOGIN`— vive ahora **en este mismo archivo**,
> al final, en la sección «SEGURIDAD_T2 (ex módulo 64)». De sus tres objetos no
> entra `FN_TIENE_PERMISO`: el `36` ya define la versión final.

Fuente: `modulos/28-LOG_ACCESOS.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

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

## SEGURIDAD_T2 (ex módulo 64)

Bloqueo por fuerza bruta: absorbido dentro del `28` el 14/11/2026 (ver «Estado de
la documentación» y el `## Log` de `odd/tasks/consolidacion-modulos.md`).

Del ex `64` entran acá **dos de sus tres objetos**, verbatim: el índice y el `SP`.
La `FN_TIENE_PERMISO` que también traía **no entra**, porque el `36` ya define la
versión final (ignora cuentas con `ESTADO <> 'ACTIVO'`) y reimportar el `36` la
vuelve a crear: en el `64` era una copia sin efecto. Queda una sola definición.

Cierra el hallazgo A4 de la auditoría del 03/11 en una base ya importada, sin
reimportar la matriz de permisos:

| Objeto | Tipo | Qué cambia |
|---|---|---|
| `IX_LOG_ACCESOS_USUARIO_FECHA` | índice | `(USUARIO_INTENTADO, FECHA_ACCESO)` sobre `LOG_ACCESOS` |
| `SP_ESTADO_BLOQUEO_LOGIN` | procedimiento | devuelve `FALLOS` y `MINUTOS` de un usuario |

El `28` ya declara el índice **inline** en el `CREATE TABLE` (línea 18) para una
base nueva; el `ALTER` idempotente de esta sección es el que lo agrega en una
base viva, donde el `CREATE TABLE` no corre (da `1050`).

Fuente: `modulos/28-LOG_ACCESOS.sql`, sección del ex módulo `64` · Base:
`BALBU_TECH` · Revisado: 03/11/2026 · Fusionado: 14/11/2026.

### Por qué

- **El índice.** El login cuenta fallos con
  `USUARIO_INTENTADO = ? AND ESTADO_INTENTO = 'FALLIDO' AND FECHA_ACCESO >= NOW() - INTERVAL 15 MINUTE`.
  Sin índice eso es un recorrido completo de `LOG_ACCESOS` en cada intento, o
  sea que un atacante podía convertir el bloqueo en una carga al servidor.
  La clave compuesta deja el filtro como rango: usuario fijo y fecha ordenada.
- **El conteo del bloqueo.** La app no puede leer `LOG_ACCESOS` (le abriría
  todo el historial de accesos), pero necesita saber cuántos fallos lleva la
  cuenta. `SP_ESTADO_BLOQUEO_LOGIN` corre como `DEFINER` y devuelve solo dos
  números.

El umbral no vive en el SQL: `P_VENTANA_MIN` llega desde `login.cpp`
(`VENTANA_BLOQUEO_MIN`) para que la ventana se cambie en un solo lugar.

### Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/28-LOG_ACCESOS.sql"
```

Es idempotente: el índice usa `ADD INDEX IF NOT EXISTS` y el procedimiento se
recrea con `DROP ... IF EXISTS`. Se puede correr las veces que haga falta.

> **Corrección al fusionar (14/11/2026):** el texto original decía «Orden:
> después de `28` y `36` (necesita `LOG_ACCESOS` y `FN_TIENE_PERMISO`). Antes de
> `66`». Ahora los dos objetos viven en el `28`, al final, así que `LOG_ACCESOS`
> ya existe arriba. `FN_TIENE_PERMISO` ya no se toca acá: es del `36`. Y sigue
> yendo antes del `66`, que es posterior.

### Cómo funciona el bloqueo

1. Un acceso **exitoso** reinicia la cuenta sin borrar evidencia: solo cuentan
   los fallos posteriores al último `EXITOSO`.
2. Se cuentan los `FALLIDO` de la ventana vigente.
3. Al llegar al límite, `SP_LOGIN_AUTENTICAR` responde `BLOQUEADO` con los
   minutos que faltan y **no escribe** en `LOG_ACCESOS`. Si escribiera, cada
   reintento correría la ventana y el bloqueo no vencería nunca.
4. Vencida la ventana, la clave correcta vuelve a entrar.

### Verificación

Aplicado en `BALBU_TECH_TEST` y en `BALBU_TECH` el 03/11/2026 y el 05/11/2026.

- `db/test-lockout.sh`: cinco fallos bloquean, el intento bloqueado no deja
  fila, la clave correcta entra al vencer la ventana y `FN_TIENE_PERMISO`
  devuelve 0 para una cuenta `INACTIVO`.
- `db/test-login-servidor.sh` e2e: el login usa el índice; el conteo del SP
  coincide con el de `LOG_ACCESOS`.

> **`SP_ESTADO_BLOQUEO_LOGIN` sigue siendo candidato a borrar** (ítem 12c de
> `PENDIENTES.md`): la app no lo llama —el bloqueo lo hace
> `SP_LOGIN_AUTENTICAR` (65)— pero `db/check-app-sps.sh` lo espera y
> `db/mapear-permisos.sql` lo mapea. Borrarlo es una decisión de negocio, no
> parte de esta fusión: acá solo cambió de archivo.
