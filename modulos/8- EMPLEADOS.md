# Módulo 8 — EMPLEADOS

Maestro de empleados: nombre, cédula, cargo, salario, teléfono, email y
fechas de ingreso/despido. Todo empleado arranca `ACTIVO`; el despido lo pasa
a `INACTIVO` y el reingreso lo devuelve a `ACTIVO`.

Es la base de RRHH: asistencia (11), vacaciones (12), permisos (13), bonos
(14), historial laboral (15), liquidaciones (16) y contratos (42) cuelgan de
este ID.

Fuente: `modulos/8- EMPLEADOS.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### EMPLEADOS

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_EMPLEADO` | `INT` | PK, AUTO_INCREMENT, NOT NULL | Identificador. |
| `NOMBRE` | `VARCHAR(100)` | NOT NULL, CHECK trim `> 0` | Nombre completo. |
| `CEDULA` | `VARCHAR(20)` | NOT NULL | Cédula. **Sin UNIQUE en la tabla**: la unicidad la controla el SP. |
| `CARGO` | `VARCHAR(50)` | NOT NULL | Cargo. Los triggers lo guardan en **MAYÚSCULAS**. |
| `SALARIO` | `DECIMAL(10,2)` | NOT NULL, CHECK `> 0` | Salario mensual. |
| `TELEFONO` | `VARCHAR(20)` | NOT NULL, **UNIQUE** | Teléfono. |
| `EMAIL` | `VARCHAR(100)` | NOT NULL, **UNIQUE** | Email. |
| `FECHA_INGRESO` | `DATE` | NOT NULL | Alta original. El reingreso la **sobrescribe**. |
| `FECHA_DESPIDO` | `DATE` | NULL | Baja; `NULL` mientras está activo. |
| `ESTADO` | `ENUM('ACTIVO','INACTIVO')` | NOT NULL, DEFAULT `'ACTIVO'` | Estado. |
| `FECHA_REGISTRO` | `TIMESTAMP` | DEFAULT `CURRENT_TIMESTAMP` | Alta del registro. |

> **Nota:** `CEDULA` no es única a nivel de tabla (sí lo es `TELEFONO` y
> `EMAIL`). Un `INSERT` directo puede duplicar cédula; la protección real está
> en `SP_INSERTAR_EMPLEADO`.

## Procedimientos almacenados

### `SP_INSERTAR_EMPLEADO(P_NOMBRE, P_CEDULA, P_CARGO, P_SALARIO, P_TELEFONO, P_EMAIL, P_FECHA_INGRESO)`

**Usada por la app** (`empleados.cpp`).

**Limpieza:** nombre con colapso de espacios; cédula sin espacios ni guiones;
teléfono sin espacios/paréntesis/guiones; email en minúsculas y sin espacios.
El cargo **no** se limpia acá: lo pasa a mayúsculas el trigger de inserción.

**Validaciones (`SIGNAL 45000`):**
- nombre o cédula vacíos → `ERROR: NOMBRE Y CÉDULA SON OBLIGATORIOS.`
- cédula repetida → `ERROR: YA EXISTE UN EMPLEADO CON ESTA CÉDULA.`
- email repetido → `ERROR: ESTE EMAIL YA ESTÁ REGISTRADO.`
- teléfono repetido → `ERROR: ESTE TELÉFONO YA ESTÁ REGISTRADO.`
- salario `<= 0` → `ERROR: EL SALARIO DEBE SER MAYOR A CERO.`

`FECHA_INGRESO` nula → usa `CURDATE()`. Devuelve
`EXITO: EMPLEADO "<nombre>" INSERTADO. ID: <id>`.

> **Nota:** un salario `NULL` **no** cae en la validación (`NULL <= 0` es
> `NULL`, no verdadero) y termina en el error técnico `1048` de la columna
> `NOT NULL`.

### `SP_ACTUALIZAR_EMPLEADO(P_ID_EMPLEADO, P_NOMBRE, P_CEDULA, P_EMAIL, P_CARGO, P_TELEFONO, P_SALARIO)`

**Usada por la app.** Los parámetros van en el **orden que manda el C++**
(email, cargo, teléfono, salario); hubo un bug histórico de parámetros
permutados que corrompía datos, por eso el orden está comentado en el archivo.
Actualización parcial: `NULL` conserva.

- ID inexistente → `ERROR: EL EMPLEADO NO EXISTE.`
- Cédula vacía → `ERROR: LA CÉDULA NO PUEDE ESTAR VACÍA.`
- Cédula de otro → `ERROR: LA CÉDULA YA PERTENECE A OTRO EMPLEADO.`
- Teléfono de otro → `ERROR: EL TELÉFONO YA PERTENECE A OTRO EMPLEADO.`
- Email de otro → `ERROR: EL EMAIL YA PERTENECE A OTRO EMPLEADO.`
- Salario: solo se aplica si `P_SALARIO > 0`; si viene `NULL`, 0 o negativo
  se **conserva** el actual (no hay mensaje de error).
- Devuelve `EXITO: EMPLEADO "<nombre>" ACTUALIZADO CON ÉXITO.`

> El nombre no se valida vacío: un `''` lo corta el CHECK de tabla con error
> técnico.

### `SP_DESPEDIR_EMPLEADO(P_ID_EMPLEADO, P_FECHA_DESPIDO)`

**Usada por la app.** Marca `INACTIVO` y setea `FECHA_DESPIDO`.

- ID inexistente → `ERROR: EL EMPLEADO NO EXISTE EN LA BASE DE DATOS.`
- Ya inactivo → `AVISO: ESTE EMPLEADO YA CONSTA COMO INACTIVO.`
- Fecha nula → hoy; fecha futura →
  `ERROR: LA FECHA DE DESPIDO NO PUEDE SER FUTURA.`
- Devuelve `EXITO: EL EMPLEADO ID <id> HA SIDO DADO DE BAJA.`

### `SP_REACTIVAR_EMPLEADO(P_ID_EMPLEADO, P_NUEVO_SALARIO)`

**Usada por la app.** Devuelve a `ACTIVO`, limpia `FECHA_DESPIDO`, **setea
`FECHA_INGRESO = CURRENT_DATE`** y aplica el salario nuevo si viene.

- ID inexistente → `ERROR: EL ID DE EMPLEADO NO EXISTE.`
- Ya activo → `AVISO: EL EMPLEADO YA SE ENCUENTRA ACTIVO.`
- Salario no nulo y `<= 0` → `ERROR: EL NUEVO SALARIO DEBE SER MAYOR A CERO.`
- Devuelve `EXITO: EMPLEADO ID <id> REINGRESADO CORRECTAMENTE.`

> El reingreso **pierde la fecha de ingreso original**: la antigüedad pasa a
> contar desde el reingreso. Es el comportamiento documentado en el código.

### `SP_REPORTE_NOMINA_TOTAL()`

**La app no la llama.** Devuelve **2 result sets**: resumen de activos
(`TOTAL_EMPLEADOS`, `GASTO_MENSUAL_NOMINA`, `SUELDO_MINIMO`, `SUELDO_MAXIMO`,
`SUELDO_PROMEDIO`) y desglose `CARGO / EMPLEADOS_POR_CARGO / TOTAL_POR_CARGO`.
Si no hay activos, un único result set con
`AVISO: NO HAY EMPLEADOS ACTIVOS PARA GENERAR NÓMINA.`

### `SP_CONSULTAR_EMPLEADOS(P_ID_EMPLEADO, P_FILTRO_NOMBRE)`

**La app no la llama.** Si llega ID, filtra por ID; si no, por nombre parcial;
si ambos vacíos, lista todo. Devuelve 10 columnas (sin `FECHA_REGISTRO`),
ordenado por ID **descendente**.

### `SP_AUMENTO_POR_CARGO(P_ID_EMPLEADO, P_CARGO, P_PORCENTAJE)`

**La app no la llama.** Aplica aumento porcentual a los activos, por ID o por
cargo. Trabaja en transacción explícita: si no hay ID ni cargo →
`ERROR: ESPECIFIQUE ID O CARGO.` (rollback); si el `UPDATE` no toca filas →
`ERROR: NO SE ENCONTRARON EMPLEADOS ACTIVOS PARA EL FILTRO DADO.`
(rollback); si actualiza, `COMMIT` y
`EXITO: SE APLICÓ EL AUMENTO A <n> EMPLEADO(S).` Redondea a 2 decimales.

> No valida el signo ni el tope del porcentaje: un valor negativo **baja** el
> salario. Uso interno, no expuesto en la app.

### `SP_ANIVERSARIOS_MES()`

**La app no la llama.** Lista activos que cumplen años de ingreso en el mes
actual, con `ANOS_EN_EMPRESA`, ordenados por día. Sin activos →
`ERROR: NO HAY EMPLEADOS ACTIVOS EN LA BASE DE DATOS.`; sin aniversarios →
`INFORMATIVO: NO HAY ANIVERSARIOS LABORALES EN EL MES ACTUAL.`

### `SP_BUSQUEDA_RAPIDA_EMPLEADOS(P_TERMINO)`

**La app no la llama.** Término obligatorio (si no,
`ERROR: DEBE INGRESAR UN DATO PARA BUSCAR.`). Busca por ID exacto, cédula,
nombre o cargo; devuelve `ID, CEDULA, NOMBRE, CARGO, ESTADO`, con los
`ACTIVO` primero y luego alfabético.

### `SP_GENERAR_RECIBO_EMPLEADO(P_ID_EMPLEADO)`

**La app no la llama.** Volante de pago de un activo: sueldo bruto,
`DESCUENTO_SFS` (3.04%), `DESCUENTO_AFP` (2.87%), `SUELDO_NETO` (bruto menos
5.91%) y fecha de emisión `dd/mm/yyyy`. ID nulo →
`ERROR: DEBE PROPORCIONAR UN ID DE EMPLEADO.`; inexistente o inactivo →
`ERROR: EL EMPLEADO NO EXISTE O NO SE ENCUENTRA ACTIVO.`

> Los porcentajes de SFS/AFP están **hardcodeados** en el SP.

## Triggers

### `TRG_CARGO_UPPER`

`BEFORE INSERT ON EMPLEADOS`: guarda `NEW.CARGO = UPPER(NEW.CARGO)`.

### `TRG_CARGO_UPPER_UPDATE`

`BEFORE UPDATE ON EMPLEADOS`: mismo uppercase del cargo en cada update.

> Por esto los cargos quedan siempre en mayúsculas; los reportes que agrupan
> por cargo dependen de eso.

## Reglas de negocio

- **Nombre y cédula obligatorios**; cédula única **por lógica de SP** (sin
  UNIQUE en la tabla).
- **Teléfono y email obligatorios y únicos** (UNIQUE real).
- **Salario > 0** (CHECK + validaciones de SP).
- **Cargo en mayúsculas** por triggers.
- **Despido** = `INACTIVO` + `FECHA_DESPIDO` (no se borra); **reingreso** =
  `ACTIVO`, fecha de despido `NULL` y fecha de ingreso = hoy.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
