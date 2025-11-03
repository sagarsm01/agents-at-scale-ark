#!/usr/bin/env bash

# Build Docker images for airgapped environments
# This script builds service images with configurable platforms and saves them for offline deployment

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
PLATFORM="linux/amd64"
OUTPUT_DIR="$PROJECT_ROOT/airgap-images"
SAVE_IMAGES=false
BUILD_SDK=true
SELECTED_SERVICES=()
LIST_SERVICES=false
ALL_SERVICES=false

# Service definitions (compatible with bash 3.x)
# Format: "service-name|path-to-service|dockerfile-name|image-name|needs-sdk"
SERVICES_DATA="
ark-api|services/ark-api|Dockerfile|ark-api|true
ark-api-a2a|services/ark-api-a2a|Dockerfile|ark-api-a2a|true
ark-cluster-memory|services/ark-cluster-memory|Dockerfile|ark-cluster-memory|false
ark-controller|ark|Dockerfile|ark-controller|false
ark-dashboard|services/ark-dashboard|Dockerfile|ark-dashboard|false
ark-evaluator|services/ark-evaluator|Dockerfile|ark-evaluator|true
ark-mcp|services/ark-mcp|Dockerfile|ark-mcp|true
executor-langchain|services/executor-langchain|Dockerfile|executor-langchain|true
mcp-filesystem|mcp/filesystem-mcp|Dockerfile|filesystem-mcp-server|false
"

# Get service info by name
get_service_info() {
    local service_name="$1"
    echo "$SERVICES_DATA" | grep "^${service_name}|" | head -n1
}

# Get all service names
get_all_services() {
    echo "$SERVICES_DATA" | grep -v "^$" | cut -d'|' -f1
}

usage() {
    cat << EOF
${white}Build Docker images for airgapped environments${nc}

${cyan}Usage:${nc} $0 [OPTIONS]

${cyan}Modes:${nc}
    ${white}Interactive Mode:${nc}  Run without service flags to select services interactively
    ${white}CLI Mode:${nc}         Use -s/--service or -a/--all to specify services directly

${cyan}Options:${nc}
    -s, --service NAME         Build specific service (can be used multiple times)
    -a, --all                  Build all services
    -l, --list                 List all available services
    -p, --platform PLATFORM    Target platform (default: linux/amd64)
                               Examples: linux/amd64, linux/arm64, linux/arm64/v8
    --save                     Save images as tar files for airgapped deployment
    -o, --output DIR           Output directory for saved images (default: ./airgap-images)
    --no-sdk                   Skip building ark-sdk (useful if already built)
    -v, --version VERSION      Override version tag (default: from version.txt)
    -h, --help                 Show this help

${cyan}Available Services:${nc}
EOF
    while IFS='|' read -r svc path dockerfile image needs_sdk; do
        if [ -n "$svc" ]; then
            printf "    ${white}%-20s${nc} %s\n" "$svc" "$path"
        fi
    done <<< "$SERVICES_DATA"
    
    cat << EOF

${cyan}Platform Options:${nc}
    linux/amd64       - Standard x86_64 architecture (Intel/AMD)
    linux/arm64       - ARM 64-bit (Apple Silicon, AWS Graviton)
    linux/arm64/v8    - ARMv8 64-bit

${cyan}Examples:${nc}
    # Interactive mode - select services, save options, and platform
    $0

    # Build a single service for amd64
    $0 --service ark-api-a2a

    # Build multiple services
    $0 -s ark-api -s ark-api-a2a

    # Build all services and save as tar files
    $0 --all --save

    # Build for ARM64 architecture
    $0 -s ark-api-a2a --platform linux/arm64

    # Build and save with custom output directory
    $0 -s ark-api-a2a --save -o /path/to/export

    # List all available services
    $0 --list

    # Build without rebuilding SDK (if already built)
    $0 -s ark-api-a2a --no-sdk

${cyan}Interactive Mode Features:${nc}
    ${white}Service Selection:${nc}
      • Type numbers and press SPACE to toggle: ${white}1 3 5${nc}
      • Press ENTER to finalize selection
      • Type ${white}all${nc} to select everything
      • Type ${white}clear${nc} to deselect all
      • Type ${white}q${nc} to quit
    
    ${white}Build Options:${nc}
      • Choose whether to save images as tar files
      • Specify custom output directory
      • Select target platform (amd64, arm64, etc.)

${cyan}Airgapped Deployment Workflow:${nc}
    1. Build images with --save flag:
       ${white}$0 --all --save${nc}
    
    2. Transfer the ${white}airgap-images/${nc} directory to target environment
    
    3. Load images on target system:
       ${white}for img in airgap-images/*.tar; do docker load -i \$img; done${nc}

${cyan}Notes:${nc}
    - Version is automatically read from ${white}version.txt${nc} (current: ${white}$VERSION${nc})
    - Services requiring ark-sdk will trigger SDK build automatically
    - All images are tagged with the version from version.txt
    - Saved images are placed in timestamped subdirectories

EOF
}

list_services() {
    echo -e "${cyan}Available Services:${nc}"
    echo ""
    printf "${white}%-20s %-30s %-20s %s${nc}\n" "SERVICE" "PATH" "IMAGE" "NEEDS SDK"
    echo "--------------------------------------------------------------------------------"
    local count=0
    while IFS='|' read -r svc path dockerfile image needs_sdk; do
        if [ -n "$svc" ]; then
            printf "%-20s %-30s %-20s %s\n" "$svc" "$path" "$image" "$needs_sdk"
            ((count++))
        fi
    done <<< "$SERVICES_DATA"
    echo ""
    echo -e "Total services: ${white}${count}${nc}"
}

interactive_service_selection() {
    echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
    echo -e "${cyan}║${nc}                       ${white}Select Services to Build${nc}                              ${cyan}║${nc}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
    echo ""
    
    # Build array of services
    local -a service_list=()
    local -a service_names=()
    local -a service_selected=()
    local index=1
    
    while IFS='|' read -r svc path dockerfile image needs_sdk; do
        if [ -n "$svc" ]; then
            service_list+=("$svc|$path|$needs_sdk")
            service_names+=("$svc")
            service_selected+=(0)  # 0 = not selected, 1 = selected
        fi
    done <<< "$SERVICES_DATA"
    
    # Display services with numbers
    echo -e "${white}Available Services:${nc}"
    echo ""
    for i in "${!service_list[@]}"; do
        local num=$((i + 1))
        IFS='|' read -r svc path needs_sdk <<< "${service_list[$i]}"
        local sdk_label=""
        if [ "$needs_sdk" = "true" ]; then
            sdk_label="${yellow}[needs SDK]${nc}"
        fi
        printf "  ${white}%2d${nc}. %-25s %-35s %s\n" "$num" "$svc" "$path" "$sdk_label"
    done
    echo ""
    echo -e "${cyan}Selection Methods:${nc}"
    echo -e "  ${white}Method 1 - Numbers:${nc}"
    echo -e "    • Enter service numbers separated by spaces (e.g., ${white}1 3 5${nc})"
    echo -e "    • Press ENTER after typing numbers"
    echo ""
    echo -e "  ${white}Method 2 - Space Selection:${nc}"
    echo -e "    • Type numbers and press SPACE to toggle (e.g., ${white}1 space 3 space 5${nc})"
    echo -e "    • Selected services will be shown with ${green}✓${nc}"
    echo -e "    • Press ENTER when done"
    echo ""
    echo -e "  ${white}Quick Options:${nc}"
    echo -e "    • Type ${white}all${nc} to select all services"
    echo -e "    • Type ${white}clear${nc} to deselect all"
    echo -e "    • Type ${white}q${nc} or ${white}quit${nc} to cancel"
    echo ""
    
    # Interactive selection loop
    local selected_services=()
    local input_buffer=""
    
    while true; do
        # Show current selection status if any services are selected
        local any_selected=false
        for sel in "${service_selected[@]}"; do
            if [ "$sel" = "1" ]; then
                any_selected=true
                break
            fi
        done
        
        if [ "$any_selected" = true ]; then
            echo -ne "\r${cyan}Currently selected:${nc} "
            for i in "${!service_names[@]}"; do
                if [ "${service_selected[$i]}" = "1" ]; then
                    echo -ne "${green}${service_names[$i]}${nc} "
                fi
            done
            echo -ne "                    \r"
        fi
        
        read -p "Select services: " selection
        
        # Handle quit
        if [[ "$selection" =~ ^[Qq](uit)?$ ]]; then
            log_warning "Selection cancelled"
            exit 0
        fi
        
        # Handle clear
        if [[ "$selection" =~ ^[Cc]lear$ ]]; then
            for i in "${!service_selected[@]}"; do
                service_selected[$i]=0
            done
            echo -e "${yellow}All selections cleared${nc}"
            continue
        fi
        
        # Handle 'all'
        if [[ "$selection" =~ ^[Aa]ll$ ]]; then
            for i in "${!service_selected[@]}"; do
                service_selected[$i]=1
            done
            echo -e "${green}All services selected${nc}"
            break
        fi
        
        # Handle empty input - finalize selection
        if [ -z "$selection" ]; then
            # Check if any services selected
            selected_services=()
            for i in "${!service_names[@]}"; do
                if [ "${service_selected[$i]}" = "1" ]; then
                    selected_services+=("${service_names[$i]}")
                fi
            done
            
            if [ ${#selected_services[@]} -eq 0 ]; then
                echo -e "${red}Error:${nc} No services selected. Try again or type 'q' to quit."
                continue
            fi
            break
        fi
        
        # Parse numbers (both space-separated toggle and regular selection)
        local valid=true
        local temp_selected=()
        
        for num in $selection; do
            # Check if it's a number
            if ! [[ "$num" =~ ^[0-9]+$ ]]; then
                echo -e "${red}Error:${nc} '$num' is not a valid number"
                valid=false
                break
            fi
            
            # Check if number is in range
            local idx=$((num - 1))
            if [ $idx -lt 0 ] || [ $idx -ge ${#service_names[@]} ]; then
                echo -e "${red}Error:${nc} '$num' is out of range (1-${#service_names[@]})"
                valid=false
                break
            fi
            
            temp_selected+=($idx)
        done
        
        if [ "$valid" = true ]; then
            # Toggle or select services
            for idx in "${temp_selected[@]}"; do
                if [ "${service_selected[$idx]}" = "1" ]; then
                    service_selected[$idx]=0
                    echo -e "  ${yellow}−${nc} Deselected: ${service_names[$idx]}"
                else
                    service_selected[$idx]=1
                    echo -e "  ${green}✓${nc} Selected: ${service_names[$idx]}"
                fi
            done
            
            # If user entered numbers, they might want to finalize or continue
            echo ""
            echo -e "${cyan}Options:${nc} Add more numbers, press ENTER to continue, or type 'clear' to reset"
        fi
    done
    
    # Build final selection list
    selected_services=()
    for i in "${!service_names[@]}"; do
        if [ "${service_selected[$i]}" = "1" ]; then
            selected_services+=("${service_names[$i]}")
        fi
    done
    
    # Display final selection
    echo ""
    echo -e "${green}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
    echo -e "${green}║${nc}                     ${white}Selected Services (${#selected_services[@]})${nc}                                    ${green}║${nc}"
    echo -e "${green}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
    for svc in "${selected_services[@]}"; do
        echo -e "  ${green}✔${nc} $svc"
    done
    echo ""
    
    # Ask about saving images
    echo -e "${cyan}Build Configuration:${nc}"
    read -p "Save images as tar files for airgapped deployment? (y/N): " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        SAVE_IMAGES=true
        echo -e "${green}✓${nc} Images will be saved as tar files"
        
        # Ask for custom output directory
        read -p "Custom output directory? (press ENTER for default: ./airgap-images): " output_choice
        if [ -n "$output_choice" ]; then
            OUTPUT_DIR="$output_choice"
            echo -e "${green}✓${nc} Output directory: $OUTPUT_DIR"
        fi
    else
        echo -e "${blue}ℹ${nc} Images will not be saved (Docker cache only)"
    fi
    echo ""
    
    # Ask about platform
    read -p "Build platform? (press ENTER for default: linux/amd64): " platform_choice
    if [ -n "$platform_choice" ]; then
        PLATFORM="$platform_choice"
        echo -e "${green}✓${nc} Platform: $PLATFORM"
    else
        echo -e "${blue}ℹ${nc} Platform: $PLATFORM (default)"
    fi
    echo ""
    
    # Return selected services
    for svc in "${selected_services[@]}"; do
        SELECTED_SERVICES+=("$svc")
    done
}

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
    
    # Check if docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker not found"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    log_success "Docker found"
    
    # Check if docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        echo "Please start Docker daemon"
        exit 1
    fi
    log_success "Docker daemon running"
    
    # Check if make is available (for building SDK)
    if [ "$BUILD_SDK" = true ] && ! command -v make >/dev/null 2>&1; then
        log_error "Make not found (required for building SDK)"
        exit 1
    fi
    
    # Check if version.txt exists
    if [ ! -f "$PROJECT_ROOT/version.txt" ]; then
        log_error "version.txt not found at $PROJECT_ROOT"
        exit 1
    fi
    log_success "Version: $VERSION"
    
    log_success "All prerequisites met"
}

build_ark_sdk() {
    log_section "Building ARK SDK"
    
    # Check if SDK is already built
    SDK_WHEEL="$PROJECT_ROOT/out/ark-sdk/py-sdk/dist/ark_sdk-${VERSION}-py3-none-any.whl"
    if [ -f "$SDK_WHEEL" ]; then
        log_info "SDK wheel already exists: $SDK_WHEEL"
        read -p "Rebuild SDK? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping SDK build"
            return 0
        fi
    fi
    
    log_info "Building ark-sdk wheel..."
    cd "$PROJECT_ROOT"
    make ark-sdk-build
    
    if [ ! -f "$SDK_WHEEL" ]; then
        log_error "SDK build failed - wheel not found"
        exit 1
    fi
    
    log_success "SDK built successfully: $SDK_WHEEL"
}

build_service() {
    local service_name="$1"
    local service_path="$2"
    local dockerfile_name="$3"
    local image_name="$4"
    local needs_sdk="$5"
    
    log_section "Building Service: $service_name"
    
    local service_dir="$PROJECT_ROOT/$service_path"
    
    # Prefer Dockerfile.airgap if it exists, otherwise use specified dockerfile
    local airgap_dockerfile="$service_dir/Dockerfile.airgap"
    if [ -f "$airgap_dockerfile" ]; then
        local dockerfile="$airgap_dockerfile"
        dockerfile_name="Dockerfile.airgap"
        log_info "Using Dockerfile.airgap for airgapped deployment"
    else
        local dockerfile="$service_dir/$dockerfile_name"
    fi
    
    # Validate paths
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory not found: $service_dir"
        return 1
    fi
    
    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi
    
    log_info "Service path: $service_path"
    log_info "Image name: $image_name:$VERSION"
    log_info "Platform: $PLATFORM"
    
    # Handle SDK requirements
    if [ "$needs_sdk" = "true" ]; then
        log_info "Service requires ark-sdk..."
        
        # Check if SDK wheel exists
        SDK_WHEEL="$PROJECT_ROOT/out/ark-sdk/py-sdk/dist/ark_sdk-${VERSION}-py3-none-any.whl"
        if [ ! -f "$SDK_WHEEL" ]; then
            log_error "SDK wheel not found: $SDK_WHEEL"
            log_error "Please build SDK first with: make ark-sdk-build"
            return 1
        fi
        
        # Check for sync-ark-sdk.sh script and run it
        if [ -f "$service_dir/sync-ark-sdk.sh" ]; then
            log_info "Running sync-ark-sdk.sh to sync dependencies..."
            cd "$service_dir"
            if bash sync-ark-sdk.sh; then
                log_success "SDK dependencies synced via sync-ark-sdk.sh"
            else
                log_warning "sync-ark-sdk.sh failed, falling back to manual copy"
                mkdir -p "$service_dir/out"
                cp "$SDK_WHEEL" "$service_dir/out/"
                log_success "SDK wheel copied manually"
            fi
        else
            # Fallback: copy SDK wheel manually
            log_info "No sync-ark-sdk.sh found, copying wheel manually..."
            mkdir -p "$service_dir/out"
            cp "$SDK_WHEEL" "$service_dir/out/"
            log_success "SDK wheel copied"
        fi
    fi
    
    # Build the image
    log_info "Building Docker image..."
    cd "$service_dir"
    
    if ! docker build \
        --platform "$PLATFORM" \
        -t "$image_name:$VERSION" \
        -f "$dockerfile_name" \
        . ; then
        log_error "Docker build failed for $service_name"
        # Cleanup on failure
        if [ "$needs_sdk" = "true" ]; then
            log_info "Cleaning up SDK artifacts..."
            rm -rf "$service_dir/out" "$service_dir/build-context"
            # Restore original pyproject.toml if backup exists
            [ -f "$service_dir/pyproject.toml.bak" ] && mv "$service_dir/pyproject.toml.bak" "$service_dir/pyproject.toml"
        fi
        return 1
    fi
    
    # Cleanup after successful build
    if [ "$needs_sdk" = "true" ]; then
        log_info "Cleaning up SDK artifacts..."
        rm -rf "$service_dir/out" "$service_dir/build-context"
        # Restore original pyproject.toml if backup exists (from sync-ark-sdk.sh)
        if [ -f "$service_dir/pyproject.toml.bak" ]; then
            mv "$service_dir/pyproject.toml.bak" "$service_dir/pyproject.toml"
            log_info "Restored original pyproject.toml"
        fi
    fi
    
    log_success "Successfully built $image_name:$VERSION"
    return 0
}

save_image() {
    local image_name="$1"
    local output_file="$2"
    
    log_info "Saving $image_name:$VERSION to $output_file"
    
    if docker save "$image_name:$VERSION" -o "$output_file"; then
        local size=$(du -h "$output_file" | cut -f1)
        log_success "Saved $image_name:$VERSION ($size)"
    else
        log_error "Failed to save $image_name:$VERSION"
        return 1
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--service)
                SELECTED_SERVICES+=("$2")
                shift 2
                ;;
            -a|--all)
                ALL_SERVICES=true
                shift
                ;;
            -l|--list)
                LIST_SERVICES=true
                shift
                ;;
            -p|--platform)
                PLATFORM="$2"
                shift 2
                ;;
            --save)
                SAVE_IMAGES=true
                shift
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --no-sdk)
                BUILD_SDK=false
                shift
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${red}error${nc}: unknown option $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Handle list services
    if [ "$LIST_SERVICES" = true ]; then
        list_services
        exit 0
    fi
    
    # Determine which services to build
    local services_to_build=()
    if [ "$ALL_SERVICES" = true ]; then
        while IFS='|' read -r svc _rest; do
            if [ -n "$svc" ]; then
                services_to_build+=("$svc")
            fi
        done <<< "$SERVICES_DATA"
    elif [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
        # Validate selected services
        for svc in "${SELECTED_SERVICES[@]}"; do
            local service_info=$(get_service_info "$svc")
            if [ -z "$service_info" ]; then
                log_error "Unknown service: $svc"
                echo "Run '$0 --list' to see available services"
                exit 1
            fi
            services_to_build+=("$svc")
        done
    else
        # No services specified via command line - use interactive selection
        interactive_service_selection
        # Validate selected services
        for svc in "${SELECTED_SERVICES[@]}"; do
            local service_info=$(get_service_info "$svc")
            if [ -z "$service_info" ]; then
                log_error "Unknown service: $svc"
                exit 1
            fi
            services_to_build+=("$svc")
        done
    fi
    
    # Display build configuration
    echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
    echo -e "${cyan}║${nc}                    ${white}ARK Airgapped Image Builder${nc}                             ${cyan}║${nc}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
    echo ""
    echo -e "${white}Configuration:${nc}"
    echo -e "  Version:         ${white}$VERSION${nc}"
    echo -e "  Platform:        ${white}$PLATFORM${nc}"
    echo -e "  Save images:     ${white}$SAVE_IMAGES${nc}"
    if [ "$SAVE_IMAGES" = true ]; then
        echo -e "  Output dir:      ${white}$OUTPUT_DIR${nc}"
    fi
    echo -e "  Build SDK:       ${white}$BUILD_SDK${nc}"
    echo ""
    echo -e "${white}Services to build (${#services_to_build[@]}):${nc}"
    for svc in "${services_to_build[@]}"; do
        echo -e "  • $svc"
    done
    echo ""
    
    # Confirm before proceeding
    read -p "Proceed with build? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Build cancelled"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Determine if any service needs SDK
    local needs_sdk=false
    for svc in "${services_to_build[@]}"; do
        local service_info=$(get_service_info "$svc")
        IFS='|' read -r _name path dockerfile image requires_sdk <<< "$service_info"
        if [ "$requires_sdk" = "true" ]; then
            needs_sdk=true
            break
        fi
    done
    
    # Build SDK if needed
    if [ "$needs_sdk" = "true" ] && [ "$BUILD_SDK" = "true" ]; then
        build_ark_sdk
    fi
    
    # Create output directory if saving images
    if [ "$SAVE_IMAGES" = true ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        OUTPUT_DIR="$OUTPUT_DIR/${VERSION}_${timestamp}"
        mkdir -p "$OUTPUT_DIR"
        log_info "Images will be saved to: $OUTPUT_DIR"
    fi
    
    # Build services
    local built_images=()
    local failed_builds=()
    
    for svc in "${services_to_build[@]}"; do
        local service_info=$(get_service_info "$svc")
        IFS='|' read -r _name path dockerfile image requires_sdk <<< "$service_info"
        
        if build_service "$svc" "$path" "$dockerfile" "$image" "$requires_sdk"; then
            built_images+=("$image")
            
            # Save image if requested
            if [ "$SAVE_IMAGES" = true ]; then
                local output_file="$OUTPUT_DIR/${image}_${VERSION}.tar"
                save_image "$image" "$output_file"
            fi
        else
            failed_builds+=("$svc")
        fi
    done
    
    # Summary
    log_section "Build Summary"
    
    if [ ${#built_images[@]} -gt 0 ]; then
        echo -e "${green}Successfully built (${#built_images[@]}):${nc}"
        for img in "${built_images[@]}"; do
            echo -e "  ${green}✔${nc} $img:$VERSION"
        done
        echo ""
    fi
    
    if [ ${#failed_builds[@]} -gt 0 ]; then
        echo -e "${red}Failed builds (${#failed_builds[@]}):${nc}"
        for svc in "${failed_builds[@]}"; do
            echo -e "  ${red}✗${nc} $svc"
        done
        echo ""
    fi
    
    if [ "$SAVE_IMAGES" = true ] && [ ${#built_images[@]} -gt 0 ]; then
        echo -e "${cyan}Saved images location:${nc}"
        echo -e "  ${white}$OUTPUT_DIR${nc}"
        echo ""
        echo -e "${cyan}To load images on target system:${nc}"
        echo -e "  ${white}cd $OUTPUT_DIR${nc}"
        echo -e "  ${white}for img in *.tar; do docker load -i \$img; done${nc}"
        echo ""
        
        # Create a manifest file
        local manifest_file="$OUTPUT_DIR/manifest.txt"
        echo "ARK Airgapped Images - Version $VERSION" > "$manifest_file"
        echo "Platform: $PLATFORM" >> "$manifest_file"
        echo "Build Date: $(date)" >> "$manifest_file"
        echo "" >> "$manifest_file"
        echo "Images:" >> "$manifest_file"
        for img in "${built_images[@]}"; do
            echo "  - $img:$VERSION" >> "$manifest_file"
        done
        log_success "Manifest created: $manifest_file"
    fi
    
    if [ ${#failed_builds[@]} -eq 0 ]; then
        echo -e "\n${green}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
        echo -e "${green}║${nc}                       ${white}All builds completed successfully!${nc}                       ${green}║${nc}"
        echo -e "${green}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
        exit 0
    else
        echo -e "\n${yellow}╔════════════════════════════════════════════════════════════════════════════════╗${nc}"
        echo -e "${yellow}║${nc}                  ${white}Build completed with some failures${nc}                          ${yellow}║${nc}"
        echo -e "${yellow}╚════════════════════════════════════════════════════════════════════════════════╝${nc}"
        exit 1
    fi
}

main "$@"

