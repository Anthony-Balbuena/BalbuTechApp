# 53 - Permisos finos de Caja

## Qué hace

Separa el módulo Caja de `GESTIONAR_VENTAS` con tres permisos propios:

| Permiso | Acción |
|---|---|
| `CONSULTAR_CAJA` | Ver el estado del turno abierto |
| `ABRIR_CAJA` | Abrir el turno de la caja |
| `CERRAR_CAJA` | Cerrar el turno y registrar el cuadre |

El ítem Caja del menú principal se muestra con cualquiera de los tres, y cada
opción del submenú pide el suyo. `Volver` es siempre visible.
`GESTIONAR_VENTAS` sigue existiendo y sigue mandando en el módulo Ventas.

> El cierre sigue siendo directo: el vendedor abre, consulta y cierra su turno,
> sin confirmación de un segundo actor. El flujo con firma del cuadre queda
> para una fase posterior.

## Matriz que deja

| Rol | Permisos de Caja |
|---|---|
| `ADMIN` | los 3 |
| `GERENTE` | los 3 |
| `SUBGERENTE` | los 3 |
| `VENDEDOR` | los 3 |
| `RRHH` | ninguno |
| `ALMACEN` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **52 permisos** y **193 pares rol-permiso**
(ADMIN 52, GERENTE 46, SUBGERENTE 40, RRHH 12, VENDEDOR 16, ALMACEN 23,
CONTABILIDAD 4).

El catálogo pasa de 49 a 52: entran tres permisos y cada uno de los cuatro
roles que ya veía Caja gana tres pares, así que el total pasa de 181 a 193.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo pide `GESTIONAR_VENTAS` para el ítem Caja; si el módulo corre
antes, el ítem desaparece del menú hasta que se despliegue el binario nuevo.
No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/53- PERMISOS_CAJA.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- Los cuatro roles del set que ya veían Caja reciben los tres permisos finos
  aunque el ítem ya no mire `GESTIONAR_VENTAS`.
- Los roles personalizados que hoy tengan `GESTIONAR_VENTAS` también reciben
  los tres, para que no pierdan el módulo.
- No toca turnos, pagos ni cuadres existentes.

## Qué no hace

- No borra roles, usuarios ni permisos.
- No modifica `TURNO_CAJA` ni sus procedimientos.
- No agrega estados de cierre ni confirmación por un segundo actor.
- No toca los otros módulos del menú.
