#!/bin/bash
# Compilacion directa con g++ (sin CMake).
# Glob *.cpp: incluye automaticamente archivos nuevos (ej. autenticacion.cpp).
# Link contra Connector/C++ (libmysqlcppconn-dev) + OpenSSL.
set -e
cd "$(dirname "$0")"
mkdir -p output
g++ -std=c++17 -Wall -Wextra \
  *.cpp \
  -o output/app \
  -lmysqlcppconn -lssl -lcrypto
echo "OK: ./output/app"
