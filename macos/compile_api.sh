#!/bin/bash

# Audio Capture Library - API Compile Script
# Compiles the Swift audio capture library with the new API layer

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="AudioCaptureLibrary API"
OUTPUT_DIR="./build"
EXECUTABLE_NAME="audio_capture_api"

# API Files
API_FILES=(
    "API/AudioError.swift"
    "API/AudioFormat.swift"
    "API/AudioDevice.swift"
    "API/AudioBufferQueue.swift"
    "API/AudioOutput.swift"
    "API/AudioSession.swift"
    "API/AudioCaptureKit.swift"
    "API/Examples.swift"
)

# Core Implementation Files
CORE_FILES=(
    "StreamingAudioRecorder.swift"
    "StreamingAudioPlayer.swift"
    "WavFileWriter.swift"
)

# Main entry point
MAIN_FILE="main_api.swift"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script requires macOS"
        exit 1
    fi
}

# Check Swift compiler
check_swift() {
    if ! command -v swiftc &> /dev/null; then
        log_error "Swift compiler not found. Please install Xcode Command Line Tools:"
        log_error "xcode-select --install"
        exit 1
    fi
    
    local swift_version=$(swiftc --version | head -n1)
    log_info "Found Swift: $swift_version"
}

# Check macOS version
check_macos_version() {
    local macos_version=$(sw_vers -productVersion)
    local major_version=$(echo $macos_version | cut -d. -f1)
    
    log_info "macOS Version: $macos_version"
    
    # Check if macOS 13.0+ (required for ScreenCaptureKit)
    if [[ $major_version -lt 13 ]]; then
        log_error "macOS 13.0+ required for ScreenCaptureKit APIs"
        exit 1
    fi
}

# Create API directory if needed
setup_api_dir() {
    if [[ ! -d "API" ]]; then
        log_info "Creating API directory..."
        mkdir -p "API"
    fi
}

# Validate source files
validate_sources() {
    log_info "Validating source files..."
    
    # Check core files
    for file in "${CORE_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Core file not found: $file"
            exit 1
        fi
        log_info "✓ Found: $file"
    done
    
    # Check API files
    for file in "${API_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "API file not found: $file"
            exit 1
        fi
        log_info "✓ Found: $file"
    done
    
    # Check main file
    if [[ ! -f "$MAIN_FILE" ]]; then
        log_error "Main file not found: $MAIN_FILE"
        exit 1
    fi
    log_info "✓ Found: $MAIN_FILE"
}

# Create build directory
setup_build_dir() {
    log_info "Setting up build directory..."
    
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
    fi
    
    log_success "Build directory ready: $OUTPUT_DIR"
}

# Compile the Swift project
compile_swift() {
    log_info "Compiling Swift API project..."
    
    # Swift compiler flags
    local SWIFT_FLAGS=(
        "-o" "$OUTPUT_DIR/$EXECUTABLE_NAME"
        "-Onone"  # No optimization for debugging
        "-g"      # Generate debug info
        "-target" "arm64-apple-macos13.0"  # Target macOS 13.0+ on Apple Silicon
        "-framework" "Foundation"
        "-framework" "AVFoundation"
        "-framework" "ScreenCaptureKit"
        "-framework" "CoreMedia"
        "-framework" "CoreAudio"
        "-framework" "SwiftUI"  # For SwiftUI examples
    )
    
    # Add all source files
    for file in "${CORE_FILES[@]}"; do
        SWIFT_FLAGS+=("$file")
    done
    
    for file in "${API_FILES[@]}"; do
        SWIFT_FLAGS+=("$file")
    done
    
    SWIFT_FLAGS+=("$MAIN_FILE")
    
    log_info "Compiling with $(( ${#CORE_FILES[@]} + ${#API_FILES[@]} + 1 )) source files..."
    
    if swiftc "${SWIFT_FLAGS[@]}"; then
        log_success "Compilation successful!"
    else
        log_error "Compilation failed!"
        exit 1
    fi
}

# Create optimized release build
compile_release() {
    log_info "Creating optimized release build..."
    
    local RELEASE_FLAGS=(
        "-o" "$OUTPUT_DIR/${EXECUTABLE_NAME}_release"
        "-O"      # Optimize for speed
        "-whole-module-optimization"
        "-target" "arm64-apple-macos13.0"
        "-framework" "Foundation"
        "-framework" "AVFoundation"
        "-framework" "ScreenCaptureKit"
        "-framework" "CoreMedia"
        "-framework" "CoreAudio"
        "-framework" "SwiftUI"
    )
    
    # Add all source files
    for file in "${CORE_FILES[@]}"; do
        RELEASE_FLAGS+=("$file")
    done
    
    for file in "${API_FILES[@]}"; do
        RELEASE_FLAGS+=("$file")
    done
    
    RELEASE_FLAGS+=("$MAIN_FILE")
    
    if swiftc "${RELEASE_FLAGS[@]}"; then
        log_success "Release build created: ${EXECUTABLE_NAME}_release"
    else
        log_warning "Release build failed, but debug build succeeded"
    fi
}

# Display build information
show_build_info() {
    log_info "Build Information:"
    echo "  Project: $PROJECT_NAME"
    echo "  Output: $OUTPUT_DIR/$EXECUTABLE_NAME"
    echo "  Size: $(ls -lh "$OUTPUT_DIR/$EXECUTABLE_NAME" | awk '{print $5}')"
    
    if [[ -f "$OUTPUT_DIR/${EXECUTABLE_NAME}_release" ]]; then
        echo "  Release Size: $(ls -lh "$OUTPUT_DIR/${EXECUTABLE_NAME}_release" | awk '{print $5}')"
    fi
    
    echo ""
    echo "  Core Files: ${#CORE_FILES[@]}"
    echo "  API Files: ${#API_FILES[@]}"
    echo "  Total Files: $(( ${#CORE_FILES[@]} + ${#API_FILES[@]} + 1 ))"
    echo ""
    echo "  Frameworks: Foundation, AVFoundation, ScreenCaptureKit, CoreMedia, CoreAudio, SwiftUI"
}

# Main execution
main() {
    log_info "Starting compilation of $PROJECT_NAME..."
    
    check_macos
    check_swift
    check_macos_version
    setup_api_dir
    validate_sources
    setup_build_dir
    compile_swift
    compile_release
    show_build_info
    
    log_success "Build completed successfully!"
    log_info "Run with: $OUTPUT_DIR/$EXECUTABLE_NAME <command>"
    log_info "Try: $OUTPUT_DIR/$EXECUTABLE_NAME help"
}

# Handle script arguments
case "${1:-}" in
    "clean")
        log_info "Cleaning build directory..."
        rm -rf "$OUTPUT_DIR"
        log_success "Build directory cleaned"
        ;;
    "release")
        log_info "Building release version only..."
        check_macos
        check_swift
        check_macos_version
        setup_api_dir
        validate_sources
        setup_build_dir
        compile_release
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [clean|release|help]"
        echo "  clean    - Clean build directory"
        echo "  release  - Build release version only"
        echo "  help     - Show this help message"
        echo ""
        echo "API Commands (after building):"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME devices    - List audio devices"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME record      - Record to file"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME stream      - Stream with playback"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME monitor     - Monitor audio levels"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME multi       - Multi-output demo"
        echo "  $OUTPUT_DIR/$EXECUTABLE_NAME examples    - Run all examples"
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac