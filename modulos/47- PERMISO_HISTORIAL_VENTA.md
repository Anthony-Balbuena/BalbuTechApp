# 47 - Permiso CONSULTAR_HISTORIAL_VENTA

## Qué hace

Separa el historial de venta del permiso general `CONSULTAR_REPORTES`. La
opción `Historial de venta` del submenú Ventas pasa a pedir
`CONSULTAR_HISTORIAL_VENTA`, así el vendedor conserva el historial aunque no
tenga reportes ni ganancias. `Garantías` no cambia: sigue con
`GESTIONAR_VENTAS`.

Con este cambio, `VENDEDOR` ve **10 opciones** en Ventas: las 7 de gestión,
`Historial de venta`, `Garantías` y `Volver`. Deja de ver `Reporte por rango`,
`Ganancias`, `Reporte por periodo`, `Ganancias por periodo` y
`Exportar datos para la web`.

## Matriz que deja

| Permiso | Roles |
|---|---|
| `CONSULTAR_HISTORIAL_VENTA` | ADMIN, GERENTE, SUBGERENTE, VENDEDOR |
| `CONSULTAR_REPORTES` | ADMIN, GERENTE, SUBGERENTE, RRHH, CONTABILIDAD (VENDEDOR ya no) |

Totales después de la migración: **35 permisos** y **125 pares rol-permiso**
(ADMIN 35, GERENTE 29, SUBGERENTE 23, RRHH 12, VENDEDOR 10, ALMACEN 12,
CONTABILIDAD 4).

`VENDEDOR` cambia un permiso por otro y sigue con 10; `ADMIN`, `GERENTE` y
`SUBGERENTE` suman uno cada uno. Por eso el total pasa de 122 a 125 pares.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `CONSULTAR_REPORTES` para el historial; si el
módulo corre antes, la opción desaparece del submenú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta una opción.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/47- PERMISO_HISTORIAL_VENTA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `VENDEDOR` quedan con el historial; los
  tres primeros también conservan `CONSULTAR_REPORTES`.
- `RRHH` y `CONTABILIDAD` no cambian: conservan `CONSULTAR_REPORTES`.
  `ALMACEN` no tiene ese permiso y tampoco lo necesita.
- No toca datos de ventas, pagos, caja ni garantías.

## Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas de ventas.
- No crea permisos de Garantías: esa opción sigue con `GESTIONAR_VENTAS`.
- No crea procedimientos almacenados.
