# Registro de sesión (opcional)

**Opcional**: solo se genera si el usuario lo pide.

Archivo: `Contextos.opencodetxt/contexto tabla <nombre>.txt`
(los 37 archivos existentes siguen esta plantilla).

---

## Plantilla

```
CONTEXTO DE DOCUMENTACION - TABLA <NOMBRE>
Proyecto: BalbuTechApp (base de datos BALBU_TECH)
Fecha: <DD/MM/AAAA>
Archivo trabajado: modulos/<NN>- <NOMBRE>.sql

================================================================================
1. OBJETIVO DE LA SESION
================================================================================
Qué se hizo hoy, en 3-6 líneas. Incluir el estilo acordado si aplica.

================================================================================
2. OBJETOS DOCUMENTADOS EN <NN>- <NOMBRE>.sql (bloques)
================================================================================
TABLA (n)
  - <TABLA> ................. descripción corta de 1-2 líneas

INDICES (n)
  - IX_XXX .................. para qué sirve

PROCEDIMIENTOS ALMACENADOS (n)
  - SP_XXX .................. qué hace (continuar indentado si es largo)

TRIGGERS (n)
  - TR_XXX .................. qué hace

VISTA (n)
  - VW_XXX .................. qué muestra

FUNCIONES (n)
  - (0 / vacío → se anota "no hay nada que documentar", no se inventa)

================================================================================
3. DECISIONES TOMADAS EN ESTA SESION
================================================================================
- Qué se eligió y por qué. Qué se dejó intacto.

================================================================================
4. PENDIENTES PARA LAS SIGUIENTES FASES
================================================================================
- Qué falta en el repo (archivos, índices, SP sin documentar, etc.)

================================================================================
5. COMO SE VERIFICA EL TRABAJO
================================================================================
- git diff "modulos/<NN>- <NOMBRE>.sql" -> solo lineas agregadas con /* ... */,
  cero lineas de SQL eliminadas o modificadas.
- /* y */ balanceados.
- Recompilar no es necesario: es SQL puro, se carga en MariaDB.
```

---

## Reglas

- Sección vacía = se anota que está vacía. **No inventar objetos.**
- Si en una sesión posterior se cambia algo del archivo, agregar una sección
  `6. ACTUALIZACION <FECHA> - <TITULO>` en lugar de reescribir las anteriores.
  Así el archivo queda como bitácora acumulativa (así están los 37 existentes).
- Los números de sección existentes se conservan; las actualizaciones nuevas
  van al final.
