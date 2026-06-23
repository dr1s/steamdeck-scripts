# steamdeck-scripts

Various helper scripts for the Steam Deck.

## Scripts

### devmode-setup.sh

Re-enables development mode after SteamOS updates. Must be run as root. Performs the following:

- Disables the read-only filesystem
- Fixes pacman (resets keyring, refreshes databases)
- Installs development packages (Docker, Docker Compose, Docker Buildx, base-devel, git, glibc, linux-headers, ydotool)
- Enables and starts the Docker service, adding the `deck` user to the `docker` group
- Enables and starts SSH (and opens the firewall port if ufw is active)
- Installs Homebrew (as the `deck` user) and configures it in `.bashrc`

A reboot is recommended after running for all changes to take effect.

### ydotool-bridge.sh

Forwards keystrokes from an SSH session to the active Steam Deck window via `ydotool`. This lets you type into the Steam Deck GUI (Game Mode, on-screen keyboard, etc.) from a remote terminal.

- Starts a `ydotoold` daemon with a user-owned socket
- Reads input byte-by-byte, translating printable characters, arrow keys, Home/End, Page Up/Down, Backspace, Tab, Enter, and Escape into `ydotool` key events
- Supports `--echo` / `--no-echo` to control whether keystrokes are echoed locally
- Supports `--dry-run` to show configuration without starting the daemon
- Cleans up the daemon and restores terminal settings on exit (Ctrl+C / Ctrl+D)

Requires `ydotool` and `ydotoold` to be installed. Must be run as root.
