# Subir contrato = alta automática de empleado
Objetivo: que registrar (subir) un contrato cuando el empleado firma cree al empleado
en EMPLEADOS solo, usando los datos que el contrato ya pidió. Rama: main (commits de
unidad tras cada tarea). Runner de tests: BALBU_TECH_TEST (rollback, residuos 0).
Formato del borrador: archivo `clave=valor` junto al HTML (sin librería JSON en el repo).

## Specs

### S1 — Alta automática por trigger (requerimiento del dueño, verbatim)
> "HAY QUE HACER QUE CUANDO SE SUBA UN CONTRATO UN TR QUE META AL EMPLEADO AUTOMATICO QUE EN CONTARTO PILA TODO LO QUE LLEVA LA TABLA EMPLEADOS PARA QUE LA INTRODUCCION DE UN EMPLEADO SEA DIRECTO"
Aprobado con "con borrador arranca". Al insertar un contrato de una persona que no
existe en EMPLEADOS, un TRIGGER la crea con ESTADO ACTIVO y le asigna el ID al
contrato; si la cédula ya existe, vincula ese mismo ID sin duplicar. CONTRATOS pasa
a guardar los datos de la persona (NOMBRE, CEDULA, CARGO, TELEFONO, EMAIL,
FECHA_INGRESO) además de SALARIO (snapshot ya existente).

### S2 — Borrador sidecar (elección aprobada: "con borrador")
La opción 12 Generar guarda junto al HTML un archivo `.borrador` con los datos
(clave=valor): persona, tipo, duración, condiciones y ruta del HTML. La nueva opción
13 Subir contrato (al firmar) lista los borradores pendientes, elige uno y registra
sin re-tipear nada. Tras subir con éxito el `.borrador` pasa a `.subido`.

### S3 — Frenos con mensaje claro
- Cédula que ya tiene contrato ACTIVO → ERROR.
- Empleado existente INACTIVO → ERROR.
- Teléfono o email que ya pertenezca a otro empleado (son UNIQUE en EMPLEADOS) →
  ERROR. Si un empleado nuevo llega con "-" (default del generador), la opción 13
  pide teléfono y email reales antes de registrar.
- Cédula con más de un empleado → ERROR (ambigüedad).
- TEMPORAL sin meses → ERROR. Tipo inválido → ERROR.

### S4 — Menú
12 Generar, 13 Subir contrato (al firmar), 14 Ver contratos, 15 Finalizar,
16 Volver. 12 sigue siendo solo borrador (sin escritura en BD).

### S5 — Verificación
Tests en BALBU_TECH_TEST con START TRANSACTION/ROLLBACK: alta nueva (contrato +
empleado con ID coincidente), vínculo de existente (no duplica), cada freno de S3,
residuos 0. Humo C++ de punta a punta con pipes + limpieza manual de filas creadas.
`db/check-app-sps.sh` en 0 faltantes.

## Tasks
- T1 — RED: script de tests SQL que falla contra la BD TEST actual (faltan columnas/trigger/SP) — inline — ✅ RED observado (SP inexistente, columnas CEDULA/NOMBRE ausentes, 8 frenos sin disparar)
- T2 — `modulos/42- CONTRATOS.sql`: ALTER TABLE + TR_ALTA_EMPLEADO + SP_SUBIR_CONTRATO (borra SP_INSERTAR_CONTRATO) → aplicar a TEST → GREEN — inline — ✅ GREEN (suite completa OK)
- T3 — C++: lado `.borrador` en generar, opción 13 Subir (listar/leer/SP/marcar), menú renumerado → smoke GREEN — inline — ✅ GREEN (humo punta a punta: borrador → prompts de contacto real → EXITO + .subido; enlace ID empleado/contrato verificado)
- T4 — check-app-sps + notas Obsidian + commits de unidad — inline — ✅ Faltantes: 0 real (con errores de conexión contados = 0)

## Log
- L1 (18/10, verbatim): "HAY QUE HACER QUE CUANDO SE SUBA UN CONTRATO UN TR QUE META AL EMPLEADO AUTOMATICO QUE EN CONTARTO PILA TODO LO QUE LLEVA LA TABLA EMPLEADOS PARA QUE LA INTRODUCCION DE UN EMPLEADO SEA DIRECTO HAZME ESE PLAN"
- L2 (18/10, verbatim): "con borrador arranca" — aprueba plan con sidecar de borrador.
- L3: sin librería JSON en el repo → formato clave=valor en vez de .json (decisión propia de diseño, no cambia el requirement).
- L4: TELEFONO/EMAIL son UNIQUE y NOT NULL en EMPLEADOS → freno en SP + re-pido reales en opción 13 si vienen "-"; no se toca la tabla EMPLEADOS (compartida).
- L5 (18/10): incidente de proceso — corrí el cleanup de un humo Y la suite de SQL en paralelo (dos sesiones mariadb a la vez) y salieron 8 filas marcador commiteadas con estado inconsistente. Lección: **tests de BD siempre en serie**. El test ahora aborta con exit 2 si la base está sucia en vez de seguir en cascada. Limpiado (residuos 0) y suite verde 2 veces seguidas.
- L6: humo punta a punta OK: generar → `.borrador` guardado → opción 13 lista "Ana Smoke - TEMPORAL 8 meses" → pidió teléfono/email reales (venían "-") → "EXITO: CONTRATO #5 REGISTRADO. EMPLEADO NUEVO CREADO." → `.borrador`→`.subido`; contrato #5 apuntaba al empleado 23 recién creado (alta directa) con snapshot y FECHA_FIN 2027-06-18 (8 meses).
- L7 (18/10): revisión RDD de e71615b → **APPROVED** (autoridad quemada, línea `review-43a214b9259a175e`). Los 3 lentes (risk/resilience/reliability) quedaron admitidos tras reiniciar OpenCode; el refuter corroboró 1 CRITICAL (`R1-hardcoded-db-credential`: `db/test-contratos-subir.sh:10` guardaba la contraseña root). Corrección acotada commiteada en **a22f23f**: la credencial pasa a `DB_PASSWORD` por entorno y el script aborta si falta (RED sin credencial observado → GREEN con credencial, residuos 0). 10 hallazgos restantes quedaron como informativos (WARNING/SUGGESTION) → anotados en Pendientes como trabajo posterior.
