# Módulo 44 — MIGRACION_ROLES

Script de migración, no de esquema: **no crea tablas, procedimientos, triggers ni
vistas**. Deja cualquier base existente en el set final de 7 roles y retira los
dos que el rediseño del 22/10/2026 absorbió.

Set final: `ADMIN`, `GERENTE`, `SUBGERENTE`, `RRHH`, `VENDEDOR`, `ALMACEN`,
`CONTABILIDAD`.

Retirados: `EMPLEADO` (renombrado a `VENDEDOR` en la base del trabajo) y
`CAJERO` (absorbido por `VENDEDOR`).

**Es usado por:** nadie desde la app. Lo corre `db/import.sh` como último módulo
y también se puede aplicar solo sobre una base ya poblada.

Fuente: `modulos/44- MIGRACION_ROLES.sql` · Base: `BALBU_TECH` · Revisado: 22/10/2026.

## Por qué existe

Ninguno de los dos módulos **retira un rol**: el `INSERT IGNORE INTO ROLES` del 3
suma nombres y nunca borra los viejos, y el 36 sí limpia (borra los permisos
paraguas con sus pares y reconstruye la matriz) pero no toca las filas de
`ROLES`. La fila del rol retirado queda huérfana del set final.

Consecuencia en una base vieja: `EMPLEADO` y `CAJERO` sobrevivían como roles
**fuera del set de 7**. Los permisos paraguas que el 36 borra
(`GESTIONAR_EMPLEADOS`, `GESTIONAR_CLIENTES`, `GESTIONAR_USUARIOS`,
`CONSULTAR_CLIENTES`) desaparecen de esos roles por el `ON DELETE CASCADE` de
`FK_ROL_PERMISO_PERMISO`, pero los que sobreviven por nombre
(`GESTIONAR_VENTAS`, `CONSULTAR_PRODUCTOS`, `REGISTRAR_ASISTENCIA`,
`SOLICITAR_PERMISO`, `GESTIONAR_METODOS_PAGO`, `CONSULTAR_REPORTES`) siguen
asignados. O sea: el usuario sigue entrando con un menú recortado y a medias, con
un rol que ya no forma parte del modelo y que nadie vuelve a mirar.

El repo no tenía forma de arreglarlo. Según el informe del 22/10/2026, la
migración se aplicó a mano en la base del trabajo con un script que quedó en
`backups/` (gitignored); en este repo no hay ningún script así versionado
(`backups/` solo tiene `pre_asist_v2_20261017_100847.sql`). Este módulo hace ese
trabajo y queda versionado.

## Qué hace, en orden

| Paso | Sentencia | Por qué ese orden |
|---|---|---|
| 1 | `INSERT IGNORE` de los 7 roles | `USUARIOS.ID_ROL` es `NOT NULL`: sin el rol destino, el paso 2 no tiene a dónde mover |
| 2 | `UPDATE USUARIOS` de `EMPLEADO`/`CAJERO` a `VENDEDOR` | `FK_USUARIO_ROL` es `RESTRICT`: con usuarios colgando, el rol no se puede borrar |
| 3 | `DELETE FROM ROL_PERMISO` de los dos roles | `FK_ROL_PERMISO_ROL` es `RESTRICT`: con pares colgando, el rol no se puede borrar |
| 4 | `DELETE FROM ROLES` de los dos roles | recién acá no queda nada que los referencie |
| 5 | `SELECT` de comprobación | tiene que devolver `Roles retirados que quedan: 0` y 7 filas |

Las dos FKs que apuntan a `ROLES` **no tienen `ON DELETE`**: si se invierte el
orden, el `DELETE` falla y la migración queda a medias. Por eso el script va
numerado en ese orden y no se reordena.

## Idempotencia

Se puede correr las veces que haga falta:

- En una base nueva (import desde cero) los pasos 2 a 4 no tocan ninguna fila:
  `EMPLEADO` y `CAJERO` no existen.
- Sobre una base ya migrada, el paso 2 no encuentra usuarios con esos roles y los
  pasos 3 y 4 no encuentran filas.
- Nunca duplica roles (`INSERT IGNORE` sobre `NOMBRE_ROL`, que es único) ni
  permisos.

## Qué NO hace

- **No toca roles personalizados** (`PRUEBA_*` del test, o cualquier rol creado a
  mano): solo actúa sobre los dos nombres retirados.
- **No reparte permisos**: la matriz es del módulo `36`, que corre antes. Los
  usuarios movidos a `VENDEDOR` heredan los 10 permisos de ese rol.
- **No borra empleados ni usuarios**: solo cambia el `ID_ROL` de los que estaban
  en los roles retirados.

## Verificación

```sql
SELECT NOMBRE_ROL FROM ROLES ORDER BY ID_ROL;                    -- 7 filas
SELECT COUNT(*) FROM ROLES WHERE NOMBRE_ROL IN ('EMPLEADO','CAJERO');  -- 0
SELECT R.NOMBRE_ROL, COUNT(*) FROM USUARIOS U JOIN ROLES R ON R.ID_ROL=U.ID_ROL
 GROUP BY R.NOMBRE_ROL;                                          -- sin EMPLEADO/CAJERO
```

Test automático: `db/test-migracion-roles.sh` (crea los dos roles retirados con un
usuario cada uno, corre el módulo dos veces y verifica el resultado).
