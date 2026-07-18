#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

FALLBACK_VERSION="2026.1.2.10"
FALLBACK_CODENAME="quail2"

RESOLVED_VERSION=""
RESOLVED_CODENAME=""
OUTDIR="${OUTDIR:-$HOME/rpkg}"

# ── Version Auto-Detection ──────────────────────────────────────────────────
resolve_latest_version() {
    local feed_url="https://dl.google.com/android/studio/patches/updates.xml"
    local base_dl="https://dl.google.com/dl/android/studio/ide-zips"

    echo -e "${YELLOW}Checking updates feed for latest version...${NC}"

    local xml
    xml=$(curl -fsSL --max-time 8 "$feed_url" 2>/dev/null) || true

    if [[ -z "$xml" ]]; then
        echo -e "${YELLOW}Warning: Feed unreachable. Using fallback v${FALLBACK_VERSION}.${NC}"
        RESOLVED_VERSION="$FALLBACK_VERSION"
        RESOLVED_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    local ver_string
    ver_string=$(echo "$xml" | grep -A1 'status="release"' | grep -oP '(?<=version=")[^"]+' | head -1 || true)

    if [[ -z "$ver_string" ]]; then
        echo -e "${YELLOW}Warning: Could not parse feed. Using fallback v${FALLBACK_VERSION}.${NC}"
        RESOLVED_VERSION="$FALLBACK_VERSION"
        RESOLVED_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    local base_ver
    base_ver=$(echo "$ver_string" | grep -oP '\d{4}\.\d+\.\d+' || true)

    if [[ -z "$base_ver" ]]; then
        echo -e "${YELLOW}Warning: Could not parse base version. Using fallback v${FALLBACK_VERSION}.${NC}"
        RESOLVED_VERSION="$FALLBACK_VERSION"
        RESOLVED_CODENAME="$FALLBACK_CODENAME"
        return
    fi

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

    local major_ver patch_floor probe_ver found_ver=""
    major_ver=$(echo "$base_ver" | cut -d. -f1-3)
    patch_floor=$(echo "$FALLBACK_VERSION" | grep -oP '\d+$' || echo "1")
    local ceiling=$(( patch_floor + 20 ))

    echo -e "${YELLOW}Probing CDN for exact version...${NC}"
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
        echo -e "${YELLOW}Warning: CDN check failed. Using fallback v${FALLBACK_VERSION}.${NC}"
        RESOLVED_VERSION="$FALLBACK_VERSION"
        RESOLVED_CODENAME="$FALLBACK_CODENAME"
        return
    fi

    RESOLVED_VERSION="$found_ver"
    RESOLVED_CODENAME="$slug"
}

# ── Build RPM ───────────────────────────────────────────────────────────────
build_rpm() {
    local version="$1"
    local slug="$2"

    echo -e "\n${BLUE}${BOLD}=== Building RPM Package ===${NC}"

    for tool in spectool rpkg; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${RED}Error: Required packaging utility '${tool}' is missing.${NC}" >&2
            echo -e "Please install it: ${BLUE}sudo dnf install -y ${tool}${NC}" >&2
            exit 1
        fi
    done

    # Ensure spec file is aligned with current version
    sed -i "s/^Version:.*/Version:        ${version}/" android-studio.spec
    sed -i "s|android-studio-.*-linux.tar.gz|android-studio-${slug}-linux.tar.gz|g" android-studio.spec

    echo "Downloading sources..."
    spectool -gS android-studio.spec

    echo "Building RPM package..."
    rpkg local --outdir "$OUTDIR" --spec android-studio.spec

    echo -e "${GREEN}✓ RPM package built successfully in ${OUTDIR}${NC}"
}

# ── Build DEB ───────────────────────────────────────────────────────────────
build_deb() {
    local version="$1"
    local slug="$2"
    local dl_url="$3"

    echo -e "\n${BLUE}${BOLD}=== Building DEB Package ===${NC}"

    if ! command -v dpkg-deb &>/dev/null; then
        echo -e "${RED}Error: Required utility 'dpkg-deb' is missing.${NC}" >&2
        echo -e "Please install it: ${BLUE}sudo dnf install -y dpkg${NC} (or apt install dpkg)" >&2
        exit 1
    fi

    local stage_dir
    stage_dir=$(mktemp -d -t android-studio-deb-XXXXXX)
    # Ensure cleanup on exit
    cleanup_deb() {
        rm -rf "$stage_dir"
    }
    trap cleanup_deb EXIT INT TERM

    local install_dir="$stage_dir/opt/android-studio"
    local bin_dir="$stage_dir/usr/bin"
    local desktop_dir="$stage_dir/usr/share/applications"
    local pixmap_dir="$stage_dir/usr/share/pixmaps"
    local control_dir="$stage_dir/DEBIAN"

    mkdir -p "$install_dir" "$bin_dir" "$desktop_dir" "$pixmap_dir" "$control_dir"

    local tarball="android-studio-${slug}-linux.tar.gz"

    if [[ ! -f "$tarball" ]]; then
        echo "Downloading Android Studio package..."
        curl -L --progress-bar -o "$tarball" "$dl_url"
    else
        echo "Using existing local package: $tarball"
    fi

    echo "Extracting to staging area..."
    tar -xzf "$tarball" -C "$stage_dir/opt"

    if [[ ! -d "$install_dir" ]]; then
        local ext_dir
        ext_dir=$(find "$stage_dir/opt" -maxdepth 1 -mindepth 1 -type d | head -n 1)
        if [[ -n "$ext_dir" ]]; then
            mv "$ext_dir" "$install_dir"
        else
            echo -e "${RED}Error: Extraction failed.${NC}" >&2
            exit 1
        fi
    fi

    echo "$version" > "$install_dir/version.txt"
    chmod +x "$install_dir/bin/studio.sh"

    echo "Creating launcher wrapper..."
    cat > "$bin_dir/android-studio" <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/android-studio/bin/studio.sh "$@"
WRAPPER
    chmod 755 "$bin_dir/android-studio"

    echo "Configuring desktop integration..."
    if [[ -f "android-studio.desktop" ]]; then
        cp "android-studio.desktop" "$desktop_dir/android-studio.desktop"
    else
        cat > "$desktop_dir/android-studio.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Android Studio
Comment=The official IDE for Android development
GenericName=IDE
Exec=/usr/bin/android-studio %f
Icon=android-studio
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=jetbrains-studio
Actions=new-project;

[Desktop Action new-project]
Name=New Project
Exec=/usr/bin/android-studio
Icon=android-studio
DESKTOP
    fi
    chmod 644 "$desktop_dir/android-studio.desktop"

    # Extract icon
    local icon_src=""
    for candidate in \
        "$install_dir/bin/studio.png" \
        "$install_dir/bin/studio_128.png"; do
        if [[ -f "$candidate" ]]; then
            icon_src="$candidate"
            break
        fi
    done
    if [[ -n "$icon_src" ]]; then
        cp "$icon_src" "$pixmap_dir/android-studio.png"
        chmod 644 "$pixmap_dir/android-studio.png"
    fi

    echo "Writing package control file..."
    cat > "$control_dir/control" <<CONTROL
Package: android-studio
Version: ${version}
Section: devel
Priority: optional
Architecture: amd64
Maintainer: solder3t <solder3t@users.noreply.github.com>
Description: The official IDE for Android development
 Android Studio is the official integrated development environment (IDE)
 for Android app development, based on IntelliJ IDEA. It provides a
 fast, feature-rich environment for building apps for every Android device.
 Repackaged precompiled upstream binaries.
Depends: liberation-fonts, libx11-6, libxext6, libxrender1, libxtst6, libxi6, libfreetype6, libfontconfig1, tar, gzip
CONTROL
    chmod 644 "$control_dir/control"

    echo "Building Debian package..."
    local deb_name="android-studio_${version}-1_amd64.deb"
    dpkg-deb --build "$stage_dir" "$OUTDIR/$deb_name"

    echo -e "${GREEN}✓ Debian package built successfully: $OUTDIR/$deb_name${NC}"
    trap - EXIT
}

# ── Main Entrypoint ──────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

# Parse package format target
TARGET=""
if [[ $# -gt 0 ]]; then
    case "$1" in
        rpm)    TARGET="rpm" ;;
        deb)    TARGET="deb" ;;
        all)    TARGET="all" ;;
        -h|--help)
            echo "Usage: $(basename "$0") [rpm | deb | all]"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown target '$1'. Choose 'rpm', 'deb', or 'all'.${NC}" >&2
            exit 1
            ;;
    esac
fi

# Auto-detect target format based on packaging tools if not specified
if [[ -z "$TARGET" ]]; then
    if command -v rpkg &>/dev/null && command -v spectool &>/dev/null; then
        TARGET="rpm"
    elif command -v dpkg-deb &>/dev/null; then
        TARGET="deb"
    else
        # Default fallback depending on host command existence
        if command -v dnf &>/dev/null; then
            TARGET="rpm"
        else
            TARGET="deb"
        fi
    fi
    echo -e "${YELLOW}Auto-detected target format: ${BOLD}${TARGET}${NC}"
fi

resolve_latest_version
DL_URL="https://dl.google.com/dl/android/studio/ide-zips/${RESOLVED_VERSION}/android-studio-${RESOLVED_CODENAME}-linux.tar.gz"

echo -e "${BLUE}Resolved version: ${BOLD}${RESOLVED_VERSION} (${RESOLVED_CODENAME})${NC}"

if [[ "$TARGET" == "rpm" || "$TARGET" == "all" ]]; then
    build_rpm "$RESOLVED_VERSION" "$RESOLVED_CODENAME"
fi

if [[ "$TARGET" == "deb" || "$TARGET" == "all" ]]; then
    build_deb "$RESOLVED_VERSION" "$RESOLVED_CODENAME" "$DL_URL"
fi
