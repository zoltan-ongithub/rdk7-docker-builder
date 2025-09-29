#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_TARGET="raspberrypi"
IMAGE_NAME="rdk7-builder"
CONTAINER_NAME="rdk7-builder"

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



show_usage() {
    cat << EOF
RDK-7 Docker Builder

Usage: $0 <command>

Commands:
    create_container  Build the Docker image with user mapping
    setup             Run generate-rdk-build-env and configure RDK target (outside container)
    run               Run the RDK build process (inside container)
    run dependency    Generate dependency graph instead of building (inside container)
    shell             Drop into a shell in the container
    help              Show this help

Examples:
    $0 create_container
    $0 setup              # Configure RDK environment
    $0 run                # Run build process
    $0 run dependency     # Generate dependency graph

EOF
}

create_container() {
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


# function: setup()
# arg 1: layer to be configured
# If no argument is supplied the user is asked to select one of the valid layers
setup() {
    print_info "Running RDK-7 setup (outside container)..."
    
    if [ -z "$1" ]
      then
         get_input "Enter layer to build (oss/vendor/middleware/application/image-assembler)" "$DEFAULT_LAYER" "LAYER"
      else
         LAYER=$1
     fi
    ./generate-rdk-build-env --layer $LAYER > build.env
}

run() {
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

case "${1:-help}" in
    create_container)
        create_container
        ;;
    setup)
        setup $2
        ;;
    run)
        if [ "$2" = "dependency" ]; then
            run_dependency
        else
            run
        fi
        ;;
    shell)
        shell
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_warning "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
