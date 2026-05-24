# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.4
ARG DISTRO=trixie
FROM php:${PHP_VERSION}-cli-${DISTRO} AS builder

ARG GRPC_VERSION=1.80.0
ARG PHP_VERSION=8.4
ARG DISTRO=trixie
ARG PROFILE=pecl
ARG TARGETARCH

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
        export MAKEFLAGS="-j$(nproc)"; \
        export CC=gcc-15; \
        export CXX=g++-15; \
        export CFLAGS="-O3 -flto -fno-semantic-interposition"; \
        export CXXFLAGS="-O3 -flto -fno-semantic-interposition"; \
        export LDFLAGS="-flto"; \
        if [[ "${GRPC_VERSION}" == "1.58.0" ]]; then \
            export CXXFLAGS="${CXXFLAGS} -include cstdint"; \
        fi; \
    else \
        export MAKEFLAGS="-j$(nproc)"; \
        export CC="$(command -v gcc)"; \
        export CXX="$(command -v g++)"; \
        export CFLAGS=""; \
        export CXXFLAGS=""; \
        export LDFLAGS=""; \
    fi; \
    pecl install "grpc-${GRPC_VERSION}"; \
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
