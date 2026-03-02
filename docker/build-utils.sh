#!/bin/bash

# Utility functions

# Extract extension version from Cargo.toml
get_extension_version() {
    local cargo_toml_path="${1:-../Cargo.toml}"
    if [[ -f "$cargo_toml_path" ]]; then
        grep '^version = ' "$cargo_toml_path" | head -n1 | cut -d'"' -f2
    else
        echo "1.0.0"
    fi
}

get_distro_version() {
    echo "scratch"
}

# Generate full image tag following the pattern:
# <extension-name>:<ext_version>-pg<pg_version>-<platform>-<distro>
generate_image_tag() {
    local registry="$1"
    local extension_name="$2"
    local ext_version="$3"
    local pg_version="$4"
    local distro="$5"
    local arch="${6:-}"
    
    if [[ -n "$arch" ]]; then
        # Convert architecture to platform naming
        local platform
        case "$arch" in
            "amd64") platform="linux-amd64" ;;
            "arm64") platform="linux-arm64" ;;
            "386") platform="linux-386" ;;
            *) platform="linux-${arch}" ;;
        esac
        echo "${registry}/${extension_name}:${ext_version}-pg${pg_version}-${platform}-${distro}"
    else
        echo "${registry}/${extension_name}:${ext_version}-pg${pg_version}-${distro}"
    fi
}

# Generate compatibility tags (for backward compatibility)
generate_compatibility_tags() {
    local registry="$1"
    local image_name="$2"  # e.g., "pgcardano-extension" 
    local pg_version_full="$3"
    local pg_version="$4"
    local arch="${5:-}"
    
    local tags=()
    if [[ -n "$arch" ]]; then
        # Convert architecture to platform naming
        local platform
        case "$arch" in
            "amd64") platform="linux-amd64" ;;
            "arm64") platform="linux-arm64" ;;
            "386") platform="linux-386" ;;
            *) platform="linux-${arch}" ;;
        esac
        tags+=("${registry}/${image_name}:pg${pg_version_full}-${platform}")
        tags+=("${registry}/${image_name}:pg${pg_version}-${platform}")
    else
        tags+=("${registry}/${image_name}:pg${pg_version_full}")
        tags+=("${registry}/${image_name}:pg${pg_version}")
    fi
    
    echo "${tags[@]}"
}

generate_latest_tag() {
    local registry="$1"
    local extension_name="$2"
    local pg_version_full="$3"
    local arch="${4:-}"
    
    if [[ "$pg_version_full" == "18.1" ]]; then
        if [[ -n "$arch" ]]; then
            # Convert architecture to platform naming
            local platform
            case "$arch" in
                "amd64") platform="linux-amd64" ;;
                "arm64") platform="linux-arm64" ;;
                "386") platform="linux-386" ;;
                *) platform="linux-${arch}" ;;
            esac
            echo "${registry}/${extension_name}:latest-${platform}"
        else
            echo "${registry}/${extension_name}:latest"
        fi
    fi
}

validate_build_params() {
    local registry="$1"
    local extension_name="$2"
    local pg_version="$3"
    
    if [[ -z "$registry" ]]; then
        echo "ERROR: Registry not specified"
        return 1
    fi
    
    if [[ -z "$extension_name" ]]; then
        echo "ERROR: Extension name not specified"
        return 1
    fi
    
    if [[ -z "$pg_version" ]]; then
        echo "ERROR: PostgreSQL version not specified"
        return 1
    fi
    
    return 0
}

get_pg_version_full() {
    local pg_major="$1"
    case "$pg_major" in
        "16") echo "16.13" ;;
        "17") echo "17.9" ;;
        "18") echo "18.1" ;;
        *) echo "$pg_major.0" ;;
    esac
}