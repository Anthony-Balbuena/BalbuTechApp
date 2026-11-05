# Realizar en casa — pendientes al 05/11/2026

Estado de partida: T1, T2, recorte de privilegios, login en servidor (65) y
guardas de permiso en los SPs (66) están aplicados en TEST y en la viva. Lo que
sigue es lo que quedó abierto, ordenado por riesgo.

> **05/11/2026** — La base local del 3306 quedó al día: se aplicaron `63`, `64`,
> `65`, `66` y `62` en `BALBU_TECH` y `64`, `65` y `66` en `BALBU_TECH_TEST`,
> con backups en `backups/*_antes_62-66_casa_20261105_004038.sql`. La exigencia
> quedó prendida (`EXIGIR = 1` en 169 rutinas de la viva y 161 en TEST), así que
> el punto 1 de abajo es ahora la tarea que falta.
>
> **05/11/2026 (cierre del día)** — Se aplicó el módulo `67` en las dos bases:
> `SP_CAMBIAR_CLAVE_USUARIO` vuelve a funcionar con el login del `65` (guarda
> `CLAVE_SERVIDOR` con pepper, deja `CONTRASENA` en `NULL` y cierra las sesiones
> del usuario) y la app manda el derivado `pbkdf2$...` tanto al cambiar la clave
> como al dar de alta un usuario. Regresión: `db/test-cambio-clave.sh`.

## 1. Validar el mapeo de permisos contra la viva (lo primero)

Las guardas exigen en 161 procedimientos y el mapeo rutina → permiso salió de un
heurístico por nombre. En TEST pasó toda la batería, pero los flujos reales se
prueban usando la app.

Qué hacer: entrar y recorrer los menús que se usan de verdad (Ventas, Compras,
Caja, Inventario, Empleados, Garantías) y hacer una operación de escritura en
cada uno.

Si algo responde `SIN PERMISO PARA ESTA OPERACION`, buscar la rutina:

```sql
SELECT RUTINA, PERMISO, USUARIO, RESULTADO, FECHA
  FROM LOG_PERMISO_SP
 WHERE RESULTADO <> 'OK'
 ORDER BY ID_LOG DESC LIMIT 20;
```

Corregir el mapeo (no hace falta tocar código):

```sql
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'EL_PERMISO_CORRECTO'
 WHERE RUTINA = 'LA_RUTINA';
```

Si urge desbloquear una sola rutina sin cambiar el permiso:

```sql
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 0 WHERE RUTINA = 'LA_RUTINA';
```

Y si hiciera falta apagar todo el control sin redeploy:

```sql
UPDATE SECRETO_SISTEMA SET VALOR = '0' WHERE CLAVE = 'EXIGIR_PERMISO_SP';
```

## 2. Decidir `SP_CAMBIAR_CONTRASENA`

Es el único procedimiento sin permiso mapeado, a propósito. No tiene caller ni
mapeo: quedó muerto cuando la app pasó a `SP_CAMBIAR_CLAVE_USUARIO` (módulo
`67`). Hay que decidir si se borra del módulo `10` o si se conserva como
autoservicio; mientras exista, la decisión de permiso sigue abierta.

```sql
-- si es autoservicio: dejarlo sin exigencia es correcto
-- si NO lo es:
UPDATE PERMISO_POR_RUTINA
   SET PERMISO = 'USUARIOS_CLAVE', EXIGIR = 1
 WHERE RUTINA = 'SP_CAMBIAR_CONTRASENA';
```

## 3. `CONTRATOS.SALARIO` sigue legible

El flujo de contratos pendientes lee la tabla directo (`empleados.cpp:101`), así
que `balbu_app` conserva `SELECT (SALARIO)` ahí. Cerrarlo requiere un SP que
devuelva la lista de pendientes sin exponer el salario crudo, y sacar la columna
del grant en `db/grant-minimos.sql`.

## 4. `balbu_app` tiene grants sobre `BALBU_TECH_TEST` en producción

No hace falta ahí. Se quita cuando los tests dejen de correr contra la misma
instancia:

```sql
REVOKE ALL PRIVILEGES ON `BALBU_TECH_TEST`.* FROM 'balbu_app'@'%';
FLUSH PRIVILEGES;
```

## 5. El token dura 12 horas fijas

No se renueva por actividad: a las 12 horas hay que volver a entrar. Si molesta,
se alarga en `SP_LOGIN_AUTENTICAR` (`INTERVAL 12 HOUR`) o se agrega renovación en
`FN_USUARIO_SESION()`.

Relacionado: `SESIONES` se limpia de vencidos en cada login, pero
`LOG_PERMISO_SP` crece sin tope. Conviene sumar los dos a
`SP_LIMPIAR_LOGS_ANTIGUOS`.

## 6. Purga de `contratos/` del historial de git

Hay 4 archivos con datos de un contrato real que estuvieron versionados. Si el
repo nunca se compartió, es decisión propia; si se compartió, el dato ya salió.

```
git rm --cached contratos/*
git commit -m "chore: sacar contratos del control de versiones"
git filter-repo --path contratos/ --invert-paths   # reescribe el historial
```

## 7. CI mínimo

Hoy los tests corren a mano. El mínimo útil: `db/import.sh` sobre una base
efímera, `db/check-app-sps.sh`, `db/test-permisos-sp.sh`,
`db/test-menus-por-rol.sh`, `db/test-lockout.sh` y `db/test-login-servidor.sh`.

## 8. Backlog funcional que ya estaba en `PENDIENTES.md`

- Venta multi-línea atómica (P-4): si falla una línea a mitad, queda a medias.
- Validaciones P-3: 8 errores pintados en verde, la advertencia de precio que se
  descarta, y el monto de la liquidación que viene del cliente.

## 9. `mysql.proc`

Se le dio `SELECT ON mysql.proc` a `balbu_admin` para que el inyector de guardas
pueda leer los cuerpos de las rutinas en la viva. Es lectura de definiciones, no
de datos. Si se prefiere quitar, el inyector tendría que correr con root por
socket dentro del contenedor `db`.

## 10. Commit

Todo el trabajo del 03/11 está sin commitear. `git add -A` y commit único, como
quedó acordado. Recordar que `modulos/64`, `65` y `66`, los scripts de `db/` y la
nota de auditoría están sin trackear.

## Recordatorio operativo

Cada vez que se reimporte un módulo con `db/import.sh`, las guardas se reinyectan
solas al final. Si se importa un archivo suelto con `mariadb < modulos/xx.sql`,
la guarda de esas rutinas **se pierde** y hay que reponerla:

```
python3 db/injectar-guardas.py BALBU_TECH --aplicar
DB_NAME=BALBU_TECH bash db/check-app-sps.sh   # falla si falta cobertura
```
