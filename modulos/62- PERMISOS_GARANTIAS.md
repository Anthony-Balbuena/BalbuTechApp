# 62 - Permisos finos de Garantias

## Que hace

Saca Garantias de `GESTIONAR_VENTAS` y le da cuatro permisos propios, con el
mismo patron que Clientes, Proveedores, Inventario y demas:

| Permiso | Accion |
|---|---|
| `GARANTIAS_REGISTRAR` | Registrar una garantia a mano |
| `GARANTIAS_RECLAMAR` | Abrir un reclamo sobre una garantia vigente |
| `GARANTIAS_FINALIZAR` | Cerrar un reclamo (decision de Gerencia) |
| `GARANTIAS_CONSULTAR` | Ver garantias y reclamos |

El item "Garantias" del submenu de Ventas se muestra con cualquiera de los
cuatro, y cada opcion adentro pide el suyo. `Volver` es siempre visible.

La diferencia clave: **el vendedor atiende y registra, pero no cierra
reclamos**. `VENDEDOR` conserva registrar, reclamar y consultar.

## Matriz que deja

| Rol | Registrar | Reclamar | Finalizar | Consultar |
|---|:-:|:-:|:-:|:-:|
| `ADMIN` | si | si | si | si |
| `GERENTE` | si | si | si | si |
| `SUBGERENTE` | si | si | si | si |
| `VENDEDOR` | si | si | **no** | si |
| `CONTABILIDAD` | no | no | no | si |
| `RRHH` | no | no | no | no |
| `ALMACEN` | no | no | no | no |

Totales despues de la migracion: **58 permisos** y **213 pares rol-permiso**
(ADMIN 58, GERENTE 52, SUBGERENTE 46, RRHH 12, VENDEDOR 15, ALMACEN 25,
CONTABILIDAD 5). Antes eran 54 permisos y 197 pares.

## Por que

- `GESTIONAR_VENTAS` es el paraguas de nueve acciones de Ventas. Colgar
  Garantias de el obliga a dar todo el modulo de ventas a quien solo tiene
  que consultar una garantia.
- Contabilidad necesita ver garantias y reclamos para costos, pero no
  registrar ni decidir.
- Cerrar un reclamo es una decision con costo (cambio, devolucion,
  reembolso). El que atiende al cliente no deberia ser el que autoriza.

## Orden de despliegue

1. Correr `63- GARANTIAS_FLUJO.sql`.
2. Compilar y desplegar el binario nuevo.
3. Correr este modulo.

El binario viejo abre Garantias con `GESTIONAR_VENTAS`; si este modulo corre
antes, el item desaparece del menu hasta desplegar el binario nuevo. No se
pierden datos: solo se oculta el modulo.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/62- PERMISOS_GARANTIAS.sql"
```

Es idempotente: los permisos usan `ON DUPLICATE KEY UPDATE` y los pares
tambien, asi que correrlo dos veces no duplica nada.

## Que preserva

- `GESTIONAR_VENTAS` no se borra ni se le quitan pares: lo siguen usando las
  otras nueve acciones de Ventas.
- Los roles que no estan en la matriz no reciben nada.
- No toca datos de ventas, garantias ni reclamos.
- No cambia los otros modulos del menu.

## Que no hace

- No borra roles ni usuarios.
- No migra roles personalizados: si alguno tuviera `GESTIONAR_VENTAS` y
  esperaba ver Garantias, deja de verla y no recibe los permisos finos.
- No crea procedimientos ni triggers: eso es el modulo 63.

## Detalle de la app

`roles.cpp` agrega los cuatro permisos al item "Ventas" del menu principal.
Sin eso, `CONTABILIDAD` tendria `GARANTIAS_CONSULTAR` y no podria llegar a
usarlo: el modulo se abriria solo para quien tiene `GESTIONAR_VENTAS`.

## Verificacion

Aplicado en `BALBU_TECH_TEST` el 30/10/2026, dos veces seguidas sin error:

- Matriz verificada: ADMIN 4, GERENTE 4, SUBGERENTE 4, VENDEDOR 3,
  CONTABILIDAD 1.
- Catalogo en 58 permisos y 213 pares.
- `GESTIONAR_VENTAS` sigue en ADMIN, GERENTE, SUBGERENTE y VENDEDOR.
- `test-menus-por-rol.sh`: el rol sintetico con solo `GESTIONAR_VENTAS` deja
  de ver Garantias (8 opciones en Ventas), y el submenu de Garantias muestra
  5 opciones para ADMIN, 4 para VENDEDOR (sin "Finalizar reclamo") y 2 para
  CONTABILIDAD.
- `test-migracion-roles.sh`: VENDEDOR pasa de 12 a 15 permisos.
