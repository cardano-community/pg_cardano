# Build Stage
FROM ubuntu:22.04 AS builder

ARG PG_VERSION=18
ARG DEBIAN_FRONTEND=noninteractive
ARG PG_VERSION_FULL=18.1
ENV DEBIAN_FRONTEND=noninteractive
ENV RUST_VERSION=1.75.0

# Add PostgreSQL APT repository
RUN apt-get update && apt-get install -y wget ca-certificates gnupg && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install dependencies with fresh package update
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y \
    build-essential \
    clang \
    libclang-dev \
    llvm-dev \
    git \
    ccache \
    curl \
    libssl-dev \
    openssl \
    pkg-config \
    make \
    libreadline-dev \
    libxml2-dev \
    libxml2-utils \
    zlib1g-dev \
    bison \
    flex \
    libicu-dev \
    perl \
    xsltproc \
    postgresql-server-dev-${PG_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

ENV OPENSSL_DIR=/usr
ENV OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu
ENV OPENSSL_INCLUDE_DIR=/usr/include/openssl
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig

WORKDIR /build

COPY . .
RUN cargo install cargo-pgrx --version 0.17.0
RUN cargo pgrx init --pg${PG_VERSION} $(which pg_config)
RUN cargo pgrx package --no-default-features --features pg${PG_VERSION}

# Extract Statge -  only the files needed for ImageVolume mount
FROM ubuntu:22.04 AS extractor

ARG PG_VERSION=18

# Copy the packaged extension files from builder
COPY --from=builder /build/target/release/pg_cardano-pg${PG_VERSION}/ /tmp/pgrx/

# Stage the final on-disk layout we want to mount into the CNPG/Postgres container
RUN mkdir -p /out/usr/lib/postgresql/${PG_VERSION}/lib/ /out/usr/share/postgresql/${PG_VERSION}/extension/ && \
    find /tmp/pgrx -name "*.so" -exec cp {} /out/usr/lib/postgresql/${PG_VERSION}/lib/ \; && \
    find /tmp/pgrx -name "*.sql" -exec cp {} /out/usr/share/postgresql/${PG_VERSION}/extension/ \; && \
    find /tmp/pgrx -name "*.control" -exec cp {} /out/usr/share/postgresql/${PG_VERSION}/extension/ \;

# Final Image
#    Minimal image to use with Kubernetes ImageVolume
#    (contains only mountable files)
FROM scratch

ARG PG_VERSION=18
ARG PG_VERSION_FULL=18.1

COPY --from=extractor /out/ /

LABEL maintainer="pg_cardano community" \
      description="PostgreSQL extension for Cardano blockchain operations (files-only image for CNPG ImageVolume)" \
      version="pg${PG_VERSION_FULL}"
