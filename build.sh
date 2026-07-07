#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

for tool in spectool rpkg; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${RED}Error: Required packaging utility '${tool}' is missing.${NC}" >&2
        echo -e "Please install it by running: ${BLUE}sudo dnf install -y ${tool}${NC}" >&2
        exit 1
    fi
done

OUTDIR="${OUTDIR:-$HOME/rpkg/}"
mkdir -p "$OUTDIR"

echo "Downloading sources for android-studio..."
spectool -gS android-studio.spec

echo "Building android-studio RPM package..."
rpkg local --outdir "$OUTDIR" --spec android-studio.spec

echo "Done! Built RPMs can be found in $OUTDIR"
