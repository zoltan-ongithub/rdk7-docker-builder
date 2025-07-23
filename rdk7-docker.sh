#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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


show_usage() {
    cat << EOF
RDK-7 Docker Builder

Usage: $0 <command>

Commands:
    build       Build the Docker image with user mapping
    start       Start interactive development environment
    setup       Run setup.sh to configure RDK target (outside container)
    run         Run the RDK build process (inside container)
    shell       Drop into a shell in the container
    stop        Stop the container
    help        Show this help

Examples:
    $0 build
    $0 setup    # Configure RDK environment
    $0 start    # Interactive development
    $0 run      # Run build process

EOF
}

build() {
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

start() {
    print_info "Starting RDK-7 development environment..."
    
    local user_id=$(id -u)
    local group_id=$(id -g)
    local workspace="$(pwd)"
    
    # Stop existing container if running
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    
    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        --user "$user_id:$group_id" \
        -v "$workspace:/workspace" \
        -v "$HOME/.ssh:/home/rdk/.ssh:ro" \
        -v "$HOME/.gitconfig:/home/rdk/.gitconfig:ro" \
        -v "$HOME/.netrc:/home/rdk/.netrc:ro" \
        -v "$HOME/community_shared:/home/rdk/community_shared" \
        -e USER_ID="$user_id" \
        -e GROUP_ID="$group_id" \
        "$IMAGE_NAME"
}

setup() {
    print_info "Running RDK-7 setup (outside container)..."
    
    # Check if setup.sh exists
    if [ ! -f "setup.sh" ]; then
        print_error "setup.sh not found in current directory"
        exit 1
    fi
    
    # Create IPK feeds directory on host
    mkdir -p "$HOME/community_shared"
    
    # Run setup.sh directly (outside container)
    print_info "Executing setup.sh..."
    bash setup.sh
    
    if [ $? -eq 0 ]; then
        print_success "Setup completed successfully!"
        print_info "You can now run:"
        print_info "  $0 start    # Start interactive development"
        print_info "  $0 run      # Run the build process"
    else
        print_error "Setup failed"
        exit 1
    fi
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

stop() {
    print_info "Stopping RDK-7 container..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    print_success "Container stopped"
}

case "${1:-help}" in
    build)
        build
        ;;
    start)
        start
        ;;
    setup)
        setup
        ;;
    run)
        run
        ;;
    shell)
        shell
        ;;
    stop)
        stop
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