# Módulo 15 — HISTORIAL_LABORAL_EMPLEADO

Bitácora de los cambios de perfil del empleado: cada vez que cambia **cargo,
salario o estado**, se guarda el antes y el después, el tipo de cambio y la
fecha. No tiene SPs: la escribe **solo** un trigger sobre `EMPLEADOS`. Si se
borra el empleado, se borra su historial (`ON DELETE CASCADE`).

**Depende de:** `EMPLEADOS` (8).
**Dependencia de orden de triggers:** `TR_AUDITORIA_PERFIL_EMPLEADO` corre
**después** de `TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` (módulo 10).

> **La app no lee este módulo** (no hay `SELECT`/`CALL` en el C++): es
> auditoría para consultar por SQL o para un reporte futuro.

Fuente: `modulos/15- HISTORIAL_LABORAL_EMPLEADO.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### HISTORIAL_LABORAL_EMPLEADO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL_EMPLEADO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` **ON DELETE CASCADE** | Empleado. |
| `CARGO_ANTERIOR` | `VARCHAR(30)` | NOT NULL | Cargo antes del cambio. |
| `CARGO_NUEVO` | `VARCHAR(30)` | NOT NULL | Cargo después. |
| `SALARIO_ANTERIOR` | `DECIMAL(10,2)` | NOT NULL | Salario antes. |
| `SALARIO_NUEVO` | `DECIMAL(10,2)` | NOT NULL | Salario después. |
| `TIPO_CAMBIO` | `ENUM('AUMENTO','PROMOCION','CAMBIO_PUESTO','CAMBIO_ESTADO','AJUSTE')` | NOT NULL | Clasificación del cambio. |
| `ESTADO_ANTERIOR` | `VARCHAR(20)` | NULL | Estado antes (`ACTIVO`/`INACTIVO`). |
| `ESTADO_NUEVO` | `VARCHAR(20)` | NULL | Estado después. |
| `FECHA_CAMBIO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento del cambio. |
| `OBSERVACION` | `VARCHAR(280)` | NULL | Texto autogenerado con cargo y estado. |

**Índices:** `IX_HISTORIAL_EMPLEADO_ID`, `IX_HISTORIAL_EMPLEADO_FECHA`,
`IX_HISTORIAL_EMPLEADO_TIPO`.

> **Nota:** `CARGO_ANTERIOR`/`CARGO_NUEVO` son `VARCHAR(30)`, pero
> `EMPLEADOS.CARGO` es `VARCHAR(50)`. Un cargo de 31 a 50 caracteres haría
> fallar el `INSERT` del trigger (`1406`, dato demasiado largo) y, con él,
> **el `UPDATE` del empleado**. No hay cargos así hoy; es un límite a tener
> en cuenta si se agregan.

## Triggers

### `TR_AUDITORIA_PERFIL_EMPLEADO`

`AFTER UPDATE ON EMPLEADOS`, con `FOLLOWS
TR_DESACTIVAR_USUARIO_POST_LIQUIDACION` (orden fijo).

Se dispara solo si cambió `SALARIO`, `CARGO` o `ESTADO`, y clasifica con esta
**precedencia**:
1. cambió el cargo → **`PROMOCION`**
2. si no, subió el salario → **`AUMENTO`**
3. si no, cambió el estado → **`CAMBIO_ESTADO`**
4. cualquier otro caso → **`AJUSTE`**

Guarda cargo, salario y estado anteriores/nuevos, y una observación:
`Cambio automático: Cargo(<viejo>-><nuevo>) Estado(<viejo>-><nuevo>)`.

> **Notas de la clasificación:**
> - Un cambio de cargo se etiqueta **siempre `PROMOCION`**, aunque sea una
>   baja de categoría.
> - Una **baja de salario** no tiene etiqueta propia: cae en `AJUSTE` (o en
>   `CAMBIO_ESTADO` si además cambió el estado), nunca en `AUMENTO`.
> - El enum conserva `CAMBIO_PUESTO`, pero el trigger ya no lo usa: el
>   comentario del archivo explica que se dejó de usar porque mentía en los
>   cambios solo de estado.
>
> El `FOLLOWS` exige que el trigger del módulo 10 exista al crear este; el
> import ordena los archivos (10 antes que 15), así que se crea bien.

## Reglas de negocio

- **Auditoría automática** de cargo, salario y estado: no se registra a mano.
- **Un registro por update relevante** (si cambian dos campos, es una sola
  fila con la clasificación de mayor precedencia).
- **El historial sigue al empleado**: se borra en cascada con él.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
