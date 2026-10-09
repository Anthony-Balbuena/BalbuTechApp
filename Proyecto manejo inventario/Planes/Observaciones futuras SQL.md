# Observaciones a futuro (SQL) — 09/10/2026

Notas que no son bugs hoy pero hay que tener presentes.

## Consumo desde C++ (fase pendiente)

- **`SP_CIERRE_CAJA` devuelve 3 result sets** (resumen, por estado, por método).
  `Recogermensaje()` solo lee el primero: cuando se consuma desde la app hay
  que iterar resultados (`nextResultSet`-style), no basta `executeQuery` simple.

## Estilo del repo (no tocar)

- **Versiones viejas comentadas** (`-- CREATE PROCEDURE/TRIGGER ...` en 19.6,
  23, 24, 32): es el estilo intencional del autor (conserva el cuerpo anterior
  como referencia). Inofensivo para el import; no borrar.

## Cobertura verificada 09/10/2026

- FKs completas donde aplican (maestros y bitácoras sin FK es lo correcto);
  toda columna FK tiene índice.
- ENUMs consistentes por dominio (43 columnas).
- Sin `CALL`s colgados en `.sql` ni en C++ (`check-app-sps.sh`: 0 faltantes).
- Import: 0 errores — 59 tablas / 124 SPs / 72 triggers.
