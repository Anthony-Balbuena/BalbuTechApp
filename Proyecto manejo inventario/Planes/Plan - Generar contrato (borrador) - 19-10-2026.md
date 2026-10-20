# Plan — Generar contrato (borrador) — 19/10/2026

**Alcance:** solo la opción **12. Generar contrato**. No entra la subida (13), ni el alta del empleado, ni la finalización (15).

## 1. Regla de negocio que manda todo

La opción 12 es **la oferta**: la persona **todavía no está en `EMPLEADOS`**. Su cédula va escrita en el contrato, pero no se busca en la base.

- La 12 **no consulta** `EMPLEADOS` y **no frena** por cédula inexistente ni por cédula repetida.
- No escribe nada en la base.
- El documento se imprime, se firma a mano y **después** se sube (opción 13). Ahí sí tiene que existir el empleado.

## 2. Quién hace qué

| Cargo | Etapa |
|---|---|
| Reclutamiento | genera el borrador (opción 12) |
| Empleado y empleador | firman el papel |
| Contrataciones | sube el contrato firmado (opción 13) |

Los tres son RRHH, pero son cargos distintos. En esta etapa solo importa que **el que genera no necesita que el empleado exista**. La separación de permisos queda para la etapa 13.

## 3. Datos que pide (en este orden)

| # | Dato | Obligatorio | Default | Va al contrato |
|---|---|---|---|---|
| 1 | Cédula del empleado | Sí | — | Sí |
| 2 | Nombre completo | Sí | — | Sí |
| 3 | Cargo que se le ofrece | Sí | — | Sí |
| 4 | Salario ofrecido | Sí | — | No (solo al `.borrador`) |
| 5 | Salario pactado | Sí | El ofrecido | **Sí** (es el que se firma) |
| 6 | Tipo de contrato (fijo / temporal) | Sí | — | Sí |
| 7 | Duración en meses (solo temporal) | Sí si temporal | — | Sí |
| 8 | Fecha de ingreso | Sí | Hoy | Sí |
| 9 | Horario | No | `9:00 AM - 6:00 PM` | Sí |
| 10 | Horas semanales | No | `44` | Sí |
| 11 | Forma de pago | No | `transferencia bancaria` | Sí |
| 12 | Dirección del empleado | Sí | — | Sí |
| 13 | Teléfono | No | `-` | No (snapshot para la 13) |
| 14 | Email | No | `-` | No (snapshot para la 13) |

**Salario:** el ofrecido y el pactado pueden diferir en las dos direcciones (el empleado pide más y se le da, o la empresa da menos). El documento firmado lleva **solo el pactado**. El ofrecido queda en el `.borrador` como referencia.

## 4. Bloque de firmas (al final del documento)

Reemplaza el bloque anterior de dos columnas (`EL EMPLEADOR` / `EL EMPLEADO`). Quedó así:

```
_________________________________          _________________________________
Firma del empleado                         Firma del empleador

Anthony BAlbuena                           {{REPRESENTANTE}}
CÉDULA: 40229519463                        CÉDULA: {{CEDULA_REPRESENTANTE}}
                                           BALBU_TECH
```

- La línea se dibuja con el borde superior de la clase `.linea` que ya tenía la plantilla.
- La cédula del empleado se imprime (ya se tipeó al generar): no se deja para escribir a mano.
- `REPRESENTANTE` y `CEDULA_REPRESENTANTE` salen de `CONFIGURACION`.

## 5. Qué se genera

En `contratos/`:

| Archivo | Contenido |
|---|---|
| `CONTRATO_<NOMBRE>_<AAAA-MM-DD>.html` | el documento con el bloque de firmas, listo para imprimir/PDF |
| `CONTRATO_<NOMBRE>_<AAAA-MM-DD>.borrador` | los datos en `clave=valor`, incluido `salario_ofrecido` |

El `.borrador` es lo que después lee la opción 13 para no volver a tipear nada.

## 6. Pie del documento

Hoy dice: *"Documento generado por BALBU_TECH el {fecha}. Borrador sujeto a revisión legal antes de su firma."*

Propuesto, general (empresa + RNC + ubicación, sin usuario):

```
Documento generado por BALBU_TECH, RNC 1-31-XXXXX-X, Santo Domingo,
Republica Dominicana, el 19/10/2026.
Borrador sujeto a revision legal antes de su firma.
```

**Problema detectado (19/10):** esos datos **no existían**. `CONFIGURACION` solo tiene tres filas: `NOMBRE_TIENDA`, `ITBIS` y `DIAS_GARANTIA`. `armarContrato` buscaba `RNC`, `CIUDAD`, `DIRECCION_EMPRESA`, `REPRESENTANTE` y `CEDULA_REPRESENTANTE`, no los encontraba y los reemplazaba por `____________`.

O sea: **todos los contratos salían con RNC, ciudad, dirección y representante en blanco.** No era un problema del pie: era del documento entero.

**Decidido (19/10):** todo lo de la empresa va en **`CONFIGURACION`**, que ya dice `BALBU_TECH` en `NOMBRE_TIENDA`. Se agregaron las claves que faltaban, **vacías**, para completarlas con un `UPDATE`:

```sql
UPDATE CONFIGURACION SET VALOR='1-31-XXXXX-X' WHERE CLAVE='RNC';
UPDATE CONFIGURACION SET VALOR='Santo Domingo' WHERE CLAVE='CIUDAD';
UPDATE CONFIGURACION SET VALOR='...' WHERE CLAVE='DIRECCION_EMPRESA';
UPDATE CONFIGURACION SET VALOR='...' WHERE CLAVE='REPRESENTANTE';
UPDATE CONFIGURACION SET VALOR='...' WHERE CLAVE='CEDULA_REPRESENTANTE';
```

Se descartó una tabla `EMPRESA` aparte: el dueño la rechazó. `CONFIGURACION` es la configuración de la empresa y ahí va todo lo suyo.

## 7. Qué NO entra en este plan

- Subir el contrato (13) y el alta del empleado.
- Permisos por cargo (reclutamiento vs contrataciones).
- Los campos legales que faltan (nacionalidad, edad, sexo, estado civil, RNL, lugar de prestación, provincia/municipio). Quedan anotados en `Flujos/Contrato de trabajo - requisitos legales RD.md`.
- Que `FECHA_INICIO` en la base salga de la fecha de ingreso (eso es la 13).

## 8. Cómo se prueba

1. Cédula que **no** existe en `EMPLEADOS` → genera igual (es el caso normal de una oferta).
2. Cédula que **sí** existe → genera igual (no precarga, no frena).
3. Cédula vacía → no deja avanzar.
4. Salario pactado distinto del ofrecido → el HTML muestra el pactado; el `.borrador` guarda los dos.
5. El HTML generado termina con las tres líneas de firma.
6. EOF en cualquier pregunta → sale con "Operación cancelada", sin colgarse.

## 9. Decisiones

1. ~~¿La cédula se valida con formato?~~ **Sí, 11 dígitos, sin guiones ni espacios.**
2. ~~¿El pie lleva el usuario que generó?~~ **No: va la empresa (nombre, RNC, ubicación).**
3. ~~¿Los datos de la empresa van a una tabla `EMPRESA` nueva o a `CONFIGURACION`?~~ **`CONFIGURACION`, con las claves nuevas vacías.** La tabla `EMPRESA` se creó, se probó y se borró: rechazada por el dueño.

## 10. Ejecutado (19/10/2026)

- **`generarContratoUI`**: se quitó la consulta a `EMPLEADOS` y los dos `return` (cédula repetida / no registrada). Pide cédula con validación de 11 dígitos, después nombre y cargo. El salario ofrecido ya no tiene default: es obligatorio.
- **`pedirMonto`**: con entrada agotada corta con `CancelarOperacionException` antes de volver a pedir, así un monto obligatorio sin default no gira.
- **`armarContrato`**: los datos de la empresa salen de `CONFIGURACION` (`NOMBRE_TIENDA`, `RNC`, `CIUDAD`, `DIRECCION_EMPRESA`, `REPRESENTANTE`, `CEDULA_REPRESENTANTE`). Lo que esté vacío muestra `____________`.
- **`plantillas/contrato.html`**: bloque de firmas nuevo y pie con empresa, RNC y ciudad.
- **`modulos/33- CONFIGURACION.sql`**: se agregaron las cinco claves de empresa (`RNC`, `CIUDAD`, `DIRECCION_EMPRESA`, `REPRESENTANTE`, `CEDULA_REPRESENTANTE`) con valor vacío, para que una base nueva ya las tenga. Aplicadas también a `BALBU_TECH` y `BALBU_TECH_TEST`.
- **`db/test-contrato-borrador.sh`**: caso 6 reescrito (cédula válida que no existe → no frena, cancela con EOF) y caso 7 nuevo (cédula de 3 dígitos → la rechaza).

**Evidencia**

- `bash build.sh` → `OK: ./output/app`.
- `db/test-contrato-borrador.sh` → **7/7 OK** contra `BALBU_TECH_TEST`.
- Prueba manual (cédula 40229519463, ofrecido 20 000, pactado 18 000, FIJO): el HTML salió con las firmas, la cédula impresa, el pie con `RNC ____________` y `____________` (tabla vacía) y `BALBU_TECH`; el `.borrador` guardó `salario_ofrecido=20000.00` y `salario=18000.00`. No hubo escrituras en la base.

**Pendiente de este plan:** cargar los datos reales de la empresa con los `UPDATE` de arriba (RNC, ciudad, dirección, representante y su cédula).
