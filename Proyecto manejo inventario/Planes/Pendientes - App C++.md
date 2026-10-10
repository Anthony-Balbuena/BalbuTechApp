# Pendientes — App C++

> Creado 10/10/2026. Solo C++ (la BD quedó cerrada). Nada ejecutado todavía.

## Submenús (mismo patrón de Roles/Usuarios: bucle + cableado)

- [x] Roles ✅ (09/10)
- [x] Usuarios ✅ (09/10)
- [x] Empleados ✅ (10/10)
- [x] Clientes ✅ (10/10)
- [x] Proveedores ✅ (10/10, hecho en otro chat y revisado)
- [x] Categorías ✅ (10/10)
- [x] Marcas ✅ (10/10)
- [x] Productos ✅ (10/10)
- [x] Métodos de pago ✅ (10/10: permiso + opción 9 + loop, probado corriendo)~

## Métodos de pago huérfano

- [ ] Crear permiso `GESTIONAR_METODOS_PAGO` (BD) y dárselo al ADMIN
- [ ] Opción 9 en el menú ADMIN + renumerar (10 Ver permisos, 11 Cerrar)
- [ ] Su loop de submenú

## Limpieza / verificación

- [ ] Borrar binario viejo `./main` (vale `output/app`)
- [ ] Probar todos los submenús corriendo (solo Roles probado)
- [ ] `git push origin main` (sin credenciales en esta máquina; lo hace el usuario)

## Calidad (no rompe, después)

- [ ] `delete pstmt` se saltea en excepciones (fuga chica, varios módulos)
- [ ] **Refactor a `unique_ptr` (plan):** reemplazar `new`/`delete` manuales por punteros inteligentes, un módulo por vez con prueba. Piloto sugerido: marcas.
- [x] Drenar result-sets pendientes ✅ (10/10: helper central + 50+ sitios; corrida completa de 9 submenús sin "out of sync")
