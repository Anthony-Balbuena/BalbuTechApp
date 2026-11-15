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

> **Absorbe el `68` (14/11/2026):** el ensanchado del cargo en el historial
> vive ahora **en este mismo archivo**, al final, en la sección «HISTORIAL_CARGO_ANCHO
> (ex módulo 68)».

Fuente: `modulos/15- HISTORIAL_LABORAL_EMPLEADO.sql` · Base: `BALBU_TECH` · Revisado: 14/11/2026.

## Tablas

### HISTORIAL_LABORAL_EMPLEADO

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_HISTORIAL_EMPLEADO` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `ID_EMPLEADO` | `INT` | NOT NULL, FK → `EMPLEADOS` **ON DELETE CASCADE** | Empleado. |
| `CARGO_ANTERIOR` | `VARCHAR(50)` | NOT NULL | Cargo antes del cambio. |
| `CARGO_NUEVO` | `VARCHAR(50)` | NOT NULL | Cargo después. |
| `SALARIO_ANTERIOR` | `DECIMAL(10,2)` | NOT NULL | Salario antes. |
| `SALARIO_NUEVO` | `DECIMAL(10,2)` | NOT NULL | Salario después. |
| `TIPO_CAMBIO` | `ENUM('AUMENTO','PROMOCION','CAMBIO_PUESTO','CAMBIO_ESTADO','AJUSTE')` | NOT NULL | Clasificación del cambio. |
| `ESTADO_ANTERIOR` | `VARCHAR(20)` | NULL | Estado antes (`ACTIVO`/`INACTIVO`). |
| `ESTADO_NUEVO` | `VARCHAR(20)` | NULL | Estado después. |
| `FECHA_CAMBIO` | `TIMESTAMP` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Momento del cambio. |
| `OBSERVACION` | `VARCHAR(280)` | NULL | Texto autogenerado con cargo y estado. |

**Índices:** `IX_HISTORIAL_EMPLEADO_ID`, `IX_HISTORIAL_EMPLEADO_FECHA`,
`IX_HISTORIAL_EMPLEADO_TIPO`.

> **Nota:** `CARGO_ANTERIOR`/`CARGO_NUEVO` estaban en `VARCHAR(30)` mientras
> `EMPLEADOS.CARGO` es `VARCHAR(50)`. Un cargo de 31 a 50 caracteres hacía
> fallar el `INSERT` del trigger (`1406`, dato demasiado largo) y, con él,
> **el `UPDATE` del empleado entero**: no se podía cambiar el cargo, ni dar un
> aumento, ni despedir a esa persona. El `CREATE TABLE` de arriba ya las crea en
> 50 y el bloque `HISTORIAL_CARGO_ANCHO` del final lo aplica a las bases viejas;
> la viva ya lo tenía hecho a mano desde antes del 22/10/2026.

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

## HISTORIAL_CARGO_ANCHO (ex módulo 68)

Cargo ancho en el historial: absorbido dentro del `15` el 14/11/2026 (ver
«Estado de la documentación» y el `## Log` de
`odd/tasks/consolidacion-modulos.md`). El cuerpo del ex `68` viaja **verbatim**:
acá solo se degradaron los encabezados un nivel.

Ensancha `CARGO_ANTERIOR` y `CARGO_NUEVO` de `HISTORIAL_LABORAL_EMPLEADO` de
`VARCHAR(30)` a `VARCHAR(50)`, para que igualen a `EMPLEADOS.CARGO`.

**Depende de:** `HISTORIAL_LABORAL_EMPLEADO` (esta misma sección, arriba) y
`EMPLEADOS` (8).
**Es usado por:** nadie. Es una migración de esquema sin objetos nuevos.

Fuente: `modulos/15- HISTORIAL_LABORAL_EMPLEADO.sql`, sección del ex módulo `68`
· Base: `BALBU_TECH` · Revisado: 12/11/2026 · Fusionado: 14/11/2026.

### El bug

El trigger `TR_AUDITORIA_PERFIL_EMPLEADO` (esta misma sección) copia
`OLD.CARGO` y `NEW.CARGO` al historial cada vez que cambia el cargo, el salario
o el estado. Con el historial en 30 y `EMPLEADOS.CARGO` en 50, un empleado con
un cargo de 31 a 50 caracteres hacía fallar el `INSERT` del trigger:

```
ERROR 1406 (22001): Data too long for column 'CARGO_ANTERIOR' at row 1
```

Y como el trigger corre dentro del `UPDATE`, **se caía el `UPDATE` entero**.
Ese empleado no podía:

- cambiar de cargo (ni siquiera a uno corto: `OLD.CARGO` ya no entra),
- recibir un aumento (cambia `SALARIO`),
- ser despedido ni reactivado (cambia `ESTADO`).

Editar nombre, cédula, email o teléfono sí funcionaba: el trigger solo escribe
cuando cambia cargo, salario o estado.

### Estado de las bases

| Base | Antes | Después |
|---|---|---|
| `BALBU_TECH` (viva) | `varchar(50)` desde antes del 22/10/2026, hecho a mano | sin cambios (el módulo no hace nada) |
| `BALBU_TECH_TEST` | `varchar(30)` | `varchar(50)` |
| Instalación nueva desde `modulos/` | `varchar(30)` | `varchar(50)` |

El cambio de la viva nunca quedó escrito en un módulo: era drift. Este bloque
lo pone por escrito y lo aplica donde falte.

### Cómo se aplica

```bash
# TEST
DB_HOST=127.0.0.1 bash -c 'mariadb -h 127.0.0.1 -u "$DB_ADMIN_USER" \
  -p"$DB_ADMIN_PASSWORD" --database=BALBU_TECH_TEST' \
  < "modulos/15- HISTORIAL_LABORAL_EMPLEADO.sql"

# Verificación
DB_HOST=127.0.0.1 DB_NAME=BALBU_TECH_TEST bash db/test-historial-laboral.sh
```

Es idempotente: consulta `INFORMATION_SCHEMA.COLUMNS` y solo hace el `ALTER` si
la columna todavía mide menos de 50. No toca datos.

### Chequeo de daño previo

El módulo imprime primero cuántas filas del historial tienen un cargo de
exactamente 30 caracteres. Con `sql_mode` estricto (`STRICT_TRANS_TABLES`, el de
la instancia) no puede haber truncados: el `1406` abortaba el `UPDATE` antes de
escribir. Si el número no es 0, esa base corrió sin modo estricto en algún
momento y hay que revisar esas filas a mano.
