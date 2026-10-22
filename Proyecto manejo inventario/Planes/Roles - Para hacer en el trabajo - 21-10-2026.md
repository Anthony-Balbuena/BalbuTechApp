# Roles — Para hacer en el trabajo — 21/10/2026

> **PRIORIDAD BLOQUEANTE.** Sin reestructurar los roles no se puede seguir:
> los submenús y los permisos finos dependen de que este set quede cerrado.

Contexto: la base viva `BALBU_TECH` ya está sincronizada con los módulos
(SPs, triggers y columnas al día). Lo que falta es el **modelo de roles**.

---

## Estado de hoy (6 roles, 1 solo usuario)

| ID | Rol | Permisos | Usuarios |
|---|---|---|---|
| 1 | ADMIN | 18 (todos) | 1 |
| 2 | RRHH | 3 | 0 |
| 3 | EMPLEADO | 5 | 0 |
| 4 | GERENTE | 16 | 0 |
| 5 | CAJERO | 6 | 0 |
| 6 | ALMACEN | 7 | 0 |

```
RRHH      -> GESTIONAR_EMPLEADOS, GESTIONAR_CONTRATOS, CONSULTAR_REPORTES
EMPLEADO  -> GESTIONAR_VENTAS, REGISTRAR_ASISTENCIA, SOLICITAR_PERMISO,
             CONSULTAR_PRODUCTOS, CONSULTAR_CLIENTES
GERENTE   -> ADMIN menos GESTIONAR_ROLES y GESTIONAR_USUARIOS (16)
CAJERO    -> GESTIONAR_VENTAS, GESTIONAR_CLIENTES, GESTIONAR_METODOS_PAGO,
             CONSULTAR_CLIENTES, CONSULTAR_PRODUCTOS, CONSULTAR_REPORTES
ALMACEN   -> GESTIONAR_PRODUCTOS, GESTIONAR_INVENTARIO, GESTIONAR_COMPRAS,
             GESTIONAR_PROVEEDORES, GESTIONAR_CATEGORIAS, GESTIONAR_MARCAS,
             CONSULTAR_PRODUCTOS
```

### Por qué EMPLEADO y CAJERO sobran

```
Comparten (3):  GESTIONAR_VENTAS, CONSULTAR_PRODUCTOS, CONSULTAR_CLIENTES
Solo EMPLEADO:  REGISTRAR_ASISTENCIA, SOLICITAR_PERMISO
Solo CAJERO:    GESTIONAR_CLIENTES, GESTIONAR_METODOS_PAGO, CONSULTAR_REPORTES
```

---

## Set objetivo

| Rol | Origen | Estado |
|---|---|---|
| ADMIN | queda igual (18 permisos) | ✅ definido |
| RRHH | queda igual (3) + `SOLICITAR_PERMISO` | ✅ casi |
| GERENTE | queda igual (16) | ✅ definido |
| SUBGERENTE | **nuevo** | ⛔ falta definir permisos |
| *(renombre de EMPLEADO)* | absorbe los 3 permisos de CAJERO; CAJERO se borra | ⛔ falta el nombre |
| CONTABILIDAD | **nuevo**, solo consulta | ⛔ falta decidir si entra |
| *(renombre de ALMACEN)* | queda con sus 7 permisos de stock | ⛔ falta el nombre |

### Nombres candidatos (decidir en el trabajo)

- **Ex EMPLEADO** (hoy hace de vendedor + asistencia + pedidos): `OPERARIO`,
  `VENDEDOR`, `AUXILIAR`, `EMPLEADO BASE`.
- **Ex ALMACEN** (stock, compras, proveedores, categorías, marcas): `DEPOSITO`,
  `LOGISTICA`, `ALMACENERO`, `INVENTARIO`.

Ojo: el ex EMPLEADO **no** puede llamarse igual que el ex ALMACEN; los dos
cubren trabajo distinto y el menú se arma por permisos, no por nombre.

---

## Lo que hay que saber antes de tocar la base

1. **Renombrar es seguro.** No hay ni una comparación de nombre de rol en el
   código (los `"EMPLEADO"` que aparecen son encabezados de columnas). La FK
   `FK_ROL_PERMISO_ROL` es `ON UPDATE CASCADE`, así que los permisos siguen al
   rol solos; `USUARIOS` apunta por `ID_ROL` y no se entera.
2. **Borrar NO está en la app.** El módulo 3 no tiene SP de borrado y el menú
   Roles no ofrece "Eliminar". Hay que hacerlo por SQL, y la FK es `RESTRICT`:
   primero las filas de `ROL_PERMISO`, después el rol.
3. **Dos semillas resucitan los nombres viejos** si se reimporta o se siembra:
   - `db/seed-admin.sh:22` → crea `ADMIN`, `RRHH`, `EMPLEADO`.
   - `modulos/3- ROLES.sql:20` → `INSERT IGNORE INTO ROLES` con los 6 nombres.
   - `modulos/36- PERMISOS_ROLES.sql` → la matriz, con las filas de `GERENTE`,
     `CAJERO` y `ALMACEN`.
   **Las tres hay que actualizarlas o el próximo import deshace el cambio.**
4. **Solo ADMIN y EMPLEADO tienen `SOLICITAR_PERMISO`.** Si no se replica,
   RRHH, GERENTE, SUBGERENTE y CONTABILIDAD no van a poder pedir sus propias
   vacaciones ni permisos.

---

## SQL (probar antes en `BALBU_TECH_TEST`)

Con backup previo de `BALBU_TECH`.

```sql
-- 1. Renombrar (los permisos siguen solos por ON UPDATE CASCADE)
UPDATE ROLES SET NOMBRE_ROL = 'OPERARIO' WHERE NOMBRE_ROL = 'EMPLEADO';
UPDATE ROLES SET NOMBRE_ROL = 'DEPOSITO' WHERE NOMBRE_ROL = 'ALMACEN';   -- nombre a definir

-- 2. Pasarle a OPERARIO los 3 permisos que solo tenia CAJERO
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'OPERARIO', ID_PERMISO FROM ROL_PERMISO WHERE ROL_NOMBRE = 'CAJERO'
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- 3. Borrar CAJERO (orden obligatorio por RESTRICT)
DELETE FROM ROL_PERMISO WHERE ROL_NOMBRE = 'CAJERO';
DELETE FROM ROLES WHERE NOMBRE_ROL = 'CAJERO';

-- 4. SUBGERENTE: copia de GERENTE, ajustar la lista de exclusion
INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES ('SUBGERENTE');
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'SUBGERENTE', ID_PERMISO FROM ROL_PERMISO WHERE ROL_NOMBRE = 'GERENTE'
  AND ID_PERMISO NOT IN (SELECT ID_PERMISO FROM PERMISOS
                         WHERE NOMBRE_PERMISO IN ('GESTIONAR_ROLES'))
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- 5. CONTABILIDAD: solo consulta
INSERT IGNORE INTO ROLES (NOMBRE_ROL) VALUES ('CONTABILIDAD');
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT 'CONTABILIDAD', ID_PERMISO FROM PERMISOS
WHERE NOMBRE_PERMISO IN ('CONSULTAR_REPORTES', 'CONSULTAR_CLIENTES', 'CONSULTAR_PRODUCTOS')
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;

-- 6. Todos piden lo suyo
INSERT INTO ROL_PERMISO (ROL_NOMBRE, ID_PERMISO)
SELECT r.NOMBRE_ROL, p.ID_PERMISO FROM ROLES r JOIN PERMISOS p
  ON p.NOMBRE_PERMISO = 'SOLICITAR_PERMISO'
ON DUPLICATE KEY UPDATE ROL_NOMBRE = ROL_NOMBRE;
```

Después, actualizar `modulos/3- ROLES.sql:20` y `modulos/36- PERMISOS_ROLES.sql`
con los nombres nuevos, y `db/seed-admin.sh:22`.

---

## Verificación

Hoy hay **1 solo usuario** (el ADMIN). Sin un usuario por rol no se puede ver
qué menú aparece, así que después del cambio:

1. Crear un usuario de prueba por rol (ADMIN, RRHH, GERENTE, SUBGERENTE,
   OPERARIO, CONTABILIDAD y el ex ALMACEN).
2. Loguearse con cada uno y anotar qué opciones muestra el menú principal.
3. Comparar contra los permisos de la tabla de arriba: lo que no coincide es un
   hueco de la matriz, no un bug de la pantalla.

---

## Checklist del día

- [ ] Definir el nombre del ex EMPLEADO
- [ ] Definir el nombre del ex ALMACEN
- [ ] Definir permisos de SUBGERENTE (¿GERENTE menos qué?)
- [ ] Decidir si CONTABILIDAD entra y con qué permisos
- [ ] Backup de `BALBU_TECH`
- [ ] Correr el SQL en `BALBU_TECH_TEST` primero
- [ ] Aplicar en `BALBU_TECH`
- [ ] Actualizar `3- ROLES.sql`, `36- PERMISOS_ROLES.sql` y `seed-admin.sh`
- [ ] Crear un usuario por rol y verificar los menús
- [ ] Volver a correr el import y confirmar que **no** reaparecen los roles viejos

---

## Lo que viene después (no hacer hoy)

Con los roles cerrados, el siguiente paso es que **los 13 submenús se armen por
permiso**, igual que el menú principal: 118 opciones, despacho por id en vez de
`switch` por número. Va en fases, con test de menú por rol en cada una.
