#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SOCKET_PATH="${HOME}/.ydotool_socket"
ECHO_MODE="no-echo"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Forward keystrokes from this terminal to the active window via ydotool.
Useful for typing into the Steam Deck screen from an SSH session.

Options:
  --echo       Echo keystrokes in this terminal as well
  --no-echo    Do not echo keystrokes in this terminal (default)
  --dry-run    Show configuration and exit (do not start daemon)
  --help       Show this help message and exit

Exit:
  Ctrl+C or Ctrl+D to quit and clean up the ydotool daemon.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --echo)
            ECHO_MODE="echo"
            shift
            ;;
        --no-echo)
            ECHO_MODE="no-echo"
            shift
            ;;
        --dry-run)
            log_info "Dry run mode"
            log_info "Echo mode: ${ECHO_MODE}"
            log_info "Socket path: ${SOCKET_PATH}"
            log_info "Socket ownership: $(id -u):$(id -g)"
            exit 0
            ;;
        *)
            log_error "Unknown option: ${1}"
            usage >&2
            exit 1
            ;;
    esac
done

log_info "Echo mode: ${ECHO_MODE}"
log_info "Socket path: ${SOCKET_PATH}"

# Preflight checks
check_root
check_steamdeck

if ! command -v ydotoold &>/dev/null; then
    log_error "ydotoold is not installed. Install ydotool first."
    exit 1
fi

if ! command -v ydotool &>/dev/null; then
    log_error "ydotool is not installed. Install ydotool first."
    exit 1
fi

log_info "Starting ydotoold daemon..."

# Kill any existing ydotoold processes
killall ydotoold 2>/dev/null || true
sleep 0.5

# Start daemon
sudo -b ydotoold --socket-path="$SOCKET_PATH" --socket-own="$(id -u):$(id -g)"

# Export socket path
export YDOTOOL_SOCKET="${SOCKET_PATH}"

# Wait for daemon to be ready (socket must exist)
for i in $(seq 1 20); do
    if [[ -e "$SOCKET_PATH" ]]; then
        break
    fi
    sleep 0.2
done

if [[ ! -e "$SOCKET_PATH" ]]; then
    log_error "ydotoold failed to start"
    exit 1
fi

log_info "Daemon started. Press Ctrl+C or Ctrl+D to exit."

# Cleanup on exit
CLEANUP_DONE=0
cleanup() {
    if [[ "${CLEANUP_DONE}" -eq 1 ]]; then
        return
    fi
    CLEANUP_DONE=1
    # Restore terminal FIRST before anything else
    stty sane 2>/dev/null || true
    log_info "Shutting down ydotoold daemon..."
    killall ydotoold 2>/dev/null || true
    killall -9 ydotoold 2>/dev/null || true
    log_info "Done."
    exit 0
}
trap cleanup EXIT INT TERM

# Set terminal mode
if [[ "${ECHO_MODE}" == "echo" ]]; then
    stty raw echo
else
    stty raw -echo
fi

# Send a key event
send_key() {
    local keycodes="${1}"
    ydotool key ${keycodes}
}

# Read and dispatch an escape sequence (after reading \x1b)
read_escape_sequence() {
    local seq=""
    # Read remaining bytes of escape sequence
    # Timeout must be long enough to capture full sequence even with fast typing
    while true; do
        IFS= read -r -n 1 -t 0.1 next_byte || break
        seq="${seq}${next_byte}"
        if [[ ${#seq} -ge 5 ]]; then
            break
        fi
    done

    # Empty seq means standalone Escape key
    if [[ -z "${seq}" ]]; then
        send_key "1:1 1:0"
        return
    fi

    case "${seq}" in
        '[A') send_key "103:1 103:0" ;;        # Up
        '[B') send_key "108:1 108:0" ;;        # Down
        '[C') send_key "106:1 106:0" ;;        # Right
        '[D') send_key "105:1 105:0" ;;        # Left
        '[H') send_key "102:1 102:0" ;;        # Home
        '[F') send_key "107:1 107:0" ;;        # End
        '[3~') send_key "111:1 111:0" ;;       # Delete
        '[2~') send_key "110:1 110:0" ;;       # Insert
        '[5~') send_key "104:1 104:0" ;;       # Page Up
        '[6~') send_key "109:1 109:0" ;;       # Page Down
        *)
            # Unknown escape sequence — send Escape key then type the rest
            send_key "1:1 1:0"
            ydotool type -- "${seq}"
            ;;
    esac
}

# Process a single byte
process_byte() {
    local byte="${1}"

    # Ctrl+C or Ctrl+D → exit
    if [[ "${byte}" == $'\x03' || "${byte}" == $'\x04' ]]; then
        log_info "Exit requested"
        RUNNING=0
        return
    fi

    # Printable ASCII (space through tilde)
    if [[ "${byte}" =~ ^[[:print:]]$ ]]; then
        # Escape backslash for ydotool type
        if [[ "${byte}" == "\\" ]]; then
            ydotool type -- "\\\\"
        else
            ydotool type -- "${byte}"
        fi
        return
    fi

    # Single-byte special keys
    case "${byte}" in
        $'\x7f') send_key "14:1 14:0" ;;       # Backspace
        $'\x09') send_key "15:1 15:0" ;;       # Tab
        $'\x1b')                                 # Escape or escape sequence
            read_escape_sequence
            ;;
        *)
            # Other control characters: skip
            ;;
    esac
}

# Main loop
RUNNING=1
while [[ "${RUNNING}" -eq 1 ]]; do
    # read -n 1 treats \n as empty string (Enter key)
    # We detect Enter by checking if read returned empty with exit 0
    if IFS= read -r -n 1 -t 0.05 byte; then
        if [[ -z "${byte}" ]]; then
            # Enter key — read returns empty string for \n
            ydotool key 28:1 28:0
            continue
        fi
        process_byte "${byte}"
    fi
done
