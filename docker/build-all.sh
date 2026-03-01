#!/bin/bash

# Multi-version build script for pg_cardano extension containers

set -euo pipefail

# Configuration
REGISTRY=${REGISTRY:-"your-registry"}
IMAGE_NAME=${IMAGE_NAME:-"pg_cardano-extension"}
PLATFORM=${PLATFORM:-"linux/amd64,linux/arm64"}
PUSH=${PUSH:-false}

# PostgreSQL versions to build (compatible with older bash)
PG_VERSIONS_16="16.13"
PG_VERSIONS_17="17.9"
PG_VERSIONS_18="18.1"
PG_MAJORS=("16" "17" "18")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Determine builder
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
log_info "Platform: ${PLATFORM}"

# Check if buildx is available for multi-platform builds
BUILDX_AVAILABLE=false
if [[ "${BUILDER}" == "docker" ]] && docker buildx version &> /dev/null; then
    BUILDX_AVAILABLE=true
    log_info "Docker buildx available for multi-platform builds"
fi

BUILT_IMAGES=()
FAILED_BUILDS=()

for PG_MAJOR in "${PG_MAJORS[@]}"; do
    # Get version using indirect variable reference
    PG_FULL_VAR="PG_VERSIONS_${PG_MAJOR}"
    PG_FULL="${!PG_FULL_VAR}"
    IMAGE_TAG="${REGISTRY}/${IMAGE_NAME}:pg${PG_FULL}"
    MAJOR_TAG="${REGISTRY}/${IMAGE_NAME}:pg${PG_MAJOR}"
    
    log_step "Building PostgreSQL ${PG_FULL} (${PG_MAJOR})"
    log_info "Image tags: ${IMAGE_TAG}, ${MAJOR_TAG}"
    
    if [[ "${BUILDX_AVAILABLE}" == "true" ]]; then
        # Try multi-platform first
        if docker buildx build \
            --platform "${PLATFORM}" \
            --build-arg PG_VERSION="${PG_MAJOR}" \
            --build-arg PG_VERSION_FULL="${PG_FULL}" \
            --tag "${IMAGE_TAG}" \
            --tag "${MAJOR_TAG}" \
            --file Dockerfile \
            .. 2>/dev/null; then
            BUILD_SUCCESS=true
        else
        # fall back to single platform
            log_warn "Multi-platform build failed, trying single platform..."
            if docker buildx build \
                --build-arg PG_VERSION="${PG_MAJOR}" \
                --build-arg PG_VERSION_FULL="${PG_FULL}" \
                --tag "${IMAGE_TAG}" \
                --tag "${MAJOR_TAG}" \
                --file Dockerfile \
                ..; then
                BUILD_SUCCESS=true
            else
                BUILD_SUCCESS=false
            fi
        fi
    else
        if ${BUILDER} build \
            --build-arg PG_VERSION="${PG_MAJOR}" \
            --build-arg PG_VERSION_FULL="${PG_FULL}" \
            --tag "${IMAGE_TAG}" \
            --tag "${MAJOR_TAG}" \
            --file Dockerfile \
            ..; then
            BUILD_SUCCESS=true
        else
            BUILD_SUCCESS=false
        fi
    fi
    
    if [[ "${BUILD_SUCCESS}" == "true" ]]; then
        log_info "✅ Successfully built PostgreSQL ${PG_FULL}"
        BUILT_IMAGES+=("${IMAGE_TAG}" "${MAJOR_TAG}")
        
        # Push if not using buildx and push is requested
        if [[ "${BUILDX_AVAILABLE}" != "true" ]] && [[ "${PUSH}" == "true" ]]; then
            log_info "Pushing ${IMAGE_TAG}..."
            ${BUILDER} push "${IMAGE_TAG}"
            ${BUILDER} push "${MAJOR_TAG}"
        fi
    else
        log_error "❌ Failed to build PostgreSQL ${PG_FULL}"
        FAILED_BUILDS+=("PostgreSQL ${PG_FULL}")
    fi
    
    echo # Empty line for readability
done

# Create latest tag pointing to PostgreSQL 18
if [[ ${#BUILT_IMAGES[@]} -gt 0 ]] && [[ " ${BUILT_IMAGES[@]} " =~ " ${REGISTRY}/${IMAGE_NAME}:pg18.1 " ]]; then
    LATEST_TAG="${REGISTRY}/${IMAGE_NAME}:latest"
    log_step "Creating latest tag pointing to PostgreSQL 18.1"
    
    if [[ "${BUILDX_AVAILABLE}" == "true" ]] && [[ "${PUSH}" == "true" ]]; then
        docker buildx imagetools create \
            -t "${LATEST_TAG}" \
            "${REGISTRY}/${IMAGE_NAME}:pg18.1"
        log_info "✅ Created and pushed latest tag"
    else
        ${BUILDER} tag "${REGISTRY}/${IMAGE_NAME}:pg18.1" "${LATEST_TAG}"
        if [[ "${PUSH}" == "true" ]]; then
            ${BUILDER} push "${LATEST_TAG}"
        fi
        log_info "✅ Created latest tag"
    fi
    BUILT_IMAGES+=("${LATEST_TAG}")
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
echo "# Use in CloudNativePG with PostgreSQL 16:"
echo "  image: ${REGISTRY}/${IMAGE_NAME}:pg16.13"
echo
echo "# Use in CloudNativePG with PostgreSQL 17:"
echo "  image: ${REGISTRY}/${IMAGE_NAME}:pg17.9"
echo
echo "# Use in CloudNativePG with PostgreSQL 18 (default):"
echo "  image: ${REGISTRY}/${IMAGE_NAME}:pg18.1"
echo "  # or"
echo "  image: ${REGISTRY}/${IMAGE_NAME}:latest"

# Exit with error if any builds failed
if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
    exit 1
fi