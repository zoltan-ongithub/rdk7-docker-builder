#!/bin/bash

set -e  -x

# Color output functions
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

extract_bitbake_envs() {
    local recipe=$1
    [ -z "$recipe" ] && { echo "Error: Recipe name is required" >&2; return 1; }
    
    local env=$(bitbake -e "$recipe")
    BUILD_IPK_DIR=$(echo "$env" | grep "^DEPLOY_DIR_IPK=" | cut -d'=' -f2 | tr -d '"')
    IPK_ARCH=$(echo "$env" | grep "^SSTATE_PKGARCH=" | cut -d'=' -f2 | tr -d '"')
    PACKAGE_ARCH=$(echo "$env" | grep "^PACKAGE_ARCH=" | cut -d'=' -f2 | tr -d '"')
    OPKG_MAKE_INDEX=$(ls "$BUILDDIR"/tmp/work/x86_64-linux/opkg-utils-native/*/git/opkg-make-index 2>/dev/null | head -1)

    ls "$BUILDDIR"/tmp/work/x86_64-linux/opkg-utils-native/*/git/opkg-make-index
}

setup_git_config() {
    for config in "user.name:.git_user" "user.email:.git_email"; do
        IFS=':' read -r git_key file_name <<< "$config"
        if [ -z "$(git config --global $git_key)" ]; then
            if [ -f "/workspace/$file_name" ]; then
                value=$(cat "/workspace/$file_name")
            else
                read -p "Enter your git ${git_key#user.}: " value
                echo "$value" > "/workspace/$file_name"
            fi
            git config --global $git_key "$value"
        fi
    done
}

setup_credentials() {
    if [ ! -f /workspace/.netrc ] && [ ! -f ~/.netrc ]; then
        print_info "Setting up RDK credentials..."
        read -p "Setup RDK Central credentials? (y/N): " -n 1 -r
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
        cp /workspace/.netrc ~/.netrc && chmod 600 ~/.netrc
    fi
}

build_layer() {
    local layer_name=$1
    local layer_prefix=${1//-/_}
    layer_prefix=${layer_prefix^^}

    echo "Building layer: ${layer_name}"
    local manifest_url_var="${layer_prefix}_MANIFEST_URL"
    local manifest_file_var="${layer_prefix}_MANIFEST_FILE"
    local ipk_path_var="${layer_prefix}_IPK_PATH"
    local package_name="lib32-packagegroup-${layer_name}-layer"
    
    # Handle special cases
    case "$layer_name" in
        "oss")
            local branch_var="OSS_BRANCH"
            local manifest_dir="rdke-oss-manifest"
            ;;
        "vendor")
            local branch_var="MANIFEST_BRANCH"
            local manifest_dir="vendor-manifest-raspberrypi"
            ;;
        "image-assembler")
            local branch_var="MANIFEST_BRANCH"
            local manifest_dir="image-assembler-manifest-rdke"
            local package_name="lib32-rdk-fullstack-image"
            ;;
        *)
            local branch_var="MANIFEST_BRANCH"
            local manifest_dir="${layer_name}-manifest-rdke"
            ;;
    esac
    
    print_info "Building $layer_name layer..."
    
    # Setup directory
    local layer_dir="/workspace/${layer_name}-layer"
    mkdir -p "$layer_dir" && cd "$layer_dir"
    
    if [ ! -d "$manifest_dir" ]; then
        print_info "Initializing $layer_name manifest..."
        repo init -u "${!manifest_url_var}" -b "refs/tags/${!branch_var}" -m "${!manifest_file_var}"
        repo sync --no-clone-bundle --no-tags -j8
    else
        print_warning "$layer_name layer already exists, skipping initialization..."
    fi
    
    configure_ipk_feeds "$layer_name"
    
    print_info "Setting up $layer_name build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment $BUILD_DIR
    echo "BUILDDIR=" $BUILDDIR
    [ "$layer_name" != "oss" ] && echo 'DEPLOY_IPK_FEED = "1"' >> conf/local.conf
    
    print_info "Building $layer_name packages..."
    bitbake "$package_name"
    
    if [ "$layer_name" != "image-assembler" ]; then
        extract_bitbake_envs "$package_name"
        create_ipk_feed "$layer_name"
    else
        print_info "Final image will be in your IA build output."
    fi
    
    print_success "$layer_name layer build completed!"
}

# TODO: this needs to be simplified the IPK paths should be set using site.conf

configure_ipk_feeds() {
    local layer=$1
    case "$layer" in
        "oss") 
            ;;  # No dependencies
        "vendor")
            sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"file:/$OSS_IPK_PATH\"|" \
                rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
            ;;
        "middleware")
            sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"file:/$OSS_IPK_PATH\"|" \
                rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
            sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"file:/$VENDOR_IPK_PATH\"|" \
                rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
            ;;
        "application")
            sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"file:/$OSS_IPK_PATH\"|" \
                rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
            sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"file:/$VENDOR_IPK_PATH\"|" \
                rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
            sed -i "s|MW_IPK_SERVER_PATH = \".*\"|MW_IPK_SERVER_PATH = \"file:/$MIDDLEWARE_IPK_PATH\"|" \
                rdke/middleware/meta-middleware-release/conf/machine/include/middleware.inc
            ;;
        "image-assembler")
            sed -i "s|OSS_IPK_SERVER_PATH = \".*\"|OSS_IPK_SERVER_PATH = \"file:/$OSS_IPK_PATH\"|" \
                rdke/common/meta-oss-reference-release/conf/machine/include/oss.inc
            sed -i "s|VENDOR_IPK_SERVER_PATH = \".*\"|VENDOR_IPK_SERVER_PATH = \"file:/$VENDOR_IPK_PATH\"|" \
                rdke/vendor/meta-vendor-release/conf/machine/include/vendor.inc
            sed -i "s|MW_IPK_SERVER_PATH = \".*\"|MW_IPK_SERVER_PATH = \"file:/$MIDDLEWARE_IPK_PATH\"|" \
                rdke/middleware/meta-middleware-release/conf/machine/include/middleware.inc
            sed -i "s|APPLICATION_IPK_SERVER_PATH = \".*\"|APPLICATION_IPK_SERVER_PATH = \"file:/$APPLICATION_IPK_PATH\"|" \
                rdke/application/meta-application-release/conf/machine/include/application.inc
            ;;
    esac
}

create_ipk_feed() {
    local layer=$1
    local ipk_path_var="${layer^^}_IPK_PATH"
    local ipk_path="${!ipk_path_var}"
    
    print_info "Creating $layer IPK feed..."
    mkdir -p "$ipk_path"
    
    if [ "$layer" = "oss" ]; then
        # OSS layer has special handling
        if [ -f "$OPKG_MAKE_INDEX" ]; then
            print_info "Creating package index at $BUILD_IPK_DIR"
            "$OPKG_MAKE_INDEX" "$BUILD_IPK_DIR" > "$BUILD_IPK_DIR/Packages"
            (cd "$BUILD_IPK_DIR" && gzip -c9 Packages > Packages.gz)
            rsync -av "$BUILD_IPK_DIR/" "$ipk_path"
        else
            print_warning "opkg-make-index not found, skipping package index creation"
        fi
    else
        # Other layers
        rsync -av "$BUILD_IPK_DIR/$PACKAGE_ARCH/" "$ipk_path"
    fi
}

generate_dependency_graph() {
    local layer_name=$1
    local layer_prefix=${1//-/_}
    layer_prefix=${layer_prefix^^}

    local package_name="lib32-packagegroup-${layer_name}-layer"
    
    # Handle special cases
    case "$layer_name" in
        "image-assembler")
            local package_name="lib32-rdk-fullstack-image"
            ;;
    esac
    
    print_info "Generating dependency graph for $layer_name layer..."
    
    # Setup directory and environment
    local layer_dir="/workspace/${layer_name}-layer"
    cd "$layer_dir"
    
    print_info "Setting up $layer_name build environment..."
    MACHINE="$MACHINE" source ./scripts/setup-environment $BUILD_DIR
    
    print_info "Generating dependency graph for $package_name..."
    bitbake -g "$package_name"
    
    print_info "Creating reduced depdency graph"
    oe-depends-dot -r task-depends.dot
    print_info "Creadting package layer list: package-layers.txt"
    bitbake-layers show-recipes > package-layers.txt

    print_success "Dependency graph generation completed for layer: $layer_name"
}

run_dependency() {
    [ ! -f /workspace/build.env ] && {
        print_error "No build.env found. Please run setup first"
        exit 1
    }
    
    print_info "Sourcing build environment..."
    source /workspace/build.env
    print_info "Generating dependency graph for layer: $LAYER"
    
    case "$LAYER" in
        "oss"|"vendor"|"middleware"|"application"|"image-assembler")
            generate_dependency_graph "$LAYER"
            ;;
        *)
            print_error "Unsupported layer: $LAYER"
            exit 1
            ;;
    esac
}

run_build() {
    [ ! -f /workspace/build.env ] && {
        print_error "No build.env found. Please run setup first"
        exit 1
    }
    
    print_info "Sourcing build environment..."
    source /workspace/build.env
    print_info "Building RDK-7 for layer: $LAYER"
    
    case "$LAYER" in
        "oss"|"vendor"|"middleware"|"application"|"image-assembler")
            build_layer "$LAYER"
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
    
    if [ $# -gt 0 ]; then
        print_info "Running in unsupervised mode"
        case "$1" in
            "build") run_build ;;
            "dependency") run_dependency ;;
            "shell") exec /bin/bash ;;
            *) print_info "Executing command: $@"; exec "$@" ;;
        esac
    else
        print_info "Running in interactive mode"
        setup_git_config
        setup_credentials
        
        if [ -f /workspace/build.env ]; then
            print_info "Build environment found. You can source it with: source build.env"
            print_info "Or run the build with: ./entrypoint.sh build"
        else
            print_warning "No build.env found. Please run setup first"
        fi
        
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
