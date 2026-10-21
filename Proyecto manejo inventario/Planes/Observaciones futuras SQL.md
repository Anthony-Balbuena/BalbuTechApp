# Observaciones a futuro (SQL) — 09/10/2026

Notas que no son bugs hoy pero hay que tener presentes.

## Consumo desde C++ (HECHO 16/10: `cierreCajaUI` consume los 3)

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

## Consolidar los ALTER dentro del CREATE TABLE (pendiente, para el final)

Hoy el esquema se arma en dos pasos: `CREATE TABLE` y después una tanda de
`ALTER TABLE` (25 en 11 módulos) para agregar columnas, defaults, NOT NULL,
índices o FK. Ejemplo claro: `PRODUCTOS.ID_PROVEEDOR` (módulo 9) ya está
definido en el `CREATE TABLE` como `INT NOT NULL` + FK; igual quedaron 4
`ALTER` de la migración (agregar con `DEFAULT 1`, forzar `NOT NULL DEFAULT 1`,
`DROP DEFAULT` y otro `MODIFY`). En ese caso no hay que reescribir el `CREATE`:
se borran los 4 `ALTER` y la tabla queda igual.

Regla: cada módulo muestra la tabla final en un solo `CREATE TABLE`; los
`ALTER` de migración se borran. Si un `ALTER` agrega algo que el `CREATE` no
tiene, primero se pasa al `CREATE` y después se borra el `ALTER`.

Cuando termine el trabajo actual: dejar cada `CREATE TABLE` con la definición
final (columnas, defaults, constraints, índices y FK) y borrar los `ALTER` que
solo existen para llegar a ese estado. Si hace falta migrar una base existente,
ese `ALTER` va en un script de migración aparte, no en el módulo de esquema.

Ojo: no todos los 25 se pueden borrar sin más; hay que revisar uno por uno
(algunos crean FK o índices que deben pasar al `CREATE`).

## Documentación de BD: índice general (hecho el 20/10/2026)

(20/10/2026) Los módulos se documentan uno por uno en `modulos/NN- NOMBRE.md`
(piloto: `42- CONTRATOS.md`). La puerta de entrada quedó escrita:
**`modulos/00- INDICE.md`**, con el mapa de la BD — los 45 módulos, totales de
objetos, orden de import, objetos que viven en otro archivo, las fórmulas
repetidas, qué módulos no usa la app y un "dónde buscar qué".
