#!/usr/bin/env bash
#
# sunscreen installer — Linux only
#
set -euo pipefail

GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}
╔══════════════════════════════════════╗
║       ☀️  SUNSCREEN INSTALLER        ║
╚══════════════════════════════════════╝
${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/sunscreen.sh"
INSTALL_DIR="${HOME}/.local/bin"

if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${YELLOW}[ERROR] sunscreen.sh not found.${RESET}"
    exit 1
fi

echo -e "${BOLD}[1/4] Installing dependencies...${RESET}"
if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq xdotool 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    sudo dnf install -y xdotool 2>/dev/null || true
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm xdotool 2>/dev/null || true
fi

echo -e "${BOLD}[2/4] Installing sunscreen...${RESET}"
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT" "$INSTALL_DIR/sunscreen"
chmod +x "$INSTALL_DIR/sunscreen"

echo -e "${BOLD}[3/4] Adding ~/.local/bin to PATH in .bashrc...${RESET}"
if ! grep -q '.local/bin' ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# Sunscreen — add local bin to PATH' >> ~/.bashrc
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo -e "${GREEN}  Added to ~/.bashrc${RESET}"
else
    echo -e "${GREEN}  Already in ~/.bashrc${RESET}"
fi

echo -e "${BOLD}[4/4] Setting up background service (autostart on boot)...${RESET}"
mkdir -p "${HOME}/.config/systemd/user"

cat > "${HOME}/.config/systemd/user/sunscreen.service" << SVCEOF
[Unit]
Description=Sunscreen screen-time limiter
After=graphical-session.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sunscreen --daemon
Restart=always
RestartSec=5
Environment=DISPLAY=${DISPLAY:-:0}
Environment=WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}

[Install]
WantedBy=default.target
SVCEOF

systemctl --user daemon-reload
systemctl --user enable sunscreen.service

echo -e "
${GREEN}${BOLD}✅ Installation complete!${RESET}

${BOLD}Commands:${RESET}
  ${BLUE}sunscreen${RESET}           — Show TUI dashboard
  ${BLUE}systemctl --user status sunscreen${RESET}  — Check service
  ${BLUE}systemctl --user stop sunscreen${RESET}    — Stop service
  ${BLUE}systemctl --user start sunscreen${RESET}   — Start service

The service runs silently in the background and starts on boot.
Run ${YELLOW}sunscreen${RESET} anytime to view your dashboard.
"
