#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_TARGET="raspberrypi"
DEFAULT_LAYER="oss"
IMAGE_NAME="rdk7-builder"
CONTAINER_NAME="rdk7-builder"

# CLI variables
HEADLESS=false
LAYER=""
LAYER_REPOS=""

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

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



print_disclaimer() {
    echo -e "${YELLOW}============================================================================${NC}"
    echo -e "${YELLOW}DISCLAIMER: This is NOT an official RDK script.${NC}"
    echo -e "${YELLOW}This is a community-contributed tool for building RDK-7 layers in Docker.${NC}"
    echo -e "${YELLOW}Use at your own risk. For official RDK documentation and tools, visit:${NC}"
    echo -e "${YELLOW}https://wiki.rdkcentral.com${NC}"
    echo -e "${YELLOW}============================================================================${NC}"
    echo
}

show_usage() {
    print_disclaimer
    cat << EOF
RDK-7 Docker Builder (Unofficial Community Tool)

Usage: $0 [OPTIONS] <command>

Commands:
    create_container  Build the Docker image with user mapping
    setup             Run generate-rdk-build-env and configure RDK target (outside container)
    run               Run the RDK build process (inside container)
    run dependency    Generate dependency graph instead of building (inside container)
    shell             Drop into a shell in the container
    help              Show this help

Options:
    -h, --headless                     Run in headless mode (no interactive prompts)
    -l, --layer LAYER                  Specify the layer to build (oss/vendor/middleware/application/image-assembler)
    -r, --layer-repos REPOS            Specify repository types per layer (e.g., "oss:remote,vendor:local,...")

Examples:
    $0 create_container
    $0 setup                           # Interactive mode
    $0 -h -l oss setup                 # Headless mode, build OSS layer
    $0 -h -l application -r "oss:remote,vendor:remote,middleware:local,application:local" setup
    $0 run                             # Run build process
    $0 run dependency                  # Generate dependency graph

EOF
}

create_container() {
    print_disclaimer
    print_info "Building RDK-7 Docker image with user mapping..."
    
    local user_id=$(id -u)
    local group_id=$(id -g)
    
    docker build \
        --build-arg USER_ID="$user_id" \
        --build-arg GROUP_ID="$group_id" \
        --build-arg USERNAME="rdk" \
        -t "$IMAGE_NAME" .
    
    print_success "Docker image built: $IMAGE_NAME"
}


# Helper function to check if local IPK directory exists and has content
check_local_ipk_available() {
    local layer=$1
    local ipk_path=""
    
    # Read config to get the shared directory path
    local shared_dir=$(grep "shared-dir:" config.yaml | awk -F': ' '{print $2}' | tr -d '"' | envsubst)
    
    case "$layer" in
        "oss")
            ipk_path="$shared_dir/rdk-arm64-oss/4.6.2-community/ipk"
            ;;
        "vendor"|"middleware"|"application")
            ipk_path="$shared_dir/raspberrypi4-64-rdke-${layer}/RDK7-1.0.0/ipk"
            ;;
    esac
    
    if [ -d "$ipk_path" ] && [ "$(ls -A $ipk_path 2>/dev/null)" ]; then
        return 0  # Local available
    else
        return 1  # Local not available
    fi
}

# function: setup()
setup() {
    print_disclaimer
    print_info "Running RDK-7 setup (outside container)..."
    
    # Get layer if not provided via CLI
    if [ -z "$LAYER" ]; then
        if [ "$HEADLESS" = "true" ]; then
            LAYER="$DEFAULT_LAYER"
            print_info "Using default layer: $LAYER"
        else
            get_input "Enter layer to build (oss/vendor/middleware/application/image-assembler)" "$DEFAULT_LAYER" "LAYER"
        fi
    fi
    
    # Handle per-layer repository selection
    local layer_repos_arg=""
    if [ -n "$LAYER_REPOS" ]; then
        # Use provided layer repos from CLI
        layer_repos_arg="--layer-repos \"$LAYER_REPOS\""
    elif [ "$HEADLESS" != "true" ]; then
        # Interactive mode: check for local availability and ask
        local repo_config=""
        for layer in oss vendor middleware application; do
            local use_local=false
            if check_local_ipk_available "$layer"; then
                print_info "Local IPK packages available for $layer layer"
                get_input "Use local repository for $layer? (y/N)" "n" "USE_LOCAL"
                if [ "${USE_LOCAL,,}" = "y" ]; then
                    use_local=true
                fi
            fi
            
            if [ "$use_local" = "true" ]; then
                if [ -n "$repo_config" ]; then
                    repo_config="${repo_config},"
                fi
                repo_config="${repo_config}${layer}:local"
            else
                if [ -n "$repo_config" ]; then
                    repo_config="${repo_config},"
                fi
                repo_config="${repo_config}${layer}:remote"
            fi
        done
        
        if [ -n "$repo_config" ]; then
            layer_repos_arg="--layer-repos \"$repo_config\""
        fi
    fi
    
    # Generate build.env
    eval "./generate-rdk-build-env --layer $LAYER $layer_repos_arg > build.env"
    
    print_success "Setup completed for $LAYER layer"
}

run() {
    print_disclaimer
    print_info "Running RDK-7 build (inside container)..."
    
    # Check if build.env exists
    if [ ! -f "build.env" ]; then
        print_error "build.env not found. Please run '$0 setup' first"
        exit 1
    fi
    
    local user_id=$(id -u)
    local group_id=$(id -g)
    local workspace="$(pwd)"
    
    docker run --rm \
        --name "$CONTAINER_NAME" \
        --user "$user_id:$group_id" \
        -v "$workspace:/workspace" \
        -v "$HOME/.ssh:/home/rdk/.ssh:ro" \
        -v "$HOME/.gitconfig:/home/rdk/.gitconfig:ro" \
        -v "$HOME/.netrc:/home/rdk/.netrc:ro" \
        -v "$HOME/community_shared:/home/rdk/community_shared" \
        -e USER_ID="$user_id" \
        -e GROUP_ID="$group_id" \
        "$IMAGE_NAME" build
}

run_dependency() {
    print_info "Running RDK-7 dependency graph generation (inside container)..."
    
    # Check if build.env exists
    if [ ! -f "build.env" ]; then
        print_error "build.env not found. Please run '$0 setup' first"
        exit 1
    fi
    
    local user_id=$(id -u)
    local group_id=$(id -g)
    local workspace="$(pwd)"
    
    docker run --rm \
        --name "$CONTAINER_NAME" \
        --user "$user_id:$group_id" \
        -v "$workspace:/workspace" \
        -v "$HOME/.ssh:/home/rdk/.ssh:ro" \
        -v "$HOME/.gitconfig:/home/rdk/.gitconfig:ro" \
        -v "$HOME/.netrc:/home/rdk/.netrc:ro" \
        -v "$HOME/community_shared:/home/rdk/community_shared" \
        -e USER_ID="$user_id" \
        -e GROUP_ID="$group_id" \
        "$IMAGE_NAME" dependency
}

shell() {
    print_info "Starting shell in RDK-7 container..."
    
    local user_id=$(id -u)
    local group_id=$(id -g)
    local workspace="$(pwd)"
    
    docker run -it --rm \
        --user "$user_id:$group_id" \
        -v "$workspace:/workspace" \
        -v "$HOME/.ssh:/home/rdk/.ssh:ro" \
        -v "$HOME/.gitconfig:/home/rdk/.gitconfig:ro" \
        -v "$HOME/.netrc:/home/rdk/.netrc:ro" \
        -v "$HOME/community_shared:/home/rdk/community_shared" \
        -e USER_ID="$user_id" \
        -e GROUP_ID="$group_id" \
        "$IMAGE_NAME" shell
}

cleanup() {
    print_info "Received interrupt signal, cleaning up..."
    docker stop "$CONTAINER_NAME" >/dev/null
    exit 130
}

trap cleanup SIGINT SIGTERM

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--headless)
            HEADLESS=true
            shift
            ;;
        -l|--layer)
            LAYER="$2"
            shift 2
            ;;
        -r|--layer-repos)
            LAYER_REPOS="$2"
            shift 2
            ;;
        *)
            # This is the command
            COMMAND="$1"
            shift
            break
            ;;
    esac
done

# If no command was provided, show usage
if [ -z "$COMMAND" ]; then
    show_usage
    exit 0
fi

case "$COMMAND" in
    create_container)
        create_container
        ;;
    setup)
        setup
        ;;
    run)
        if [ "$1" = "dependency" ]; then
            run_dependency
        else
            run
        fi
        ;;
    shell)
        shell
        ;;
    help|--help)
        show_usage
        ;;
    *)
        print_warning "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
