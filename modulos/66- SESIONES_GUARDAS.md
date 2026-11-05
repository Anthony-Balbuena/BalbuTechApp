# 66 - Sesiones de servidor y guardas de permiso en los SP

## Que hace

Cierra el ultimo tramo del hallazgo A6: que el permiso valga **tambien** cuando
el procedimiento se llama desde un cliente SQL y no desde la app. Antes el
control era solo del menu: quien tuviera la clave de `balbu_app` podia llamar
cualquier `SP` y el `SP` no miraba el rol.

El mecanismo:

1. `SP_LOGIN_AUTENTICAR` emite un token aleatorio y lo guarda en `SESIONES`.
2. La app lo deja en la conexion: `SET @TOKEN_SESION = '<token>'`.
3. `FN_USUARIO_SESION()` lo resuelve a un `ID_USUARIO`, o `NULL` si no existe o
   vencio.
4. Cada `SP` sensible arranca con `CALL SP_EXIGIR_PERMISO('NOMBRE_SP')`.

El cliente puede setear la variable, pero **no puede inventar un token**: solo
existen los que emitio el servidor. Un token robado sirve para ese usuario, con
sus permisos y hasta que venza (12 horas).

## Objetos

### Tabla `SESIONES`

| Columna | Tipo | Para que |
|---|---|---|
| `TOKEN` | `CHAR(64)` PK | `SHA2(UUID(), UUID(), RAND(), NOW(6), ID_USUARIO)` |
| `ID_USUARIO` | `INT` NOT NULL | FK a `USUARIOS`, `ON DELETE CASCADE` |
| `CREADA` | `TIMESTAMP` | default `CURRENT_TIMESTAMP` |
| `EXPIRA` | `TIMESTAMP` NOT NULL | `NOW() + INTERVAL 12 HOUR` |

Indice `IX_SESIONES_EXPIRA`. Los vencidos se borran en cada login exitoso, asi
la tabla no crece sin control.

### Tabla `PERMISO_POR_RUTINA`

| Columna | Tipo | Para que |
|---|---|---|
| `RUTINA` | `VARCHAR(80)` PK | nombre del procedimiento |
| `PERMISO` | `VARCHAR(80)` NULL | permiso que exige; `NULL` = sin mapeo |
| `EXIGIR` | `TINYINT` default 0 | 0 = auditoria, 1 = corta |

`PERMISO` tiene FK a `PERMISOS.NOMBRE_PERMISO` con `ON UPDATE CASCADE`: un
permiso renombrado arrastra el mapeo en vez de romperlo.

### Tabla `LOG_PERMISO_SP`

| Columna | Tipo | Para que |
|---|---|---|
| `ID_LOG` | `INT` PK auto | orden de lectura |
| `FECHA` | `TIMESTAMP` | default `CURRENT_TIMESTAMP` |
| `RUTINA` | `VARCHAR(80)` | procedimiento llamado |
| `PERMISO` | `VARCHAR(80)` | permiso evaluado |
| `USUARIO` | `VARCHAR(50)` | usuario resuelto del token |
| `RESULTADO` | `ENUM` | `OK`, `SIN_SESION`, `SIN_PERMISO`, `SIN_MAPEO` |

### Funcion y procedimientos

| Objeto | Que hace |
|---|---|
| `FN_USUARIO_SESION()` | `ID_USUARIO` de `@TOKEN_SESION`, o `NULL` |
| `SP_EXIGIR_PERMISO(P_RUTINA)` | punto unico de control |
| `SP_CERRAR_SESION_SERVIDOR()` | borra el token de la conexion |
| `SP_LOGIN_AUTENTICAR(...)` | **reemplaza** la version del 65 y agrega `TOKEN` |

## Como decide `SP_EXIGIR_PERMISO`

1. Busca `EXIGIR` y `PERMISO` en `PERMISO_POR_RUTINA`. Sin fila: `SIN_MAPEO`.
2. Lee el interruptor global `SECRETO_SISTEMA.EXIGIR_PERMISO_SP`.
3. Si `USER()` es `root` o `balbu_admin`, **queda exento**. Ya tienen `ALL
   PRIVILEGES` sobre el esquema: bloquearlos solo rompe mantenimiento y tests.
4. Sin token valido: registra `SIN_SESION` y corta
   (`ERROR: SESION INVALIDA O VENCIDA.`).
5. Con token: evalua `FN_TIENE_PERMISO(usuario, permiso)`.
   - Denegado: registra `SIN_PERMISO` (o `SIN_MAPEO`) y corta con
     `ERROR: SIN PERMISO PARA ESTA OPERACION.` si `EXIGIR = 1` o si el
     interruptor global esta en 1.
   - Permitido: registra `OK` **solo** cuando la exigencia esta prendida. En
     modo auditoria el log guardaria cada lectura normal y se llenaria solo.

## Modo auditoria y modo estricto

Son dos interruptores distintos:

| Interruptor | Alcance | Como se cambia |
|---|---|---|
| `PERMISO_POR_RUTINA.EXIGIR` | una rutina | `UPDATE`, sin redeploy |
| `SECRETO_SISTEMA.EXIGIR_PERMISO_SP` | todas | `UPDATE`, sin redeploy |

El modulo entra en **modo auditoria** (ambos en 0). Para prender una rutina:

```sql
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 1 WHERE RUTINA = 'SP_LISTAR_CATEGORIAS';
```

Para apagar todo sin tocar rutina por rutina:

```sql
UPDATE SECRETO_SISTEMA SET VALOR = '0' WHERE CLAVE = 'EXIGIR_PERMISO_SP';
```

Si algo responde `SIN PERMISO`, no hace falta tocar codigo ni recompilar:

```sql
SELECT RUTINA, PERMISO, USUARIO, RESULTADO, FECHA
  FROM LOG_PERMISO_SP
 WHERE RESULTADO <> 'OK'
 ORDER BY ID_LOG DESC LIMIT 20;
```

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/66- SESIONES_GUARDAS.sql"
mysql -h127.0.0.1 -uroot -p BALBU_TECH < db/mapear-permisos.sql
python3 db/injectar-guardas.py BALBU_TECH --aplicar
bash db/check-app-sps.sh
```

Orden obligatorio: `63`, `64`, `65`, `66`, mapeo, guardas, **y despues** el
binario nuevo. `66` redefine `SP_LOGIN_AUTENTICAR`; importar `65` despues de
`66` deja el login sin token y, con la exigencia prendida, todo responde
`SESION INVALIDA`.

El `.sql` solo crea las tablas, la funcion y los SP del control: la guarda en
cada procedimiento la inyecta `db/injectar-guardas.py`, porque MariaDB no
permite envolver un procedimiento existente.

## Que preserva

- Los permisos y pares existentes: no toca `PERMISOS` ni `ROL_PERMISO`.
- `SP_CAMBIAR_CONTRASENA` quedo **sin mapeo a proposito** mientras existio (un
  usuario que no puede entrar no puede pedir permiso para cambiar su clave).
  El 05/11/2026 se elimino del modulo `10`: no tenia caller y el `65` la dejo
  sin funcion posible.
- El login: si el usuario ya usaba el formato del 65, sigue entrando igual.

## Que no hace

- No prende la exigencia: deja todo en modo auditoria. El bloqueo real se
  activa por datos cuando el mapeo ya se valido con uso real.
- No asigna permisos a roles: eso es el mapeo y los modulos 44 a 62.
- No renueva tokens: a las 12 horas hay que volver a entrar.

## Verificacion

Aplicado en `BALBU_TECH_TEST` el 03/11/2026 y en `BALBU_TECH` el 05/11/2026.

- `db/check-app-sps.sh`: "Guardas de permiso: cobertura completa" en ambas
  bases (102 objetos verificados).
- `db/test-permisos-sp.sh`: sin token rechaza, token de `VENDEDOR` pasa
  `SP_LISTAR_METODOS_PAGO`, se corta en `SP_LISTAR_CATEGORIAS` y el rechazo
  queda en `LOG_PERMISO_SP`.
- Prueba manual con el binario nuevo contra `BALBU_TECH` (05/11/2026): login,
  alta de categoria y `LOG_PERMISO_SP` con
  `SP_INSERTAR_CATEGORIA | CATEGORIAS_CREAR | OK`.
