#!/bin/bash
set -euo pipefail

# Steam Deck Post-Update Development Setup
# Re-enables development mode after SteamOS updates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

disable_readonly() {
    log_info "Disabling read-only filesystem..."
    if steamos-readonly disable; then
        log_info "Read-only mode disabled."
    else
        log_error "Failed to disable read-only mode."
        exit 1
    fi
}

fix_pacman() {
    log_info "Fixing pacman configuration..."

    # Reset pacman keyring
    log_info "Resetting pacman keyring..."
    pacman-key --init
    pacman-key --populate archlinux holo

    # Refresh package databases
    log_info "Refreshing package databases..."
    pacman -Sy --noconfirm

    log_info "Pacman fixed."
}

install_packages() {
    log_info "Installing development packages..."
    pacman -S --noconfirm --needed \
        docker \
        docker-compose \
        docker-buildx \
        base-devel \
        git \
        glibc \
        linux-headers \
        linux-api-headers \
        ydotool

    log_info "Packages installed."
}

setup_docker() {
    log_info "Setting up Docker..."

    # Reload systemd to pick up any new or changed unit files
    systemctl daemon-reload

    # Enable and start Docker service
    systemctl enable docker
    systemctl start docker

    # Add deck user to docker group if it exists
    if id -u deck &>/dev/null; then
        usermod -aG docker deck
        log_info "Added 'deck' user to docker group."
    fi

    log_info "Docker setup complete."
}

enable_ssh() {
    log_info "Enabling SSH..."

    # Reload systemd to pick up any new or changed unit files
    systemctl daemon-reload

    # Enable and start sshd
    systemctl enable sshd
    systemctl start sshd

    # Allow SSH through firewall if ufw is active
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow ssh
        log_info "SSH allowed through firewall."
    fi

    log_info "SSH enabled."
}

setup_homebrew() {
    local install_user="${SUDO_USER:-deck}"

    if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
        log_info "Homebrew is already installed."
        return
    fi

    log_info "Installing Homebrew..."

    # Homebrew must be installed as a non-root user
    if ! id -u "${install_user}" &>/dev/null; then
        log_error "User '${install_user}' not found. Cannot install Homebrew."
        return
    fi

    # Install dependencies that Homebrew needs
    pacman -S --noconfirm --needed \
        curl \
        file

    # Run the official installer as the target user
    sudo -u "${install_user}" bash -c 'NONINTERACTIVE=1 eval "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

    # Add brew to PATH in the target user's .bashrc if not already present
    local user_home
    user_home=$(eval echo "~${install_user}")
    local bashrc="${user_home}/.bashrc"
    local brew_shellenv='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

    if [[ -f "${bashrc}" ]] && grep -qF "${brew_shellenv}" "${bashrc}"; then
        log_info "Homebrew PATH already configured in ${bashrc}."
    else
        echo "# Homebrew" >> "${bashrc}"
        echo "${brew_shellenv}" >> "${bashrc}"
        log_info "Added Homebrew PATH to ${bashrc}."
    fi

    log_info "Homebrew installed. Open a new terminal or run 'eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"' to use it."
}

# Main
main() {
    echo "========================================"
    echo " Steam Deck Dev Mode Setup"
    echo "========================================"
    echo ""

    check_root
    check_steamdeck

    disable_readonly
    fix_pacman
    install_packages
    setup_docker
    enable_ssh
    setup_homebrew

    echo ""
    echo "========================================"
    log_info "All done! Reboot your Steam Deck for changes to take full effect."
    log_warn "After reboot, you may need to run this script again if SteamOS updates."
    echo "========================================"
}

main "${@}"
