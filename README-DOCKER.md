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
docker compose exec app bash db/import.sh        # schema 0 errores: 59 tablas, 124 SPs, 65 triggers
docker compose exec app bash db/seed-admin.sh    # crea admin/admin123 (hash legacy; la app lo migra a PBKDF2 al entrar)
docker compose exec app bash db/seed-catalogo.sh # catálogo demo opt-in (4 categorías, 10 marcas, 4 métodos; idempotente)
docker compose exec app bash db/check-app-sps.sh # verifica los 47 SPs que la app invoca
docker compose exec app ./output/app
```
Importar es para DB fresca (el script hace seeds con CALLs no idempotentes):
para reimportar limpio, recrea la DB antes (ver `db/import.sh`).
Credenciales de entrada: `admin` / `admin123`.

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
