# Módulo 33 — CONFIGURACION

Los ajustes del sistema como pares **clave/valor**: tasa de ITBIS, nombre de la
tienda y los datos de la empresa que se imprimen en los contratos. La idea es
cambiar ajustes **sin tocar código**.

**Es usado por:** `contrato.cpp` (lee la tabla entera) y `ventas.cpp`,
`compras.cpp`, `productos.cpp` (tasa de ITBIS con `FN_TASA_ITBIS`).

Fuente: `modulos/33- CONFIGURACION.sql` · Base: `BALBU_TECH` · Revisado: 20/10/2026.

## Tablas

### CONFIGURACION

| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
| `ID_CONFIG` | `INT` | PK, AUTO_INCREMENT | Identificador. |
| `CLAVE` | `VARCHAR(50)` | NOT NULL, **UNIQUE** | Ej. `ITBIS`, `NOMBRE_TIENDA`. |
| `VALOR` | `VARCHAR(100)` | NOT NULL | **Siempre texto**, incluso si es un número. |
| `DESCRIPCION` | `VARCHAR(200)` | NULL | Para qué sirve. |

**Semillas (`INSERT IGNORE`, no pisan lo cargado):**

| Clave | Valor inicial | Uso |
|---|---|---|
| `ITBIS` | `18` | Tasa de impuesto (`FN_TASA_ITBIS`). |
| `DIAS_GARANTIA` | `30` | **Sin uso**: ni la app ni el SQL la leen. |
| `NOMBRE_TIENDA` | `BALBU_TECH` | Contratos (con default si falta). |
| `RNC` | vacío | Contratos. |
| `CIUDAD` | vacío | Contratos. |
| `DIRECCION_EMPRESA` | vacío | Contratos. |
| `REPRESENTANTE` | vacío | Contratos. |
| `CEDULA_REPRESENTANTE` | vacío | Contratos. |

> **Los datos de la empresa nacen vacíos a propósito**: se completan con un
> `UPDATE` cuando el dueño los tenga, sin tocar código. Mientras estén vacíos,
> `contrato.cpp` imprime `____________` en su lugar.
>
> **`DIAS_GARANTIA` es una semilla muerta**: ningún `cpp` ni ningún `SP` consulta
> esa clave. La garantía no se calcula desde acá.
>
> **Todo es texto.** `VALOR` no tiene tipo numérico ni `CHECK`: las validaciones
> viven en el código que lo lee (o no viven).
>
> **No hay `SP` de lectura ni de escritura**: `contrato.cpp` hace
> `SELECT CLAVE, VALOR FROM CONFIGURACION` directo, y un cambio de ajuste se hace
> por SQL.

## Funciones

### `FN_TASA_ITBIS() → DECIMAL(5,2)`

Devuelve la tasa vigente leyendo `ITBIS` de `CONFIGURACION`. **La app la usa** en
ventas, compras y productos para mostrar precios con impuesto.

- si la fila no existe, está vacía o no es un número → **18.00** por defecto.
- si el valor es `0` o negativo → también 18.00.

> **No se puede poner ITBIS en 0 %.** La condición `V_TXT + 0 > 0` trata el cero
> como "falta de dato" y vuelve al 18. Un país sin impuesto no se puede
> configurar sin cambiar la función.
>
> **No hay tope superior**: un `VALOR` de `999` devuelve `999.00` y
> `DECIMAL(5,2)` lo corta en silencio. Nada valida que sea un porcentaje.
>
> **`V_TXT + 0` es una conversión implícita**: `'18%'` se convierte en `18` en
> MariaDB, pero con un aviso, y `'abc'` en `0` (que cae al default). Funciona por
> tolerancia del motor, no por validación.
>
> Declarada `READS SQL DATA`, que es lo correcto para una función que consulta
> tablas.

## Reglas de negocio

- **Los ajustes se leen de la base, no del código** (salvo el default de 18 %).
- **Las semillas no pisan valores existentes** (`INSERT IGNORE`).
- **La tasa de ITBIS nunca es cero**: si falta o es inválida, vale 18 %.
- **Los datos de la empresa se cargan a mano** y admiten estar vacíos.
- **Sin `USE` hardcodeado:** la base la define el `--database` del import.
