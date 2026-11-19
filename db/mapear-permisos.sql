-- ================================================================
-- MAPEO RUTINA -> PERMISO
-- ================================================================
-- (03/11/2026) Llena PERMISO_POR_RUTINA para todos los procedimientos del
-- esquema. EXIGIR se respeta si ya estaba en 1: este script solo propone el
-- permiso, nunca prende la exigencia.
--
-- El mapeo es heuristico por nombre; las areas ya verificadas se corrigen
-- despues con un UPDATE puntual. Una rutina sin regla queda en NULL, que en
-- modo auditoria aparece como SIN_MAPEO y con exigencia cortaria la llamada.
-- ================================================================

INSERT INTO PERMISO_POR_RUTINA (RUTINA, PERMISO, EXIGIR)
SELECT R.ROUTINE_NAME,
       CASE
           -- Usuarios
           WHEN R.ROUTINE_NAME LIKE '%USUARIO%' AND R.ROUTINE_NAME LIKE '%INSERT%'  THEN 'USUARIOS_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%USUARIO%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'USUARIOS_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%USUARIO%' AND R.ROUTINE_NAME LIKE '%TOGGLE%'  THEN 'USUARIOS_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%USUARIO%' AND R.ROUTINE_NAME LIKE '%CLAVE%'   THEN 'USUARIOS_CLAVE'
           WHEN R.ROUTINE_NAME LIKE '%USUARIO%'                                     THEN 'USUARIOS_VER'

           -- Roles y permisos
           WHEN R.ROUTINE_NAME LIKE '%ASIGNAR_PERMISO%' OR R.ROUTINE_NAME LIKE '%QUITAR_PERMISO%' THEN 'GESTIONAR_ROLES'
           WHEN R.ROUTINE_NAME LIKE '%ROL%'                                         THEN 'GESTIONAR_ROLES'

           -- Empleados (incluye permisos y vacaciones del empleado)
           -- (18/11/2026) Bonos del empleado: modulo 14, pantalla nueva. Va
           -- antes que las reglas de Empleados para que ningun LIKE generico
           -- se lo quede.
           WHEN R.ROUTINE_NAME LIKE '%BONO%'                                        THEN 'GESTIONAR_BONOS_EMPLEADO'
           WHEN R.ROUTINE_NAME LIKE '%VACACION%' AND R.ROUTINE_NAME LIKE '%SOLICITAR%' THEN 'SOLICITAR_PERMISO'
           WHEN R.ROUTINE_NAME LIKE '%VACACION%'                                    THEN 'GESTIONAR_VACACIONES_EMPLEADO'
           WHEN R.ROUTINE_NAME LIKE '%PERMISO%' AND R.ROUTINE_NAME LIKE '%SOLICITAR%' THEN 'SOLICITAR_PERMISO'
           WHEN R.ROUTINE_NAME LIKE '%CONTRATO%'                                    THEN 'GESTIONAR_CONTRATOS'
           WHEN R.ROUTINE_NAME LIKE '%EMPLEADO%' AND R.ROUTINE_NAME LIKE '%INSERT%'  THEN 'EMPLEADOS_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%EMPLEADO%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'EMPLEADOS_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%EMPLEADO%' AND (R.ROUTINE_NAME LIKE '%DESPEDIR%' OR R.ROUTINE_NAME LIKE '%REACTIVAR%') THEN 'EMPLEADOS_BAJA'
           WHEN R.ROUTINE_NAME LIKE '%EMPLEADO%'                                    THEN 'EMPLEADOS_VER'

           -- Asistencia
           WHEN R.ROUTINE_NAME LIKE '%ASISTENCIA%' AND (R.ROUTINE_NAME LIKE '%JUSTIFICAR%' OR R.ROUTINE_NAME LIKE '%BLOQUEAR%') THEN 'JUSTIFICAR_ASISTENCIA'
           WHEN R.ROUTINE_NAME LIKE '%ASISTENCIA%' AND R.ROUTINE_NAME LIKE '%RESUMEN%' THEN 'CONSULTAR_ASISTENCIA'
           WHEN R.ROUTINE_NAME LIKE '%ASISTENCIA%'                                  THEN 'REGISTRAR_ASISTENCIA'

           -- Clientes, proveedores, categorias, marcas, metodos de pago
           WHEN R.ROUTINE_NAME LIKE '%CLIENTE%' AND R.ROUTINE_NAME LIKE '%INSERT%'   THEN 'CLIENTES_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%CLIENTE%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'CLIENTES_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%CLIENTE%' AND R.ROUTINE_NAME LIKE '%TOGGLE%'   THEN 'CLIENTES_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%CLIENTE%'                                     THEN 'CLIENTES_VER'
           WHEN R.ROUTINE_NAME LIKE '%PROVEEDOR%' AND R.ROUTINE_NAME LIKE '%INSERT%' THEN 'PROVEEDORES_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%PROVEEDOR%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'PROVEEDORES_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%PROVEEDOR%' AND R.ROUTINE_NAME LIKE '%TOGGLE%' THEN 'PROVEEDORES_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%PROVEEDOR%'                                   THEN 'PROVEEDORES_VER'
           WHEN R.ROUTINE_NAME LIKE '%CATEGORIA%' AND R.ROUTINE_NAME LIKE '%INSERT%' THEN 'CATEGORIAS_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%CATEGORIA%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'CATEGORIAS_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%CATEGORIA%' AND R.ROUTINE_NAME LIKE '%TOGGLE%' THEN 'CATEGORIAS_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%CATEGORIA%'                                   THEN 'CATEGORIAS_VER'
           WHEN R.ROUTINE_NAME LIKE '%MARCA%' AND R.ROUTINE_NAME LIKE '%INSERT%'     THEN 'MARCAS_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%MARCA%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'MARCAS_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%MARCA%' AND R.ROUTINE_NAME LIKE '%TOGGLE%'     THEN 'MARCAS_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%MARCA%'                                       THEN 'MARCAS_VER'
           WHEN R.ROUTINE_NAME LIKE '%METODO%PAGO%' AND R.ROUTINE_NAME LIKE '%INSERT%' THEN 'METODOS_PAGO_CREAR'
           WHEN R.ROUTINE_NAME LIKE '%METODO%PAGO%' AND R.ROUTINE_NAME LIKE '%ACTUALIZAR%' THEN 'METODOS_PAGO_EDITAR'
           WHEN R.ROUTINE_NAME LIKE '%METODO%PAGO%' AND R.ROUTINE_NAME LIKE '%TOGGLE%' THEN 'METODOS_PAGO_ESTADO'
           WHEN R.ROUTINE_NAME LIKE '%METODO%PAGO%'                                 THEN 'METODOS_PAGO_VER'

           -- Compras
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND (R.ROUTINE_NAME LIKE '%PAGO%' OR R.ROUTINE_NAME LIKE '%PAGAR%') THEN 'COMPRAS_PAGAR'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND R.ROUTINE_NAME LIKE '%CANCELAR%'  THEN 'COMPRAS_CANCELAR'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND R.ROUTINE_NAME LIKE '%DEVOLUCION%' THEN 'COMPRAS_DEVOLVER'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND R.ROUTINE_NAME LIKE '%REPORTE%'   THEN 'COMPRAS_REPORTES'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND R.ROUTINE_NAME LIKE '%PRECIO%'    THEN 'COMPRAS_REPORTES'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%' AND (R.ROUTINE_NAME LIKE '%INSERT%' OR R.ROUTINE_NAME LIKE '%INICIAR%' OR R.ROUTINE_NAME LIKE '%DETALLE%' OR R.ROUTINE_NAME LIKE '%REGISTRAR%') THEN 'COMPRAS_REGISTRAR'
           WHEN R.ROUTINE_NAME LIKE '%COMPRA%'                                      THEN 'COMPRAS_VER'

           -- Caja
           WHEN R.ROUTINE_NAME LIKE '%TURNO%' AND R.ROUTINE_NAME LIKE '%ABRIR%'      THEN 'ABRIR_CAJA'
           WHEN R.ROUTINE_NAME LIKE '%TURNO%' AND R.ROUTINE_NAME LIKE '%CERRAR%'     THEN 'CERRAR_CAJA'
           WHEN R.ROUTINE_NAME LIKE '%TURNO%' OR R.ROUTINE_NAME LIKE '%CAJA%'        THEN 'CONSULTAR_CAJA'

           -- Ventas y garantias
           WHEN R.ROUTINE_NAME LIKE '%GARANTIA%' OR R.ROUTINE_NAME LIKE '%RECLAMO%'  THEN 'GESTIONAR_VENTAS'
           WHEN R.ROUTINE_NAME LIKE '%VENTA%' AND R.ROUTINE_NAME LIKE '%HISTORIAL%'  THEN 'CONSULTAR_HISTORIAL_VENTA'
           WHEN R.ROUTINE_NAME LIKE '%VENTA%'                                       THEN 'GESTIONAR_VENTAS'

           -- Inventario y productos
           WHEN R.ROUTINE_NAME LIKE '%COSTO%'                                       THEN 'INVENTARIO_COSTO'
           WHEN R.ROUTINE_NAME LIKE '%KARDEX%' OR R.ROUTINE_NAME LIKE '%INVENTARIO%' THEN 'INVENTARIO_VER'
           WHEN R.ROUTINE_NAME LIKE '%PRODUCTO%' AND (R.ROUTINE_NAME LIKE '%INSERT%' OR R.ROUTINE_NAME LIKE '%ACTUALIZAR%' OR R.ROUTINE_NAME LIKE '%TOGGLE%' OR R.ROUTINE_NAME LIKE '%ESTADO%') THEN 'GESTIONAR_PRODUCTOS'
           WHEN R.ROUTINE_NAME LIKE '%PRODUCTO%'                                    THEN 'CONSULTAR_PRODUCTOS'

           -- Reportes
           WHEN R.ROUTINE_NAME LIKE '%REPORTE%' OR R.ROUTINE_NAME LIKE '%GANANCIA%'  THEN 'CONSULTAR_REPORTES'

           ELSE NULL
       END AS PERMISO,
       0
  FROM information_schema.ROUTINES R
 WHERE R.ROUTINE_SCHEMA = DATABASE()
   AND R.ROUTINE_TYPE = 'PROCEDURE'
   AND R.ROUTINE_NAME NOT IN (
       'SP_EXIGIR_PERMISO', 'SP_LOGIN_PARAMETROS', 'SP_LOGIN_AUTENTICAR',
       'SP_CERRAR_SESION_SERVIDOR', 'SP_REGISTRAR_ACCESO', 'SP_ESTADO_BLOQUEO_LOGIN',
       -- (15/11/2026) Helper interno del movimiento de stock: no lleva guarda
       -- propia, la llevan las puertas que lo llaman. Misma lista que
       -- db/injectar-guardas.py y db/check-app-sps.sh.
       'SP_MOVER_STOCK'
   )
ON DUPLICATE KEY UPDATE PERMISO = VALUES(PERMISO);

-- Correcciones puntuales del heurístico: nombres que no siguen el patrón del
-- área o que quedaban sin mapeo. Sin esto quedan en SIN_MAPEO y con exigencia
-- cortarían llamadas legítimas.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_VENTAS'
 WHERE RUTINA IN ('SP_MARCAR_GARANTIAS_VENCIDAS', 'SP_REGISTRAR_LIQUIDACION',
                  'SP_REGISTRAR_DEVOLUCION', 'SP_DEVOLUCION_PENDIENTE_POR_DETALLE');
-- (15/11/2026) SP_REGISTRAR_AVANCE_REPARACION salio de este paraguas: lo tenia
-- GESTIONAR_VENTAS, que VENDEDOR tiene, asi que un vendedor podia llamar el
-- avance de reparacion - justo el SP que mueve el stock de repuestos. Ahora va
-- con GARANTIAS_AVANZAR, abajo con el resto de garantias.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'COMPRAS_PAGAR'
 WHERE RUTINA IN ('24_SP_REGISTRAR_PAGO', 'SP_ANULAR_PAGO');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'COMPRAS_DEVOLVER'
 WHERE RUTINA IN ('25_SP_PROCESAR_DEVOLUCION', '26_SP_RECHAZAR_DEVOLUCION');
-- (15/11/2026) 11_SP_REGISTRAR_SALIDA salio del proyecto (item 12c de
-- PENDIENTES.md): lo reemplazo el fichaje del 66. La app no la llamaba.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'REGISTRAR_ASISTENCIA'
 WHERE RUTINA = '11_SP_REGISTRAR_ENTRADA';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'EMPLEADOS_EDITAR'
 WHERE RUTINA = 'SP_ELIMINAR_BONO';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'JUSTIFICAR_ASISTENCIA'
 WHERE RUTINA = '11_SP_BLOQUEAR_EDICION_ANTIGUA';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_PERMISOS_EMPLEADO'
 WHERE RUTINA IN ('SP_GESTIONAR_PERMISO', 'SP_LISTAR_PERMISOS_PENDIENTES');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'EMPLEADOS_EDITAR'
 WHERE RUTINA = 'SP_AUMENTO_POR_CARGO';
-- (18/11/2026) Bonos del empleado (modulo 14): dejan EMPLEADOS_EDITAR y pasan a
-- su propio permiso. Es plata de un empleado, y la pantalla nueva se abre con
-- GESTIONAR_BONOS_EMPLEADO: si la rutina exigiera otro permiso, el rol que llega
-- a la pantalla (RRHH, por ejemplo) recibiria SIN_PERMISO al llamarla.
-- SP_LISTAR_BONOS ya no existe (lo reemplazo el par paginado): su fila se borra
-- unas lineas abajo, como las demas rutinas retiradas.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_BONOS_EMPLEADO'
 WHERE RUTINA IN ('SP_REGISTRAR_BONO', 'SP_ACTUALIZAR_BONO', 'SP_ANULAR_BONO',
                  'SP_PAGAR_BONO', 'SP_LISTAR_BONOS_PAGINADO', 'SP_CONTAR_BONOS');
DELETE FROM PERMISO_POR_RUTINA WHERE RUTINA = 'SP_LISTAR_BONOS';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'EMPLEADOS_VER'
 WHERE RUTINA = 'SP_ANIVERSARIOS_MES';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_ROLES'
 WHERE RUTINA IN ('SP_LIMPIAR_AUDITORIA', 'SP_LIMPIAR_LOGS_ANTIGUOS',
                  'SP_REPORTAR_ACCESOS');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_REPORTES'
 WHERE RUTINA IN ('6_SP_LISTAR_AUDITORIA_GENERAL', '6_SP_CONSULTAR_HISTORIAL_REGISTRO');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_PRODUCTOS'
 WHERE RUTINA IN ('PARA_ACTIVARODESACTIVAR_PROC', 'PARA_ACTUALIZARDATOS');

SELECT COUNT(*) AS MAPEADAS,
       SUM(PERMISO IS NULL) AS SIN_PERMISO,
       SUM(EXIGIR = 1) AS EXIGIENDO
  FROM PERMISO_POR_RUTINA;

-- ================================================================
-- CORRECCIONES DE MAPEO (07/11/2026)
-- ================================================================
-- Regla: el permiso que exige una rutina debe ser el mismo que abre la
-- pantalla que la llama. El heuristico de arriba mira el nombre de la rutina,
-- no el flujo, asi que varias quedaron con el permiso de otra area y el rol
-- que llegaba a esa pantalla recibia SIN_PERMISO (se ve en LOG_PERMISO_SP).
-- Verificado contra la tabla de opciones de cada modulo en el codigo.
-- ================================================================

-- Ventas: cobrar una VENTA y anular su pago se abren con GESTIONAR_VENTAS.
-- COMPRAS_PAGAR es para "Pagar compra" (SP_REGISTRAR_PAGO_COMPRA).
-- (08/11/2026) SP_PAGOS_ULTIMOS y SP_DETALLES_VENDIDOS_ULTIMOS se eliminaron
-- (sin caller tras el paginado); quedan solo los dos que siguen.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_VENTAS'
 WHERE RUTINA IN ('24_SP_REGISTRAR_PAGO', 'SP_ANULAR_PAGO');

-- "Reporte por rango" del menu Ventas se abre con CONSULTAR_REPORTES.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_REPORTES'
 WHERE RUTINA = 'SP_REPORTE_VENTAS';

-- (08/11/2026) Reporte de ventas paginado: el mismo permiso que su hermana.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_REPORTES'
 WHERE RUTINA IN ('SP_REPORTE_VENTAS_PAGINADO', 'SP_CONTAR_REPORTE_VENTAS');

-- Garantias: el submenu usa un permiso fino por accion. Las consultas se
-- comparten entre "Reclamar" y "Consultar", y todo rol que reclama tambien
-- consulta, asi que GARANTIAS_CONSULTAR cubre las dos pantallas.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_REGISTRAR'
 WHERE RUTINA IN ('SP_REGISTRAR_GARANTIA', 'SP_LINEAS_VENTA_CON_GARANTIA');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_RECLAMAR'
 WHERE RUTINA = '27_SP_REGISTRAR_RECLAMO_GARANTIA';
-- (15/11/2026) 27_SP_FINALIZAR_RECLAMO_TOTAL SE ELIMINO: el cierre va por
-- SP_FINALIZAR_RECLAMO(id_asignacion). Sin el SP, su fila de mapeo sobra.
DELETE FROM PERMISO_POR_RUTINA WHERE RUTINA = '27_SP_FINALIZAR_RECLAMO_TOTAL';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_CONSULTAR'
 WHERE RUTINA IN ('SP_CONSULTAR_GARANTIAS', 'SP_CONSULTAR_RECLAMOS');
-- SP_CONSULTAR_GARANTIAS llama internamente a SP_MARCAR_GARANTIAS_VENCIDAS
-- antes de listar: si esa exige GESTIONAR_VENTAS, el rol que solo consulta
-- garantias recibe SIN_PERMISO y no puede ver nada. Hereda el permiso de la
-- pantalla que la dispara.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_CONSULTAR'
 WHERE RUTINA = 'SP_MARCAR_GARANTIAS_VENCIDAS';

-- (15/11/2026) Asignacion de reclamos y bitacora de reparacion. Los tres SP
-- estaban en GESTIONAR_VENTAS o sin fila, y son tres trabajos distintos:
--   asignar  -> GARANTIAS_ASIGNAR  (gerencia decide quien repara)
--   reparar  -> GARANTIAS_AVANZAR  (el tecnico registra el avance)
--   cerrar   -> GARANTIAS_FINALIZAR (ya estaba; cierra Gerencia)
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_ASIGNAR'
 WHERE RUTINA = 'SP_ASIGNAR_TECNICO_RECLAMO';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_AVANZAR'
 WHERE RUTINA = 'SP_REGISTRAR_AVANCE_REPARACION';
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_FINALIZAR'
 WHERE RUTINA = 'SP_FINALIZAR_RECLAMO';
-- (15/11/2026) La lista de asignaciones que alimentan las pantallas de avance y
-- de cierre. Antes no existia ningun SP que listara ASIGNACIONES_RECLAMOS.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_CONSULTAR'
 WHERE RUTINA = 'SP_CONSULTAR_ASIGNACIONES';
-- Quien puede asignar es quien necesita la lista de tecnicos.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_ASIGNAR'
 WHERE RUTINA = 'SP_TECNICOS_DISPONIBLES';

-- Historial propio: "Mis vacaciones" y "Mis permisos" se abren con
-- SOLICITAR_PERMISO. El historial del empleado no puede exigir el permiso de
-- gestion de RRHH: el propio empleado no lo tiene (y no debe tenerlo).
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'SOLICITAR_PERMISO'
 WHERE RUTINA IN ('SP_HISTORIAL_VACACIONES_EMPLEADO', 'SP_HISTORIAL_PERMISOS_EMPLEADO');

-- Inventario: "Ajuste de stock" se abre con INVENTARIO_AJUSTAR.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'INVENTARIO_AJUSTAR'
 WHERE RUTINA = '20_SP_REGISTRAR_AJUSTE_INVENTARIO';

-- Consulta de inventario compartida: la usan "Productos > Consultar
-- Inventario" (CONSULTAR_PRODUCTOS) y la venta (GESTIONAR_VENTAS). Todo rol
-- con GESTIONAR_VENTAS tambien tiene CONSULTAR_PRODUCTOS, asi que este ultimo
-- cubre las dos pantallas.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_PRODUCTOS'
 WHERE RUTINA = 'SP_CONSULTAR_INVENTARIO';

-- Productos: "Reporte De Stock" se abre con CONSULTAR_PRODUCTOS.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_PRODUCTOS'
 WHERE RUTINA = 'SP_REPORTE_STOCK_CRITICO';

-- Usuarios: "Cambiar Estado" se abre con USUARIOS_ESTADO, no con USUARIOS_VER.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'USUARIOS_ESTADO'
 WHERE RUTINA = 'PARA_ACT_DESAC_USUARIOS';

-- Garantias: el listado de ventas sobre las que se puede registrar una
-- garantia lo abre "Registrar garantia" (GARANTIAS_REGISTRAR). Es rutina
-- nueva, asi que el heuristico de arriba no la conoce.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GARANTIAS_REGISTRAR'
 WHERE RUTINA = 'SP_VENTAS_GARANTIZABLES';

-- (08/11/2026) Productos paginado: el par que usa "Buscar Producto" para traer
-- de a 10. La pantalla se abre con CONSULTAR_PRODUCTOS (su listado hermano
-- SP_CONSULTAR_PRODUCTOS_FILTRADO ya tiene ese permiso).
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_PRODUCTOS'
 WHERE RUTINA IN ('SP_CONSULTAR_PRODUCTOS_PAGINADO', 'SP_CONTAR_PRODUCTOS_FILTRADOS');

-- (08/11/2026) Compras paginado: el listado lo comparten "Ver compra con IVA"
-- (COMPRAS_VER), "Devolucion" (COMPRAS_DEVOLVER), "Pagar" (COMPRAS_PAGAR) y
-- "Cancelar" (COMPRAS_CANCELAR). En la matriz ADMIN, ALMACEN, GERENTE y
-- SUBGERENTE tienen los cinco permisos de compras, asi que COMPRAS_VER cubre a
-- todos los llamadores.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'COMPRAS_VER'
 WHERE RUTINA IN ('SP_COMPRAS_ULTIMAS_PAGINADO', 'SP_CONTAR_COMPRAS',
                  'SP_COMPRAS_PENDIENTES_PAGINADO', 'SP_CONTAR_COMPRAS_PENDIENTES');

-- (08/11/2026) Ventas paginado: los tres listados los abren pantallas que
-- exigen GESTIONAR_VENTAS (cobrar, anular pago y devolucion), y es el mismo
-- permiso que ya tienen sus hermanas sin paginar.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_VENTAS'
 WHERE RUTINA IN ('SP_VENTAS_PENDIENTES_PAGINADO', 'SP_CONTAR_VENTAS_PENDIENTES',
                  'SP_PAGOS_ULTIMOS_PAGINADO', 'SP_CONTAR_PAGOS',
                  'SP_DETALLES_VENDIDOS_PAGINADO', 'SP_CONTAR_DETALLES_VENDIDOS',
                  'SP_VENTAS_ULTIMAS_PAGINADO', 'SP_CONTAR_VENTAS_ULTIMAS',
                  'SP_VENTAS_BORRADOR_VIEJO');

-- (08/11/2026) Productos: paginado de la edicion (GESTIONAR_PRODUCTOS), de la
-- consulta de inventario y del reporte de stock critico (CONSULTAR_PRODUCTOS).
-- Mismo permiso que su hermana sin paginar en cada caso; la consulta de
-- inventario ya estaba mapeada a CONSULTAR_PRODUCTOS porque la comparten
-- "Productos > Consultar Inventario" y la venta.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_PRODUCTOS'
 WHERE RUTINA IN ('PARA_ACTUALIZARDATOS_PAGINADO', 'SP_CONTAR_PRODUCTOS');
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'CONSULTAR_PRODUCTOS'
 WHERE RUTINA IN ('SP_CONSULTAR_INVENTARIO_PAGINADO', 'SP_CONTAR_INVENTARIO',
                  'SP_REPORTE_STOCK_CRITICO_PAGINADO', 'SP_CONTAR_STOCK_CRITICO');

-- (08/11/2026) Kardex paginado: lo abre "Inventario > Movimientos", que exige
-- INVENTARIO_VER, el mismo permiso que sus hermanas sin paginar. El heuristico
-- de arriba los agarra por el nombre (%KARDEX%), pero se deja explicito.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'INVENTARIO_VER'
 WHERE RUTINA IN ('SP_KARDEX_PAGINADO', 'SP_CONTAR_MOVIMIENTOS');

-- (12/11/2026) Auditoria de permisos: la pantalla "Ver auditoria de permisos"
-- se abre con GESTIONAR_PERMISOS_EMPLEADO, el mismo permiso que aprueba y
-- rechaza. El heuristico de arriba no las conoce (son rutinas nuevas y su
-- nombre no cae en ninguna regla), asi que quedarian en SIN_MAPEO y con
-- EXIGIR = 1 cortarian la consulta.
UPDATE PERMISO_POR_RUTINA SET PERMISO = 'GESTIONAR_PERMISOS_EMPLEADO'
 WHERE RUTINA IN ('SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO',
                  'SP_CONTAR_AUDITORIA_PERMISOS');

-- ================================================================
-- ACTIVAR EXIGENCIA (lista verificada)
-- ================================================================
-- (15/11/2026) El INSERT heuristico de arriba NUNCA prende la exigencia:
-- propone el permiso y deja EXIGIR como estaba, para que una base recien
-- mapeada quede en modo auditoria hasta que alguien revise. Este bloque es el
-- acto explicito de prenderla, y SOLO para rutinas cuyo mapeo ya se verifico y
-- cuyos roles realmente tienen el permiso. Una rutina que no exista no rompe
-- nada: el UPDATE simplemente no toca ninguna fila.
--
-- Las dos son del flujo de garantias y quedaban en 0 mientras sus hermanas
-- (SP_CONSULTAR_RECLAMOS, SP_ASIGNAR_TECNICO_RECLAMO, ...) ya exigian:
--   SP_CONSULTAR_ASIGNACIONES -> GARANTIAS_CONSULTAR  (TECNICO la tiene)
--   SP_TECNICOS_DISPONIBLES   -> GARANTIAS_ASIGNAR    (quien asigna la tiene)
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 1
 WHERE RUTINA IN ('SP_CONSULTAR_ASIGNACIONES', 'SP_TECNICOS_DISPONIBLES');

-- (15/11/2026) Rutinas nuevas del paginado de ventas. El heuristico de arriba
-- les propuso el permiso pero las dejo en modo auditoria (EXIGIR = 0), asi que
-- la guarda solo registraba y no cortaba. Sus hermanas ya exigen
-- (SP_VENTAS_ULTIMAS, SP_VENTAS_PENDIENTES_PAGINADO, SP_VENTAS_PENDIENTES) y
-- las pantallas que las llaman ya piden GESTIONAR_VENTAS, asi que prenderlas no
-- cierra ninguna puerta legitima.
--   SP_VENTAS_ULTIMAS_PAGINADO y SP_CONTAR_VENTAS_ULTIMAS: pantalla
--     «Ver venta con IVA».
--   SP_VENTAS_BORRADOR_VIEJO: aviso de borradores en «Cobrar venta».
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 1
 WHERE RUTINA IN ('SP_VENTAS_ULTIMAS_PAGINADO', 'SP_CONTAR_VENTAS_ULTIMAS',
                  'SP_VENTAS_BORRADOR_VIEJO',
                  'SP_HISTORIAL_VENTA_PAGINADO', 'SP_CONTAR_HISTORIAL_VENTA');

-- (15/11/2026) Las dos rutinas de la auditoria de permisos quedaron con
-- EXIGIR = 0: el bloque de correcciones de arriba les propone el permiso pero
-- NO prende la exigencia, asi que su guarda solo registraba y no cortaba. Con
-- el interruptor global SECRETO_SISTEMA.EXIGIR_PERMISO_SP en 0 —que es como
-- esta en las dos bases— EXIGIR es lo UNICO que decide si la guarda bloquea.
-- La pantalla se abre con GESTIONAR_PERMISOS_EMPLEADO y es el mismo permiso que
-- ya tienen sus hermanas, asi que prenderlas no cierra ninguna puerta legitima.
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 1
 WHERE RUTINA IN ('SP_CONSULTAR_AUDITORIA_PERMISOS_PAGINADO',
                  'SP_CONTAR_AUDITORIA_PERMISOS');

-- (18/11/2026) Par paginado de bonos: el heuristico les propone el permiso pero
-- las deja en modo auditoria. Sus cuatro hermanas (registrar, actualizar, pagar,
-- anular) ya exigen, y la pantalla que las llama —«Gestionar bonos»— se abre con
-- GESTIONAR_BONOS_EMPLEADO, el mismo permiso. Prenderlas no cierra ninguna
-- puerta legitima y evita que el listado quede como la unica lectura sin control
-- de un modulo que ahora tiene pantalla.
UPDATE PERMISO_POR_RUTINA SET EXIGIR = 1
 WHERE RUTINA IN ('SP_LISTAR_BONOS_PAGINADO', 'SP_CONTAR_BONOS');

-- Comprobacion: las rutinas de garantias tienen que quedar TODAS exigiendo.
SELECT RUTINA, PERMISO, EXIGIR
  FROM PERMISO_POR_RUTINA
 WHERE PERMISO LIKE 'GARANTIAS%'
 ORDER BY EXIGIR, RUTINA;

-- Comprobacion: las rutinas de las pantallas de ventas tienen que quedar
-- TODAS exigiendo (EXIGIR = 1). Si alguna sale en 0, se colo una rutina nueva
-- y su guarda esta en modo auditoria: solo registra, no corta.
SELECT RUTINA, PERMISO, EXIGIR
  FROM PERMISO_POR_RUTINA
 WHERE PERMISO = 'GESTIONAR_VENTAS'
   AND (RUTINA LIKE 'SP_VENTAS%' OR RUTINA LIKE 'SP_CONTAR_VENTAS%')
 ORDER BY EXIGIR, RUTINA;
