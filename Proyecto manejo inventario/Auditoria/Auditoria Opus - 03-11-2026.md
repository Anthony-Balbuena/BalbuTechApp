# Auditoría Opus — Código, BD y hallazgos (03-11-2026)

**Alcance.** Revisión estática de los 24 módulos C++ de la raíz (~9.000 líneas propias), 64 archivos SQL de `modulos/` (45 tablas, 64 FK, 60 índices secundarios, 170 procedimientos, 108 triggers), scripts de `db/`, Docker (`docker-compose.yml`, `.devcontainer/`), web estática (`Pagina_Web/`) y estado de git.

**Método.** Lectura directa y búsqueda dirigida, sin modificar código ni datos. Complementa —no reemplaza— a `Auditoria completa - Codigo y BD - 18-10-2026.md`.

**Veredicto en una línea.** La arquitectura y la base de datos están bien hechas (transacciones, `FOR UPDATE`, `DECIMAL`, PBKDF2, prepared statements); los problemas reales son **tres decisiones de producto**, **la higiene del repositorio** y **un control de permisos que solo existe en la interfaz**.

---

## Resumen numérico

| Severidad | Cantidad |
| --- | --- |
| Crítico | 1 |
| Alto | 6 |
| Medio | 8 |
| Bajo | 8 |
| **Total** | **23** |

---

## 1. Las dos dudas abiertas: verificadas

### 1.1 ¿Los SP validan permisos del lado del servidor? — **NO**

Evidencia:

| Comprobación | Resultado |
| --- | --- |
| Usos reales de `FN_TIENE_PERMISO(...)` dentro de rutinas | **Cero.** Las únicas apariciones son `DROP` (`36- PERMISOS_ROLES.sql:452`), `CREATE` (`:459`) y un comentario en `10- USUARIOS.sql:402`. |
| Cláusulas `SQL SECURITY DEFINER/INVOKER` en las rutinas | **Cero** en los 64 archivos. Rigen con el definer por defecto (quien importó: `balbu_admin`). |
| `GRANT` / `CREATE USER` en el código del proyecto | **Ninguno** fuera de `backups/` (ignorado por git). El alta de usuarios de BD es manual. |
| Columnas de intentos fallidos o bloqueo en `USUARIOS` | **No existen.** La tabla es `ID_USUARIO, ID_EMPLEADO, ID_ROL, USUARIO, CONTRASENA, ESTADO, FECHA_CREACION`. |

**Conclusión.** El permiso se evalúa **solo en C++**, al construir el menú (`roles.cpp:74-98` y `:205-221`). Cualquier cliente que se conecte con las credenciales de `balbu_app` —que según `.env.example` tiene **DML + EXECUTE sobre todo `BALBU_TECH`**— puede ejecutar cualquier rutina: cambiar roles, ver sueldos, borrar movimientos. El menú es una puerta con cartel, no una cerradura.

**Agravante.** `@ID_USUARIO_ACTUAL` (15 referencias) lo **setea el cliente** (`login.cpp:102-108`) y ningún trigger lo valida contra una sesión autenticada. Cualquiera con `EXECUTE` puede hacer `SET @ID_USUARIO_ACTUAL = <otro id>` y **falsificar la autoría de la auditoría**.

**Mitigación existente.** La BD solo publica en `127.0.0.1:3307` y las claves viven en `.env`. El riesgo se materializa cuando alguien ya tiene acceso al host o al contenedor —que además monta el repo con escritura.

### 1.2 ¿Existe un SP de lockout por intentos fallidos sin conectar? — **NO existe**

Evidencia:

| Comprobación | Resultado |
| --- | --- |
| Rutinas en `28- LOG_ACCESOS.sql` | Tres: `SP_REGISTRAR_ACCESO`, `SP_REPORTAR_ACCESOS`, `SP_LIMPIAR_LOGS_ANTIGUOS`. Ninguna cuenta fallos ni bloquea. |
| Columnas de bloqueo en `USUARIOS` | No existen. |
| Búsqueda de `INTENTOS`, `BLOQUEO`, `LOCKOUT` en `modulos/` | Solo coincidencias textuales sin relación (liquidaciones, bloqueo de venta finalizada). |
| Índice sobre `LOG_ACCESOS.USUARIO_INTENTADO` o `FECHA_ACCESO` | No hay. Un conteo por ventana sería un scan completo. |

**Conclusión.** La única protección es `MAX_INTENTOS = 3` **por proceso** (`main.cpp:48-84`). Cerrar y reabrir la app reinicia el contador. Los intentos quedan registrados en `LOG_ACCESOS`, pero nadie los consulta en tiempo real.

---

## 2. Crítico

### C1. Datos personales versionados en git

`git ls-files` devuelve cuatro archivos bajo `contratos/`:

```
contratos/CONTRATO_JOse_2026-10-19.borrador
contratos/CONTRATO_JOse_2026-10-19.html
contratos/CONTRATO_Jose_Alcantara_2026-10-19.html
contratos/CONTRATO_Jose_Alcantara_2026-10-19.subido
```

Contienen nombre, fecha y salario. El `.gitignore` ya los excluye, pero **eso no borra lo ya commiteado**.

**Acción.** `git rm --cached contratos/*`, commit, y si el repo se compartió: `git filter-repo --path contratos/ --invert-paths`. Asumir que el dato ya se filtró.

---

## 3. Alto

### A1. `dinero()` imprime mal todos los montos

`seguridad.cpp:80-85` usa el `ostringstream` sin `fixed` ni `setprecision`:

```cpp
o << "$" << v;   // $75.5  y  $1.23457e+06
```

Se usa en el arqueo de caja (`caja.cpp:87-149`), compras y export web. En un punto de venta, un total en notación científica es inutilizable.

**Agravante.** Convive con un segundo formateador distinto (`compras.cpp:1096`, `snprintf("%.2f")`), y `productos.cpp:197` imprime `getDouble` crudo.

**Fix.** `o << "$" << fixed << setprecision(2) << v;` y unificar todos los usos.

### A2. Backdoor de login por variables de entorno

`main.cpp:34-46`: si existen `BALBU_USER` y `BALBU_PASS`, entra sin pedir credenciales y sin pasar por el contador de intentos. La clave queda visible en el historial del shell, en `ps` y en cualquier dump de entorno.

**Fix.** Compilar bajo `#ifndef NDEBUG` o exigir un flag explícito tipo `BALBU_ALLOW_DEV_LOGIN=1`.

### A3. La venta se puede atribuir a cualquier empleado

`ventas.cpp:335` y `compras.cpp:518` piden el ID de empleado **a mano**:

```cpp
string empStr = leerDatoSeguro("ID empleado: ");
```

El sistema ya conoce al usuario logueado (`sesionActual.idEmpleado`, usado bien en `ventas.cpp:1286`). Esto permite registrar una venta a nombre de otro: comisiones, control de caja y auditoría quedan falseados.

**Fix.** Usar `sesionActual.idEmpleado`; permitir override solo con permiso propio.

### A4. Sin lockout de fuerza bruta

Ver 1.2. Tres intentos por proceso, reiniciables.

**Fix.** Conteo por usuario en ventana de 15 minutos dentro del flujo de login, e índice sobre `LOG_ACCESOS(USUARIO_INTENTADO, FECHA_ACCESO)`.

**Estado (03/11/2026): RESUELTO, y el bloqueo es del servidor.** Módulo `64- SEGURIDAD_T2.sql` agrega `IX_LOG_ACCESOS_USUARIO_FECHA` y recrea `FN_TIENE_PERMISO` para que devuelva 0 con `ESTADO = 'INACTIVO'`. El módulo `65- LOGIN_SERVIDOR.sql` mueve el conteo y el registro dentro de `SP_LOGIN_AUTENTICAR` (5 fallos / 15 minutos), así que no se saltea llamando a la base desde otro cliente; un intento ya bloqueado no escribe en `LOG_ACCESOS` (si escribiera, cada reintento correría la ventana y el bloqueo no vencería nunca). `login.cpp` ya no cuenta nada: pide la verificación y recibe `BLOQUEADO` con los minutos restantes. `main.cpp` informa esos minutos y cierra el proceso. `MAX_INTENTOS = 3` queda igual: sigue siendo el corte por proceso y lo comparten ventas y compras. Regresión: `db/test-lockout.sh` (TEST), con `EXPLAIN` verificando el uso del índice. `EXPLAIN` en vivo: `range`, `rows=1`.

### A5. Contraseña visible al escribir

`main.cpp:61-65` lee la clave con `getline`, con eco en pantalla.

**Fix.** `_getch` en Windows, `termios` en Linux, o equivalente del conector.

### A6. Los permisos y la auditoría no se pueden sostener contra la BD

Ver 1.1. El menú es el único control; `@ID_USUARIO_ACTUAL` es falsificable por el cliente.

**Fix.** (a) Validar permiso dentro de cada SP sensible con `FN_TIENE_PERMISO` sobre un usuario tomado de una variable de sesión que el servidor pueda verificar; (b) o crear un usuario de BD por rol y usar `GRANT EXECUTE` selectivo; (c) como mínimo, reducir `balbu_app` a los SPs que la app realmente usa.

**Estado (03/11/2026): CERRADO el acceso directo y cerrada la lectura de hashes.** Se aplicó (c) y, además, se movió la verificación de la clave al servidor con el módulo `65- LOGIN_SERVIDOR.sql`: la app deriva PBKDF2 y manda solo el derivado; `SP_LOGIN_AUTENTICAR` compara, aplica el bloqueo y escribe `LOG_ACCESOS`. El valor guardado es `SHA2(pepper || derivado)` y el pepper vive en `SECRETO_SISTEMA`, que la app no puede leer. Con la clave del `.env` ya no se bajan hashes: `SELECT CONTRASENA` y `SELECT * FROM SECRETO_SISTEMA` fallan con `1143` y `1142`. Los usuarios se migran solos en su primer login (`CONTRASENA` queda en NULL).

`balbu_app` quedó con `EXECUTE`, `SELECT` en 13 tablas, `SELECT` por columna en `EMPLEADOS` (sin `SALARIO`), `USUARIOS` y `CONTRATOS`, y `UPDATE` solo de `CONTRATOS.RUTA_DOCUMENTO`. Verificado: `UPDATE USUARIOS SET ID_ROL` → `1143`; `SELECT SALARIO FROM EMPLEADOS` → `1143`; `DELETE FROM VENTAS` → `1142`.

Efecto colateral detectado y corregido: el conteo del lockout leía `LOG_ACCESOS` directo y quedó denegado en silencio (el `catch` devolvía 0). Con el módulo 65 el bloqueo vive entero en el SP, así que tampoco se saltea llamando a la base desde un cliente SQL.

Pendiente para cerrar A6 del todo: (b), un usuario de BD por rol, si algún día se quiere que el permiso también valga contra llamadas directas a los SPs. Hoy cualquier cliente con la clave de `balbu_app` puede llamar a cualquier SP; lo que ya no puede es leer datos ni escribir tablas por su cuenta. `CONTRATOS.SALARIO` sigue legible por el flujo de contratos pendientes.

**Cierre final (03/11/2026): el permiso también vale dentro de los SPs.** Módulo `66- SESIONES_GUARDAS.sql`: el login emite un token (`SESIONES`, 12 h), la app lo deja en `@TOKEN_SESION` y cada procedimiento arranca con `SP_EXIGIR_PERMISO('RUTINA')`, que resuelve el usuario con `FN_USUARIO_SESION()` y exige el permiso de `PERMISO_POR_RUTINA`. Las guardas están inyectadas en 162 de 168 procedimientos (los 6 restantes son el propio control de acceso y el login); 161 exigen y `SP_CAMBIAR_CONTRASENA` queda sin mapear a propósito. El cliente puede setear la variable, pero no puede inventar un token: solo existen los que emitió el servidor, con los permisos de ese usuario y hasta que venzan. Las conexiones de `root` y `balbu_admin` quedan fuera del control porque ya tienen `ALL PRIVILEGES`. Evidencia: con token de VENDEDOR, `SP_LISTAR_METODOS_PAGO` pasa y `SP_LISTAR_CATEGORIAS` se corta con `SIN PERMISO`, y el rechazo queda en `LOG_PERMISO_SP` (`db/test-permisos-sp.sh`). Queda abierto (b) si se quiere separar además por credenciales de conexión.

---

## 4. Medio

### M1. Código muerto con credenciales hardcodeadas

`autenticacion.cpp:26` conecta con `"tu_usuario"` / `"tu_clave"`. Nadie llama a `iniciarSesion()`, pero `build.sh:15` compila `*.cpp`, así que **entra al binario**. Además usa `delete con;` crudo (`:48`) y `cin >>` para la clave.

**Fix.** Borrar el archivo o sacarlo del glob.

### M2. Una consulta SQL por ítem de menú

`roles.cpp:205-221` recorre 18 ítems y llama `tienePermiso()` para cada uno; cada llamada ejecuta `SELECT FN_TIENE_PERMISO(?, ?)` (`:74-98`). Cada render del menú principal son ~20 round-trips, y cada submenú repite el patrón.

**Fix.** Traer `permisosDelUsuario()` una vez y consultar un `std::set` en memoria.

### M3. La venta no es atómica

`ventas.cpp:327-433`: `SP_INICIAR_VENTA` → N × `SP_AGREGAR_DETALLE_VENTA` → pago. Si el proceso muere a mitad, queda una venta `PENDIENTE` con stock descontado; la compensación del `catch` solo cubre errores controlados.

**Fix.** `setAutoCommit(false)` + `commit()` / `rollback()` en el bloque.

### M4. Protocolo de error por prefijo de string

`database.cpp:39-51` devuelve `"Error DB: ..."` y los llamadores hacen `rfind("Error DB:", 0)`. Un mensaje legítimo que empiece así se interpreta como fallo.

**Fix.** Struct `{ bool ok; std::string mensaje; }`.

### M5. Inyección SQL latente en los `CALL`

`ventas.cpp:345` y `compras.cpp:526` concatenan los IDs en el texto de la llamada. Hoy son `int` —no es explotable—, pero el patrón se vuelve vulnerabilidad el día que se agregue un parámetro de texto.

**Fix.** `prepareStatement` con `?` y `setInt`, como el resto del código.

### M6. CRLF en scripts del devcontainer

`git ls-files --eol` marca `w/crlf` en `.devcontainer/install-mariadb.sh` y `reinstall-cmake.sh`, pese a `*.sh text eol=lf`. En Linux fallan con `$'\r': command not found`.

**Fix.** `git add --renormalize .devcontainer/`.

### M7. Sin CI ni tests automatizados

`.github/` solo contiene `dependabot.yml`. Los `db/test-*.sh` son manuales.

**Fix.** Workflow que levante MariaDB efímero, corra `bash db/import.sh` y los `test-*.sh`.

### M8. Ruido y datos versionados de más

`modulos/.~lock.Documentacion base de datos.odt#` y `modulos/Documentacion base de datos.odt` están en git.

**Fix.** `git rm --cached` y agregar `*.odt` y `.*#` al `.gitignore`.

---

## 5. Bajo

| # | Hallazgo | Evidencia | Fix |
| --- | --- | --- | --- |
| B1 | `using namespace std;` en un header | `seguridad.h:3` | quitarlo del header |
| B2 | `system()` para abrir el navegador | `contrato.cpp:187-189`, `:411-415` | `ShellExecute` / `fork+exec` |
| B3 | `stoi` sobre el hash leído de la BD | `seguridad.cpp:214` | validar `parts[1]` |
| B4 | Comparación de dinero con `!=` | `ventas.cpp:301-302` | comparar en centavos |
| B5 | Dinero en `double` en toda la app | general | centavos (`long long`); la BD ya usa `DECIMAL` |
| B6 | Ruta relativa al CWD en el export | `web_export.cpp:99` | resolver contra el directorio del ejecutable |
| B7 | Hash vacío podría aceptar cualquier clave si OpenSSL falla | `seguridad.cpp:227-238` | rechazar `stored.empty()` |
| B8 | Respaldos C-API muertos en la raíz | `database.cpp.c-api-bak` | borrar del disco |

---

## 6. Lo que está bien (no tocar)

| Fortaleza | Evidencia |
| --- | --- |
| Integridad del esquema | 45 tablas, 64 FK, 60 índices secundarios, 108 triggers, todo InnoDB |
| Dinero en la BD | Cero `FLOAT`/`DOUBLE`; `DECIMAL` con precisión explícita en todos los montos |
| Transacciones | `EXIT HANDLER FOR SQLEXCEPTION` + `ROLLBACK` + bandera de transacción propia, y `FOR UPDATE` en stock, pagos y cancelaciones |
| Contraseñas | PBKDF2-SHA256, 100.000 iteraciones, salt por usuario, `CRYPTO_memcmp`, rehash automático del SHA-256 legacy |
| Llamadas a SP | `drenarResultados()` aplicado consistentemente; evita el clásico “Commands out of sync” |
| Docker | BD publicada solo en `127.0.0.1`, `healthcheck` y `depends_on: service_healthy`, root sin TCP |
| EOF | `leerOpcionMenu()` corta el bucle sin el `cin.clear()` infinito |

---

## 7. Plan de acción

1. Purgar `contratos/` del historial.
2. `dinero()` con `fixed` + `setprecision(2)` y unificar formateadores.
3. Eliminar el backdoor `BALBU_USER`/`BALBU_PASS`.
4. Usar `sesionActual.idEmpleado` en ventas y compras.
5. Borrar `autenticacion.cpp`.
6. Decidir el modelo de autorización: SP con validación, o usuario de BD por rol.
7. Lockout real support en el login. **Hecho el 03/11/2026 (`64- SEGURIDAD_T2.sql` + `login.cpp`).**
8. CI mínimo con import + tests.

---

## Anexo — Configuración de OpenCode (herramientas, no proyecto)

Hechos verificados contra la documentación de OpenCode V2 y el catálogo de modelos:

- `max_concurrent_subagents` **no existe**. No hay límite de concurrencia por configuración; el runtime solo permite restringir **qué** agentes se pueden lanzar (permiso `task`/`subagent`).
- `effort` no es campo de configuración. El equivalente es el variant en el modelo: `provider/modelo#high`.
- `openrouter/deepseek/deepseek-v4.1-pro` **no existe**. Los reales son `deepseek-v4-pro-0813` ($0.115/$4.00 por millón) y `deepseek-v4.1-flash` ($0.045/$0.50).
- La disciplina de “un subagente por turno” vive en `.opencode/instructions/cost-policy.md`; es conducta, no candado.
- `gentle-orchestrator` quedó restringido a `general` (DeepSeek, coder) y `qa` (Sonnet 5.5, auditor de solo lectura) vía `.opencode/agents/qa.md`.

**Consecuencia.** Mientras ese allowlist esté activo, las fases SDD y las revisiones 4R de Gentle AI no pueden lanzarse.
