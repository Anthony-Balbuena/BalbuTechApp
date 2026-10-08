FROM mcr.microsoft.com/devcontainers/cpp:1-bookworm

# Toolchain C++ + conectores MariaDB/MySQL + cliente para importar SQL.
# Nota: bookworm no trae el Connector/C++ de MariaDB en APT, asi que se usa
# libmysqlcppconn-dev de Debian (API JDBC: mysql_connection.h + cppconn/*,
# link -lmysqlcppconn), 100% compatible con el codigo (sql::mysql) y con el
# protocolo de MariaDB 10.11 por TCP con clave nativa.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        g++ \
        gdb \
        make \
        git \
        locales \
        mariadb-client \
        libmariadb-dev \
        libmysqlcppconn-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Locale UTF-8 para los mensajes en espanol de la app y los .sql
RUN sed -i 's/# es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || echo "es_ES.UTF-8 UTF-8" >> /etc/locale.gen; \
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen; \
    locale-gen || true
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
