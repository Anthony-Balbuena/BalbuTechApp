# 58 - Permisos finos de Inventario

## Qué hace

Reemplaza el permiso paraguas `GESTIONAR_INVENTARIO` por tres permisos finos,
con el mismo patrón que Clientes, Proveedores, Categorías, Marcas, Métodos de
pago y Compras:

| Permiso | Acción |
|---|---|
| `INVENTARIO_VER` | Movimientos (kardex) |
| `INVENTARIO_AJUSTAR` | Ajuste de stock |
| `INVENTARIO_COSTO` | Ajustar p.compra |

La app deja de usar el permiso viejo: el ítem Inventario del menú principal se
muestra con cualquiera de los tres, y cada opción del submenú pide el suyo.
`Volver` es siempre visible. Es el **último módulo con permiso paraguas de la
Tanda B**.

## Matriz que deja

| Rol | Permisos de Inventario |
|---|---|
| `ADMIN` | los 3 |
| `GERENTE` | los 3 |
| `SUBGERENTE` | los 3 |
| `ALMACEN` | los 3 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **54 permisos** y **201 pares rol-permiso**
(ADMIN 54, GERENTE 48, SUBGERENTE 42, RRHH 12, VENDEDOR 16, ALMACEN 25,
CONTABILIDAD 4).

> (26/10/2026) VENDEDOR bajó a 12 permisos y el total a 197 por el ajuste de
> Clientes y Métodos de pago. La matriz vigente está en `36- PERMISOS_ROLES.md`.

El catálogo pasa de 52 a 54: se va un permiso y entran tres. Cada uno de los
cuatro roles que tenía el paraguas gana dos pares (los tres finos menos el
viejo), así que el total pasa de 193 a 201.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_INVENTARIO`; si el módulo corre
antes, el ítem Inventario desaparece del menú hasta que se despliegue el binario
nuevo. No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/58- PERMISOS_INVENTARIO.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los tres permisos finos
  aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de productos, stock, movimientos ni compras.
- Las compras siguen moviendo stock por diseño: ese efecto no depende de
  `INVENTARIO_AJUSTAR`.

## Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas de inventario ni los procedimientos de stock.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_INVENTARIO`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).
