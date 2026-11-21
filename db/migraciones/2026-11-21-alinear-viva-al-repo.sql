-- ============================================================
-- 2026-11-21 - ALINEAR LA BASE VIVA CON LO QUE PRODUCE EL REPO
-- ============================================================
-- Medido con db/verificar-esquema.sh (9 secciones) contra un import desde cero:
-- la viva diferia en 4 secciones. Este archivo cierra las 5 diferencias con
-- efecto y el orden de columnas de 8 tablas. Al terminar, la viva queda
-- IDENTICA a lo que produce `bash db/import.sh` sobre una base nueva.
--
-- Diferencias con efecto real:
--   1. PRODUCTOS.P_COMPRA          la viva no tenia DEFAULT, el repo 0.00
--   2. LOG_ACCESOS.USUARIO_INTENTADO  la viva tenia DEFAULT '', el repo ninguno
--   3. PRODUCTOS.FK_PRODUCTO_PROVEEDOR  la viva ON UPDATE CASCADE, el repo RESTRICT
--   4. LOG_USUARIOS                a la viva le faltaban las 2 FK a USUARIOS
--   5. DETALLES_VENTA              la FK se llamaba FK_DETALLE_PRODUCTO
--                                  (nombre que ademas usa DETALLE_COMPRA en el
--                                  modulo 19 para otra tabla)
--
-- Este archivo NO lo ejecuta db/import.sh (solo globbea modulos/*.sql).
-- Se aplica a mano sobre una base que ya existe:
--
--   set -a; . ./.env; set +a
--   mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" --database=BALBU_TECH \
--     < db/migraciones/2026-11-21-alinear-viva-al-repo.sql
--
-- Es idempotente: reordenar dos veces deja lo mismo, y cada FK se dropea con
-- IF EXISTS antes de crear, asi que una corrida cortada se puede repetir. En
-- una base creada por los modulos actuales no cambia nada.
--
-- Por que reordenar es seguro (medido, no supuesto):
--   - el codigo C++ no tiene NINGUN `SELECT *`      -> nadie lee por posicion
--   - no hay NINGUN `INSERT INTO x VALUES (...)`    -> nadie inserta por posicion
--   - las tablas afectadas tienen entre 0 y 60 filas
--   - las columnas que se mueven NO son generadas; SUBTOTAL (la unica generada
--     de esta lista) no se toca, solo se corre de lugar PORCENTAJE_DESCUENTO.
--
-- Las definiciones de abajo salen de SHOW CREATE TABLE de un import desde cero.
-- El CHECK se repite SOLO en las tres columnas que lo tienen a nivel de columna
-- (PORCENTAJE_DESCUENTO, MONTO_RECIBIDO, P_COMPRA): un MODIFY COLUMN que lo omite
-- BORRA ese CHECK, porque en MariaDB el CHECK de columna viaja con la definicion
-- de la columna. Medido: sin el CHECK se perdian 3 de los 63 constraints.
-- Las demas columnas movidas no tienen CHECK propio y no se les agrega nada.
--
-- Los indices: en MariaDB, DROP FOREIGN KEY NO borra el indice que usaba la FK.
-- Si se dropea y se vuelve a crear la FK, MariaDB REUSA ese indice y queda con
-- el nombre viejo. Por eso hay que dropear el indice viejo a mano antes de
-- volver a crear la constraint, o el nombre nunca cambia.
-- ============================================================

-- 1. DETALLES_VENTA: PORCENTAJE_DESCUENTO va antes de SUBTOTAL.
ALTER TABLE DETALLES_VENTA
    MODIFY COLUMN PORCENTAJE_DESCUENTO decimal(5,2) NOT NULL DEFAULT 0.00
        CHECK (`PORCENTAJE_DESCUENTO` between 0 and 100)
        AFTER PRECIO_UNITARIO;

-- 2. DEVOLUCIONES: ESTADO va al final.
ALTER TABLE DEVOLUCIONES
    MODIFY COLUMN ESTADO enum('PENDIENTE','APROBADA','RECHAZADA','REEMBOLSADA')
        NOT NULL DEFAULT 'PENDIENTE' AFTER MONTO_GANANCIA_REEMBOLSADA;

-- 3. DEVOLUCION_COMPRA: ESTADO va al final.
ALTER TABLE DEVOLUCION_COMPRA
    MODIFY COLUMN ESTADO enum('PENDIENTE','PROCESADA','RECHAZADA')
        NOT NULL DEFAULT 'PENDIENTE' AFTER MONTO_ITBIS_DEVUELTO;

-- 4. LOG_ACCESOS: USUARIO_INTENTADO va tercero Y pierde el DEFAULT '' (el repo
--    no lo declara; todos los INSERT del codigo pasan la columna explicita).
ALTER TABLE LOG_ACCESOS
    MODIFY COLUMN USUARIO_INTENTADO varchar(50) NOT NULL AFTER ID_USUARIO;

-- 5. PAGOS: ID_EMPLEADO antes de MONTO; MONTO_RECIBIDO antes de FECHA.
ALTER TABLE PAGOS
    MODIFY COLUMN ID_EMPLEADO int(11) NOT NULL AFTER ID_METODO_PAGO,
    MODIFY COLUMN MONTO_RECIBIDO decimal(10,2) DEFAULT NULL
        CHECK (`MONTO_RECIBIDO` >= `MONTO`) AFTER MONTO;

-- 6. PAGOS_COMPRA: mismo criterio, con TIPO y OBSERVACION en el medio.
ALTER TABLE PAGOS_COMPRA
    MODIFY COLUMN ID_EMPLEADO int(11) NOT NULL AFTER ID_METODO_PAGO,
    MODIFY COLUMN TIPO enum('PAGO','NOTA_CREDITO') NOT NULL DEFAULT 'PAGO' AFTER ID_EMPLEADO,
    MODIFY COLUMN OBSERVACION varchar(100) DEFAULT NULL AFTER MONTO;

-- 7. PRODUCTOS: P_COMPRA va quinto Y gana el DEFAULT 0.00 del repo.
ALTER TABLE PRODUCTOS
    MODIFY COLUMN P_COMPRA decimal(10,2) NOT NULL DEFAULT 0.00
        CHECK (`P_COMPRA` >= 0) AFTER PRECIO;

-- 8. VACACIONES_EMPLEADOS: ESTADO antes de FECHA_REGISTRO.
ALTER TABLE VACACIONES_EMPLEADOS
    MODIFY COLUMN ESTADO enum('PENDIENTE','APROBADO','RECHAZADO')
        NOT NULL DEFAULT 'PENDIENTE' AFTER FECHA_FIN;

-- 9. PRODUCTOS.FK_PRODUCTO_PROVEEDOR: ON UPDATE CASCADE -> RESTRICT.
--    El modulo 9 no declara ON UPDATE ni ON DELETE, o sea RESTRICT en los dos.
--    La viva tenia ademas un IX_PRODUCTOS_PROVEEDOR explicito que el repo no
--    crea (ahi el indice lo aporta la propia FK); se dropea para que quede igual.
ALTER TABLE PRODUCTOS DROP FOREIGN KEY IF EXISTS FK_PRODUCTO_PROVEEDOR;
ALTER TABLE PRODUCTOS DROP INDEX IF EXISTS IX_PRODUCTOS_PROVEEDOR;
ALTER TABLE PRODUCTOS ADD CONSTRAINT FK_PRODUCTO_PROVEEDOR
    FOREIGN KEY (ID_PROVEEDOR) REFERENCES PROVEEDORES (ID_PROVEEDOR);

-- 10. DETALLES_VENTA: la FK toma el nombre del modulo 21. Hay que soltar el
--     indice viejo: si no, la constraint nueva lo reusa y el nombre no cambia.
ALTER TABLE DETALLES_VENTA DROP FOREIGN KEY IF EXISTS FK_DETALLE_PRODUCTO;
ALTER TABLE DETALLES_VENTA DROP FOREIGN KEY IF EXISTS FK_DETALLE_VENTA_PRODUCTO;
ALTER TABLE DETALLES_VENTA DROP INDEX IF EXISTS FK_DETALLE_PRODUCTO;
ALTER TABLE DETALLES_VENTA ADD CONSTRAINT FK_DETALLE_VENTA_PRODUCTO
    FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTOS (ID_PRODUCTO);

-- 11. LOG_USUARIOS: las dos FK a USUARIOS que el modulo 29 declara.
--     Medido antes de escribir: 0 filas huerfanas en ID_USUARIO y en
--     ID_USUARIO_ADMIN, y los tipos coinciden con USUARIOS.ID_USUARIO (int(11)).
--     Sin ON DELETE: el modulo no declara ninguno, o sea RESTRICT.
ALTER TABLE LOG_USUARIOS DROP FOREIGN KEY IF EXISTS FK_LOG_USUARIOS_USUARIO;
ALTER TABLE LOG_USUARIOS DROP FOREIGN KEY IF EXISTS FK_LOG_USUARIOS_ADMIN;
ALTER TABLE LOG_USUARIOS ADD CONSTRAINT FK_LOG_USUARIOS_USUARIO
    FOREIGN KEY (ID_USUARIO) REFERENCES USUARIOS (ID_USUARIO);
ALTER TABLE LOG_USUARIOS ADD CONSTRAINT FK_LOG_USUARIOS_ADMIN
    FOREIGN KEY (ID_USUARIO_ADMIN) REFERENCES USUARIOS (ID_USUARIO);

SELECT 'Viva alineada con el repo: 8 reordenamientos + 5 diferencias con efecto.' AS RESULTADO;
