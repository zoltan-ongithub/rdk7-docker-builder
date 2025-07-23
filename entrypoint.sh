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

setup_git_config() {
    if [ -z "$(git config --global user.name)" ]; then
        if [ -f /workspace/.git_user ]; then
            GIT_USER=$(cat /workspace/.git_user)
        else
            print_info "Setting up git configuration..."
            read -p "Enter your git username: " GIT_USER
            echo "$GIT_USER" > /workspace/.git_user
        fi
        git config --global user.name "$GIT_USER"
    fi

    if [ -z "$(git config --global user.email)" ]; then
        if [ -f /workspace/.git_email ]; then
            GIT_EMAIL=$(cat /workspace/.git_email)
        else
            read -p "Enter your git email: " GIT_EMAIL
            echo "$GIT_EMAIL" > /workspace/.git_email
        fi
        git config --global user.email "$GIT_EMAIL"
    fi
}

setup_credentials() {
    if [ ! -f /workspace/.netrc ] && [ ! -f ~/.netrc ]; then
        print_info "Setting up RDK credentials..."
        print_info "You can skip this if you don't need RDK Central access"
        read -p "Do you want to setup RDK Central credentials? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter your RDK Central email: " RDK_EMAIL
            read -s -p "Enter your RDK Central PAT: " RDK_PAT
            echo
            
            cat > /workspace/.netrc << EOF
machine code.rdkcentral.com
    login $RDK_EMAIL
    password $RDK_PAT

machine github.com
    login $RDK_EMAIL
    password $RDK_PAT
EOF
            chmod 600 /workspace/.netrc
            cp /workspace/.netrc ~/.netrc
            print_success "Credentials saved to /workspace/.netrc"
        fi
    elif [ -f /workspace/.netrc ] && [ ! -f ~/.netrc ]; then
        cp /workspace/.netrc ~/.netrc
        chmod 600 ~/.netrc
    fi
}

build_oss_layer() {
    print_info "Building OSS layer..."
    
    # Create OSS layer directory
    OSS_DIR="/workspace/oss-layer"
    mkdir -p "$OSS_DIR"
    cd "$OSS_DIR"
    
    # Check if OSS layer is already set up
    if [ -d "rdke-oss-manifest" ]; then
        print_warning "OSS layer already exists, skipping initialization..."
    else
        print_info "Initializing OSS manifest..."
        repo init -u "$OSS_MANIFEST_URL" -b "refs/tags/$OSS_BRANCH" -m "$OSS_MANIFEST_FILE"
        repo sync --no-clone-bundle --no-tags
    fi
    
    print_info "Setting up OSS build environment..."
    print_info "Current directory: $(pwd)"
    print_info "Looking for setup-environment script..."
    
    print_info "OEROOT: $OEROOT"
    # Check if setup-environment script exists
    if [ -f "./scripts/setup-environment" ]; then
        print_info "Found setup-environment script"
    else
        print_error "setup-environment script not found in ./scripts/"
        print_info "Available files in current directory:"
        ls -la
        exit 1
    fi
    
    # Source the setup-environment script with the correct MACHINE
    # This script will set up the Yocto build environment and change to the build directory
    print_info "Sourcing setup-environment script with MACHINE=$MACHINE"
    
    # Debug: Check if repo is properly initialized
    print_info "Checking repo status..."
    if [ -d ".repo" ]; then
        print_info "Repo is initialized"
        print_info "Repo manifest: $(cat .repo/manifest.xml | head -5)"
    else
        print_error "Repo is not initialized"
        exit 1
    fi
    echo "RUNNING: MACHINE=$MACHINE source ./scripts/setup-environment"
    MACHINE="$MACHINE" source ./scripts/setup-environment
    
    print_info "Checking if bitbake is available..."
    if command -v bitbake >/dev/null 2>&1; then
        print_info "bitbake command found"
    else
        print_error "bitbake command not found after sourcing environment"
        print_info "PATH: $PATH"
        exit 1
    fi
    
    print_info "Building OSS layer packages..."
    bitbake lib32-packagegroup-oss-layer
    
    print_info "Creating OSS IPK feed..."
    mkdir -p "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/"
    rsync -av ./build-rdk-arm64/tmp/deploy/ipk/rdk-arm64-oss/ "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/"
    
    # Create package index
    if [ -f "./build-rdk-arm64/tmp/work/x86_64-linux/opkg-utils-native/0.5.0-r0/git/opkg-make-index" ]; then
        ./build-rdk-arm64/tmp/work/x86_64-linux/opkg-utils-native/0.5.0-r0/git/opkg-make-index "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/" > "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/Packages"
        gzip -c9 "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/Packages" > "/home/rdk/community_shared/rdk-arm64-oss/${OSS_BRANCH}/ipk/Packages.gz"
    fi
    
    print_success "OSS layer build completed!"
}

build_vendor_layer() {
    print_info "Building Vendor layer..."
    
    # Create vendor layer directory
    VENDOR_DIR="/workspace/vendor-layer"
    mkdir -p "$VENDOR_DIR"
    cd "$VENDOR_DIR"
    
    # Check if vendor layer is already set up
    if [ -d "vendor-manifest-raspberrypi" ]; then
        print_warning "Vendor layer already exists, skipping initialization..."
    else
        print_info "Initializing vendor manifest..."
        repo init -u "$VENDOR_MANIFEST_URL" -b "refs/tags/$MANIFEST_BRANCH" -m "$VENDOR_MANIFEST_FILE"
        repo sync --no-clone-bundle --no-tags
    fi
    
    # Configure OSS IPK feed
    print_info "Configuring OSS IPK feed..."
    sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"$OSS_IPK_PATH\"|" rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
    
    print_info "Setting up vendor build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment
    
    # Enable IPK feed deployment
    echo 'DEPLOY_IPK_FEED = "1"' >> conf/local.conf
    
    print_info "Building vendor layer packages..."
    bitbake lib32-packagegroup-vendor-layer
    
    print_info "Creating vendor IPK feed..."
    mkdir -p "/home/rdk/community_shared/raspberrypi4-64-rdke-vendor/${MANIFEST_BRANCH}/ipk/"
    rsync -av ./build-raspberrypi4-64-rdke/tmp/deploy/ipk/raspberrypi4-64-rdke-vendor/ "/home/rdk/community_shared/raspberrypi4-64-rdke-vendor/${MANIFEST_BRANCH}/ipk/"
    
    print_success "Vendor layer build completed!"
}

build_middleware_layer() {
    print_info "Building Middleware layer..."
    
    # Create middleware layer directory
    MW_DIR="/workspace/middleware-layer"
    mkdir -p "$MW_DIR"
    cd "$MW_DIR"
    
    # Check if middleware layer is already set up
    if [ -d "middleware-manifest-rdke" ]; then
        print_warning "Middleware layer already exists, skipping initialization..."
    else
        print_info "Initializing middleware manifest..."
        repo init -u "$MW_MANIFEST_URL" -b "refs/tags/$MANIFEST_BRANCH" -m "$MW_MANIFEST_FILE"
        repo sync --no-clone-bundle --no-tags
    fi
    
    # Configure IPK feeds
    print_info "Configuring IPK feeds..."
    sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"$OSS_IPK_PATH\"|" rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
    sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"$VENDOR_IPK_PATH\"|" rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
    
    print_info "Setting up middleware build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment
    
    # Enable IPK feed deployment
    echo 'DEPLOY_IPK_FEED = "1"' >> conf/local.conf
    
    print_info "Building middleware layer packages..."
    bitbake lib32-packagegroup-middleware-layer
    
    print_info "Creating middleware IPK feed..."
    mkdir -p "/home/rdk/community_shared/raspberrypi4-64-rdke-middleware/${MANIFEST_BRANCH}/ipk/"
    rsync -av ./build-raspberrypi4-64-rdke/tmp/deploy/ipk/raspberrypi4-64-rdke-middleware/ "/home/rdk/community_shared/raspberrypi4-64-rdke-middleware/${MANIFEST_BRANCH}/ipk/"
    
    print_success "Middleware layer build completed!"
}

build_application_layer() {
    print_info "Building Application layer..."
    
    # Create application layer directory
    APP_DIR="/workspace/application-layer"
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Check if application layer is already set up
    if [ -d "application-manifest-rdke" ]; then
        print_warning "Application layer already exists, skipping initialization..."
    else
        print_info "Initializing application manifest..."
        repo init -u "$APP_MANIFEST_URL" -b "refs/tags/$MANIFEST_BRANCH" -m "$APP_MANIFEST_FILE"
        repo sync --no-clone-bundle --no-tags
    fi
    
    # Configure IPK feeds
    print_info "Configuring IPK feeds..."
    sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"$OSS_IPK_PATH\"|" rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
    sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"$VENDOR_IPK_PATH\"|" rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
    sed -i "s|MW_IPK_SERVER_PATH = \".*\"|MW_IPK_SERVER_PATH = \"$MW_IPK_PATH\"|" rdke/middleware/meta-middleware-release/conf/machine/include/middleware.inc
    
    print_info "Setting up application build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment
    
    # Enable IPK feed deployment
    echo 'DEPLOY_IPK_FEED = "1"' >> conf/local.conf
    
    print_info "Building application layer packages..."
    bitbake lib32-packagegroup-application-layer
    
    print_info "Creating application IPK feed..."
    mkdir -p "/home/rdk/community_shared/raspberrypi4-64-rdke-application/${MANIFEST_BRANCH}/ipk/"
    rsync -av ./build-raspberrypi4-64-rdke/tmp/deploy/ipk/raspberrypi4-64-rdke-application/ "/home/rdk/community_shared/raspberrypi4-64-rdke-application/${MANIFEST_BRANCH}/ipk/"
    
    print_success "Application layer build completed!"
}

build_image_assembler() {
    print_info "Building Image Assembler..."
    
    # Create image assembler directory
    IA_DIR="/workspace/image-assembler-layer"
    mkdir -p "$IA_DIR"
    cd "$IA_DIR"
    
    # Check if image assembler is already set up
    if [ -d "image-assembler-manifest-rdke" ]; then
        print_warning "Image assembler already exists, skipping initialization..."
    else
        print_info "Initializing image assembler manifest..."
        repo init -u "$IA_MANIFEST_URL" -b "refs/tags/$MANIFEST_BRANCH" -m "$IA_MANIFEST_FILE"
        repo sync --no-clone-bundle --no-tags
    fi
    
    # Configure all IPK feeds
    print_info "Configuring IPK feeds..."
    sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"$OSS_IPK_PATH\"|" rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
    sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"$VENDOR_IPK_PATH\"|" rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
    sed -i "s|MW_IPK_SERVER_PATH = \".*\"|MW_IPK_SERVER_PATH = \"$MW_IPK_PATH\"|" rdke/middleware/meta-middleware-release/conf/machine/include/middleware.inc
    sed -i "s|APPLICATION_IPK_SERVER_PATH = \".*\"|APPLICATION_IPK_SERVER_PATH = \"$APP_IPK_PATH\"|" rdke/application/meta-application-release/conf/machine/include/application.inc
    
    print_info "Setting up image assembler build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment
    
    print_info "Building full stack image..."
    bitbake lib32-rdk-fullstack-image
    
    print_success "Image assembler build completed!"
    print_info "Final image will be in: ./build-raspberrypi4-64-rdke/tmp/deploy/images/raspberrypi4-64-rdke/"
}

run_build() {
    if [ ! -f /workspace/build.env ]; then
        print_error "No build.env found. Please run setup.sh outside the container first"
        exit 1
    fi
    
    print_info "Sourcing build environment..."
    source /workspace/build.env
    
    print_info "Building RDK-7 for layer: $LAYER"
    
    # Build layers based on selection
    case "$LAYER" in
        "oss")
            build_oss_layer
            ;;
        "vendor")
            build_oss_layer
            build_vendor_layer
            ;;
        "middleware")
            build_oss_layer
            build_vendor_layer
            build_middleware_layer
            ;;
        "application")
            build_oss_layer
            build_vendor_layer
            build_middleware_layer
            build_application_layer
            ;;
        "image-assembler")
            build_oss_layer
            build_vendor_layer
            build_middleware_layer
            build_application_layer
            build_image_assembler
            ;;
        *)
            print_error "Unsupported layer: $LAYER"
            exit 1
            ;;
    esac
    
    print_success "RDK-7 build completed for layer: $LAYER"
}

main() {
    print_info "RDK-7 Docker Builder Environment"
    print_info "Workspace: /workspace"
    print_info "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
    
    # Check if we have arguments (unsupervised mode)
    if [ $# -gt 0 ]; then
        print_info "Running in unsupervised mode"
        
        case "$1" in
            "build")
                run_build
                ;;
            "shell")
                exec /bin/bash
                ;;
            *)
                print_info "Executing command: $@"
                exec "$@"
                ;;
        esac
    else
        # Interactive mode
        print_info "Running in interactive mode"
        
        # Setup git and credentials if needed
        setup_git_config
        setup_credentials
        
        # Check if build.env exists
        if [ -f /workspace/build.env ]; then
            print_info "Build environment found. You can source it with:"
            print_info "  source build.env"
            print_info "Or run the build with:"
            print_info "  ./entrypoint.sh build"
        else
            print_warning "No build.env found. Please run setup.sh outside the container first"
        fi
        
        # Drop into shell
        print_info "Starting interactive shell..."
        print_info "Available commands:"
        print_info "  source build.env - Source the build environment (if available)"
        print_info "  ./entrypoint.sh build - Run the build process"
        print_info "  bitbake <target> - Run bitbake commands"
        print_info "  repo <command> - Run repo commands"
        print_info "  exit - Exit the container"
        echo
        
        exec /bin/bash
    fi
}

main "$@"
