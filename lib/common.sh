#!/bin/bash
# Shared utilities for Steam Deck helper scripts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} ${1}"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} ${1}"; }
log_error() { echo -e "${RED}[ERROR]${NC} ${1}"; }

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo bash ${0}"
        exit 1
    fi
}

check_steamdeck() {
    if ! grep -qi "steamos" /etc/os-release 2>/dev/null; then
        log_warn "This does not appear to be SteamOS. Proceed anyway? (y/N)"
        read -r confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
            exit 1
        fi
    fi
}
