# Build Stage
FROM ubuntu:22.04 AS builder

ARG PG_VERSION=18
ARG DEBIAN_FRONTEND=noninteractive
ARG PG_VERSION_FULL=18.1
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
ENV RUST_VERSION=1.75.0

RUN apt-get update && apt-get install -y wget ca-certificates gnupg && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

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

# Set architecture-specific OpenSSL paths based on target architecture
ENV OPENSSL_DIR=/usr
ENV OPENSSL_INCLUDE_DIR=/usr/include/openssl

# Dynamic OpenSSL library paths
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
      export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu && \
      export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig && \
      echo "export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu" >> ~/.bashrc && \
      echo "export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig" >> ~/.bashrc; \
    elif [ "${TARGETARCH}" = "arm64" ]; then \
      export OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu && \
      export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig && \
      echo "export OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu" >> ~/.bashrc && \
      echo "export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig" >> ~/.bashrc; \
    fi

WORKDIR /build

COPY . .
RUN . ~/.bashrc && cargo install cargo-pgrx --version 0.17.0
RUN . ~/.bashrc && cargo pgrx init --pg${PG_VERSION} $(which pg_config)
RUN . ~/.bashrc && cargo pgrx package --no-default-features --features pg${PG_VERSION}

# Extractor stage
FROM ubuntu:22.04 AS extractor

ARG PG_VERSION=18

USER 0

RUN mkdir -p /output/lib /output/lib/bitcode /output/share/extension

COPY --from=builder /build/target/release/pg_cardano-pg${PG_VERSION}/ /tmp/pgrx/

RUN find /tmp/pgrx -name "*.so" -exec cp {} /output/lib/ \; || true

RUN if [ -d "/tmp/pgrx/usr/lib/postgresql/${PG_VERSION}/lib/bitcode" ]; then \
      cp -r /tmp/pgrx/usr/lib/postgresql/${PG_VERSION}/lib/bitcode/* /output/lib/bitcode/ 2>/dev/null || true; \
    fi

# Copy extension control and SQL files  
RUN find /tmp/pgrx -name "*.control" -exec cp {} /output/share/extension/ \; || true && \
    find /tmp/pgrx -name "*.sql" -exec cp {} /output/share/extension/ \; || true

# Final: ImageVolume Files
FROM scratch

ARG PG_VERSION=18
ARG PG_VERSION_FULL=18.1

COPY --from=extractor /output/lib/ /lib/

COPY --from=extractor /output/share/ /share/

USER 65532:65532

LABEL maintainer="pgcardano community" \
      description="PostgreSQL extension for Cardano blockchain operations (files-only image for CNPG ImageVolume)" \
      version="pg${PG_VERSION_FULL}" \
      org.opencontainers.image.title="pgcardano" \
      org.opencontainers.image.description="PostgreSQL extension for Cardano blockchain operations" \
      org.opencontainers.image.version="pg${PG_VERSION_FULL}" \
      org.opencontainers.image.base.name="scratch" \
      org.opencontainers.image.documentation="https://github.com/cardano-community/pg_cardano" \
      org.opencontainers.image.source="https://github.com/cardano-community/pg_cardano" \
      io.cloudnativepg.image.base.name="scratch" \
      io.cloudnativepg.image.base.pgmajor="${PG_VERSION}"
