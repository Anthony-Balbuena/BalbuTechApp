# 56 - Auditoría de cambios de usuarios

## Qué arregla

`TRG_AUDITORIA_USUARIOS` anotaba los cambios de rol y de estado, pero no
sabía **quién** los hizo. También faltaba el cambio de nombre de usuario.

| Antes | Ahora |
|---|---|
| `ID_USUARIO_ADMIN` siempre `NULL` | el id del usuario logueado |
| `CAMBIO_USUARIO` nunca se generaba | se registra con valor anterior y nuevo |
| la vista no mostraba al admin | muestra `ID_USUARIO_ADMIN` y `USUARIO_ADMIN` |

## Cómo se sabe quién lo hizo

La app deja el id en la variable de conexión `@ID_USUARIO_ACTUAL` al iniciar
sesión (`login.cpp`) y la limpia al cerrar sesión (`sesion.cpp`). El trigger
la lee.

Si la variable no está, o el usuario ya no existe, el trigger guarda `NULL`
y **no falla**: un problema del log nunca debe tumbar el cambio de usuario.

## Qué registra

| Acción | Cuándo |
|---|---|
| `CAMBIO_ROL` | cambia `ID_ROL` |
| `CAMBIO_ESTADO` | cambia `ESTADO` |
| `CAMBIO_USUARIO` | cambia `USUARIO` |

Si un mismo `UPDATE` cambia rol y estado, deja dos filas: son dos cambios
distintos. Las comparaciones usan `<=>` para tratar `NULL` sin sorpresas.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/56- AUDITORIA_USUARIOS.sql"
```

Es idempotente y no toca datos. Requiere el binario nuevo para que
`@ID_USUARIO_ACTUAL` llegue seteada; con el binario viejo el log sigue
funcionando, solo que con admin `NULL`.

## Cómo verificar

```sql
SET @ID_USUARIO_ACTUAL = 1;
UPDATE USUARIOS SET ESTADO = IF(ESTADO = 'ACTIVO', 'INACTIVO', 'ACTIVO')
 WHERE ID_USUARIO = 1;
SELECT ACCION, VALOR_ANTERIOR, VALOR_NUEVO, ID_USUARIO_ADMIN
  FROM LOG_USUARIOS
 WHERE ID_USUARIO = 1
 ORDER BY ID_LOG DESC LIMIT 1;
```

El `ID_USUARIO_ADMIN` tiene que ser `1`. El test automático está en
`db/test-auditoria-usuarios.sh`.

## Orden de despliegue

1. Correr este módulo.
2. Compilar y desplegar el binario nuevo.

Al revés también funciona: el binario nuevo setea la variable y el trigger
viejo la ignora hasta que se corra el módulo.
