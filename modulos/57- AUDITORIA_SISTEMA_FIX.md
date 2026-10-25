# 57 - Auditoría del sistema: SPs y triggers

## Qué arregla

Completa el módulo 6 en bases que ya existen. No toca la tabla ni los índices.

| Problema | Arreglo |
|---|---|
| `DROP` de los SP no coincidía con el `CREATE` | se dropean los dos nombres (con y sin `6_`) |
| `DATE(FECHA_HORA)` anulaba `IX_AUDITORIA_FECHA` | rango sobre la columna, con `LIMIT 500` |
| `USUARIO_SISTEMA` guardaba `balbu_app` | usa `@ID_USUARIO_ACTUAL` y cae a `USER()` |
| no había auditoría de `DELETE` | `TR_AUDIT_PROVEEDORES_DELETE` |
| la limpieza no decía cuántas filas borró | cuenta con `ROW_COUNT()` |

## El usuario real

La app deja el id del usuario logueado en `@ID_USUARIO_ACTUAL` (lo hace
`login.cpp`, módulo 56). El trigger busca su nombre:

```sql
IFNULL((SELECT USUARIO FROM USUARIOS WHERE ID_USUARIO = @ID_USUARIO_ACTUAL), USER())
```

Si no hay variable (por ejemplo, un cambio por consola), queda el usuario de
MySQL como antes. No rompe nada.

## El rango de fechas

Antes:

```sql
DATE(FECHA_HORA) BETWEEN P_FECHA_INICIO AND P_FECHA_FIN
```

La función sobre la columna impide usar el índice. Ahora:

```sql
FECHA_HORA >= P_FECHA_INICIO
AND FECHA_HORA < DATE_ADD(P_FECHA_FIN, INTERVAL 1 DAY)
```

Incluye todo el día final y el índice se usa.

## Qué NO toca

- `AUDITORIA_SISTEMA` no tiene FK: la auditoría sobrevive al borrado.
- Los triggers de `CLIENTES` (módulo 7) y `PRODUCTOS` (módulo 9) siguen con
  `CURRENT_USER()`/`USER()`. Se pueden migrar después con el mismo patrón.
- No se auditan `DELETE` de otras tablas: solo proveedores.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/57- AUDITORIA_SISTEMA_FIX.sql"
```

Es idempotente.

## Cómo verificar

```sql
-- No deben quedar versiones sin prefijo
SELECT ROUTINE_NAME FROM information_schema.ROUTINES
 WHERE ROUTINE_SCHEMA = 'BALBU_TECH'
   AND ROUTINE_NAME IN ('SP_LISTAR_AUDITORIA_GENERAL', 'SP_CONSULTAR_HISTORIAL_REGISTRO');

-- Los tres triggers de proveedores
SELECT TRIGGER_NAME FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'BALBU_TECH'
   AND EVENT_OBJECT_TABLE = 'PROVEEDORES'
 ORDER BY EVENT_MANIPULATION;
```

El test automático está en `db/test-auditoria-sistema.sh`.
