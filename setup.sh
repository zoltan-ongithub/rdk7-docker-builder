#!/bin/bash

set -e

print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

DEFAULT_TARGET="raspberrypi"
DEFAULT_LAYER="oss"
DEFAULT_MANIFEST_BRANCH="RDK7-1.0.0"
DEFAULT_OSS_BRANCH="4.6.2-community"

get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        if [ -z "$input" ]; then
            input="$default"
        fi
    else
        read -p "$prompt: " input
    fi
    
    eval "$var_name='$input'"
}

generate_build_env() {
    print_info "Generating build environment configuration..."
    
    # Create shared directory for IPK feeds on host
    mkdir -p "${HOME}/community_shared"
    
    cat > build.env << EOF
# RDK-7 Build Environment Configuration
# Generated on $(date)

# Target configuration
export TARGET="$TARGET"
export LAYER="$LAYER"
export MANIFEST_BRANCH="$MANIFEST_BRANCH"
export OSS_BRANCH="$OSS_BRANCH"

# Build environment - use container paths
export MACHINE="raspberrypi4-64-rdke"

# Layer directories
export OSS_DIR="/workspace/oss-layer"
export VENDOR_DIR="/workspace/vendor-layer"
export MW_DIR="/workspace/middleware-layer"
export APP_DIR="/workspace/application-layer"
export IA_DIR="/workspace/image-assembler-layer"

# IPK feed paths - use container paths
export OSS_IPK_PATH="file:/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/"
export VENDOR_IPK_PATH="file:/home/rdk/community_shared/raspberrypi4-64-rdke-vendor/${MANIFEST_BRANCH}/ipk/"
export MW_IPK_PATH="file:/home/rdk/community_shared/raspberrypi4-64-rdke-middleware/${MANIFEST_BRANCH}/ipk/"
export APP_IPK_PATH="file:/home/rdk/community_shared/raspberrypi4-64-rdke-application/${MANIFEST_BRANCH}/ipk/"

# Layer-specific build commands and directories
case "\$LAYER" in
    "oss")
        export BUILD_COMMAND="bitbake lib32-packagegroup-oss-layer"
        export BUILD_DIR="build-rdk-arm64"
        export MACHINE="rdk-arm64"
        export WORK_DIR="\$OSS_DIR"
        ;;
    "vendor")
        export BUILD_COMMAND="bitbake lib32-packagegroup-vendor-layer"
        export BUILD_DIR="build-raspberrypi4-64-rdke"
        export WORK_DIR="\$VENDOR_DIR"
        ;;
    "middleware")
        export BUILD_COMMAND="bitbake lib32-packagegroup-middleware-layer"
        export BUILD_DIR="build-raspberrypi4-64-rdke"
        export WORK_DIR="\$MW_DIR"
        ;;
    "application")
        export BUILD_COMMAND="bitbake lib32-packagegroup-application-layer"
        export BUILD_DIR="build-raspberrypi4-64-rdke"
        export WORK_DIR="\$APP_DIR"
        ;;
    "image-assembler")
        export BUILD_COMMAND="bitbake lib32-rdk-fullstack-image"
        export BUILD_DIR="build-raspberrypi4-64-rdke"
        export WORK_DIR="\$IA_DIR"
        ;;
esac

export BUILDDIR="\$WORK_DIR/\$BUILD_DIR"

# Manifest URLs and files
export OSS_MANIFEST_URL="https://github.com/rdkcentral/rdke-oss-manifest/"
export OSS_MANIFEST_FILE="rdk-arm.xml"
export VENDOR_MANIFEST_URL="https://github.com/rdkcentral/vendor-manifest-raspberrypi/"
export VENDOR_MANIFEST_FILE="rdke-raspberrypi.xml"
export MW_MANIFEST_URL="https://github.com/rdkcentral/middleware-manifest-rdke/"
export MW_MANIFEST_FILE="raspberrypi4-64.xml"
export APP_MANIFEST_URL="https://github.com/rdkcentral/application-manifest-rdke/"
export APP_MANIFEST_FILE="raspberrypi4-64.xml"
export IA_MANIFEST_URL="https://github.com/rdkcentral/image-assembler-manifest-rdke/"
export IA_MANIFEST_FILE="raspberrypi4-64.xml"

echo "RDK-7 build environment loaded for \$TARGET/\$LAYER"
echo "Work directory: \$WORK_DIR"
echo "Build directory: \$BUILDDIR"
echo "Machine: \$MACHINE"
echo "Build command: \$BUILD_COMMAND"
EOF
    
    print_success "Build environment configuration saved to build.env"
    print_info "IPK feeds directory created: ${HOME}/community_shared"
}

main() {
    print_info "RDK-7 Setup Script"
    print_info "This script will configure the RDK-7 layered build environment for Raspberry Pi 4"
    
    # Check if we're in the right directory
    if [ ! -f "setup.sh" ]; then
        print_error "Please run this script from the workspace root directory"
        exit 1
    fi
    
    # Get configuration
    get_input "Enter target platform" "$DEFAULT_TARGET" "TARGET"
    get_input "Enter layer to build (oss/vendor/middleware/application/image-assembler)" "$DEFAULT_LAYER" "LAYER"
    get_input "Enter manifest branch/tag" "$DEFAULT_MANIFEST_BRANCH" "MANIFEST_BRANCH"
    get_input "Enter OSS branch/tag" "$DEFAULT_OSS_BRANCH" "OSS_BRANCH"
    
    print_info "Target: $TARGET"
    print_info "Layer: $LAYER"
    print_info "Manifest Branch: $MANIFEST_BRANCH"
    print_info "OSS Branch: $OSS_BRANCH"
    
    # Generate build environment file
    generate_build_env
    
    print_success "Setup completed successfully!"
    print_info "Configuration saved to build.env"
    print_info "Next steps:"
    print_info "1. Review the generated build.env file"
    print_info "2. Run: ./rdk7-docker.sh start    # For interactive development"
    print_info "3. Run: ./rdk7-docker.sh run      # For automated build"
    print_info "4. IPK feeds will be stored in: ${HOME}/community_shared/ (persistent across container restarts)"
}

main "$@" 
