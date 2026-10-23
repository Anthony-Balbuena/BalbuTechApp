# 46 - Permisos finos de Proveedores

## Qué hace

Reemplaza el permiso paraguas `GESTIONAR_PROVEEDORES` por cuatro permisos
finos, con el mismo corte que Clientes:

| Permiso | Acción |
|---|---|
| `PROVEEDORES_VER` | Buscar y listar |
| `PROVEEDORES_CREAR` | Agregar |
| `PROVEEDORES_EDITAR` | Actualizar |
| `PROVEEDORES_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Proveedores del menú principal
se muestra con cualquiera de los cuatro, y cada opción del submenú pide el
suyo.

## Matriz que deja

| Rol | Permisos de Proveedores |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `ALMACEN` | los 4 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **34 permisos** y **122 pares rol-permiso**
(ADMIN 34, GERENTE 28, SUBGERENTE 22, RRHH 12, VENDEDOR 10, ALMACEN 12,
CONTABILIDAD 4).

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_PROVEEDORES`; si el módulo corre
antes, el ítem Proveedores desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/46- PERMISOS_PROVEEDORES.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- Cualquier rol personalizado que tuviera `GESTIONAR_PROVEEDORES` recibe los
  cuatro permisos finos antes de que se borre el paraguas.
- Los roles del set final (`ADMIN`, `GERENTE`, `SUBGERENTE`, `ALMACEN`)
  reciben los cuatro aunque el paraguas ya no exista.
- No toca datos de proveedores, compras ni productos.

## Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `PROVEEDORES`.
- No crea procedimientos almacenados.
