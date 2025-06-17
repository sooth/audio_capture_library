#!/bin/bash

# Audio Capture Library - Run Script
# Runs the compiled audio capture and playback system

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_DIR="./build"
EXECUTABLE_NAME="audio_capture"
RELEASE_EXECUTABLE="${EXECUTABLE_NAME}_release"

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

log_highlight() {
    echo -e "${CYAN}[RUN]${NC} $1"
}

# Check if executable exists
check_executable() {
    local exe_path="$1"
    
    if [[ ! -f "$exe_path" ]]; then
        log_error "Executable not found: $exe_path"
        log_error "Please run './compile.sh' first to build the project"
        exit 1
    fi
    
    if [[ ! -x "$exe_path" ]]; then
        log_error "Executable is not runnable: $exe_path"
        log_error "Fix permissions with: chmod +x $exe_path"
        exit 1
    fi
}

# Check system requirements
check_system() {
    # Check macOS version
    local macos_version=$(sw_vers -productVersion)
    local major_version=$(echo $macos_version | cut -d. -f1)
    
    log_info "macOS Version: $macos_version"
    
    if [[ $major_version -lt 13 ]]; then
        log_error "macOS 13.0+ required for ScreenCaptureKit APIs"
        exit 1
    fi
    
    # Check permissions (Screen Recording permission required)
    log_warning "This application requires Screen Recording permission in System Preferences > Security & Privacy > Privacy > Screen Recording"
}

# Show usage information
show_usage() {
    echo -e "${CYAN}Audio Capture Library - Usage${NC}"
    echo ""
    echo "Interactive Mode:"
    echo "  ./run.sh                    - Run in interactive mode"
    echo "  ./run.sh release            - Run optimized release version"
    echo ""
    echo "Recording Mode:"
    echo "  ./run.sh record <seconds> <filename> - Silent recording to WAV file (no playback)"
    echo "  ./run.sh record 30 meeting          - Record for 30 seconds to meeting.wav"
    echo ""
    echo "Streaming Mode:"
    echo "  ./run.sh stream [seconds] [delay] [filename] - Stream system audio to speakers"
    echo "  ./run.sh stream 30                           - Stream for 30 seconds (default: 30s)"
    echo "  ./run.sh stream 10 2.5                       - Stream for 10s with 2.5s playback delay"
    echo "  ./run.sh stream 30 0 recording               - Stream for 30s AND save to recording.wav"
    echo "  ./run.sh stream 20 3 myaudio                 - Stream for 20s with 3s delay, also save to myaudio.wav"
    echo ""
    echo "Test Mode (Legacy):"
    echo "  ./run.sh test <seconds> <filename>  - Record for specified duration"
    echo "  ./run.sh test 10 test_audio         - Record for 10 seconds to test_audio.wav"
    echo ""
    echo "Test Audio:"
    echo "  ./run.sh test-tone [seconds]            - Play test tone (default: 5s)"
    echo ""
    echo "Diagnostics:"
    echo "  ./run.sh check-permissions          - Check macOS 15 permissions status"
    echo ""
    echo "Examples:"
    echo "  ./run.sh                            - Interactive CLI"
    echo "  ./run.sh test 30 system_audio       - 30-second test recording"
    echo "  ./run.sh stream 60                  - 60-second audio streaming"
    echo "  ./run.sh check-permissions          - Check ScreenCaptureKit permissions"
    echo "  ./run.sh release stream 10          - 10-second streaming with optimized build"
    echo ""
    echo "Interactive Commands:"
    echo "  start <filename>  - Start recording to specified file"
    echo "  stream           - Start streaming system audio to speakers"
    echo "  stop             - Stop current recording/streaming"
    echo "  status           - Show current status"
    echo "  quit/exit        - Exit the application"
}

# Run interactive mode
run_interactive() {
    local exe_path="$1"
    
    log_highlight "Starting Audio Capture Library in interactive mode..."
    log_info "Press Ctrl+C to exit or use 'quit' command"
    echo ""
    
    # Run the executable
    "$exe_path"
}

# Run test mode
run_test() {
    local exe_path="$1"
    local duration="$2"
    local filename="$3"
    
    # Validate duration
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid duration: $duration (must be a number)"
        exit 1
    fi
    
    # Validate filename
    if [[ -z "$filename" ]]; then
        log_error "Filename cannot be empty"
        exit 1
    fi
    
    log_highlight "Starting test recording..."
    log_info "Duration: ${duration} seconds"
    log_info "Output file: ${filename}.wav"
    log_info "Press Ctrl+C to stop early"
    echo ""
    
    # Run the test
    "$exe_path" test "$duration" "$filename"
}

# Run record mode (silent recording)
run_record() {
    local exe_path="$1"
    local duration="$2"
    local filename="$3"
    
    # Validate duration
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid duration: $duration (must be a number)"
        exit 1
    fi
    
    # Validate filename
    if [[ -z "$filename" ]]; then
        log_error "Filename cannot be empty"
        exit 1
    fi
    
    log_highlight "Starting silent recording..."
    log_info "Duration: ${duration} seconds"
    log_info "Output file: ${filename}.wav"
    log_warning "No audio will be played during recording"
    log_info "Press Ctrl+C to stop early"
    echo ""
    
    # Run the recording
    "$exe_path" record "$duration" "$filename"
}

# Run streaming mode
run_stream() {
    local exe_path="$1"
    local duration="$2"
    local delay="${3:-0}"
    local filename="${4:-}"
    
    # Validate duration
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid duration: $duration (must be a number)"
        exit 1
    fi
    
    # Validate delay
    if ! [[ "$delay" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid delay: $delay (must be a number)"
        exit 1
    fi
    
    log_highlight "Starting audio streaming to system output..."
    log_info "Duration: ${duration} seconds"
    if (( $(echo "$delay > 0" | bc -l) )); then
        log_info "Playback delay: ${delay} seconds"
    fi
    if [[ -n "$filename" ]]; then
        log_info "Saving to WAV file: ${filename}.wav"
    fi
    log_warning "Make sure your system volume is set appropriately"
    log_info "Press Ctrl+C to stop early"
    echo ""
    
    # Run the streaming with all parameters
    if [[ -n "$filename" ]]; then
        "$exe_path" stream "$duration" "$delay" "$filename"
    elif (( $(echo "$delay > 0" | bc -l) )); then
        "$exe_path" stream "$duration" "$delay"
    else
        "$exe_path" stream "$duration"
    fi
}

# Run test tone
run_test_tone() {
    local exe_path="$1"
    local duration="$2"
    
    # Validate duration
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid duration: $duration (must be a number)"
        exit 1
    fi
    
    log_highlight "Playing test tone with new streaming player..."
    log_info "Duration: ${duration} seconds"
    log_info "Frequency: 440Hz (A4 note)"
    log_warning "Make sure your system volume is set appropriately"
    echo ""
    
    # Run the test tone
    "$exe_path" test-tone "$duration"
}

# Monitor system resources during execution
monitor_resources() {
    local pid=$1
    
    while kill -0 "$pid" 2>/dev/null; do
        local cpu_usage=$(ps -p "$pid" -o %cpu= | tr -d ' ')
        local mem_usage=$(ps -p "$pid" -o rss= | tr -d ' ')
        
        if [[ -n "$cpu_usage" && -n "$mem_usage" ]]; then
            # Convert KB to MB
            mem_mb=$((mem_usage / 1024))
            log_info "CPU: ${cpu_usage}% | Memory: ${mem_mb}MB"
        fi
        
        sleep 5
    done
}

# Handle cleanup on script exit
cleanup() {
    log_info "Cleaning up..."
    # Kill any running audio processes if needed
    pkill -f "$EXECUTABLE_NAME" 2>/dev/null || true
}

trap cleanup EXIT

# Main execution function
main() {
    local mode="$1"
    local exe_path="$OUTPUT_DIR/$EXECUTABLE_NAME"
    
    # Use release version if requested
    if [[ "$mode" == "release" ]]; then
        exe_path="$OUTPUT_DIR/$RELEASE_EXECUTABLE"
        shift
        mode="$1"
    fi
    
    check_executable "$exe_path"
    check_system
    
    case "$mode" in
        "test")
            if [[ $# -lt 3 ]]; then
                log_error "Test mode requires duration and filename"
                echo "Usage: $0 test <seconds> <filename>"
                exit 1
            fi
            run_test "$exe_path" "$2" "$3"
            ;;
        "record")
            if [[ $# -lt 3 ]]; then
                log_error "Record mode requires duration and filename"
                echo "Usage: $0 record <seconds> <filename>"
                exit 1
            fi
            run_record "$exe_path" "$2" "$3"
            ;;
        "stream")
            local duration="${2:-30}"
            local delay="${3:-0}"
            local filename="${4:-}"
            run_stream "$exe_path" "$duration" "$delay" "$filename"
            ;;
        "test-tone")
            local duration="${2:-5}"
            run_test_tone "$exe_path" "$duration"
            ;;
        "check-permissions")
            log_highlight "Checking macOS 15 ScreenCaptureKit permissions..."
            "$exe_path" check-permissions
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        "monitor")
            log_highlight "Starting with resource monitoring..."
            run_interactive "$exe_path" &
            local app_pid=$!
            monitor_resources $app_pid
            wait $app_pid
            ;;
        "")
            run_interactive "$exe_path"
            ;;
        *)
            log_error "Unknown mode: $mode"
            show_usage
            exit 1
            ;;
    esac
}

# Pre-flight checks
preflight_check() {
    # Check if build directory exists
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_error "Build directory not found: $OUTPUT_DIR"
        log_error "Please run './compile.sh' first"
        exit 1
    fi
    
    # Check audio permissions (advisory)
    log_info "Checking system requirements..."
    
    # Check if running in Terminal vs other contexts
    if [[ -t 1 ]]; then
        log_success "Running in terminal environment"
    else
        log_warning "Not running in terminal - output may be limited"
    fi
}

# Entry point
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Audio Capture Library         ║${NC}"
echo -e "${CYAN}║     macOS System Audio Recorder      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

preflight_check
main "$@"