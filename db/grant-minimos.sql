-- ================================================================
-- BALBU_TECH - PRIVILEGIOS MINIMOS PARA LA APP (balbu_app)
-- ================================================================
-- (03/11/2026) La app tenia SELECT/INSERT/UPDATE/DELETE sobre todas las
-- tablas. Eso dejaba sin efecto cualquier control de permisos: con la
-- credencial del .env, cualquier cliente SQL podia cambiar un rol, leer
-- sueldos o borrar movimientos sin pasar por el menu ni por FN_TIENE_PERMISO.
--
-- Este archivo se ejecuta con root sobre UN esquema; el nombre llega como
-- __DB__ y lo sustituye db/aplicar-grants.sh.
--
-- (05/11/2026) El usuario de conexion llega como __HOST__ y lo sustituye el
-- mismo script, que recorre TODAS las cuentas 'balbu_app' del servidor. Antes
-- estaba fijo en '%': en una maquina fuera del contenedor la app entra como
-- 'balbu_app'@'localhost' y esa cuenta conservaba SELECT/INSERT/UPDATE/DELETE
-- sobre todo el esquema, o sea que el recorte no tenia efecto.
--
-- Matriz derivada del codigo (grep de sentencias directas en *.cpp):
--   - 16 tablas se leen directo; el resto pasa por SPs DEFINER (no necesitan
--     privilegios de tabla).
--   - Solo se escriben directo: CONTRATOS.RUTA_DOCUMENTO (subir contrato) y
--     USUARIOS.CONTRASENA (rehash PBKDF2 al iniciar sesion).
--   - Funciones que la app llama directo: FN_TASA_ITBIS, FN_TIENE_PERMISO.
-- ================================================================

REVOKE ALL PRIVILEGES ON `__DB__`.* FROM 'balbu_app'@'__HOST__';

-- (03/11/2026) El REVOKE de arriba NO limpia los grants por columna: quedan
-- pegados entre corridas y la app conservaba SELECT(CONTRASENA). Hay que
-- revocarlos a nivel de tabla antes de volver a otorgar.
REVOKE ALL PRIVILEGES ON `__DB__`.USUARIOS  FROM 'balbu_app'@'__HOST__';
REVOKE ALL PRIVILEGES ON `__DB__`.EMPLEADOS FROM 'balbu_app'@'__HOST__';
REVOKE ALL PRIVILEGES ON `__DB__`.CONTRATOS FROM 'balbu_app'@'__HOST__';

-- Solo se conserva EXECUTE: los SPs son DEFINER, asi que corren con los
-- privilegios del dueno y no necesitan DML para la app.
GRANT EXECUTE ON `__DB__`.* TO 'balbu_app'@'__HOST__';

-- Lecturas directas, tabla completa.
GRANT SELECT ON `__DB__`.TURNO_CAJA      TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.CLIENTES        TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.COMPRAS         TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.CONFIGURACION   TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.CATEGORIAS      TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.MARCAS          TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.METODOS_PAGO    TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.PROVEEDORES     TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.ROLES           TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.PERMISOS        TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.ROL_PERMISO     TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.VENTAS          TO 'balbu_app'@'__HOST__';
GRANT SELECT ON `__DB__`.DETALLES_VENTA  TO 'balbu_app'@'__HOST__';

-- EMPLEADOS: solo las columnas que el codigo lee. Queda fuera SALARIO,
-- asi la lista de sueldos no se puede volcar con un SELECT directo.
GRANT SELECT (ID_EMPLEADO, NOMBRE, CEDULA, CARGO, ESTADO)
  ON `__DB__`.EMPLEADOS TO 'balbu_app'@'__HOST__';

-- USUARIOS: (03/11/2026) la app ya no verifica la clave: lo hace
-- SP_LOGIN_AUTENTICAR. Por eso no lleva CONTRASENA ni CLAVE_SERVIDOR: un
-- volcado con la clave del .env no expone material para atacar offline.
GRANT SELECT (ID_USUARIO, ID_EMPLEADO, ID_ROL, USUARIO, ESTADO)
  ON `__DB__`.USUARIOS TO 'balbu_app'@'__HOST__';

-- CONTRATOS: el flujo de contratos pendientes lee estas columnas directo.
GRANT SELECT (ID_CONTRATO, ID_EMPLEADO, NOMBRE, CEDULA, CARGO, TELEFONO,
              EMAIL, FECHA_INICIO, FECHA_INGRESO, SALARIO, ESTADO)
  ON `__DB__`.CONTRATOS TO 'balbu_app'@'__HOST__';

-- Escrituras directas, acotadas a la columna que la app realmente toca.
GRANT UPDATE (RUTA_DOCUMENTO) ON `__DB__`.CONTRATOS TO 'balbu_app'@'__HOST__';
-- (03/11/2026) Ya no hay UPDATE sobre USUARIOS: el rehash y la migracion al
-- formato del servidor los hace SP_LOGIN_AUTENTICAR como DEFINER.

FLUSH PRIVILEGES;
