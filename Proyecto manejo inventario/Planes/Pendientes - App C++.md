# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje, unique_ptr, pausa y autologin pruebas: hechos ✅ (10-11/10). Push: lo hace el usuario.

- [x] `git push origin main` ✅ (10/10, pusheado desde terminal del usuario)

## C++ críticos (barrido 10/10, verificados)

- [x] `leerDatoSeguro` comía el Enter (doble Enter para omitir) ✅ (10/10: fuera peek/ignore; 1 Enter muestra todo, prompts en orden)

- [x] Menú muerto resto-2 ✅ (10/10: ahora abre el submenú; probado con usuario EMPLEADO real + limpieza)
- [x] `seguridad.h:21` fantasma ✅ (10/10: línea borrada, build + login OK)
- [x] Submenús sin validar `failbit` ✅ (10/10: guardia en 10 loops; letra = 1 aviso sin loop)
- [x] `login.cpp` + `roles.cpp:82-96` con `new` crudo ✅ (10/10: a `unique_ptr` a mano + build + login OK)
- [x] Autologin SOLO PRUEBAS ✅ (11/10: `BALBU_USER`/`BALBU_PASS` entran directo; sin vars, login normal; clave jamás en repo; `~/.balbuenv` + `envFile` en launch + `~/.bashrc` para Run/Code Runner)
- [x] Listar categorías comentado ✅ (11/10: buscar-con-Enter lo cubre; menú 1-4 + 5 volver, probado corriendo)
- [x] `sesion.cpp:22-23` guarda `idRol=0` ✅ (10/10: `ID_ROL` viaja del login a la sesión; login OK)

## BD medios (barrido 10/10, con línea)

- [x] Vacaciones-update con una sola fecha ✅ (10/10: valida combinación efectiva, 4 casos verdes)
- [x] `P_TIPO_BONO` / `P_MOTIVO` sin validar ✅ (10/10: ambos amables + rutas felices, residuos 0)
- [x] `SP_ACTUALIZAR_BONO` sin validar monto ✅ (10/10: NULL/≤0/>100000 amables + ruta feliz, residuos 0)
- [x] Mensaje "30 DÍAS" vs código de 60 ✅ (10/10: regla 60 días + huérfano `14_` dado de baja; 45 entra, 70 no, residuos 0)
- [x] Cambio solo-estado etiquetado `CAMBIO_PUESTO` ✅ (10/10: nuevo valor `CAMBIO_ESTADO`; baja y promo verificados, residuos 0)
- [x] `ON DELETE CASCADE` en bitácora ✅ (10/10: ahora `SET NULL`; la evidencia sobrevive, residuos 0)
- [x] `SP_LIMPIAR_AUDITORIA` con días ≤0 ✅ (10/10: valida positivo + nombre sin `6_`; 0/neg/NULL amables, bitácora intacta)
- [x] SALIDA sobrescribe SALIDA; ENTRADA nunca graba `TARDE` ✅ (10/10: segunda SALIDA bloqueada, TARDE desde 08:30, residuos 0)
- [x] Auditoría laboral trunca cargos ✅ (10/10: a VARCHAR(50); cargo de 38 verificado, residuos 0)
- [x] Solape de permisos incompleto ✅ (10/10: 3ra cláusula; envolvente y toque bloqueados, vecino ok, residuos 0)
- [x] `SP_LIMPIAR_LOGS_ANTIGUOS` sin `DROP` ✅ (10/10: rehabilitado con default 120 + validación; viejo se va, reciente queda, residuos 0)

## Web / Docker (barrido 10/10)

- [x] 4 SPs llamados por la app que no existían en BD ✅ (11/10: `SP_BUSCAR_CATEGORIA/MARCA/USUARIOS` + `SP_CAMBIAR_CLAVE_USUARIO` cargados de archivos y probados)

- [ ] `Pagina_Web` es mock (`Math.random()`); CDN sin SRI
- [ ] Sin `.env`; seed `admin/admin123` en plano e inyectable
- [ ] `.devcontainer` abandonado; labels de tasks desactualizados
