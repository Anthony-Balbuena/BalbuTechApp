# Pendientes — App C++

> Creado 10/10/2026. Solo C++ (la BD quedó cerrada). Nada ejecutado todavía.

## Submenús (mismo patrón de Roles/Usuarios: bucle + cableado)

- [x] Roles ✅ (09/10)
- [x] Usuarios ✅ (09/10)
- [ ] Empleados
- [ ] Clientes
- [ ] Proveedores
- [ ] Categorías
- [ ] Marcas
- [ ] Productos
- [ ] Métodos de pago~

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
