#!/usr/bin/env bash

# Android Studio Linux Uninstaller
# Safe, robust, and clean removal utility.

set -euo pipefail

# Text formatters
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}=== Android Studio Uninstaller ===${NC}"

# Default values
INSTALL_SCOPE="all"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --user      Limit scope to user space (~/.local) without requiring root privileges.
  -h, --help  Show this help message.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            INSTALL_SCOPE="user"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

# Define target paths
SYSTEM_DESKTOP_DIR="/usr/share/applications"
USER_DESKTOP_DIR="$HOME/.local/share/applications"

# Interactive confirmation
if [[ -t 0 ]]; then
    echo -e "\n${BOLD}This will remove Android Studio from your system.${NC}"
    echo -ne "Do you want to proceed? [y/N]: "
    read -r CONFIRM
    CONFIRM=$(echo "${CONFIRM:-n}" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
        echo -e "${RED}Uninstallation aborted by user.${NC}"
        exit 0
    fi
fi

# Function to safely delete files/folders
safe_remove() {
    local target="$1"
    local use_sudo="${2:-false}"

    if [[ -e "$target" || -L "$target" ]]; then
        echo -e "${YELLOW}Removing: $target${NC}"
        if [[ "$use_sudo" == "true" ]]; then
            sudo rm -rf "$target"
        else
            rm -rf "$target"
        fi
    fi
}

# ── System-wide removal ──────────────────────────────────────────────────────
if [[ "$INSTALL_SCOPE" != "user" ]]; then
    echo -e "\n${BLUE}Checking for system-wide components...${NC}"
    safe_remove "/opt/android-studio"              "true"
    safe_remove "/usr/local/bin/android-studio"   "true"
    safe_remove "$SYSTEM_DESKTOP_DIR/android-studio.desktop" "true"
    safe_remove "/usr/share/pixmaps/android-studio.png"      "true"

    if [[ -d "$SYSTEM_DESKTOP_DIR" ]]; then
        command -v update-desktop-database &>/dev/null && sudo update-desktop-database "$SYSTEM_DESKTOP_DIR" || true
    fi
fi

# ── User-local removal ───────────────────────────────────────────────────────
echo -e "\n${BLUE}Checking for user-local components...${NC}"
safe_remove "$HOME/.local/share/android-studio"             "false"
safe_remove "$HOME/.local/bin/android-studio"               "false"
safe_remove "$USER_DESKTOP_DIR/android-studio.desktop"      "false"
safe_remove "$HOME/.local/share/pixmaps/android-studio.png" "false"

if [[ -d "$USER_DESKTOP_DIR" ]]; then
    command -v update-desktop-database &>/dev/null && update-desktop-database "$USER_DESKTOP_DIR" || true
fi

# ── Optional: remove Android SDK & config ────────────────────────────────────
echo ""
echo -e "${YELLOW}Note: The Android SDK directory (~/.android, ~/Android/Sdk) was NOT removed.${NC}"
echo -e "${YELLOW}To also remove SDK data, manually run:${NC}"
echo -e "${BLUE}  rm -rf ~/Android/Sdk ~/.android${NC}"

echo -e "\n${GREEN}${BOLD}✓ Android Studio uninstallation completed successfully!${NC}"
