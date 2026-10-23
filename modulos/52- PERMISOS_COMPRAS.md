# 52 - Permisos finos de Compras

## Qué hace

Reemplaza el permiso paraguas `GESTIONAR_COMPRAS` por seis permisos finos, con
el mismo patrón que Clientes, Proveedores, Categorías, Marcas y Métodos de pago:

| Permiso | Acción |
|---|---|
| `COMPRAS_VER` | Ver compra con IVA |
| `COMPRAS_REGISTRAR` | Compra rápida (carrito) |
| `COMPRAS_PAGAR` | Pagar compra |
| `COMPRAS_CANCELAR` | Cancelar compra |
| `COMPRAS_DEVOLVER` | Devolución de compra |
| `COMPRAS_REPORTES` | Reporte por periodo y Precios por suplidor |

La app deja de usar el permiso viejo: el ítem Compras del menú principal se
muestra con cualquiera de los seis, y cada opción del submenú pide el suyo.
`Volver` es siempre visible.

## Matriz que deja

| Rol | Permisos de Compras |
|---|---|
| `ADMIN` | los 6 |
| `GERENTE` | los 6 |
| `SUBGERENTE` | los 6 |
| `ALMACEN` | los 6 |
| `RRHH` | ninguno |
| `VENDEDOR` | ninguno |
| `CONTABILIDAD` | ninguno |

Totales después de la migración: **49 permisos** y **181 pares rol-permiso**
(ADMIN 49, GERENTE 43, SUBGERENTE 37, RRHH 12, VENDEDOR 13, ALMACEN 23,
CONTABILIDAD 4).

El catálogo pasa de 44 a 49: se va un permiso y entran seis. Cada uno de los
cuatro roles que tenía el paraguas gana cinco pares (los seis finos menos el
viejo), así que el total pasa de 161 a 181.

## Orden de despliegue

1. Compilar y desplegar el binario nuevo.
2. Hacer backup de la base viva.
3. Correr este módulo.

El binario viejo sigue pidiendo `GESTIONAR_COMPRAS`; si el módulo corre antes,
el ítem Compras desaparece del menú hasta que se despliegue el binario nuevo.
No se pierden datos: solo se oculta el módulo.

## Cómo aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/52- PERMISOS_COMPRAS.sql"
```

Es idempotente: se puede correr dos veces sin duplicar pares.

## Qué preserva

- `ADMIN`, `GERENTE`, `SUBGERENTE` y `ALMACEN` reciben los seis permisos finos
  aunque el paraguas ya no exista (base nueva o reimportación del 36).
- `RRHH`, `VENDEDOR` y `CONTABILIDAD` siguen sin acceso al módulo.
- No toca datos de compras, pagos, devoluciones, inventario ni proveedores.
- Las altas rápidas de producto y suplidor siguen exigiendo
  `GESTIONAR_PRODUCTOS` y `PROVEEDORES_CREAR`: el permiso de Compras no las
  habilita por sí solo.

## Qué no hace

- No borra roles ni usuarios.
- No modifica las tablas `COMPRAS`, `DETALLE_COMPRA`, `PAGOS_COMPRA` ni
  `DEVOLUCION_COMPRA`.
- No crea procedimientos almacenados ni triggers.
- No toca los otros módulos del menú.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_COMPRAS`, el
  módulo le quita el paraguas y **no** le da los finos (solo el set final de
  roles los recibe).
