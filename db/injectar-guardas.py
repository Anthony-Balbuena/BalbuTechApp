#!/usr/bin/env python3
"""Inyecta la guarda de permisos en los procedimientos de un esquema.

(03/11/2026) Cada SP sensible arranca con CALL SP_EXIGIR_PERMISO('<nombre>').
Con PERMISO_POR_RUTINA.EXIGIR = 0 la guarda solo registra; el bloqueo real se
prende por datos, sin reescribir rutinas.

Por que reescribe: MariaDB no permite envolver un procedimiento existente, asi
que se lee SHOW CREATE, se inserta la linea despues del primer BEGIN del cuerpo
y se recrea. Antes de tocar nada se guarda un dump de los originales.

Uso (dentro del contenedor app):
    python3 db/injectar-guardas.py BALBU_TECH_TEST [--aplicar]

Sin --aplicar solo informa que haria.
"""
import os
import re
import subprocess
import sys
import tempfile

DB = sys.argv[1] if len(sys.argv) > 1 else ""
APLICAR = "--aplicar" in sys.argv
if not DB:
    print("Falta el esquema. Uso: python3 db/injectar-guardas.py BALBU_TECH_TEST [--aplicar]")
    sys.exit(1)

HOST = os.environ.get("DB_HOST", "db")
PORT = os.environ.get("DB_PORT", "3306")
USER = os.environ.get("DB_ADMIN_USER", "balbu_admin")
PASS = os.environ.get("DB_ADMIN_PASSWORD")
if not PASS:
    print("Falta DB_ADMIN_PASSWORD")
    sys.exit(1)

# Rutinas que no llevan guarda: son las del propio control de acceso.
EXCLUIR = {
    "SP_EXIGIR_PERMISO",
    "SP_LOGIN_PARAMETROS",
    "SP_LOGIN_AUTENTICAR",
    "SP_CERRAR_SESION_SERVIDOR",
    "SP_REGISTRAR_ACCESO",
    "SP_ESTADO_BLOQUEO_LOGIN",
}

GUARDA = "    CALL SP_EXIGIR_PERMISO('{nombre}');\n"


def maria(args, stdin=None):
    return subprocess.run(
        ["mariadb", "-h", HOST, "-P", PORT, "-u", USER, "-p" + PASS] + args,
        input=stdin, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )


def rutinas():
    out = maria(["-N", "-B", "-e",
                 "SELECT ROUTINE_NAME FROM information_schema.ROUTINES "
                 f"WHERE ROUTINE_SCHEMA = '{DB}' AND ROUTINE_TYPE = 'PROCEDURE' "
                 "ORDER BY ROUTINE_NAME"])
    if out.returncode != 0:
        print("ERROR consultando rutinas:\n" + out.stderr)
        sys.exit(1)
    return [l.strip() for l in out.stdout.splitlines() if l.strip()]


def crear(nombre):
    # Sin --raw: el modo batch escapa tabs y saltos de linea dentro de los
    # valores, asi los \t reales separan columnas y el cuerpo llega entero.
    out = maria(["-N", "-B", "-e",
                 f"SHOW CREATE PROCEDURE `{DB}`.`{nombre}`"])
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    partes = out.stdout.rstrip("\n").split("\t")
    if len(partes) < 3:
        raise RuntimeError("formato inesperado de SHOW CREATE")
    cuerpo = (partes[2]
              .replace("\\\\", "\x00")
              .replace("\\n", "\n")
              .replace("\\t", "\t")
              .replace("\x00", "\\"))
    # (03/11/2026) En la base viva muchas rutinas quedaron con
    # DEFINER=root@localhost y balbu_admin no puede recrearlas con ese
    # definidor (haria falta SUPER). Se normaliza para que queden a nombre del
    # usuario de mantenimiento, que ya tiene ALL PRIVILEGES sobre el esquema.
    cuerpo = re.sub(r"DEFINER=`[^`]*`@`[^`]*`\s+", "", cuerpo, count=1)
    return cuerpo


def inyectar(create_sql, nombre):
    lineas = create_sql.split("\n")
    inicio = None
    for i, linea in enumerate(lineas):
        # Algunos SPs usan bloque etiquetado ("proc_label: BEGIN"): hay que
        # aceptar el prefijo o se quedan sin guarda.
        limpia = linea.strip()
        if limpia == "BEGIN" or limpia.endswith(": BEGIN"):
            inicio = i
            break
    if inicio is None:
        raise RuntimeError("no se encontro el BEGIN del cuerpo")

    # Los DECLARE tienen que ir antes de cualquier sentencia: la guarda se
    # inserta despues del ultimo DECLARE del bloque, no pegada al BEGIN.
    destino = inicio
    for i in range(inicio + 1, len(lineas)):
        limpia = lineas[i].strip()
        if limpia.startswith("DECLARE"):
            destino = i
        elif limpia == "" or limpia.startswith("--"):
            continue
        else:
            break

    lineas.insert(destino + 1, GUARDA.format(nombre=nombre).rstrip("\n"))
    return "\n".join(lineas)


def aplicar_bloque(sql):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False,
                                     encoding="utf-8", newline="\n") as f:
        f.write("DELIMITER //\n")
        f.write(sql)
        f.write("\n//\nDELIMITER ;\n")
        ruta = f.name
    try:
        with open(ruta, "r", encoding="utf-8") as fh:
            return maria(["--database=" + DB], stdin=fh.read())
    finally:
        os.unlink(ruta)


nombres = rutinas()
print(f"{DB}: {len(nombres)} procedimientos encontrados")

originales = []
parcheados = []
ya_tenian = []
fallidos = []

for n in nombres:
    if n in EXCLUIR:
        continue
    try:
        original = crear(n)
    except Exception as e:
        fallidos.append((n, f"SHOW CREATE: {e}"))
        continue
    originales.append((n, original))

    if "SP_EXIGIR_PERMISO(" in original:
        ya_tenian.append(n)
        continue

    try:
        nuevo = inyectar(original, n)
    except Exception as e:
        fallidos.append((n, str(e)))
        continue
    parcheados.append((n, original, nuevo))

print(f"  a parchear: {len(parcheados)}   ya tenian guarda: {len(ya_tenian)}   fallidos: {len(fallidos)}")

if not APLICAR:
    for n, _ in [(x[0], x[1]) for x in parcheados[:5]]:
        print(f"  (dry-run) {n}")
    if fallidos:
        print("  no se pudieron leer:")
        for n, e in fallidos:
            print(f"    {n}: {e.splitlines()[0] if e else 'sin detalle'}")
    print("Dry-run: usar --aplicar para escribir.")
    sys.exit(0)

# Dump de seguridad antes de tocar nada.
with open(f"/tmp/originales_{DB}.sql", "w", encoding="utf-8", newline="\n") as f:
    for n, sql in originales:
        f.write(f"DROP PROCEDURE IF EXISTS `{n}`;\nDELIMITER //\n{sql}\n//\nDELIMITER ;\n")
print(f"  originales guardados en /tmp/originales_{DB}.sql")

aplicados = 0
for n, original, nuevo in parcheados:
    r = aplicar_bloque(f"DROP PROCEDURE IF EXISTS `{n}`;\n{nuevo}")
    if r.returncode != 0:
        # Restaura el original en el acto para no dejar la rutina rota.
        aplicar_bloque(f"DROP PROCEDURE IF EXISTS `{n}`;\n{original}")
        fallidos.append((n, r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "error"))
        continue
    aplicados += 1

print(f"  parcheados: {aplicados}")
if fallidos:
    print("  FALLIDOS (se restauro el original):")
    for n, e in fallidos:
        print(f"    {n}: {e}")
    sys.exit(1)
print("OK: guardas inyectadas.")
