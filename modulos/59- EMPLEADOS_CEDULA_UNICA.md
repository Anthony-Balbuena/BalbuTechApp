# 59 - Cedula unica en Empleados

## Que hace

Agrega el indice unico `UQ_EMPLEADOS_CEDULA` sobre `EMPLEADOS.CEDULA`.

## Por que

El comentario del modulo 8 decia que la cedula era obligatoria y unica, y
la app confiaba en eso, pero el esquema solo tenia `UNIQUE` en `TELEFONO`
y `EMAIL`. Dos empleados con la misma cedula entraban sin error y despues
rompian la busqueda de contratos, que asume una cedula = una persona.

## Como aplicarlo

```bash
mysql -h127.0.0.1 -uroot -p BALBU_TECH < "modulos/59- EMPLEADOS_CEDULA_UNICA.sql"
```

Es idempotente: se puede correr dos veces.

## Que preserva

- No toca datos, empleados, contratos ni usuarios.
- Si hay duplicados, el modulo no aplica y los lista para limpiarlos.

## Que no hace

- No fusiona empleados duplicados.
- No cambia los SPs de alta o edicion; el error de la base se propaga.
