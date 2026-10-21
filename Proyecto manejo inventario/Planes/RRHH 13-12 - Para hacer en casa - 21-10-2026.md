# RRHH 13/12 — Estado y plan para casa — 21/10/2026

> Estado real al cerrar el 21/10: **13 y 12 implementados y commiteados** en `d623ac0`.
> El 13 pasó la verificación independiente. **El 12 quedó sin esa verificación**
> (se cortó al final). Lo primero al retomar es terminar esa lectura; después,
> prueba visual y seguir con 14/15/30.

## Estado actual

| Módulo | Estado | Evidencia |
|---|---|---|
| **13 — Permisos** | ✅ Implementado y verificado | `permisos.cpp/h`, `SP_LISTAR_PERMISOS_PENDIENTES`, `SP_GESTIONAR_PERMISO` atómico; PASS del verificador; warning de concurrencia corregido |
| **12 — Vacaciones** | ✅ Implementado, ⏳ verificación independiente pendiente | `vacaciones.cpp/h`, `ESTADO`, 8 SPs, 2 triggers; build OK; `check-app-sps` 93/0; pruebas SQL OK |
| **28 — LOG_ACCESOS** | ✅ Commiteado, ⏳ prueba visual | `accesos.cpp/h`, `login.cpp`, 28 SQL/MD |
| **30 — Auditoría de permisos** | ◐ Tabla + trigger; sin lector | `LOG_AUDITORIA_PERMISOS` + `TR_LOG_GESTION_PERMISO`; registra, no se muestra |

- **Commit:** `d623ac0 Armando mas modulos` — incluye 28 + 13 + 12.
- **Worktree:** limpio.
- **Base viva:** migraciones `backups/95` y `96` aplicadas; datos de prueba limpios
  (permisos 0, vacaciones 0, log 0; asistencia 1 fila preexistente del 19/10).
- **Índice:** 367 objetos / 159 SPs (actualizado).
- **Build:** OK. **`check-app-sps`:** 93/0 (última corrida).

## Lo que falta, en orden

- [ ] **1. Verificación independiente de 12** (5–10 min, solo lectura).
- [ ] **2. Prueba visual 13 + 12 con `admin`** (ver abajo).
- [ ] **3. Prueba visual 28** ("Accesos"; quedó sin probar).
- [ ] **4. 14 Bonos** — pantalla mínima (20–30 min).
- [ ] **5. 15 Historial** — fix ancho `VARCHAR(30)`→50 (10 min).
- [ ] **6. 16 Liquidaciones** — decisión de negocio; no implementar aún.
- [ ] **7. 30 Auditoría** — lector + decidir actor (15–20 min).
- [ ] **8. Pendientes chicos** (lista al final).

## 1. Verificación de 12 — qué mirar

El writer self-verificó, pero **no hay PASS independiente**. Revisar:

- [ ] `SP_GESTIONAR_VACACION` solo acepta `PENDIENTE` → `APROBADO`/`RECHAZADO`;
      atómico (`AND ESTADO='PENDIENTE'` + `ROW_COUNT()`); segundo intento amable.
- [ ] `SP_ACTUALIZAR_VACACIONES` solo permite editar pendientes.
- [ ] `SP_REPORTE_DIAS_CONSUMIDOS`, `SP_CONSULTAR_EMPLEADOS_DE_VACACIONES` y
      `SP_VALIDAR_CUPO_VACACIONES` cuentan **solo `APROBADO`**.
- [ ] Tope/solapamiento (triggers `TR_VALIDAR_LIMITE_VACACIONES*`) cuentan
      `PENDIENTE` + `APROBADO`; un `RECHAZADO` libera.
- [ ] 11: `SP_REGISTRAR_ASISTENCIA`, `11_SP_JUSTIFICAR_ASISTENCIA` y
      `TR_BLOQUEAR_ASISTENCIA_INAPROPIADA` filtran `APROBADO`;
      pendiente/rechazada **no** bloquea.
- [ ] Menú: "Mis vacaciones" + Empleados 17 "Gestionar vacaciones" + 18 volver;
      1–15 intactos.
- [ ] Docs: `12- VACACIONES_EMPLEADOS.md`, `11-ASISTENCIA_EMPLEADOS.md`,
      `00- INDICE.md`, `db/check-app-sps.sh`.
- [ ] Falso positivo conocido: `vacaciones.cpp` repite `empleadoDeSesion`
      (SUGGESTION, no bloqueante). Confirmar si el verificador lo marca.

Si encuentra algo: corregir, rebuild, `check-app-sps`, y commit `fix(vacaciones): ...`.

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
```

La base viva ya tiene 95/96; **no re-aplicar** salvo que se reconstruya.
`backups/` está gitignored: las migraciones no están en el repo.

## Criterio de cierre

1. Verificación de 12 PASS (o hallazgos corregidos y re-verificados).
2. Build OK y `check-app-sps` 93/0.
3. Prueba visual 13 + 12 OK; sin datos de prueba.
4. 28 probado (o anotado como pendiente aparte).
5. Recién después: 14, 15, 30.

## Ver también

- [[Pendientes - App C++]]
- [[Roles y permisos - C-3 - 19-10-2026]]
- [[Para mañana en el trabajo - 21-10-2026]]
