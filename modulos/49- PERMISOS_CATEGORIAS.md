# 49 - Permisos finos de Categorías

## Qué hace

Reemplaza el permiso paraguas `GESTIONAR_CATEGORIAS` por cuatro permisos
finos, con el mismo corte que Clientes y Proveedores:

| Permiso | Acción |
|---|---|
| `CATEGORIAS_VER` | Buscar |
| `CATEGORIAS_CREAR` | Agregar |
| `CATEGORIAS_EDITAR` | Actualizar |
| `CATEGORIAS_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Categorías del menú principal se
muestra con cualquiera de los cuatro, y cada opción del submenú pide el suyo.
`Volver` es siempre visible.

## Matriz que deja

| Rol | Permisos de Categorías |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `ALMACEN` | los 4 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **38 permisos** y **137 pares rol-permiso**
(ADMIN 38, GERENTE 32, SUBGERENTE 26, RRHH 12, VENDEDOR 10, ALMACEN 15,
CONTABILIDAD 4).

El catálogo pasa de 35 a 38: se va un permiso y entran cuatro. Cada uno de los
cuatro roles que tenía el paraguas gana tres pares (los cuatro finos menos el
viejo), así que el total pasa de 125 a 137.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_CATEGORIAS`; si el módulo corre
antes, el ítem Categorías desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/49- PERMISOS_CATEGORIAS.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los cuatro permisos
  finos aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de categorías, productos, marcas ni movimientos de inventario.

## Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `CATEGORIAS`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_CATEGORIAS`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).
