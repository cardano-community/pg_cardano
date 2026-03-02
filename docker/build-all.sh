#!/bin/bash

# The script will build images for ALL PostgreSQL versions (16, 17, 18) and BOTH platforms (linux-amd64, linux-arm64).

set -euo pipefail

# Source utility functions
source "$(dirname "$0")/build-utils.sh"

# Configuration
REGISTRY=${REGISTRY:-"your-registry"}
EXTENSION_NAME=${EXTENSION_NAME:-"pgcardano"}
PLATFORMS=("linux/amd64" "linux/arm64")
ARCHS=("amd64" "arm64")
PUSH=${PUSH:-false}
BUILD_MULTI_ARCH=${BUILD_MULTI_ARCH:-false}  # Set to true for legacy multi-arch builds (not recommended

EXT_VERSION=$(get_extension_version)
DISTRO=$(get_distro_version)

PG_VERSIONS_16="16.13"
PG_VERSIONS_17="17.9"
PG_VERSIONS_18="18.1"
PG_MAJORS=("16" "17" "18")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "../Cargo.toml" ]]; then
    log_error "Please run this script from the docker directory"
    exit 1
fi

if command -v docker &> /dev/null; then
    BUILDER="docker"
elif command -v podman &> /dev/null; then
    BUILDER="podman"
else
    log_error "Neither docker nor podman found. Please install one of them."
    exit 1
fi

log_info "Using ${BUILDER} to build images..."
log_info "Registry: ${REGISTRY}"
log_info "Extension: ${EXTENSION_NAME} v${EXT_VERSION}"
log_info "Distro: ${DISTRO}"
log_info "Platforms: ${PLATFORMS[*]}"
log_info "Architectures: ${ARCHS[*]}"
log_info "Multi-arch mode: ${BUILD_MULTI_ARCH}"

# Is buildx available for multi-platform builds?
BUILDX_AVAILABLE=false
if [[ "${BUILDER}" == "docker" ]] && docker buildx version &> /dev/null; then
    BUILDX_AVAILABLE=true
    log_info "Docker buildx available for multi-platform builds"
fi

BUILT_IMAGES=()
FAILED_BUILDS=()

# Build for each PostgreSQL version and architecture combination
for PG_MAJOR in "${PG_MAJORS[@]}"; do
    # Get version using indirect variable reference
    PG_FULL_VAR="PG_VERSIONS_${PG_MAJOR}"
    PG_FULL="${!PG_FULL_VAR}"
    
    if [[ "${BUILD_MULTI_ARCH}" == "true" ]]; then
        # Legacy multi-arch build (single image with multiple platforms)
        PLATFORM_STR="$(IFS=,; echo "${PLATFORMS[*]}")"
        NEW_IMAGE_TAG=$(generate_image_tag "$REGISTRY" "$EXTENSION_NAME" "$EXT_VERSION" "$PG_FULL" "$DISTRO")
        COMPAT_TAGS=($(generate_compatibility_tags "$REGISTRY" "pgcardano-extension" "$PG_FULL" "$PG_MAJOR"))
        LATEST_TAG=$(generate_latest_tag "$REGISTRY" "$EXTENSION_NAME" "$PG_FULL")
        
        log_step "Building PostgreSQL ${PG_FULL} (${PG_MAJOR}) - Multi-arch"
    else
        # Architecture-specific builds
        for i in "${!PLATFORMS[@]}"; do
            PLATFORM="${PLATFORMS[$i]}"
            ARCH="${ARCHS[$i]}"
            
            NEW_IMAGE_TAG=$(generate_image_tag "$REGISTRY" "$EXTENSION_NAME" "$EXT_VERSION" "$PG_FULL" "$DISTRO" "$ARCH")
            COMPAT_TAGS=($(generate_compatibility_tags "$REGISTRY" "pgcardano-extension" "$PG_FULL" "$PG_MAJOR" "$ARCH"))
            LATEST_TAG=$(generate_latest_tag "$REGISTRY" "$EXTENSION_NAME" "$PG_FULL" "$ARCH")
            
            # Convert arch to platform name for display
            case "$ARCH" in
                "amd64") PLATFORM_NAME="linux-amd64" ;;
                "arm64") PLATFORM_NAME="linux-arm64" ;;
                "386") PLATFORM_NAME="linux-386" ;;
                *) PLATFORM_NAME="linux-${ARCH}" ;;
            esac
            
            log_step "Building PostgreSQL ${PG_FULL} (${PG_MAJOR}) - ${PLATFORM_NAME}"
            log_info "Docker Platform: ${PLATFORM}"
            log_info "Primary tag: ${NEW_IMAGE_TAG}"
            log_info "Compatibility tags: ${COMPAT_TAGS[*]}"
            if [[ -n "$LATEST_TAG" ]]; then
                log_info "Latest tag: ${LATEST_TAG}"
            fi
            
            # Build tag arguments
            TAG_ARGS=("--tag" "$NEW_IMAGE_TAG")
            for tag in "${COMPAT_TAGS[@]}"; do
                TAG_ARGS+=("--tag" "$tag")
            done
            if [[ -n "$LATEST_TAG" ]]; then
                TAG_ARGS+=("--tag" "$LATEST_TAG")
            fi
    
            if [[ "${BUILDX_AVAILABLE}" == "true" ]]; then
                # Build single-platform architecture-specific image
                if docker buildx build \
                    --platform "${PLATFORM}" \
                    --build-arg PG_VERSION="${PG_MAJOR}" \
                    --build-arg PG_VERSION_FULL="${PG_FULL}" \
                    --build-arg TARGETARCH="${ARCH}" \
                    "${TAG_ARGS[@]}" \
                    --file Dockerfile \
                    ..; then
                    BUILD_SUCCESS=true
                else
                    BUILD_SUCCESS=false
                fi
            else
                if ${BUILDER} build \
                    --build-arg PG_VERSION="${PG_MAJOR}" \
                    --build-arg PG_VERSION_FULL="${PG_FULL}" \
                    --build-arg TARGETARCH="${ARCH}" \
                    "${TAG_ARGS[@]}" \
                    --file Dockerfile \
                    ..; then
                    BUILD_SUCCESS=true
                else
                    BUILD_SUCCESS=false
                fi
            fi
            
            if [[ "${BUILD_SUCCESS}" == "true" ]]; then
                log_info "✅ Successfully built PostgreSQL ${PG_FULL} - ${PLATFORM_NAME}"
                BUILT_IMAGES+=("${NEW_IMAGE_TAG}")
                BUILT_IMAGES+=("${COMPAT_TAGS[@]}")
                if [[ -n "$LATEST_TAG" ]]; then
                    BUILT_IMAGES+=("${LATEST_TAG}")
                fi
                
                # Push if not using buildx and push is requested
                if [[ "${BUILDX_AVAILABLE}" != "true" ]] && [[ "${PUSH}" == "true" ]]; then
                    log_info "Pushing ${NEW_IMAGE_TAG}..."
                    ${BUILDER} push "${NEW_IMAGE_TAG}"
                    for tag in "${COMPAT_TAGS[@]}"; do
                        ${BUILDER} push "$tag"
                    done
                    if [[ -n "$LATEST_TAG" ]]; then
                        ${BUILDER} push "$LATEST_TAG"
                    fi
                fi
            else
                log_error "❌ Failed to build PostgreSQL ${PG_FULL} - ${PLATFORM_NAME}"
                FAILED_BUILDS+=("PostgreSQL ${PG_FULL} - ${PLATFORM_NAME}")
            fi
            
            echo
        done
    fi
done

if [[ ${#BUILT_IMAGES[@]} -gt 0 ]]; then
    log_info "✅ All builds completed successfully"
fi

# Summary
echo
log_info "Build Summary:"
echo "=============="

if [[ ${#BUILT_IMAGES[@]} -gt 0 ]]; then
    log_info "Successfully built images:"
    for image in "${BUILT_IMAGES[@]}"; do
        echo "  ✅ ${image}"
    done
fi

if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
    log_warn "Failed builds:"
    for build in "${FAILED_BUILDS[@]}"; do
        echo "  ❌ ${build}"
    done
fi

echo
log_info "Usage examples:"
if [[ "${BUILD_MULTI_ARCH}" == "true" ]]; then
    echo "# Multi-arch images (legacy pattern):"
    echo "  image: ${REGISTRY}/${EXTENSION_NAME}:${EXT_VERSION}-pg16.13-${DISTRO}"
    echo "  image: ${REGISTRY}/pgcardano-extension:pg16.13"
else
    echo "# Platform-specific images (recommended):"
    echo "# For Linux AMD64:"
    echo "  image: ${REGISTRY}/${EXTENSION_NAME}:${EXT_VERSION}-pg18.1-linux-amd64-${DISTRO}"
    echo "  image: ${REGISTRY}/pgcardano-extension:pg18.1-linux-amd64"
    echo "  image: ${REGISTRY}/${EXTENSION_NAME}:latest-linux-amd64"
    echo
    echo "# For Linux ARM64:"
    echo "  image: ${REGISTRY}/${EXTENSION_NAME}:${EXT_VERSION}-pg18.1-linux-arm64-${DISTRO}"
    echo "  image: ${REGISTRY}/pgcardano-extension:pg18.1-linux-arm64"
    echo "  image: ${REGISTRY}/${EXTENSION_NAME}:latest-linux-arm64"
fi

if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
    exit 1
fi