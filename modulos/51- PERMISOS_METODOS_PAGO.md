# 51 - Permisos finos de Métodos de pago

## Qué hace

Reemplaza el permiso paraguas `GESTIONAR_METODOS_PAGO` por cuatro permisos
finos, con el mismo corte que Clientes, Proveedores, Categorías y Marcas:

| Permiso | Acción |
|---|---|
| `METODOS_PAGO_VER` | Buscar y Listar |
| `METODOS_PAGO_CREAR` | Agregar |
| `METODOS_PAGO_EDITAR` | Actualizar |
| `METODOS_PAGO_ESTADO` | Activar/Desactivar |

La app deja de usar el permiso viejo: el ítem Métodos de pago del menú
principal se muestra con cualquiera de los cuatro, y cada opción del submenú
pide el suyo. `Volver` es siempre visible.

## Matriz que deja

| Rol | Permisos de Métodos de pago |
|---|---|
| `ADMIN` | los 4 |
| `GERENTE` | los 4 |
| `SUBGERENTE` | los 4 |
| `VENDEDOR` | solo `METODOS_PAGO_VER` |
| `RRHH` | ninguno |
| `ALMACEN` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales en su primera aplicación (23/10/2026): **44 permisos** y **161 pares
rol-permiso** (ADMIN 44, GERENTE 38, SUBGERENTE 32, RRHH 12, VENDEDOR 13,
ALMACEN 18, CONTABILIDAD 4).

> (26/10/2026) VENDEDOR ya no recibe los cuatro: conserva solo
> `METODOS_PAGO_VER` y el `DELETE` de abajo le quita los tres de gestión. La
> matriz vigente completa está en `36- PERMISOS_ROLES.md` (54 permisos y 197
> pares).

El catálogo pasa de 41 a 44: se va un permiso y entran cuatro. Cada uno de los
cuatro roles que tenía el paraguas gana tres pares (los cuatro finos menos el
viejo), así que el total pasa de 149 a 161.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_METODOS_PAGO`; si el módulo corre
antes, el ítem Métodos de pago desaparece del menú hasta que se despliegue el
binario nuevo. No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/51- PERMISOS_METODOS_PAGO.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- `ADMIN`, `GERENTE` y `SUBGERENTE` reciben los cuatro permisos finos aunque el
  paraguas ya no exista (base nueva o reimportación del 36).
- (26/10/2026) `VENDEDOR` recibe solo `METODOS_PAGO_VER`: consulta los métodos
  existentes y no los mantiene.
- `RRHH`, `ALMACEN` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de métodos de pago, ventas, pagos ni cierres de caja.

## Qué no hace

- No borra roles ni usuarios.
- No modifica la tabla `METODOS_PAGO`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_METODOS_PAGO`,
  el módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).
