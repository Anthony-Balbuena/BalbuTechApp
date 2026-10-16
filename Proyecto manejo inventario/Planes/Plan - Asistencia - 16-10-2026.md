# Plan - Asistencia (automática + huella futura) - 16-10-2026

> Todo lo hablado el 16/10 sobre asistencia: estado actual, v1 automática,
> anti-doble-ponche, corte para huella, v2 y lector biométrico.
> Estado: PLANIFICADO (sin implementar). Ver pendiente en
> `Pendientes - App C++.md` (Menú empleados).

## 1. Estado actual verificado (16/10)

- BD completa y aplicada: tabla `ASISTENCIA_EMPLEADOS` (entrada/salida,
  horas auto, `PRESENTE/AUSENTE/TARDE/PERMISO`, 1 fila por empleado/día).
- SPs (archivo `11-ASISTENCIA_EMPLEADOS.sql`, sin tocar en v1):
  - `SP_REGISTRAR_ASISTENCIA(id, ENTRADA/SALIDA)`: tope 08:30 (después
    queda TARDE), valida vacaciones y permisos aprobados, frena doble
    ENTRADA / doble SALIDA / SALIDA sin entrada con errores amables,
    devuelve `EXITO: ASISTENCIA REGISTRADA.`
  - `11_SP_JUSTIFICAR_ASISTENCIA` (fecha + estado + motivo).
  - `11_SP_REPORTE_ASISTENCIA_INDIVIDUAL` (por empleado y rango).
  - `11_SP_BLOQUEAR_EDICION_ANTIGUA` (regla 7 días).
- App: SIN pantalla (menú Empleados 1-6 + Volver). El permiso
  `REGISTRAR_ASISTENCIA` ya existe en roles.

## 2. Decisiones tomadas (16/10)

- Una sola opción automática (no entrada/salida separadas):
  hora BD < 12:00 = ENTRADA, >= 12:00 = SALIDA. Corte 12:00 como
  constante (1 línea para cambiarlo).
- Hora desde la BD (`SELECT CURTIME()`), no del contenedor (evita
  desfase de zona horaria cerca del límite).
- Sin ponche de almuerzo: solo entrada + salida por día (dueño 16/10).
- Anti-doble-ponche: ya existe en el SP. Para el lector, el doble-dedo
  cae en el error amable ("ya está registrado").
- Regla espejo: si el SP dice "tipo equivocado", se ofrece el otro
  movimiento (s/n) y el humano confirma. Cubre salida temprana con
  permiso (10:00) y primera marca de tarde (ENTRADA tardía).
- Permiso de día completo aprobado sigue bloqueando todo ponche
  (regla actual, sin cambios).
- Supuesto: una entrada + una salida por día (sin tanda partida).

## 3. Diseño v1 (solo `empleados.cpp`, cero SQL)

Menú: `7. Marcar asistencia`, `8. Ver asistencia`, `9. Volver`.

Funciones nuevas:

- `identificarEmpleado()` — EL CORTE: hoy pide el ID con reintentos;
  mañana la huella entra aquí sin tocar lo demás.
- `marcarAsistenciaAuto()` — ID → hora BD → tipo → CALL SP → mensaje.
- `verAsistenciaUI()` — ID + rango `AAAA-MM-DD` → tabla
  `FECHA | ENTRADA | SALIDA | HORAS | ESTADO`.

Flujo del ponche:

```text
7. Marcar asistencia
        |
        v
identificarEmpleado()  <- hoy: teclea ID / mañana: huella o ID
        |
        v
hora = SELECT CURTIME()   (reloj de la BD)
        |
   +----+-----+
   | < 12:00  | >= 12:00
   v          v
 ENTRADA    SALIDA
   +----+-----+
        |
        v
CALL SP_REGISTRAR_ASISTENCIA
        |
  +-----+------------+
  v     v            v
 EXITO  "ya tiene /  otros errores
  ok    sin entrada"  (permiso, vacaciones,
        |             doble salida)
        |               |
   Ofrecer el       Mostrar mensaje
   otro mov. (s/n)  y fin
        |
    s = registra
    n = nada
```

Tabla de casos (para prueba en vivo):

| Hora | Situación | Resultado |
|---|---|---|
| 8:00 | sin entrada | ENTRADA ok |
| 8:01 / 11:00 | ya entró | error + ofrece SALIDA → n = nada |
| 10:00 | permiso salir antes | error + ofrece SALIDA → s = SALIDA ok |
| 13:00 | primera vez del día | error + ofrece ENTRADA tardía → s ok |
| 18:00 | ya entró | SALIDA ok, calcula horas |
| 18:05 | ya salió | error "ya tiene salida", sin oferta |
| cualquiera | permiso día completo | bloqueado (sin cambios) |

## 4. Corte para huella futura (sin reescribir nada)

```text
[Teclado: ID] --+
                +--> SP_REGISTRAR (igual, no cambia)
[Huella: puente] -+
```

Cuando llegue el aparato solo se agrega (nada se reescribe):

- Columna `HUELLA_TEMPLATE` (BLOB, nullable) en `EMPLEADOS`.
- Pantalla de enrolar (admin).
- Modo huella en el menú. El marcado a mano queda como respaldo.

## 5. Lector biométrico (opciones, sin equipo todavía)

- Concepto: el lector guarda plantilla matemática (~1 KB, no la foto);
  enrolar = 2-3 capturas; marcar = el SDK dice qué empleado es.
  Preferir plantillas estándar ISO 19794-2 (no formato propietario).
- Problema: la app corre en Docker (Linux), el lector va en la PC
  Windows → el hardware no entra al contenedor.
- A) Lector USB + puente en Windows (si compran lector): programita
  en la PC con el SDK del fabricante, responde por localhost.
- B) Reloj ZKTeco autónomo + script importador (si hay presupuesto
  de equipo): sin vivo, cero drivers, aguanta apagones.
- C) SDK directo en el contenedor (última opción).
- Siempre: fallback por ID (lector roto, dedo lastimado) y enrolar
  con varias capturas.

## 6. v2 (después de v1)

- Justificar (fecha + estado + motivo, regla 7 días).
- Reporte del día: presentes / ausentes / tarde (SP nuevo).
- Resumen mensual por empleado: días, horas, tardes (SP nuevo,
  útil si algún día ata a nómina).
- Permiso por rol: cajero solo marca, justificar solo admin
  (mismo patrón del botón 10 en ventas).
- Opcional: hora tope (08:30) configurable en vez de fija en el SP.

## 7. Preguntas abiertas

- Corte 12:00 confirmado (propuesto, 1 línea).
- Equipo de huella: cuál / cuándo (define A vs B).
