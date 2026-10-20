# Contrato de trabajo — requisitos legales (RD)

Investigación del 19/10/2026, con fuentes primarias. Sirve para decidir el flujo de contratos de la app.

## Qué exige la ley (Ley 16-92, Código de Trabajo)

| Artículo | Qué dice | Impacto en la app |
|---|---|---|
| **24.1** | El contrato escrito debe enunciar nombres y apellidos, **nacionalidad**, edad, sexo, estado civil, domicilio y residencia de los contratantes, **y las menciones legales de sus cédulas personales de identidad** | La cédula es un **elemento obligatorio** del contrato, no un dato opcional. Faltan: nacionalidad, edad, sexo y estado civil. |
| **22** | Se hacen **cuatro originales**: uno para cada parte y **dos que el empleador remite al Departamento de Trabajo dentro de los 3 días** de la fecha | La app genera 1 HTML. No produce los 4 originales ni la comunicación de remisión. |
| **20** | Si el contrato consta por escrito, sus modificaciones van por escrito | Un cambio de salario/cargo debería generar una enmienda, no editar el contrato. |
| **25 / 33 / 34** | Tipos: indefinido, por cierto tiempo, o por obra/servicio. Se presume **indefinido**; los de cierto tiempo u obra **deben ser escritos** y solo en los 3 casos del art. 33 | El ENUM `TEMPORAL`/`FIJO` cubre dos de los tres tipos; falta "por obra o servicio". |
| **70** | Al terminar, el empleador da certificado con: **fecha de entrada, fecha de salida, clase de trabajo y salario** | No existe "certificado de trabajo" en la app. |
| **76-77** | Desahucio: aviso previo por escrito y participación al Departamento de Trabajo en 48 h | No hay registro de preaviso. |
| **91** | Despido: se comunica al trabajador **y al Departamento de Trabajo en 48 h**, con la causa | No existe. |

## Qué pide el Ministerio de Trabajo para registrar el contrato

Servicio oficial: *Registro de Contrato de Trabajo Nacional* (arts. 22, 23 y 24). Presencial, gratuito, dentro de los 3 días de la firma.

Datos exigidos:
- RNC y nombre de la empresa
- **RNL** (Registro Nacional Laboral) — la app no lo tiene
- Nombres y apellidos del trabajador
- **Nacionalidad** — falta
- Domicilio del trabajador
- **Cédula del trabajador** — es la clave con la que se identifica a la persona
- Cargo u ocupación
- Turno de horario
- **Lugar donde prestará servicio** — falta
- Salario mensual en pesos dominicanos
- **Fecha de inicio del contrato**
- Tipo de contrato
- **Provincia y municipio** — falta (hoy solo `CIUDAD`)
- Copia de la cédula del trabajador

## Conclusión para el diseño

1. **La cédula es la identificación real de la persona.** La app nunca debería pedir `ID_EMPLEADO` ni `ID_CONTRATO` al usuario. Hoy lo hace en la opción 14 (ver contratos) y 15 (finalizar).
2. **El ID interno sigue siendo necesario** como FK (`CONTRATOS.ID_EMPLEADO`): una cédula se puede corregir por error de tipeo, y el contrato debe conservar su snapshot histórico. Lo que se elimina es pedírselo a la persona, no la columna.
3. **`FECHA_INICIO` debe ser la fecha de inicio pactada**, no `CURDATE()` al subir. Hoy `SP_SUBIR_CONTRATO` guarda `CURDATE()` aunque el usuario tipea `P_FECHA_INGRESO`. Eso contradice el art. 24 y el dato que pide el MT.
4. Faltan campos legales: nacionalidad, edad, sexo, estado civil, RNL, lugar de prestación, provincia/municipio.

## Fuentes

- Ley 16-92, Código de Trabajo (texto completo): https://dpej.rae.es/eli/do/l/1992/05/29/16
- Ministerio de Trabajo — Registro de Contrato de Trabajo Nacional: https://mt.gob.do/servicios/registro-de-contrato-de-trabajo/
- PDF del servicio (requerimientos): https://mt.gob.do/wp-content/uploads/2023/05/Registro-de-Contrato-de-Trabajo.pdf
