# Plan — Registrar contrato firmado (opción 13) — 19/10/2026

**Estado:** ejecutado el 19/10/2026 (fases 1 a 8). Resultado y evidencia al final.
**Alcance:** opción 13 (cotejo + registro), alta desde el contrato, y las opciones 14/15 por cédula.

## 0. Modelo

`CONTRATOS` es el **registro del papel**. No da de alta empleados, no guarda la evidencia escaneada en la base y no toca `EMPLEADOS`.

- **La cédula es la llave.** Existe desde la oferta y no cambia.
- **El ID llega después.** El contrato nace con `ID_EMPLEADO = NULL`; cuando RRHH da el alta, un trigger lo completa.
- **El escaneo es opcional.** Si RRHH lo tiene, la app copia el PDF a `contratos/firmados/` y guarda la ruta. Si no, el contrato se registra igual.

## 1. Flujo

```
12  reclutamiento arma el borrador            → HTML + .borrador
        ↓ firman el papel
13  contrataciones coteja y registra          → CONTRATOS con CEDULA e ID_EMPLEADO = NULL
        ↓
    queda en "firmados sin empleado"
        ↓
1   el encargado de altas elige el contrato   → datos precargados
        ↓ confirma
    INSERT en EMPLEADOS → la base saca el ID
        ↓
    TR_VINCULAR_CONTRATO completa ID_EMPLEADO
```

## 2. Fase 1 — Base de datos (`modulos/42- CONTRATOS.sql`)

```sql
-- 1. El contrato puede existir sin empleado.
ALTER TABLE CONTRATOS MODIFY ID_EMPLEADO INT NULL;

-- 2. La búsqueda por cédula pasa a ser el camino normal (idempotente).
SET @hay := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'CONTRATOS'
               AND INDEX_NAME = 'IX_CONTRATOS_CEDULA');
SET @sql := IF(@hay = 0,
               'CREATE INDEX IX_CONTRATOS_CEDULA ON CONTRATOS (CEDULA)',
               'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. Engancha los contratos huérfanos cuando se da el alta.
DROP TRIGGER IF EXISTS TR_VINCULAR_CONTRATO;
CREATE TRIGGER TR_VINCULAR_CONTRATO AFTER INSERT ON EMPLEADOS
FOR EACH ROW
UPDATE CONTRATOS SET ID_EMPLEADO = NEW.ID_EMPLEADO
WHERE CEDULA = NEW.CEDULA AND ID_EMPLEADO IS NULL;
```

En el `CREATE TABLE IF NOT EXISTS` también se cambia `ID_EMPLEADO INT NOT NULL` → `INT NULL`, para que una base nueva nazca bien. La FK se mantiene: `NULL` no se valida.

## 3. Fase 2 — `SP_SUBIR_CONTRATO`

- Deja de exigir que la cédula esté en `EMPLEADOS`.
  - 0 empleados → `v_id = NULL`, sigue.
  - 1 empleado → toma el ID.
  - 2 o más → error de ambigüedad (se mantiene).
- El freno de contrato activo mira `CONTRATOS.CEDULA` directo:
  `IF EXISTS (SELECT 1 FROM CONTRATOS WHERE CEDULA = P_CEDULA AND ESTADO = 'ACTIVO')`.
- Se elimina el chequeo de empleado `INACTIVO`: no hay empleado todavía; ese control pertenece al alta.
- `FECHA_INICIO = P_FECHA_INGRESO`.
- `FECHA_FIN = DATE_ADD(P_FECHA_INGRESO, INTERVAL P_MESES MONTH)` solo si es temporal.
- Mensaje final:
  - con ID → `EXITO: CONTRATO #N REGISTRADO. EMPLEADO VINCULADO.`
  - sin ID → `EXITO: CONTRATO #N REGISTRADO. EMPLEADO PENDIENTE DE ALTA.`

## 4. Fase 3 — Opción 13: cotejo y registro (`contrato.cpp`)

**Lista de borradores** (hoy muestra solo nombre y tipo):

```
1. Anthony BAlbuena — 00000000000 — Cajero — ingreso 2026-11-01  (contratos/...)
2. Descartar un borrador (no sube nada)
0. Volver
```

**Cotejo campo por campo.** Enter deja el valor del borrador; escribir otro valor lo corrige:

```
--- COTEJO CONTRA EL PAPEL FIRMADO ---
(Enter deja el valor del borrador; escribi el valor si el papel dice otra cosa)

Nombre [Anthony BAlbuena]:
Cedula [00000000000]:
Cargo [Cajero]:
Salario pactado [18000.00]:
Tipo [FIJO]:
Fecha de ingreso [2026-11-01]:
Telefono [-]:
Email [-]:
```

**Validaciones antes de tocar la base:** cédula de 11 dígitos, salario > 0, fecha `AAAA-MM-DD`, tipo `FIJO` o `TEMPORAL` (y meses > 0 si es temporal, y la pregunta de meses solo se hace si el tipo es temporal).

**Resumen de diferencias:**

```
Cambios detectados:
  - salario: 18000.00 → 19000.00
  - cargo:   Cajero → Encargado
¿Registrar el contrato con estos valores? (S/N)
```

Sin cambios: `El papel coincide con el borrador.` y confirmación.

**Registro:** llama al SP con los valores cotejados. Si sale bien, renombra el borrador a `.subido` y avisa el número de contrato.

## 5. Fase 4 — Escaneo opcional (`contrato.cpp`)

Antes de registrar:

```
Ruta del PDF firmado (Enter = sin escaneo):
```

- Vacío → `RUTA_DOCUMENTO` = el HTML del borrador. No se copia nada.
- Con ruta → valida que exista, que sea archivo regular y que la extensión sea `.pdf`, `.jpg` o `.png`; máximo 20 MB. Copia a `contratos/firmados/FIRMADO_<CEDULA>_<AAAA-MM-DD>.pdf` (si existe, agrega `_2`, `_3`). Muestra la ruta destino y pide confirmación.
- La app **no** guarda el archivo en la base ni lo abre.
- Desde la opción 14 se puede **adjuntar el escaneo después** a un contrato ya registrado.

## 6. Fase 5 — Alta desde el contrato (`empleados.cpp`)

En la opción 1 (Agregar Empleado), antes de pedir datos:

```
Contratos firmados sin empleado:
  1. Anthony BAlbuena — 00000000000 — Cajero — 18,000.00 — ingreso 01/11/2026
  2. ...
  0. Dar de alta a alguien sin contrato
```

- Elegir uno precarga nombre, cédula, cargo, salario, teléfono, email y fecha de ingreso.
- El alta sigue el flujo actual (validaciones y `INSERT` en `EMPLEADOS`).
- El trigger engancha el contrato solo. No hay paso manual de asociación.

## 7. Fase 6 — Opciones 14 y 15 por cédula (`contrato.cpp`)

- **14 Ver contratos:** pide cédula (11 dígitos) y llama a `SP_CONTRATOS_POR_CEDULA` (se renombra el SP actual). Muestra tipo, fechas, salario, estado y si el documento tiene escaneo. Ofrece "Adjuntar escaneo" si falta.
- **15 Finalizar contrato:** pide cédula, busca el contrato `ACTIVO` y llama a `SP_FINALIZAR_CONTRATO` con el ID encontrado.

## 8. Fase 7 — Pruebas

**SQL — `db/test-contratos-subir.sh`** (contra `BALBU_TECH_TEST`, todo con `ROLLBACK`):

1. Cédula sin empleado → registra con `ID_EMPLEADO = NULL`.
2. Alta posterior → el trigger completa el ID.
3. Cédula con empleado existente → toma el ID en el momento.
4. Cédula con contrato `ACTIVO` → frena.
5. `FECHA_INICIO` = fecha de ingreso (no `CURDATE()`).
6. Temporal → `FECHA_FIN` = ingreso + meses.
7. Fijo → `FECHA_FIN = NULL`.
8. Dos empleados con la misma cédula → error de ambigüedad.

**UI — `db/test-contrato-borrador.sh`**:

9. Cotejo sin cambios → registra.
10. Cotejo con cambio de salario → registra el valor nuevo.
11. Cédula inválida en el cotejo → la rechaza.
12. Escaneo con ruta inexistente → no registra.
13. Sin escaneo → registra igual.
14. EOF en el cotejo → cancela sin escribir.

**Manual:** flujo completo contra `BALBU_TECH_TEST` (12 → cotejo → registro → alta → verificar ID vinculado).

## 9. Fase 8 — Documentación

- `modulos/42- CONTRATOS.md`: modelo nuevo, columnas, trigger, reglas.
- `Realizado.md`: sección del día con evidencia.
- Este plan: marcar como ejecutado.

## 10. Fuera de alcance

- Permisos por cargo (reclutamiento vs contrataciones).
- Guardar PDFs en la base de datos.
- Firma digital.
- Firma escaneada obligatoria.

## 11. Decisiones cerradas

1. La cédula es la llave; `ID_EMPLEADO` puede ser `NULL`.
2. El vínculo se completa con trigger al dar el alta.
3. `FECHA_INICIO` sale de la fecha de ingreso.
4. El escaneo es opcional y se guarda en disco, no en la base.
5. La 13 coteja y registra; no crea empleados.

## 12. Resultado de la ejecución (19/10/2026)

**Fase 1 — base.** `modulos/42- CONTRATOS.sql` con `ID_EMPLEADO INT NULL` en el
`CREATE TABLE` y en un `ALTER ... MODIFY` idempotente; índice
`IX_CONTRATOS_CEDULA` (se crea solo si falta); `TR_VINCULAR_CONTRATO` (AFTER
INSERT en `EMPLEADOS`). Aplicado a `BALBU_TECH` y `BALBU_TECH_TEST`. El contrato
real de la viva (Empleado de prueba, #4) quedó intacto.

**Fase 2 — `SP_SUBIR_CONTRATO`.** Cédula sin empleado → registra con
`ID_EMPLEADO = NULL` y responde `EMPLEADO PENDIENTE DE ALTA`; con empleado →
vincula y responde `EMPLEADO VINCULADO`; dos empleados con la misma cédula →
error. `FECHA_INICIO` y `FECHA_FIN` salen de `P_FECHA_INGRESO`.

> **Desvío del plan, a propósito:** el chequeo de empleado INACTIVO no se borró
> del todo. Se mantiene **solo cuando la cédula ya existe** en `EMPLEADOS`
> (recontratar a alguien inactivo sigue siendo un error), y no afecta al caso
> nuevo (persona sin alta), que es el que el plan quería habilitar.

**Fase 3 — opción 13.** Lista de borradores con cédula, cargo y fecha de
ingreso. Cotejo campo por campo con el valor del borrador como default; Enter
lo deja. Validaciones de cédula (11 dígitos), salario y fecha. Resumen de
diferencias antes de escribir y confirmación S/N. Al registrar, el borrador
pasa a `.subido`.

**Fase 4 — escaneo.** Opcional: pide una ruta, valida que exista, que sea
PDF/JPG/PNG y que no pase de 20 MB, y copia a `contratos/firmados/` con nombre
`FIRMADO_<cedula>_<fecha>`. Enter = sin escaneo. Nunca se guarda el archivo en
la base.

**Fase 5 — alta desde el contrato.** La opción 1 lista los contratos firmados
sin empleado y precarga nombre, cédula, cargo, salario, teléfono, email y fecha
de ingreso. `SP_INSERTAR_EMPLEADO` pasó a recibir `P_FECHA_INGRESO` (7º
parámetro, `COALESCE(..., CURDATE())`) para respetar la fecha del contrato; el
alta gratuita sigue funcionando con la fecha vacía.

**Fase 6 — opciones 14 y 15.** Las dos piden cédula. `SP_CONTRATOS_POR_EMPLEADO`
se reemplazó por `SP_CONTRATOS_POR_CEDULA` (devuelve nombre, cargo y la columna
`VINCULO`). La 14 ofrece adjuntar el escaneo si falta; la 15 busca el contrato
ACTIVO de esa cédula y lo finaliza.

**Fase 7 — pruebas.**
- `db/test-contratos-subir.sh` → **OK** (9 aserciones: contrato huérfano, fechas
  desde el ingreso, vínculo inmediato, FIJO sin fin, trigger al dar el alta,
  historial por cédula y los cuatro frenos).
- `db/test-contrato-borrador.sh` → **14/14 OK** (cotejo con EOF, cambio
  resumido, registro huérfano, alta precargada, salario corregido, cédula
  inválida, escaneo inexistente, ver y finalizar por cédula).
- `DB_HOST=127.0.0.1 bash db/check-app-sps.sh` → `Faltantes: 0 (verificados 82)`.
- `bash build.sh` → `OK: ./output/app`.

**Fase 8 — documentación.** `modulos/42- CONTRATOS.md` actualizado (modelo,
columnas, SP, trigger, reglas) y `Realizado.md` con la sección del día.

**Pendiente fuera de alcance:** cargar RNC, dirección, representante y su cédula
en `CONFIGURACION`; campos legales que el contrato todavía no pide
(nacionalidad, edad, sexo, estado civil, RNL, lugar de prestación,
provincia/municipio).
