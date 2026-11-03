#!/usr/bin/env bash
# (03/11/2026) Helpers de clave para los tests que necesitan crear usuarios.
#
# Desde que la verificacion vive en el servidor (modulo 65), CONTRASENA suele
# estar en NULL: copiar el hash del admin ya no sirve. Estos helpers derivan
# desde la clave real que el test ya conoce (BALBU_PASS), sin leer hashes.
#
# Uso:  . "$(dirname "$0")/lib-clave-prueba.sh"
#       HASH=$(clave_pbkdf2 "$BALBU_PASS")     # formato viejo, migra solo
#
# Requiere python3 (esta en la imagen del contenedor app).

# Imprime pbkdf2$<iter>$<sal_b64>$<hash_b64> para la clave dada.
clave_pbkdf2() {
    printf '%s' "${1:-}" | python3 -c '
import base64, hashlib, os, sys
password = sys.stdin.buffer.read()
iteraciones = 100000
sal = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha256", password, sal, iteraciones, 32)
print("pbkdf2${}${}${}".format(
    iteraciones,
    base64.b64encode(sal).decode(),
    base64.b64encode(dk).decode(),
))
'
}

# Imprime "sal|iter|clave_servidor" para la clave y el pepper dados.
# clave_servidor = SHA2(pepper || derivado) en hex, igual que el SP.
clave_servidor() {
    printf '%s' "${1:-}" | python3 -c '
import base64, hashlib, os, sys
password = sys.stdin.buffer.read()
pepper = sys.argv[1]
iteraciones = 100000
sal = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha256", password, sal, iteraciones, 32)
derivado = base64.b64encode(dk).decode()
servidor = hashlib.sha256((pepper + derivado).encode()).hexdigest()
print("{}|{}|{}".format(base64.b64encode(sal).decode(), iteraciones, servidor))
' "${2:-}"
}
