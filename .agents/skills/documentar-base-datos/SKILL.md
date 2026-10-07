---
name: Documentar Base de Datos
description: Documentar los módulos SQL de BalbuTechApp (BALBU_TECH). Elige entre bloques de comentarios dentro del .sql, documentación Markdown detallada, o ambos.
---

# Documentar Base de Datos

## Paso 0 — Elegir el estilo (obligatorio antes de escribir)

- Comentarios **dentro** del `.sql` → leer `references/estilo-comentarios-sql.md`
- **Documento** Markdown aparte → leer `references/documentacion-markdown.md`
- Si el usuario no aclara, preguntar. No asumir: los dos estilos son incompatibles entre sí.

## Reglas de oro

1. Leer el archivo completo primero. Inventariar tablas, SP, triggers, funciones y vistas antes de escribir nada.
2. Documentar SOLO los objetos presentes. Si un tipo de objeto no existe en el archivo, se salta. Si una sección está vacía, se deja intacta: no se inventa nada.
3. El SQL operativo **nunca** se modifica: solo se agregan comentarios.
4. Mantener el motor InnoDB, las claves primarias, foráneas, índices y restricciones existentes.
5. Limpiar comentarios viejos o basura solo dentro del bloque que se reescribe; no tocar el resto del archivo.

## Estructura de los archivos del proyecto

- `modulos/NN- NOMBRE.sql` → los 36 módulos de la base, cargados en orden numérico.
- `Contextos.opencodetxt/contexto tabla X.txt` → registro de sesión por módulo (opcional).
- La base se llama `BALBU_TECH` (pruebas en `BALBU_TECH_TEST`).

## Al terminar (verificación obligatoria)

- `git diff <archivo>` → debe mostrar **solo** líneas agregadas `/* ... */`. Cero líneas de SQL eliminadas o modificadas.
- Verificar que los delimitadores `/*` y `*/` quedan balanceados.
- Conteo: objetos `CREATE` == bloques de descripción.
- Recompilar no hace falta: el archivo es SQL puro, se carga en MariaDB.

## Registro de sesión

Opcional. Solo si el usuario lo pide: `references/registro-sesion.md`.
