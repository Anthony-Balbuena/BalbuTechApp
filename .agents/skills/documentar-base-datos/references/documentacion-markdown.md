# Estilo: documentación Markdown aparte del `.sql`

Salida **completa** en formato Markdown para la base de datos `BALBU_TECH`.
Este documento NO se escribe dentro del `.sql`: se genera como archivo `.md`
nuevo (o se entrega como respuesta).

Fuente original: `.vscode/prompts/Documentar.prompt.md` (que quedó cortado en la
línea 4; aquí se completa).

---

## Rol

Documentador técnico experto en bases de datos SQL y arquitectura de software.
Leer el archivo SQL indicado y generar su **Documentación Técnica en formato
Markdown**.

## Reglas estrictas

1. **Estructura clara.** Organizar la salida usando títulos Markdown (`#`, `##`, `###`).
2. **Tablas detalladas.** Para cada tabla encontrada, crear una tabla en Markdown
   que desglose columna por columna indicando:

   | Columna | Tipo | Restricciones | Descripción |
   |---|---|---|---|
   | `ID_VENTA` | `INT` | PK, AUTO_INCREMENT | ... |
   | `ID_CLIENTE` | `INT` | FK → CLIENTES, NOT NULL | ... |

   - **Nombre** de la columna
   - **Tipo de dato**
   - **Restricciones**: PK, FK, Unique, Not Null, Defaults
   - **Breve descripción** de su propósito
3. **Inventario completo.** Documentar todos los objetos presentes en el archivo
   en orden: Tablas, Procedimientos Almacenados (SPs), Triggers (TR), Funciones
   (TF) y Vistas (VIEWS), especificando sus parámetros o comportamientos clave.
   Si un tipo de objeto no existe en el archivo, se omite: no se inventa nada.
4. **Tono profesional y técnico.** Explicar claramente las restricciones del
   motor (InnoDB) y las reglas de negocio que apliquen en el módulo.

---

## Estructura sugerida de salida

```markdown
# Módulo NN — NOMBRE

Resumen de una o dos frases.

## Tablas
### TABLA_X
Descripción de la tabla.
| Columna | Tipo | Restricciones | Descripción |
|---|---|---|---|
...

## Procedimientos almacenados
### SP_NOMBRE(P_PARAM)
Qué hace, qué valida, qué devuelve.

## Triggers
### TR_NOMBRE
Cuándo se dispara y qué efecto tiene.

## Funciones
### FN_NOMBRE
Qué calcula y con qué firma.

## Vistas
### VW_NOMBRE
Qué consulta representa.

## Reglas de negocio
Restricciones del motor y reglas de negocio del módulo.
```

---

## Verificación

- Todos los objetos `CREATE` del archivo aparecen en la documentación.
- Ninguna columna del `.sql` falta en las tablas Markdown.
- Toda FK apunta a una tabla que exista (o se anota como pendiente).
- El `.sql` **no** se modificó en esta salida: es documentación aparte.
