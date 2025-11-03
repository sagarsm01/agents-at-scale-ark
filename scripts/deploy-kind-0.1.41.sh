#!/usr/bin/env bash

# Deploy ARK 0.1.41 to Kind cluster and open dashboard
# This script loads local Docker images into kind and deploys ARK

set -e -o pipefail

# Colors for output
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
white='\033[1;37m'
blue='\033[0;34m'
cyan='\033[0;36m'
nc='\033[0m'

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version from version.txt
VERSION=$(cat "$PROJECT_ROOT/version.txt" | tr -d '[:space:]')

# Default values
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
SKIP_IMAGE_LOAD="${SKIP_IMAGE_LOAD:-false}"

log_info() {
    echo -e "${blue}ℹ${nc} $1"
}

log_success() {
    echo -e "${green}✔${nc} $1"
}

log_error() {
    echo -e "${red}✗${nc} $1"
}

log_warning() {
    echo -e "${yellow}⚠${nc} $1"
}

log_section() {
    echo ""
    echo -e "${cyan}▶${nc} ${white}$1${nc}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check if kind is installed
    if ! command -v kind >/dev/null 2>&1; then
        log_error "Kind not found"
        echo "Please install kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
    log_success "Kind found"
    
    # Check if kind cluster exists
    if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_error "Kind cluster '${KIND_CLUSTER_NAME}' not found"
        echo "Please create a kind cluster first:"
        echo "  kind create cluster --name ${KIND_CLUSTER_NAME}"
        exit 1
    fi
    log_success "Kind cluster '${KIND_CLUSTER_NAME}' found"
    
    # Check if kubectl is configured
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Kubectl not configured or cluster not accessible"
        exit 1
    fi
    log_success "Kubectl configured"
    
    # Check if docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        exit 1
    fi
    log_success "Docker daemon running"
    
    # Check if ark CLI is installed
    if ! command -v ark >/dev/null 2>&1; then
        log_warning "Ark CLI not found in PATH"
        echo "Installing ark CLI..."
        cd "$PROJECT_ROOT/tools/ark-cli"
        npm link --force
        cd "$PROJECT_ROOT"
        log_success "Ark CLI installed"
    else
        log_success "Ark CLI found"
    fi
    
    log_success "All prerequisites met"
}

load_images_to_kind() {
    log_section "Loading Docker Images to Kind Cluster"
    
    # List of images to load
    local images=(
        "ark-api:${VERSION}"
        "ark-api-a2a:${VERSION}"
        "ark-cluster-memory:${VERSION}"
        "ark-controller:${VERSION}"
        "ark-dashboard:${VERSION}"
        "ark-evaluator:${VERSION}"
        "ark-mcp:${VERSION}"
        "executor-langchain:${VERSION}"
        "filesystem-mcp-server:${VERSION}"
    )
    
    local loaded_count=0
    local failed_count=0
    
    for image in "${images[@]}"; do
        # Check if image exists locally
        if ! docker image inspect "$image" >/dev/null 2>&1; then
            log_warning "Image not found locally: $image (skipping)"
            ((failed_count++))
            continue
        fi
        
        log_info "Loading $image into kind cluster..."
        if kind load docker-image "$image" --name "$KIND_CLUSTER_NAME" >/dev/null 2>&1; then
            log_success "Loaded $image"
            ((loaded_count++))
        else
            log_error "Failed to load $image"
            ((failed_count++))
        fi
    done
    
    echo ""
    log_info "Loaded $loaded_count images, $failed_count failed/skipped"
    
    if [ $failed_count -gt 0 ]; then
        log_warning "Some images were not loaded. Make sure all images are built."
    fi
}

deploy_ark() {
    log_section "Deploying ARK ${VERSION}"
    
    log_info "Installing ARK using ark CLI..."
    log_info "This will install:"
    log_info "  - cert-manager (if not already installed)"
    log_info "  - Gateway API CRDs"
    log_info "  - ark-controller"
    log_info "  - ark-api, ark-api-a2a"
    log_info "  - ark-dashboard"
    log_info "  - ark-evaluator"
    log_info "  - ark-mcp"
    log_info "  - localhost-gateway"
    echo ""
    
    # Use ark install with non-interactive mode
    if ark install --yes 2>&1; then
        log_success "ARK deployment initiated"
    else
        log_error "ARK deployment failed"
        return 1
    fi
    
    log_info "Waiting for ARK services to be ready..."
    sleep 5
    
    # Wait for controller to be ready
    log_info "Waiting for ark-controller to be ready..."
    kubectl wait --for=condition=ready pod \
        -l control-plane=controller-manager \
        -n ark-system \
        --timeout=300s || {
        log_warning "Controller may still be starting"
    }
}

open_dashboard() {
    log_section "Opening ARK Dashboard"
    
    log_info "Starting dashboard port-forward..."
    
    # Check if dashboard is available
    if ! kubectl get svc -n default ark-dashboard >/dev/null 2>&1; then
        log_warning "Dashboard service not found. It may still be deploying."
        log_info "You can manually open the dashboard with: ${white}ark dashboard${nc}"
        return
    fi
    
    log_info "Opening dashboard in browser..."
    if ark dashboard >/dev/null 2>&1 & then
        log_success "Dashboard opening in browser"
        log_info "Dashboard will be available at the URL shown above"
        log_info "To stop port-forwarding, press Ctrl+C or run: ${white}pkill -f 'ark dashboard'${nc}"
    else
        log_warning "Failed to open dashboard automatically"
        log_info "Run manually: ${white}ark dashboard${nc}"
    fi
}

show_status() {
    log_section "ARK Deployment Status"
    
    echo ""
    log_info "ARK Version: ${white}${VERSION}${nc}"
    echo ""
    
    log_info "Checking Helm releases..."
    helm list -A | grep -E "ark|NAME" || echo "No ARK releases found"
    
    echo ""
    log_info "Checking pods in ark-system namespace..."
    kubectl get pods -n ark-system 2>/dev/null || echo "ark-system namespace not found"
    
    echo ""
    log_info "Checking ARK services..."
    kubectl get pods -n default -l app.kubernetes.io/name=ark 2>/dev/null || echo "No ARK services found"
    
    echo ""
    log_info "To check ARK resources:"
    echo "  ${white}kubectl get agents,teams,models,queries -A${nc}"
    echo ""
    log_info "To view dashboard:"
    echo "  ${white}ark dashboard${nc}"
}

main() {
    echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
    echo -e "${cyan}║${nc}                    ${white}ARK ${VERSION} Kind Deployment${nc}                            ${cyan}║${nc}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Load images to kind
    if [ "$SKIP_IMAGE_LOAD" != "true" ]; then
        load_images_to_kind
    else
        log_info "Skipping image load (SKIP_IMAGE_LOAD=true)"
    fi
    
    # Deploy ARK
    deploy_ark
    
    # Show status
    show_status
    
    # Open dashboard
    open_dashboard
    
    echo ""
    log_success "╔════════════════════════════════════════════════════════════════════════════════╗"
    log_success "║                       Deployment Complete!                                    ║"
    log_success "╚════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Next steps:"
    echo "  1. Configure a model: ${white}ark models create default${nc}"
    echo "  2. Open dashboard: ${white}ark dashboard${nc}"
    echo "  3. Create your first agent: ${white}ark generate agent${nc}"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-image-load)
                SKIP_IMAGE_LOAD=true
                shift
                ;;
            --cluster-name)
                KIND_CLUSTER_NAME="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Deploy ARK ${VERSION} to Kind cluster

Usage: $0 [OPTIONS]

Options:
    --skip-image-load      Skip loading images to kind (useful if already loaded)
    --cluster-name NAME    Kind cluster name (default: kind)
    -h, --help            Show this help

Environment Variables:
    KIND_CLUSTER_NAME      Name of kind cluster (default: kind)
    SKIP_IMAGE_LOAD        Skip image loading (default: false)

Examples:
    $0
    $0 --cluster-name my-cluster
    $0 --skip-image-load
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Parse arguments first
parse_args "$@"

# Run main function
main
