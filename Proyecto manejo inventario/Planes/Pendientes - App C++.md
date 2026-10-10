# Pendientes — App C++

> Submenús 9/9, métodos rescatado, drenaje y unique_ptr: hechos ✅ (10/10). Push: lo hace el usuario.

- [ ] `git push origin main` (sin credenciales en esta máquina; lo hace el usuario)

## C++ críticos (barrido 10/10, verificados)

- [ ] Menú muerto resto-2: llama `mostrarMenuClientes()` en vez del submenú (`roles.cpp:294-302`)
- [ ] `seguridad.h:21` declara `base64_encode` que no existe (el `.cpp:66` define otro `static`)
- [ ] Submenús sin validar `failbit`: una letra = loop infinito (todos los loops)
- [ ] `login.cpp` + `roles.cpp:82-96` con `new` crudo fugan en excepción (quedó fuera del unique_ptr)
- [ ] `sesion.cpp:22-23` guarda `idRol=0` siempre

## BD medios (barrido 10/10, con línea)

- [ ] Vacaciones-update con una sola fecha puede violar su `CHECK` (`12-`)
- [ ] `P_TIPO_BONO` / `P_MOTIVO` sin validar contra su `ENUM` (`14-`/`16-`)
- [ ] `SP_ACTUALIZAR_BONO` sin validar monto (`14-`)
- [ ] Mensaje "30 DÍAS" vs código de 60 (`14-`)
- [ ] Cambio solo-estado etiquetado `CAMBIO_PUESTO` (`15-`)
- [ ] `ON DELETE CASCADE` en bitácora de permisos (`30-`)
- [ ] `SP_LIMPIAR_AUDITORIA` con días ≤0 borra todo (`6-`)
- [ ] SALIDA sobrescribe SALIDA; ENTRADA nunca graba `TARDE` (`11-`)
- [ ] Auditoría laboral trunca cargos VARCHAR(30 vs 50) (`15-`)
- [ ] Solape de permisos incompleto (`13-`)
- [ ] `SP_LIMPIAR_LOGS_ANTIGUOS` sin `DROP` (`28-`)

## Web / Docker (barrido 10/10)

- [ ] `Pagina_Web` es mock (`Math.random()`); CDN sin SRI
- [ ] Sin `.env`; seed `admin/admin123` en plano e inyectable
- [ ] `.devcontainer` abandonado; labels de tasks desactualizados
