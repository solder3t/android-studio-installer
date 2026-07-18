#!/usr/bin/env bash

# Android Studio Linux Installer
# A secure, robust, and native installation script for Linux.
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --user             Install to user space (~/.local) without requiring root privileges.
#   --url <url>        Override the default download URL.
#   --dry-run          Run pre-flight checks and download the package but do not write any files.
#   -y, --yes          Automatic yes to prompts (bypass confirmation).
#   --offline          Skip version check and use the bundled fallback version.
#   -h, --help         Show help message.

set -euo pipefail

# ANSI color codes for premium terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Application Constants ────────────────────────────────────────────────────
APP_NAME_SHORT="android-studio"
APP_NAME_PRETTY="Android Studio"
BINARY_WRAPPER="studio.sh"        # launch script inside the extracted directory
APP_COMMENT="The official IDE for Android development"
WM_CLASS="jetbrains-studio"

# ── Bundled Fallback (used if the update feed is unreachable) ────────────────
FALLBACK_VERSION="2026.1.2.10"
FALLBACK_CODENAME="quail2"

# ── Runtime State ────────────────────────────────────────────────────────────
APP_VERSION=""      # resolved at runtime
APP_CODENAME=""     # resolved at runtime
DOWNLOAD_URL_X64="" # resolved at runtime

# ── Runtime State ────────────────────────────────────────────────────────────
INSTALL_SCOPE="system"
DOWNLOAD_URL=""
DRY_RUN=false
AUTO_CONFIRM=false
OFFLINE=false
TEMP_DIR=""
BACKUP_APP_DIR=""
INSTALL_SUCCESSFUL=false

# ── Privilege Helper ─────────────────────────────────────────────────────────
escalate_cmd() {
    if [[ "$INSTALL_SCOPE" == "system" ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Installs the latest stable ${APP_NAME_PRETTY} on Linux.
The latest version is resolved automatically from Google's update feed.

Options:
  --user             Install to user space (~/.local) without requiring root/sudo.
  --url <url>        Override the download URL (skips version auto-detection).
  --offline          Skip the version feed check; use the bundled fallback version.
  --dry-run          Perform pre-flight checks and package download only. No files written.
  -y, --yes          Automatic yes to prompts (bypass confirmation during upgrades).
  -h, --help         Show this help message.
EOF
}

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            INSTALL_SCOPE="user"
            shift
            ;;
        --url)
            if [[ -n "${2:-}" ]]; then
                DOWNLOAD_URL="$2"
                shift 2
            else
                echo -e "${RED}Error: --url requires a value.${NC}" >&2
                exit 1
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --offline)
            OFFLINE=true
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

echo -e "${BLUE}${BOLD}=== Android Studio Linux Installer ===${NC}"

# ── Architecture Check ───────────────────────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo -e "${RED}Error: Android Studio Linux builds are only available for x86_64.\n       Detected architecture: ${ARCH}${NC}" >&2
    exit 1
fi

# ── Version Auto-Detection ──────────────────────────────────────────────────
# Derives the download slug from the update feed version string, then probes
# Google's CDN to find the correct numeric version (which the feed omits).
# Falls back to FALLBACK_VERSION/FALLBACK_CODENAME if the feed is unreachable.
resolve_latest_version() {
    local feed_url="https://dl.google.com/android/studio/patches/updates.xml"
    local base_dl="https://dl.google.com/dl/android/studio/ide-zips"

    echo -e "${YELLOW}Checking for the latest stable release...${NC}"

    # Fetch the update XML; timeout quickly so we don't stall the install
    local xml
    xml=$(curl -fsSL --max-time 8 "$feed_url" 2>/dev/null) || true

    if [[ -z "$xml" ]]; then
        echo -e "${YELLOW}Warning: Update feed unreachable. Using bundled fallback v${FALLBACK_VERSION}.${NC}"
        APP_VERSION="$FALLBACK_VERSION"
        APP_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    # Extract the first <build version="..."> inside the release channel
    # The release channel has status="release"; it appears before beta/canary
    local ver_string
    ver_string=$(echo "$xml" | grep -A1 'status="release"' | grep -oP '(?<=version=")[^"]+' | head -1 || true)

    if [[ -z "$ver_string" ]]; then
        echo -e "${YELLOW}Warning: Could not parse update feed. Using bundled fallback v${FALLBACK_VERSION}.${NC}"
        APP_VERSION="$FALLBACK_VERSION"
        APP_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    # Derive base version (e.g. "Quail 1 | 2026.1.1 Patch 2" -> "2026.1.1")
    local base_ver
    base_ver=$(echo "$ver_string" | grep -oP '\d{4}\.\d+\.\d+' || true)

    if [[ -z "$base_ver" ]]; then
        echo -e "${YELLOW}Warning: Could not parse base version from '${ver_string}'. Using bundled fallback v${FALLBACK_VERSION}.${NC}"
        APP_VERSION="$FALLBACK_VERSION"
        APP_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    # Derive codename slug:
    #   "Quail 1 | 2026.1.1"          -> "quail1"
    #   "Quail 1 | 2026.1.1 Patch 2"  -> "quail1-patch2"
    local codename_raw
    codename_raw=$(echo "$ver_string" | sed -E 's/ \| [0-9].*//' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    local patch_raw
    patch_raw=$(echo "$ver_string" | grep -oiP 'Patch \d+' | tr '[:upper:]' '[:lower:]' | tr -d ' ' || true)

    local slug
    if [[ -n "$patch_raw" ]]; then
        slug="${codename_raw}-${patch_raw}"
    else
        slug="${codename_raw}"
    fi

    echo -e "${BLUE}Latest stable: ${BOLD}${ver_string}${NC}"
    echo -e "${BLUE}Codename slug: ${BOLD}${slug}${NC}"

    # Probe the CDN to find the correct numeric version.
    # The feed omits this number so we scan downward from a ceiling.
    # We start from FALLBACK_VERSION's last segment + a small buffer.
    local base_prefix major_ver patch_floor probe_ver found_ver=""
    major_ver=$(echo "$base_ver" | cut -d. -f1-3)   # e.g. 2026.1.1
    patch_floor=$(echo "$FALLBACK_VERSION" | grep -oP '\d+$' || echo "1") # last segment of fallback, e.g. 10
    local ceiling=$(( patch_floor + 20 ))

    echo -e "${YELLOW}Probing CDN for version number (this is fast)...${NC}"
    for (( n=ceiling; n>=1; n-- )); do
        probe_ver="${major_ver}.${n}"
        local probe_url="${base_dl}/${probe_ver}/android-studio-${slug}-linux.tar.gz"
        local code
        code=$(curl -sI --max-time 4 "$probe_url" -o /dev/null -w "%{http_code}" 2>/dev/null)
        if [[ "$code" == "200" ]]; then
            found_ver="$probe_ver"
            break
        fi
    done

    if [[ -z "$found_ver" ]]; then
        echo -e "${YELLOW}Warning: Could not locate download for '${slug}'. Using bundled fallback v${FALLBACK_VERSION}.${NC}"
        APP_VERSION="$FALLBACK_VERSION"
        APP_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    APP_VERSION="$found_ver"
    APP_CODENAME="$slug"
    echo -e "${GREEN}✓ Resolved: Android Studio ${APP_VERSION} (${APP_CODENAME})${NC}"
}

# Resolve version unless --url was given (user supplied their own) or --offline
if [[ -z "$DOWNLOAD_URL" && "$OFFLINE" == "false" ]]; then
    resolve_latest_version
else
    # Use fallback values for offline/url-override mode
    APP_VERSION="$FALLBACK_VERSION"
    APP_CODENAME="$FALLBACK_CODENAME"
    [[ "$OFFLINE" == "true" ]] && echo -e "${YELLOW}Offline mode: using bundled fallback v${APP_VERSION}.${NC}"
fi

DOWNLOAD_URL_X64="https://dl.google.com/dl/android/studio/ide-zips/${APP_VERSION}/android-studio-${APP_CODENAME}-linux.tar.gz"

# Set download URL if not overridden by --url
[[ -z "$DOWNLOAD_URL" ]] && DOWNLOAD_URL="$DOWNLOAD_URL_X64"

echo -e "${BLUE}Version:       ${BOLD}${APP_VERSION}${NC}"
echo -e "${BLUE}Architecture:  ${BOLD}${ARCH}${NC}"
echo -e "${BLUE}Install scope: ${BOLD}${INSTALL_SCOPE}${NC}"

# ── Path Definitions ─────────────────────────────────────────────────────────
if [[ "$INSTALL_SCOPE" == "system" ]]; then
    TARGET_PARENT_DIR="/opt"
    TARGET_APP_DIR="/opt/android-studio"
    TARGET_BIN_PATH="/usr/local/bin/android-studio"
    DESKTOP_ENTRY_DIR="/usr/share/applications"
    DESKTOP_ENTRY_PATH="${DESKTOP_ENTRY_DIR}/android-studio.desktop"
    ICON_TARGET_DIR="/usr/share/pixmaps"
else
    TARGET_PARENT_DIR="$HOME/.local/share"
    TARGET_APP_DIR="$HOME/.local/share/android-studio"
    TARGET_BIN_PATH="$HOME/.local/bin/android-studio"
    DESKTOP_ENTRY_DIR="$HOME/.local/share/applications"
    DESKTOP_ENTRY_PATH="${DESKTOP_ENTRY_DIR}/android-studio.desktop"
    ICON_TARGET_DIR="$HOME/.local/share/pixmaps"
fi

# ── Version Detection (Upgrade / Reinstall) ──────────────────────────────────
CURRENT_VERSION="none"
if [[ -f "$TARGET_APP_DIR/version.txt" ]]; then
    CURRENT_VERSION=$(cat "$TARGET_APP_DIR/version.txt" 2>/dev/null || echo "unknown")
elif [[ -d "$TARGET_APP_DIR" || -L "$TARGET_BIN_PATH" ]]; then
    CURRENT_VERSION="legacy"
fi

if [[ "$CURRENT_VERSION" != "none" ]]; then
    if [[ "$CURRENT_VERSION" == "legacy" ]]; then
        echo -e "${GREEN}Upgrade Notice: Existing installation detected. Upgrading to v${APP_VERSION}...${NC}"
    elif [[ "$CURRENT_VERSION" == "$APP_VERSION" ]]; then
        echo -e "${YELLOW}Notice: ${APP_NAME_PRETTY} v${CURRENT_VERSION} is already installed. Reinstalling...${NC}"
    else
        echo -e "${GREEN}Upgrade Notice: Upgrading from v${CURRENT_VERSION} to v${APP_VERSION}...${NC}"
    fi

    if [[ "$AUTO_CONFIRM" == "false" && "$DRY_RUN" == "false" ]]; then
        if [[ ! -t 0 ]]; then
            echo -e "${YELLOW}Warning: Non-interactive terminal detected. Proceeding automatically...${NC}"
        else
            echo -ne "\nDo you want to proceed? [Y/n]: "
            read -r CONFIRM
            CONFIRM=$(echo "${CONFIRM:-y}" | tr '[:upper:]' '[:lower:]')
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
                echo -e "${RED}Installation aborted by user.${NC}"
                exit 0
            fi
        fi
    fi
else
    echo -e "${GREEN}New installation: Installing ${APP_NAME_PRETTY} v${APP_VERSION}...${NC}"
fi

# ── Pre-flight: Required Utilities ───────────────────────────────────────────
echo -e "${YELLOW}Verifying system utilities...${NC}"
for util in curl tar sed df awk; do
    if ! command -v "$util" &>/dev/null; then
        echo -e "${RED}Error: Required command '$util' is missing.${NC}" >&2
        exit 1
    fi
done
# update-desktop-database is optional — present on most distros but not all (e.g. NixOS)
if ! command -v update-desktop-database &>/dev/null; then
    echo -e "${YELLOW}Warning: 'update-desktop-database' not found. Desktop entry may not register immediately.${NC}"
fi
echo -e "${GREEN}✓ All core utilities verified.${NC}"

# ── Pre-flight: Disk Space ───────────────────────────────────────────────────
echo -e "${YELLOW}Verifying available disk space...${NC}"
CHECK_PATH="$TARGET_PARENT_DIR"
while [[ ! -d "$CHECK_PATH" ]]; do
    CHECK_PATH=$(dirname "$CHECK_PATH")
done

AVAILABLE_KB=$(df -Pk "$CHECK_PATH" | tail -1 | awk '{print $4}')
# Android Studio is ~1.5 GB; require at least 2 GB headroom
if [[ -n "$AVAILABLE_KB" && "$AVAILABLE_KB" -lt 2097152 ]]; then
    echo -e "${RED}Error: Insufficient disk space in target partition ($CHECK_PATH).${NC}" >&2
    echo -e "${RED}Available: $((AVAILABLE_KB / 1024))MB, Required: ~2000MB headroom.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ Disk space verification passed ($((AVAILABLE_KB / 1024))MB available).${NC}"

# ── Cleanup / Rollback Trap ──────────────────────────────────────────────────
cleanup() {
    if [[ "${INSTALL_SUCCESSFUL}" == "false" && -n "${BACKUP_APP_DIR:-}" && -d "$BACKUP_APP_DIR" ]]; then
        echo -e "\n${RED}Installation interrupted or failed. Rolling back to previous state...${NC}"
        if [[ -d "${TARGET_APP_DIR:-}" ]]; then
            escalate_cmd rm -rf "$TARGET_APP_DIR"
        fi
        escalate_cmd mv "$BACKUP_APP_DIR" "$TARGET_APP_DIR"
        echo -e "${GREEN}✓ Rollback completed successfully.${NC}"
    fi

    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        echo -e "${YELLOW}Cleaning up temporary directory: $TEMP_DIR${NC}"
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

# ── Secure Temporary Directory ───────────────────────────────────────────────
TEMP_DIR=$(mktemp -d -t android-studio-install-XXXXXX)
TEMP_ARCHIVE="$TEMP_DIR/android-studio.tar.gz"

# ── Download ─────────────────────────────────────────────────────────────────
echo -e "${YELLOW}Downloading ${APP_NAME_PRETTY} package...${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}[DRY RUN] Would download from: $DOWNLOAD_URL${NC}"
fi

HTTP_CODE=$(curl -L --progress-bar -w "%{http_code}" -o "$TEMP_ARCHIVE" "$DOWNLOAD_URL")
if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo -e "${RED}Error: Download failed with HTTP status code $HTTP_CODE${NC}" >&2
    echo -e "${RED}URL tried: $DOWNLOAD_URL${NC}" >&2
    echo -e "${YELLOW}Hint: Visit https://developer.android.com/studio to get the latest download URL" \
            "and pass it via --url.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ Downloaded successfully.${NC}"

# ── Retrieve Icon ────────────────────────────────────────────────────────────
echo -e "${YELLOW}Retrieving application icon...${NC}"
LOCAL_ICON="$(dirname "$0")/android-studio.png"
if [[ -f "$LOCAL_ICON" ]]; then
    echo -e "${GREEN}✓ Found local icon file.${NC}"
    cp "$LOCAL_ICON" "$TEMP_DIR/android-studio.png"
else
    # Fall back to the icon bundled inside the archive (extracted later)
    echo -e "${YELLOW}No local icon found. Will extract icon from the package archive.${NC}"
fi

# ── Dry-run Exit ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}[DRY RUN] Would extract files and configure launcher paths.${NC}"
    echo -e "${GREEN}✓ Dry-run completed successfully. Environment and download verified.${NC}"
    exit 0
fi

# ── Extract & Install ────────────────────────────────────────────────────────
echo -e "${YELLOW}Extracting and installing binaries...${NC}"

# Back up existing installation
if [[ -d "$TARGET_APP_DIR" ]]; then
    BACKUP_APP_DIR="${TARGET_APP_DIR}.bak"
    echo -e "${YELLOW}Backing up existing installation to $BACKUP_APP_DIR...${NC}"
    if [[ -d "$BACKUP_APP_DIR" ]]; then
        escalate_cmd rm -rf "$BACKUP_APP_DIR"
    fi
    escalate_cmd mv "$TARGET_APP_DIR" "$BACKUP_APP_DIR"
fi

escalate_cmd mkdir -p "$TARGET_PARENT_DIR"

EXTRACT_TEMP="$TEMP_DIR/extract_temp"
mkdir -p "$EXTRACT_TEMP"
tar -xzf "$TEMP_ARCHIVE" -C "$EXTRACT_TEMP"

# Locate the extracted directory (android-studio)
EXTRACTED_DIR_NAME=""
for d in "$EXTRACT_TEMP"/*/; do
    if [[ -d "$d" ]]; then
        EXTRACTED_DIR_NAME=$(basename "$d")
        break
    fi
done

if [[ -z "$EXTRACTED_DIR_NAME" ]]; then
    echo -e "${RED}Error: Archive extraction failed or archive is empty.${NC}" >&2
    exit 1
fi
echo -e "${BLUE}Detected package folder: $EXTRACTED_DIR_NAME${NC}"

# Move to final destination
escalate_cmd mv "$EXTRACT_TEMP/$EXTRACTED_DIR_NAME" "$TARGET_APP_DIR"

# Write version metadata
echo "$APP_VERSION" | escalate_cmd tee "$TARGET_APP_DIR/version.txt" >/dev/null

# Verify launch script exists
if [[ ! -f "$TARGET_APP_DIR/bin/$BINARY_WRAPPER" ]]; then
    echo -e "${RED}Error: Extraction completed but launch script not found at" \
            "$TARGET_APP_DIR/bin/$BINARY_WRAPPER${NC}" >&2
    exit 1
fi
escalate_cmd chmod +x "$TARGET_APP_DIR/bin/$BINARY_WRAPPER"

# ── Commit ───────────────────────────────────────────────────────────────────
INSTALL_SUCCESSFUL=true
if [[ -n "$BACKUP_APP_DIR" && -d "$BACKUP_APP_DIR" ]]; then
    echo -e "${GREEN}✓ Verification passed. Removing installation backup...${NC}"
    escalate_cmd rm -rf "$BACKUP_APP_DIR"
fi

# ── Wrapper Script / Symlink ─────────────────────────────────────────────────
echo -e "${YELLOW}Configuring system command shortcuts...${NC}"
if [[ "$INSTALL_SCOPE" == "user" ]]; then
    mkdir -p "$(dirname "$TARGET_BIN_PATH")"
fi

# Create a thin wrapper so the binary name is "android-studio" in the shell
WRAPPER_SCRIPT="$TEMP_DIR/android-studio-wrapper"
cat >"$WRAPPER_SCRIPT" <<'WRAPPER'
#!/usr/bin/env bash
exec "__TARGET_APP_DIR__/bin/__BINARY_WRAPPER__" "$@"
WRAPPER
sed -i "s|__TARGET_APP_DIR__|${TARGET_APP_DIR}|g" "$WRAPPER_SCRIPT"
sed -i "s|__BINARY_WRAPPER__|${BINARY_WRAPPER}|g" "$WRAPPER_SCRIPT"
chmod +x "$WRAPPER_SCRIPT"

escalate_cmd rm -f "$TARGET_BIN_PATH"
escalate_cmd cp "$WRAPPER_SCRIPT" "$TARGET_BIN_PATH"
escalate_cmd chmod +x "$TARGET_BIN_PATH"

# ── Icon Installation ────────────────────────────────────────────────────────
echo -e "${YELLOW}Installing application icon...${NC}"
escalate_cmd mkdir -p "$ICON_TARGET_DIR"

# Try several common icon locations inside the extracted archive
ICON_SRC=""
for candidate in \
    "$TARGET_APP_DIR/bin/studio.png" \
    "$TARGET_APP_DIR/bin/studio_128.png" \
    "$TARGET_APP_DIR/plugins/android/resources/draw/studio.png"; do
    if [[ -f "$candidate" ]]; then
        ICON_SRC="$candidate"
        break
    fi
done

if [[ -n "$ICON_SRC" ]]; then
    escalate_cmd cp "$ICON_SRC" "$ICON_TARGET_DIR/android-studio.png"
    escalate_cmd chmod 644 "$ICON_TARGET_DIR/android-studio.png"
    echo -e "${GREEN}✓ Icon installed from archive.${NC}"
elif [[ -f "$TEMP_DIR/android-studio.png" ]]; then
    escalate_cmd cp "$TEMP_DIR/android-studio.png" "$ICON_TARGET_DIR/android-studio.png"
    escalate_cmd chmod 644 "$ICON_TARGET_DIR/android-studio.png"
    echo -e "${GREEN}✓ Icon installed from local copy.${NC}"
else
    echo -e "${YELLOW}Warning: Icon not found in archive. Skipping icon installation.${NC}"
    echo -e "${YELLOW}You can copy a PNG to ${ICON_TARGET_DIR}/android-studio.png manually.${NC}"
fi

# ── Desktop Entry ────────────────────────────────────────────────────────────
echo -e "${YELLOW}Generating Desktop integration entry...${NC}"
ICON_LOOKUP="android-studio"

TEMP_DESKTOP="$TEMP_DIR/android-studio.desktop"
cat >"$TEMP_DESKTOP" <<'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=__NAME__
Comment=__COMMENT__
GenericName=IDE
Exec=__EXEC_PATH__ %f
Icon=__ICON__
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=__WM_CLASS__
Actions=new-project;

[Desktop Action new-project]
Name=New Project
Exec=__EXEC_PATH__
Icon=__ICON__
DESKTOP_EOF

sed -i "s|__NAME__|$APP_NAME_PRETTY|g"     "$TEMP_DESKTOP"
sed -i "s|__COMMENT__|$APP_COMMENT|g"      "$TEMP_DESKTOP"
sed -i "s|__EXEC_PATH__|$TARGET_BIN_PATH|g" "$TEMP_DESKTOP"
sed -i "s|__ICON__|$ICON_LOOKUP|g"         "$TEMP_DESKTOP"
sed -i "s|__WM_CLASS__|$WM_CLASS|g"        "$TEMP_DESKTOP"

escalate_cmd mkdir -p "$DESKTOP_ENTRY_DIR"
escalate_cmd cp "$TEMP_DESKTOP" "$DESKTOP_ENTRY_PATH"
escalate_cmd chmod 644 "$DESKTOP_ENTRY_PATH"

# ── SELinux Context Restore (Fedora) ─────────────────────────────────────────
if [[ "$INSTALL_SCOPE" == "system" ]] && command -v restorecon &>/dev/null; then
    echo -e "${YELLOW}Restoring SELinux contexts for $TARGET_APP_DIR...${NC}"
    sudo restorecon -R "$TARGET_APP_DIR" || true
fi

# ── Update Desktop Database ──────────────────────────────────────────────────
echo -e "${YELLOW}Updating desktop database...${NC}"
if command -v update-desktop-database &>/dev/null; then
    escalate_cmd update-desktop-database "$DESKTOP_ENTRY_DIR" || true
fi
escalate_cmd touch "$DESKTOP_ENTRY_PATH"

# ── Success ──────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}✓ ${APP_NAME_PRETTY} ${APP_VERSION} successfully installed!${NC}"
echo -e "You can launch the application via:"
echo -e "  * Terminal command:   ${BOLD}android-studio${NC}"
echo -e "  * Application menu:   ${BOLD}${APP_NAME_PRETTY}${NC}"
echo ""
echo -e "${YELLOW}${BOLD}📝 First-run tip:${NC}"
echo -e "  On first launch, Android Studio will guide you through SDK setup."
echo -e "  Set your SDK location to: ${BOLD}\$HOME/Android/Sdk${NC}"

# ── PATH check for user installs ─────────────────────────────────────────────
if [[ "$INSTALL_SCOPE" == "user" ]]; then
    BIN_DIR=$(dirname "$TARGET_BIN_PATH")
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        SHELL_NAME=$(basename "${SHELL:-bash}")
        CONFIG_FILE="$HOME/.bashrc"
        [[ "$SHELL_NAME" == "zsh" ]] && CONFIG_FILE="$HOME/.zshrc"
        [[ "$SHELL_NAME" == "ksh" ]] && CONFIG_FILE="$HOME/.kshrc"

        echo -e "\n${YELLOW}${BOLD}⚠️  Shell Configuration Notice:${NC}"
        echo -e "  The local bin directory (${BOLD}${BIN_DIR}${NC}) is not in your \$PATH."
        echo -e "  To use the '${BOLD}android-studio${NC}' command, run:"
        echo -e "  ${BLUE}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${CONFIG_FILE} && source ${CONFIG_FILE}${NC}"
    fi
fi
