# Módulo 35 — DETALLE_REPARACIONES

Bitácora del trabajo técnico sobre una asignación: qué se hizo, qué repuesto se
usó, cuánto costó, cuánto tiempo llevó, en qué estado va y dónde está la
evidencia.

**Depende de:** `ASIGNACIONES_RECLAMOS` (34) y `USUARIOS` (10).

> **La app no usa este módulo**: ni la tabla ni el SP aparecen en el código C++.
> Está en la base, sin flujo que lo alimente.

Fuente: `modulos/35- DETALLE_REPARACIONES.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### DETALLE_REPARACIONES

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_REPARACION` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_ASIGNACION` | `INT` | NOT NULL, FK → `ASIGNACIONES_RECLAMOS` **ON DELETE CASCADE** | Asignación que avanza. |
| `ID_USUARIO` | `INT` | NOT NULL, FK → `USUARIOS` | Quién registra el avance. |
| `FECHA_ACCION` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Cuándo. |
| `ACCION_REALIZADA` | `VARCHAR(255)` | NOT NULL | Qué se hizo. |
| `REPUESTO_UTILIZADO` | `VARCHAR(100)` | NULL | Repuesto usado. |
| `COSTO_REPUESTO` | `DECIMAL(10,2)` | DEFAULT `0.00` | Costo del repuesto. |
| `TIEMPO_EMPLEADO_MIN` | `INT` | DEFAULT `0` | Minutos de trabajo. |
| `ESTADO_AVANCE` | `ENUM('PENDIENTE','EN_PROCESO','COMPLETADO','CANCELADO')` | NOT NULL, DEFAULT `'EN_PROCESO'` | Estado del avance. |
| `RUTA_EVIDENCIA` | `VARCHAR(255)` | NULL | Ruta o nombre del archivo de evidencia. |

**Sin índices propios:** solo los que crean las FK (asignación y usuario).

> **El repuesto es texto libre, no `ID_PRODUCTO`**: no descuenta stock ni entra
> en el costo de ventas. Si el repuesto sale del inventario, esa salida se
> registra por otro lado (o no se registra).

## Procedimientos almacenados

### `SP_REGISTRAR_AVANCE_REPARACION(P_ID_ASIGNACION, P_ID_USUARIO, P_ACCION, P_REPUESTO, P_COSTO, P_TIEMPO, P_ESTADO, P_RUTA)`

**La app no lo llama.**

1. asignación inexistente → `ERROR: ASIGNACIÓN NO EXISTE.`
2. asignación `COMPLETADO` → `ERROR: REPARACIÓN YA FINALIZADA.`
3. estado de avance fuera del `ENUM` → `ERROR: ESTADO DE AVANCE DESCONOCIDO.`
4. Inserta y devuelve `EXITO: AVANCE Y EVIDENCIA REGISTRADOS.`

> **Lo que no valida:**
> - **`P_ID_USUARIO`**: si no existe, salta el `1452` del FK, no un mensaje.
> - **`P_ACCION`**: vacía o `NULL` termina en el `NOT NULL` (error técnico).
> - **`P_COSTO` y `P_TIEMPO`**: negativos se aceptan; `NULL` en `COSTO_REPUESTO`
>   también (la columna admite nulos, aunque tenga `DEFAULT 0.00`).
> - **El estado de la asignación `CANCELADO`**: solo frena `COMPLETADO`, así que
>   se puede seguir cargando avances sobre una reparación cancelada.

## Reglas de negocio

- **Es una bitácora**: cada fila es un avance, no se actualiza ni se cierra.
- **No se avanza una asignación completada.**
- **El avance no mueve stock ni dinero**: el repuesto es un dato descriptivo.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
