# 45 - Permiso CONSULTAR_ASISTENCIA

## Qué hace

Separa los reportes de asistencia del permiso general `CONSULTAR_REPORTES` y
habilita el fichaje a todos los roles. La asistencia deja de depender del
módulo Empleados: pasa a un ítem propio del menú principal.

## Matriz que deja

| Permiso | Roles |
|---|---|
| `REGISTRAR_ASISTENCIA` | ADMIN, GERENTE, SUBGERENTE, RRHH, VENDEDOR, ALMACEN, CONTABILIDAD |
| `CONSULTAR_ASISTENCIA` | ADMIN, GERENTE, SUBGERENTE, RRHH |
| `JUSTIFICAR_ASISTENCIA` | ADMIN, GERENTE, RRHH, SUBGERENTE |
| `EMPLEADOS_VER` | ADMIN, GERENTE, SUBGERENTE, RRHH |

VENDEDOR no recibe `CONSULTAR_ASISTENCIA`: el cajero puede fichar y ver su
propia asistencia, pero no la de todos. Conserva `CONSULTAR_REPORTES` y todos
los reportes de venta.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH_TEST < "modulos/45- PERMISO_CONSULTAR_ASISTENCIA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué no hace

- No borra permisos ni pares rol-permiso.
- No toca datos de empleados, contratos ni asistencia.
- No crea procedimientos almacenados.
