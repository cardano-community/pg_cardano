#!/bin/bash

# Build script for pg_cardano extension container
set -euo pipefail

# Configuration
REGISTRY=${REGISTRY:-"cardano-community"}
IMAGE_NAME=${IMAGE_NAME:-"pg_cardano-extension"}
PG_VERSION=${PG_VERSION:-"18"}
PG_VERSION_FULL=${PG_VERSION_FULL:-"18.1"}
VERSION=${VERSION:-"pg${PG_VERSION_FULL}"}
PLATFORM=${PLATFORM:-"linux/amd64,linux/arm64"}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Are we in the right directory
if [[ ! -f "../Cargo.toml" ]]; then
    log_error "Please run this script from the docker directory"
    exit 1
fi

FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:latest"

log_info "Building pg_cardano extension container..."
log_info "PostgreSQL Version: ${PG_VERSION_FULL}"
log_info "Image: ${FULL_IMAGE_NAME}"

# Build the image
if command -v docker &> /dev/null; then
    BUILDER="docker"
elif command -v podman &> /dev/null; then
    BUILDER="podman"
else
    log_error "Neither docker nor podman found. Please install one of them."
    exit 1
fi

log_info "Using ${BUILDER} to build the image..."

# Build for multiple platforms if supported
if [[ "${BUILDER}" == "docker" ]] && docker buildx version &> /dev/null; then
    log_info "Building with buildx..."
    # Try multi-platform first, fall back to single platform
    if docker buildx build \
        --platform "${PLATFORM}" \
        --build-arg PG_VERSION="${PG_VERSION}" \
        --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
        --tag "${FULL_IMAGE_NAME}" \
        --tag "${LATEST_IMAGE_NAME}" \
        --file Dockerfile \
        --push \
        .. 2>/dev/null; then
        log_info "Multi-platform build successful"
    else
        log_warn "Multi-platform build failed, trying single platform..."
        docker buildx build \
            --build-arg PG_VERSION="${PG_VERSION}" \
            --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
            --tag "${FULL_IMAGE_NAME}" \
            --tag "${LATEST_IMAGE_NAME}" \
            --file Dockerfile \
            ..
    fi
else
    log_info "Building single-platform image..."
    ${BUILDER} build \
        --build-arg PG_VERSION="${PG_VERSION}" \
        --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
        --tag "${FULL_IMAGE_NAME}" \
        --tag "${LATEST_IMAGE_NAME}" \
        --file Dockerfile \
        ..
    
    # Maybe Push
    if [[ "${1:-}" == "--push" ]]; then
        log_info "Pushing image to registry..."
        ${BUILDER} push "${FULL_IMAGE_NAME}"
        ${BUILDER} push "${LATEST_IMAGE_NAME}"
    fi
fi

log_info "Build completed successfully!"
log_info "Image tags:"
log_info "  - ${FULL_IMAGE_NAME}"
log_info "  - ${LATEST_IMAGE_NAME}"

if [[ "${1:-}" != "--push" ]] && [[ "${BUILDER}" != "buildx" ]]; then
    echo "4. Push the image: ${BUILDER} push ${FULL_IMAGE_NAME}"
fi

echo
log_info "Usage examples:"
echo "# Use in CloudNativePG with PostgreSQL ${PG_VERSION_FULL}"
echo "  image: ${FULL_IMAGE_NAME}"
echo