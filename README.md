# ext-grpc artifacts

Artifact container images for the official PHP `grpc` extension.

This repository builds `grpc.so` from PECL and publishes small artifact images to GitHub Container Registry. The images are intended to be used as `COPY --from=...` sources by benchmark and compatibility-test images, not as runtime application images.

## Image

```text
ghcr.io/dkkoma/ext-grpc-artifacts
```

Tag format:

```text
<grpc-version>-php<php-version>-<distro>-<arch>-<profile>
```

Examples:

```text
ghcr.io/dkkoma/ext-grpc-artifacts:1.58.0-php8.4-trixie-amd64-pecl
ghcr.io/dkkoma/ext-grpc-artifacts:1.58.0-php8.4-trixie-amd64-optimized
ghcr.io/dkkoma/ext-grpc-artifacts:1.80.0-php8.5-trixie-arm64-pecl
ghcr.io/dkkoma/ext-grpc-artifacts:1.80.0-php8.5-trixie-arm64-optimized
```

## Artifact contents

Each image contains:

```text
/artifacts/grpc.so
/artifacts/metadata.json
/licenses/APACHE-2.0.txt
/licenses/NOTICE
```

`metadata.json` records the gRPC version, PHP minor version, PHP extension directory, distro, architecture, build profile, compiler flags, build timestamp, source URLs, license, and license file paths.

## Matrix

The initial publish matrix is:

| Dimension | Values |
| --- | --- |
| gRPC | `1.58.0`, `1.80.0` |
| PHP | `8.4`, `8.5` |
| Distro | `trixie` |
| Architecture | `amd64`, `arm64` |
| Profile | `pecl`, `optimized` |

Profiles:

- `pecl`: standard `pecl install grpc-${GRPC_VERSION}` build using the PHP image toolchain.
- `optimized`: `gcc-15` / `g++-15` with `-O3 -flto -fno-semantic-interposition` and `-flto`. The base image remains `trixie`; the Dockerfile adds Debian unstable with low apt priority only to install the requested GCC 15 toolchain. For `grpc 1.58.0`, `-include cstdint` is added to `CXXFLAGS`.

## Usage

```dockerfile
FROM ghcr.io/dkkoma/ext-grpc-artifacts:1.58.0-php8.4-trixie-amd64-optimized AS ext-grpc
FROM php:8.4-fpm-trixie

COPY --from=ext-grpc /artifacts/grpc.so /usr/local/lib/php/extensions/no-debug-non-zts-20240924/grpc.so
RUN echo "extension=grpc.so" > /usr/local/etc/php/conf.d/docker-php-ext-grpc.ini
```

If the PHP extension directory is not known ahead of time, copy `/artifacts/metadata.json` first and use its `php_extension_dir` value in the consuming build script.

## Local build

```sh
docker buildx build \
  --platform linux/amd64 \
  --build-arg GRPC_VERSION=1.80.0 \
  --build-arg PHP_VERSION=8.4 \
  --build-arg DISTRO=trixie \
  --build-arg PROFILE=pecl \
  --target artifact \
  -t ext-grpc-artifacts:1.80.0-php8.4-trixie-amd64-pecl \
  --load \
  .
```

## Verification

The Docker build verifies each artifact before creating the final image:

```sh
php -d extension=/artifacts/grpc.so -m | grep -x grpc
php -d extension=/artifacts/grpc.so --ri grpc
php -r 'var_dump(class_exists("Grpc\\Channel"));'
```

The build exports `MAKEFLAGS=-j$(nproc)` so PECL compilation can use the CPUs available to the Docker builder.

## License and source

The artifact is built from the PECL `grpc` package, which is published from the upstream gRPC project.

- PECL package: <https://pecl.php.net/package/grpc>
- Upstream source: <https://github.com/grpc/grpc>
- Upstream license: Apache License 2.0

This repository and the generated artifact images are distributed under the Apache License 2.0. The generated `grpc.so` artifacts are built from upstream gRPC/PECL grpc and retain the upstream Apache License 2.0 terms. Each artifact image includes `/licenses/APACHE-2.0.txt` and `/licenses/NOTICE`.
