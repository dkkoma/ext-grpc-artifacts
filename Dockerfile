# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.4
ARG DISTRO=trixie
FROM php:${PHP_VERSION}-cli-${DISTRO} AS builder

ARG GRPC_VERSION=1.80.0
ARG PHP_VERSION=8.4
ARG DISTRO=trixie
ARG PROFILE=pecl
ARG TARGETARCH
ARG MAKE_JOBS=4

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

COPY LICENSE /licenses/APACHE-2.0.txt
COPY NOTICE /licenses/NOTICE

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        ca-certificates \
        dpkg-dev \
        file \
        g++ \
        gcc \
        make \
        pkg-config \
        re2c \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN if [[ "${PROFILE}" == "optimized" ]]; then \
        printf 'deb http://deb.debian.org/debian unstable main\n' > /etc/apt/sources.list.d/unstable.list; \
        printf 'Package: *\nPin: release a=unstable\nPin-Priority: 50\n' > /etc/apt/preferences.d/limit-unstable; \
        apt-get update; \
        apt-get install -y --no-install-recommends -t unstable gcc-15 g++-15; \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN if [[ "${PROFILE}" == "optimized" ]]; then \
        export MAKEFLAGS="-j${MAKE_JOBS}"; \
        export CC=gcc-15; \
        export CXX=g++-15; \
        export CFLAGS="-O3 -flto -fno-semantic-interposition"; \
        export CXXFLAGS="-O3 -flto -fno-semantic-interposition"; \
        export LDFLAGS="-flto"; \
        if [[ "${GRPC_VERSION}" == "1.58.0" ]]; then \
            export CXXFLAGS="${CXXFLAGS} -include cstdint"; \
        fi; \
    else \
        export MAKEFLAGS="-j${MAKE_JOBS}"; \
        export CC="$(command -v gcc)"; \
        export CXX="$(command -v g++)"; \
        export CFLAGS=""; \
        export CXXFLAGS=""; \
        export LDFLAGS=""; \
    fi; \
    mkdir -p /tmp/grpc-src; \
    cd /tmp/grpc-src; \
    pecl download "grpc-${GRPC_VERSION}"; \
    tar -xf "grpc-${GRPC_VERSION}.tgz"; \
    cd "grpc-${GRPC_VERSION}"; \
    if [[ "${GRPC_VERSION}" == "1.58.0" ]]; then \
        find src/php/ext/grpc -type f -name '*.c' -print0 \
            | xargs -0 sed -i 's/zend_exception_get_default(TSRMLS_C)/zend_ce_exception/g'; \
        sed -i '1i#include <cstdint>' \
            third_party/abseil-cpp/absl/container/internal/container_memory.h; \
    fi; \
    phpize; \
    ./configure --with-php-config="$(command -v php-config)"; \
    if [[ "${PROFILE}" == "optimized" ]]; then \
        sed -i 's/-g -O2/-O3 -flto -fno-semantic-interposition/g' Makefile; \
    fi; \
    find . -type d ! -name .libs -print0 | xargs -0 -I{} mkdir -p "{}/.libs"; \
    make; \
    make install; \
    extension_dir="$(php-config --extension-dir)"; \
    mkdir -p /artifacts; \
    cp "${extension_dir}/grpc.so" /artifacts/grpc.so; \
    php -d "extension=/artifacts/grpc.so" -m | grep -x grpc; \
    php -d "extension=/artifacts/grpc.so" --ri grpc; \
    php -r 'var_dump(class_exists("Grpc\\Channel"));'; \
    GRPC_VERSION="${GRPC_VERSION}" PHP_VERSION="${PHP_VERSION}" PHP_EXTENSION_DIR="${extension_dir}" DISTRO="${DISTRO}" TARGETARCH="${TARGETARCH}" PROFILE="${PROFILE}" CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}" php -r ' \
        $metadata = [ \
            "grpc_version" => getenv("GRPC_VERSION"), \
            "php_version" => getenv("PHP_VERSION"), \
            "php_extension_dir" => basename(getenv("PHP_EXTENSION_DIR")), \
            "distro" => getenv("DISTRO"), \
            "arch" => getenv("TARGETARCH"), \
            "profile" => getenv("PROFILE"), \
            "compiler" => getenv("PROFILE") === "optimized" ? "gcc-15" : "default php image toolchain", \
            "cflags" => getenv("CFLAGS"), \
            "cxxflags" => getenv("CXXFLAGS"), \
            "ldflags" => getenv("LDFLAGS"), \
            "built_at" => gmdate("c"), \
            "source" => "pecl grpc-" . getenv("GRPC_VERSION"), \
            "source_url" => "https://pecl.php.net/package/grpc", \
            "upstream_url" => "https://github.com/grpc/grpc", \
            "license" => "Apache-2.0", \
            "license_files" => ["/licenses/APACHE-2.0.txt", "/licenses/NOTICE"], \
        ]; \
        file_put_contents("/artifacts/metadata.json", json_encode($metadata, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL); \
    '; \
    file /artifacts/grpc.so

FROM scratch AS artifact
COPY --from=builder /artifacts /artifacts
COPY --from=builder /licenses /licenses
