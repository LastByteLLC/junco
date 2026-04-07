#!/bin/bash
# install.sh — Install junco from the latest GitHub Release
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LastByteLLC/junco/master/install.sh | bash
#
# Options:
#   JUNCO_INSTALL_DIR — Override install directory (default: /usr/local/bin)
#   JUNCO_VERSION     — Install a specific version (default: latest)

set -euo pipefail

REPO="LastByteLLC/junco"
INSTALL_DIR="${JUNCO_INSTALL_DIR:-/usr/local/bin}"
BINARY_NAME="junco-arm64"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${DIM}$1${RESET}"; }
ok()    { echo -e "${GREEN}$1${RESET}"; }
err()   { echo -e "${RED}error: $1${RESET}" >&2; exit 1; }

# --- Pre-flight checks ---

# macOS only
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "junco requires macOS. Detected: $(uname -s)"
fi

# Apple Silicon only
if [[ "$(uname -m)" != "arm64" ]]; then
  err "junco requires Apple Silicon (arm64). Detected: $(uname -m)"
fi

# Check macOS version (need 26+)
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$MACOS_MAJOR" -lt 26 ]]; then
  err "junco requires macOS 26 or later. Detected: macOS $(sw_vers -productVersion)"
fi

# Need curl
command -v curl >/dev/null 2>&1 || err "curl is required but not found."

# --- Resolve version ---

if [[ -n "${JUNCO_VERSION:-}" ]]; then
  TAG="v${JUNCO_VERSION#v}"
  RELEASE_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
else
  RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
fi

info "Fetching release info..."
RELEASE_JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" "$RELEASE_URL" 2>/dev/null)" \
  || err "Failed to fetch release info. Check your network connection."

# Extract version
VERSION="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/')"
if [[ -z "$VERSION" ]]; then
  err "Could not determine version from release."
fi

# Skip LoRA-only releases
if echo "$VERSION" | grep -q "lora"; then
  err "Latest release is a LoRA adapter release (v${VERSION}), not a binary release."
fi

echo -e "${BOLD}Installing junco v${VERSION}${RESET}"

# --- Download binary ---

DOWNLOAD_URL="$(echo "$RELEASE_JSON" | grep "browser_download_url.*${BINARY_NAME}" | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"
if [[ -z "$DOWNLOAD_URL" ]]; then
  err "Could not find ${BINARY_NAME} asset in release v${VERSION}."
fi

CHECKSUMS_URL="$(echo "$RELEASE_JSON" | grep 'browser_download_url.*checksums.txt' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading junco-arm64..."
curl -fsSL -o "${TMPDIR}/junco" "$DOWNLOAD_URL" \
  || err "Failed to download binary."

# --- Verify checksum ---

if [[ -n "${CHECKSUMS_URL:-}" ]]; then
  info "Verifying checksum..."
  CHECKSUMS="$(curl -fsSL "$CHECKSUMS_URL" 2>/dev/null || true)"
  if [[ -n "$CHECKSUMS" ]]; then
    EXPECTED="$(echo "$CHECKSUMS" | grep "$BINARY_NAME" | awk '{print $1}')"
    ACTUAL="$(shasum -a 256 "${TMPDIR}/junco" | awk '{print $1}')"
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
      err "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Actual:   ${ACTUAL}"
    fi
    ok "Checksum verified."
  fi
fi

# --- Install ---

chmod +x "${TMPDIR}/junco"

# Create install dir if needed
if [[ ! -d "$INSTALL_DIR" ]]; then
  info "Creating ${INSTALL_DIR}..."
  sudo mkdir -p "$INSTALL_DIR"
fi

# Install (may need sudo)
if [[ -w "$INSTALL_DIR" ]]; then
  mv "${TMPDIR}/junco" "${INSTALL_DIR}/junco"
else
  info "Requesting permission to install to ${INSTALL_DIR}..."
  sudo mv "${TMPDIR}/junco" "${INSTALL_DIR}/junco"
fi

# --- Verify installation ---

if command -v junco >/dev/null 2>&1; then
  INSTALLED_VERSION="$(junco --version 2>/dev/null || true)"
  ok "junco installed successfully! (${INSTALLED_VERSION})"
else
  ok "junco installed to ${INSTALL_DIR}/junco"
  echo ""
  echo "Add ${INSTALL_DIR} to your PATH if it's not already:"
  echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
fi

echo ""
echo "Get started:"
echo "  cd your-swift-project"
echo "  junco"
echo ""
echo "Run 'junco update' anytime to get the latest version."
