#!/bin/bash

# Build script for pg_cardano extension container
set -euo pipefail

source "$(dirname "$0")/build-utils.sh"

REGISTRY=${REGISTRY:-"cardano-community"}
EXTENSION_NAME=${EXTENSION_NAME:-"pgcardano"}
PG_VERSION=${PG_VERSION:-"18"}
PG_VERSION_FULL=${PG_VERSION_FULL:-"18.1"}
PLATFORM=${PLATFORM:-"linux/amd64"}

if [[ -z "${ARCH:-}" ]]; then
    case "$PLATFORM" in
        *"amd64"*) ARCH="amd64" ;;
        *"arm64"*) ARCH="arm64" ;;
        *"386"*) ARCH="386" ;;
        *) 
            log_warn "Could not determine architecture from platform '$PLATFORM', defaulting to amd64"
            ARCH="amd64"
            ;;
    esac
fi

EXT_VERSION=$(get_extension_version)
DISTRO=$(get_distro_version)

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

# Generate image names
NEW_IMAGE_NAME=$(generate_image_tag "$REGISTRY" "$EXTENSION_NAME" "$EXT_VERSION" "$PG_VERSION_FULL" "$DISTRO" "$ARCH")

# Generate compatibility tags
COMPAT_TAGS=($(generate_compatibility_tags "$REGISTRY" "pgcardano-extension" "$PG_VERSION_FULL" "$PG_VERSION" "$ARCH"))
LATEST_TAG=$(generate_latest_tag "$REGISTRY" "$EXTENSION_NAME" "$PG_VERSION_FULL" "$ARCH")

log_info "Building pgcardano extension container..."
log_info "Extension Version: ${EXT_VERSION}"
log_info "PostgreSQL Version: ${PG_VERSION_FULL}"
log_info "Primary Image: ${NEW_IMAGE_NAME}"
log_info "Compatibility Tags: ${COMPAT_TAGS[*]}"
if [[ -n "$LATEST_TAG" ]]; then
    log_info "Latest Tag: ${LATEST_TAG}"
fi

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

TAG_ARGS=("--tag" "$NEW_IMAGE_NAME")
for tag in "${COMPAT_TAGS[@]}"; do
    TAG_ARGS+=("--tag" "$tag")
done
if [[ -n "$LATEST_TAG" ]]; then
    TAG_ARGS+=("--tag" "$LATEST_TAG")
fi

# Build for multiple platforms if supported
if [[ "${BUILDER}" == "docker" ]] && docker buildx version &> /dev/null; then
    log_info "Building with buildx..."
    # Try multi-platform first, fall back to single platform
    if docker buildx build \
        --platform "${PLATFORM}" \
        --build-arg PG_VERSION="${PG_VERSION}" \
        --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
        --build-arg TARGETARCH="${ARCH}" \
        "${TAG_ARGS[@]}" \
        --file Dockerfile \
        --push \
        .. 2>/dev/null; then
        log_info "Multi-platform build successful"
    else
        log_warn "Multi-platform build failed, trying single platform..."
        docker buildx build \
            --build-arg PG_VERSION="${PG_VERSION}" \
            --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
            --build-arg TARGETARCH="${ARCH}" \
            "${TAG_ARGS[@]}" \
            --file Dockerfile \
            ..
    fi
else
    log_info "Building single-platform image..."
    ${BUILDER} build \
        --build-arg PG_VERSION="${PG_VERSION}" \
        --build-arg PG_VERSION_FULL="${PG_VERSION_FULL}" \
        --build-arg TARGETARCH="${ARCH}" \
        "${TAG_ARGS[@]}" \
        --file Dockerfile \
        ..
    
    # Maybe Push
    if [[ "${1:-}" == "--push" ]]; then
        log_info "Pushing images to registry..."
        ${BUILDER} push "$NEW_IMAGE_NAME"
        for tag in "${COMPAT_TAGS[@]}"; do
            ${BUILDER} push "$tag"
        done
        if [[ -n "$LATEST_TAG" ]]; then
            ${BUILDER} push "$LATEST_TAG"
        fi
    fi
fi

log_info "Build completed successfully!"
log_info "Image tags:"
log_info "  - ${NEW_IMAGE_NAME} (primary)"
for tag in "${COMPAT_TAGS[@]}"; do
    log_info "  - ${tag} (compatibility)"
done
if [[ -n "$LATEST_TAG" ]]; then
    log_info "  - ${LATEST_TAG} (latest)"
fi

if [[ "${1:-}" != "--push" ]] && [[ "${BUILDER}" != "buildx" ]]; then
    echo "4. Push the images: ${BUILDER} push ${NEW_IMAGE_NAME}"
fi

echo
log_info "Usage examples:"
echo "# Use in CloudNativePG with PostgreSQL ${PG_VERSION_FULL} (new pattern):"
echo "  image: ${NEW_IMAGE_NAME}"
echo "# Use in CloudNativePG with PostgreSQL ${PG_VERSION_FULL} (compatibility):"
echo "  image: ${COMPAT_TAGS[0]}"
echo