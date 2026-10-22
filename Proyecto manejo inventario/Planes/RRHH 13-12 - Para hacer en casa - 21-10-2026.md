# RRHH 13/12 — Estado y plan para casa — 21/10/2026

> Estado real al cerrar el 21/10: **13 y 12 implementados y commiteados** en `d623ac0`.
> **Verificación independiente de los dos: PASS** (la del 12 se hizo el 21/10
> contra `BALBU_TECH_TEST`; detalle en la sección 1). Única excepción: el hueco
> de `SP_ACTUALIZAR_VACACIONES`, que no es alcanzable desde la UI.
> Queda la prueba visual y seguir con 14/15/30.

## Estado actual

| Módulo | Estado | Evidencia |
|---|---|---|
| **13 — Permisos** | ✅ Implementado y verificado | `permisos.cpp/h`, `SP_LISTAR_PERMISOS_PENDIENTES`, `SP_GESTIONAR_PERMISO` atómico; PASS del verificador; warning de concurrencia corregido |
| **12 — Vacaciones** | ✅ Implementado y verificado | `vacaciones.cpp/h`, `ESTADO`, 8 SPs, 2 triggers; verificación independiente PASS el 21/10 (dos huecos del SP de edición anotados, no alcanzables desde la UI) |
| **28 — LOG_ACCESOS** | ✅ Commiteado, ⏳ prueba visual | `accesos.cpp/h`, `login.cpp`, 28 SQL/MD |
| **30 — Auditoría de permisos** | ◐ Tabla + trigger; sin lector | `LOG_AUDITORIA_PERMISOS` + `TR_LOG_GESTION_PERMISO`; registra, no se muestra |

- **Commit:** `d623ac0 Armando mas modulos` — incluye 28 + 13 + 12.
- **Worktree:** limpio.
- **Base viva:** migraciones `backups/95` y `96` aplicadas; datos de prueba limpios
  (permisos 0, vacaciones 0, log 0; asistencia 1 fila preexistente del 19/10).
- **Índice:** 367 objetos / 159 SPs (actualizado).
- **Build:** OK. **`check-app-sps`:** 93/0 (última corrida).

## Lo que falta, en orden

- [x] **1. Verificación independiente de 12** — PASS el 21/10 (ver sección 1).
- [ ] **2. Prueba visual 13 + 12 con `admin`** (ver abajo).
- [ ] **3. Prueba visual 28** ("Accesos"; quedó sin probar).
- [ ] **4. 14 Bonos** — pantalla mínima (20–30 min).
- [ ] **5. 15 Historial** — fix ancho `VARCHAR(30)`→50 (10 min).
- [ ] **6. 16 Liquidaciones** — decisión de negocio; no implementar aún.
- [ ] **7. 30 Auditoría** — lector + decidir actor (15–20 min).
- [ ] **8. Pendientes chicos** (lista al final).

## 1. Verificación de 12 — HECHA (21/10/2026)

**PASS.** Corrida contra `BALBU_TECH_TEST` recreada desde cero: import 45/45 sin
errores, `check-app-sps` 93/0, suite de contratos 15/15, más ejecución directa de
cada `SP` y trigger. Lo que se comprobó:

- [x] `SP_GESTIONAR_VACACION` solo acepta `PENDIENTE` → `APROBADO`/`RECHAZADO`;
      atómico (`AND ESTADO='PENDIENTE'` + `ROW_COUNT()`); segundo intento amable
      ("SOLO SE PUEDEN GESTIONAR VACACIONES PENDIENTES").
- [x] `SP_ACTUALIZAR_VACACIONES` solo permite editar pendientes — **con dos
      huecos**: no re-valida solapamiento (mover una pendiente encima de una
      aprobada devuelve `EXITO`) ni valida fecha nueva futura. No son
      alcanzables desde la UI.
- [x] `SP_REPORTE_DIAS_CONSUMIDOS`, `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES` y
      `SP_VALIDAR_CUPO_VACACIONES` cuentan **solo `APROBADO`** (5 días tomados y
      10 restantes con una aprobada de 5; la consulta lista solo a quien está
      fuera hoy).
- [x] Tope/solapamiento (triggers `TR_VALIDAR_LIMITE_VACACIONES*`) cuentan
      `PENDIENTE` + `APROBADO`; un `RECHAZADO` libera. Un `INSERT` directo de 15
      días con 5 ya aprobados queda bloqueado.
- [x] 11: `SP_REGISTRAR_ASISTENCIA`, `11_SP_JUSTIFICAR_ASISTENCIA` y
      `TR_BLOQUEAR_ASISTENCIA_INAPROPIADA` filtran `APROBADO`;
      pendiente/rechazada **no** bloquea (probado con `INSERT` directo a
      `ASISTENCIA_EMPLEADOS` en las tres fechas).
- [x] Menú: "Mis vacaciones" + Empleados 17 "Gestionar vacaciones" + 18 volver;
      1–15 intactos (corrida real de la app).
- [x] Docs: `12- VACACIONES_EMPLEADOS.md`, `11-ASISTENCIA_EMPLEADOS.md`,
      `00- INDICE.md`, `db/check-app-sps.sh` (0 descuadres, 0 objetos sin
      mención).
- [x] Falso positivo conocido: `vacaciones.cpp` repite `empleadoDeSesion`
      (SUGGESTION, no bloqueante). Confirmado.

Cierre del 21/10: se corrigió el login que giraba con EOF (dejaba 3 filas
`(vacio)` por corrida, con test nuevo `db/test-login-eof.sh`) y la suite de
contratos pasó a usar 18 para volver de Empleados.

## 2. Prueba visual con `admin`

Único usuario: `admin` (`ID_EMPLEADO=1`; ADMIN tiene todo). El permiso
`SOLICITAR_PERMISO` habilita ambas pantallas de empleado; `GESTIONAR_EMPLEADOS`
habilita ambas de gestión.

### 13 — Permisos

- [ ] "Mis permisos" → solicitar un permiso (fecha/motivo) → aparece en el historial.
- [ ] "Empleados" → **16 "Gestionar permisos"** → aprobar uno y rechazar otro.
- [ ] Reintentar aprobar el ya aprobado: debe decir "solo pendientes".
- [ ] Ver que el cambio quedó en `LOG_AUDITORIA_PERMISOS` (trigger de 30).

### 12 — Vacaciones

- [ ] "Mis vacaciones" → solicitar (fechas válidas) → aparece en el historial.
- [ ] "Empleados" → **17 "Gestionar vacaciones"** → aprobar uno y rechazar otro.
- [ ] Reintentar gestionar el ya resuelto: "solo pendientes".
- [ ] Asistencia: una vacación **aprobada** que cubra hoy debe bloquear el registro;
      una **pendiente o rechazada** no debe bloquear.
- [ ] Cupo/solapamiento: pedir 15 días y luego otro solapado → debe rechazar;
      rechazar la primera y reintentar → debe liberar.
- [ ] Limpiar los datos de prueba (permisos/vacaciones/log) al terminar.

## Decisiones tomadas (no re-discutir)

**13**

- Tabla/SPs existentes; se agregó `SP_LISTAR_PERMISOS_PENDIENTES`.
- `SP_GESTIONAR_PERMISO` endurecido: solo `PENDIENTE` → `APROBADO`/`RECHAZADO`,
  atómico; el trigger de 30 registra el cambio (sin actor).
- Pantallas: "Mis permisos" (empleado) y "Gestionar permisos" (Empleados 16).

**12**

- `VACACIONES_EMPLEADOS.ESTADO` con default `PENDIENTE`.
- `SP_SOLICITAR_VACACIONES` reemplaza a `SP_INSERTAR_VACACIONES`.
- `SP_GESTIONAR_VACACION` atómico; `SP_ACTUALIZAR` solo pendiente.
- Reportes/consulta/cupo: solo `APROBADO`.
- Tope/solapamiento: `PENDIENTE` + `APROBADO`; `RECHAZADO` libera.
- 11: los tres puntos filtran `APROBADO`; pendiente/rechazada no bloquea.
- Pantallas: "Mis vacaciones" (empleado) y "Gestionar vacaciones" (Empleados 17);
  18 vuelve. `SOLICITAR_PERMISO` se reutiliza.

## 3. Backlog después de RRHH

- **14 Bonos** — el 1% ya lo genera el trigger de 24; falta pantalla mínima
  (listar, pagar, anular).
- **15 Historial laboral** — bug vivo: `CARGO_ANTERIOR/NUEVO VARCHAR(30)` vs
  `EMPLEADOS.CARGO VARCHAR(50)`; ampliar a 50 y migrar.
- **16 Liquidaciones** — postergado: fórmula `SALARIO * AÑOS` es placeholder y
  "Despedir" vs "Liquidar" no cierran; decidir flujo primero.
- **30 Auditoría** — trigger activo; falta lector y decidir si guarda actor
  (hoy el trigger no tiene actor).
- **Parte 4:** 8, 17, 19.5, 22, 38.

## 4. Pendientes chicos

- [x] **Login con EOF** — cortaba gastando los 3 intentos y dejaba 3 filas
  `(vacio) / FALLIDO` en `LOG_ACCESOS`. Corregido el 21/10 con
  `db/test-login-eof.sh`.
- [x] **Suite de contratos** — enviaba `16` para volver de Empleados; ahora 16 es
  "Gestionar permisos". Pasada a `18` (9 envíos).
- [ ] **12** — al cablear la edición de vacaciones, que `SP_ACTUALIZAR_VACACIONES`
  valide solapamiento y fecha futura.
- [ ] **34 ASIGNAR RECLAMOS** — decisión: asignar o borrar.
- [ ] 11: `DROP IF EXISTS` en los `CREATE` (idempotencia).
- [ ] 3 tests shell pendientes.
- [ ] Notas obsoletas del índice.
- [ ] `crear-usuarios.sh`.
- [ ] Consolidar los `ALTER` de 25.
- [ ] **Ojo:** `d623ac0` incluyó `.atl/` (estaba en la lista de no commitear).
      Si no querés versionarlo: `git rm -r --cached .atl` + commit.

## Comandos

```bash
# build
docker compose exec -T app bash -lc "cd /workspace && ./build.sh"

# SPs de la app (debe dar 93/0)
docker compose exec -T app bash -lc "cd /workspace && bash db/check-app-sps.sh"

# login con entrada agotada (no gira, no ensucia LOG_ACCESOS)
docker compose exec -T app bash -lc "cd /workspace && DB_NAME=BALBU_TECH_TEST bash db/test-login-eof.sh"
```

La base viva ya tiene 95/96; **no re-aplicar** salvo que se reconstruya.
`backups/` está gitignored: las migraciones no están en el repo.

## Criterio de cierre

1. ~~Verificación de 12 PASS~~ — hecha el 21/10; quedan dos huecos del `SP` de
   edición anotados (no alcanzables desde la UI).
2. Build OK y `check-app-sps` 93/0.
3. Prueba visual 13 + 12 OK; sin datos de prueba.
4. 28 probado (o anotado como pendiente aparte).
5. Recién después: 14, 15, 30.

## Ver también

- [[Pendientes - App C++]]
- [[Roles y permisos - C-3 - 19-10-2026]]
- [[Para mañana en el trabajo - 21-10-2026]]
