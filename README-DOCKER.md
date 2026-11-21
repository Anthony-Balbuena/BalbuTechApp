# BalbuTechApp en Docker (Windows + Linux)

Setup hibrido: `docker-compose.yml` en raiz + `.devcontainer/devcontainer.json` que lo referencia.
Compilacion directa con `g++` (sin CMake). MariaDB `10.11` LTS para compatibilidad con tus `.sql`.

## Requisitos
- Docker Desktop con backend WSL2 (Windows) o Docker Engine (Linux).
- VS Code + extension "Dev Containers" (recomendado), o terminal con `docker compose`.

## Uso rapido (terminal, desde la raiz del repo)
```bash
docker compose up --build -d
docker compose exec app bash build.sh
docker compose exec app bash db/import.sh        # schema 0 errores: 47 tablas, 191 SPs, 82 triggers
docker compose exec app bash db/seed-admin.sh admin 'TU_CLAVE'  # crea/actualiza el admin; la clave es obligatoria
docker compose exec app bash db/seed-catalogo.sh # catálogo demo opt-in (4 categorías, 10 marcas, 4 métodos; idempotente)
docker compose exec app bash db/check-app-sps.sh # verifica los 139 SPs que la app invoca
docker compose exec app ./output/app
```
Importar es para DB fresca: reimportar sobre una base ya creada deja avisos de
"la tabla ya existe" (`1050`) y no repara objetos que falten. Para reimportar
limpio, recrea la DB antes (ver `db/import.sh`).
`db/import.sh` termina el trabajo solo: importa los módulos, llena
`PERMISO_POR_RUTINA` con `db/mapear-permisos.sql` e inyecta las guardas de
permiso. Si recreaste la base, el `DROP` se llevó los privilegios de
`balbu_app`: el script lo avisa **y te imprime el comando exacto** para
reponerlos. Es `db/aplicar-grants.sh`, pide root y es **idempotente** (correrlo
de más no rompe nada). Desde el host:

```bash
set -a; . ./.env; set +a
DB_HOST=127.0.0.1 bash db/aplicar-grants.sh BALBU_TECH
```

Dentro del contenedor `db`, `bash db/aplicar-grants.sh BALBU_TECH` (usa el
socket, `DB_ROOT_PASSWORD` ya está en el entorno).
`db/migraciones/` son parches para bases que ya existen: **`db/import.sh` no
los ejecuta**, se aplican a mano y son idempotentes (correrlos dos veces deja lo
mismo).

| Archivo | Qué arregla |
|---|---|
| `2026-11-19-proveedores-indices-duplicados.sql` | deja un solo índice único por columna en `PROVEEDORES` (había dos por `TELEFONO` y dos por `EMAIL`) |
| `2026-11-21-alinear-viva-al-repo.sql` | alinea una base creada por los módulos viejos con lo que produce el repo hoy: 8 reordenamientos de columnas y 5 diferencias con efecto (`PRODUCTOS.P_COMPRA` sin default, `LOG_ACCESOS.USUARIO_INTENTADO` con default de más, `FK_PRODUCTO_PROVEEDOR` en `CASCADE`, la `FK` de `DETALLES_VENTA` con otro nombre, y las 2 `FK` que le faltaban a `LOG_USUARIOS`) |
| `2026-11-21-productos-exento-itbis.sql` | agrega `PRODUCTOS.EXENTO_ITBIS` (exención de ITBIS por producto) con `AFTER DIAS_GARANTIA`, la misma posición que el `CREATE TABLE` del módulo 9. Si la posición no coincidiera, `db/verificar-esquema.sh` marcaría diferencia de columnas |

La prueba de un parche es el verificador, antes y despues:

```bash
set -a; . ./.env; set +a
export DB_HOST=127.0.0.1 DB_ADMIN_USER=root DB_ADMIN_PASSWORD="$DB_ROOT_PASSWORD"

bash db/verificar-esquema.sh BALBU_TECH     # antes: sale 1, 4 secciones con diferencias
mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" --database=BALBU_TECH \
  < db/migraciones/2026-11-21-alinear-viva-al-repo.sql
bash db/verificar-esquema.sh BALBU_TECH     # despues: sale 0, IDENTICAS en las 9 secciones
```
`db/verificar-esquema.sh` responde "¿la base que corre es la que produce el
repo?" comparando tablas, columnas, índices, FK, CHECK, **cuerpos de triggers**
(con su `ACTION_ORDER`) y cuerpos de rutinas. Sin segundo argumento crea una base
temporal, importa `modulos/` ahí y compara; con dos bases compara las dos que ya
existen. Sale 0 si son iguales, 1 si hay diferencias, 2 si no pudo trabajar.
Credenciales de entrada: el usuario que definas en el seed y la clave que elijas. No hay clave por defecto.

## Uso en VS Code
1. `Dev Containers: Reopen in Container`.
2. Terminal ya esta dentro de `app` (Linux): `bash build.sh`, `./output/app`.
3. O usa `Ctrl+Shift+B` -> `Docker: compilar con g++`, y las tareas `Docker: importar...`, `Docker: ver tablas`.

## Variables (.env)
(19/10/2026) Las claves viven SOLO en `.env` (ignorado por git); `.env.example` es la plantilla.
- `DB_HOST=db DB_PORT=3306 DB_NAME=BALBU_TECH` — conexion y base.
- `DB_USER=balbu_app` + `DB_PASSWORD` — usuario dedicado de la app (DML + EXECUTE sobre la base).
- `DB_ADMIN_USER=balbu_admin` + `DB_ADMIN_PASSWORD` — scripts de mantenimiento (import, seeds, check).
- `DB_ROOT_PASSWORD` — clave de root, solo administracion por socket dentro del contenedor `db`.
La app lee `DB_*` en `database.cpp`; sin `DB_USER`/`DB_PASSWORD` no arranca (falla clara, sin defaults).
En Windows local sin Docker usa `DB_HOST=127.0.0.1` y exporta las variables en la terminal.
El contenedor publica MariaDB en el host como `127.0.0.1:3307` (`DB_PORT_HOST`)
porque el `3306` suele estar ocupado por MariaDB local en Windows; dentro de
la red Docker la app usa `db:3306`.

## Notas
- `database.cpp.c-api-bak` / `database.h.c-api-bak`: respaldo de tu experimento con API C (`MYSQL*`).
  Se restauro la version Connector/C++ (`sql::Connection`) porque los otros 14 `.cpp` usan `sql::*`.
- `mysql-connector-c++-26.7.0-winx64/` es solo Windows y esta excluido del contexto Docker (`.dockerignore`).
- `db/import.sh` importa `modulos/*.sql` en orden numerico y excluye `todo_modulos.sql` / `Mejoras_extras.sql`.
- **El cliente `mariadb` dentro de `docker compose exec` pierde las comillas dobles
  del SQL**: `docker compose exec db mariadb -e "SELECT \"x\""` llega sin las
  comillas internas. Para SQL con comillas, usar un archivo `.sql` o un here-doc
  (`... <<'EOF'`), no `-e`.
- Los tests de `db/test-*.sh` **solo corren contra una base de prueba**: los que
  escriben se niegan a apuntar a `BALBU_TECH`. Desde el host hay que forzar
  `DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST`, porque el `.env` apunta a la viva
  (`DB_NAME=BALBU_TECH` y `DB_HOST=db`).
