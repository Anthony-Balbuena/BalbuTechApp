#!/bin/bash
# Compilacion directa con g++ (sin CMake).
# Glob *.cpp: incluye automaticamente archivos nuevos (ej. autenticacion.cpp).
# Conector: prefiere el C++ 8 en ~/conectores (funciona sin sudo y exige
# C++17); si no esta, usa el del sistema. OJO: el conector 1.1 del sistema
# corrompe al LEER strings de mas de 64 bytes (ej. el hash) y sus headers
# no compilan con C++17.
set -e
cd "$(dirname "$0")"
mkdir -p output
C8="$HOME/conectores/mysql-connector-c++-8.4.0-linux-glibc2.28-x86-64bit"
if [ -d "$C8/include/jdbc" ]; then
  g++ -std=c++17 -Wall -Wextra \
    -I"$C8/include/jdbc" \
    *.cpp \
    -o output/app \
    -L"$C8/lib64" -lmysqlcppconn -lssl -lcrypto \
    -Wl,-rpath,"$C8/lib64"
else
  g++ -std=c++17 -Wall -Wextra \
    *.cpp \
    -o output/app \
    -lmysqlcppconn -lssl -lcrypto
fi
echo "OK: ./output/app"
