# Auditoría general de la BD — 08/10/2026 · solo lo que quedó abierto

> **Todo lo cerrado de esta auditoría se movió a `../Planes/Realizado.md`** (sección «18/10 — Auditoría BD general (08/10) cerrada») el 18/10/2026.
> Acá queda únicamente lo que **seguía abierto** al reverificar contra la viva `BALBU_TECH` el 18/10/2026.
> Alcance: BD. El único ítem de C++ (el 9) quedó porque nació en esta nota; el resto de C++ va en `../Planes/Pendientes - App C++.md`.

## 🔴 Con impacto real

1. **`SP_CREAR_USUARIO` trunca el hash de la contraseña.** Es una de las rutinas que vive **solo en la viva** (ningún archivo la crea) y su parámetro es `P_PASSWORD_HASH VARCHAR(255)`, mientras `USUARIOS.CONTRASENA` es `VARCHAR(512)` y el PBKDF2 real mide 83–512 caracteres. La mejora #4a del 09/10 tocó `SP_INSERTAR_USUARIO` y `SP_CAMBIAR_CONTRASENA`, pero no esta. → subir a `VARCHAR(512)`.

2. **Quedan dos gemelos byte-idénticos en la viva.** `SP_BUSCAR_CATEGORIAS` ≡ `SP_BUSCAR_CATEGORIA` y `SP_BUSCAR_MARCAS` ≡ `SP_BUSCAR_MARCA` (mismo `MD5(ROUTINE_DEFINITION)` en los dos pares). Las plurales no las crea ningún archivo —solo aparecen en un comentario de `1- CATEGORIAS.sql:203` y `2- MARCAS.sql:94`— y nadie las llama: el C++ usa las singulares (`categorias.cpp:138`, `marcas.cpp:109`). → `DROP` de las plurales.

3. **`LOG_USUARIOS` sin FK a `USUARIOS`** (`ID_USUARIO`, `ID_USUARIO_ADMIN`). Nada impide un ID fantasma; en la viva las 32 filas tienen `ID_USUARIO_ADMIN` en `NULL`.

4. **`HISTORIAL_ESTADOS_COMPRA` y `HISTORIAL_ESTADOS_VENTA`: `ESTADO_ANTERIOR` y `ESTADO_NUEVO` siguen `varchar(20)`.** Nada restringe el valor que se escribe. (`DETALLE_REPARACIONES.ESTADO_AVANCE` sí se migró a ENUM.)

5. **`PROVEEDORES.EMAIL` y `.TELEFONO`: UNIQUE anulable + índice duplicado.** Ambos son `UNIQUE` con `NULL` permitido, así que varios `NULL` burlan la unicidad; y en la viva hay **dos índices por columna**: `EMAIL` + `UQ_PROVEEDOR_EMAIL`, `TELEFONO` + `UQ_PROVEEDOR_TELEFONO`.

6. **`VACACIONES` es la única tabla de RRHH sin ningún trigger.** `BONOS_EMPLEADOS` y `LIQUIDACIONES` ya tienen `BEFORE INSERT`/`UPDATE` (más `DELETE` en liquidaciones); vacaciones admite `UPDATE` y `DELETE` libres.

7. **`RECLAMOS_GARANTIAS` tiene `BEFORE UPDATE` y `BEFORE DELETE`, pero no `BEFORE INSERT`.** Los estados al crear quedan libres.

## 🟡 Deuda técnica

8. **SP multi-statement sin transacción ni handler** (siguen escribiendo a pelo): `SP_ASIGNAR_TECNICO_RECLAMO`, `26_SP_RECHAZAR_DEVOLUCION`, `SP_REGISTRAR_GARANTIA`, `SP_REGISTRAR_AVANCE_REPARACION`, `SP_ELIMINAR_BONO`.
   Ya blindados con `START TRANSACTION` + `EXIT HANDLER`: `SP_REGISTRAR_LIQUIDACION`, `SP_FINALIZAR_RECLAMO`, `20_SP_REGISTRAR_AJUSTE_INVENTARIO`.

9. **`mostrarCategoriasYMarcas()` es código muerto** (`database.h:15`, `database.cpp:70`): ya no está rota (usa `CATEGORIAS`/`MARCAS` en plural, corregido el 09/10) pero **nadie la llama**. Son ~25 líneas sin uso.

## Contexto cruzado

- Los ítems 1 y 2 se solapan con el informe del 18/10: las **7 rutinas que existen solo en la BD** y la truncación de hashes están en `Auditoria completa - Codigo y BD - 18-10-2026.md` (§3 P-5 y §4).
- Dos mejoras de esta nota ya quedaron **cerradas**: «Sin FK: `PRODUCTOS.ID_PROVEEDOR`» (hoy existe `FK_PRODUCTO_PROVEEDOR`) y «Sin ENUM: `DETALLE_REPARACIONES.ESTADO_AVANCE`» (hoy es ENUM).

## Ya resuelto de esta nota

Los 8 errores reales; las mejoras 1–4 (incluida la alineación de roles y la FK de `ROL_PERMISO`); los planes 1, 2 y 3; el contrato C++↔SQL (C1–C5, V1–V4); los gemelos numerados (`13_`, `1_`, `5_`, `35_`) y `VERANTESDEINSERT`; el orden explícito de triggers (`FOLLOWS`); `USUARIOS_SISTEMA`; el quirk de `leerDatoSeguro`; y el bloqueo de toolchain del build. El detalle completo está en `../Planes/Realizado.md`.
