#!/bin/bash

set -euo pipefail

REPO="karle0wne/context-for-ai"
VERSION="${VERSION:-latest}"
PREFIX="/usr/local/bin"
FORCE=false
DRY_RUN=false

print_usage() {
  echo "Usage: install.sh [--prefix DIR] [--force] [--dry-run]"
  echo ""
  echo "Options:"
  echo "  --prefix DIR   Install to DIR instead of /usr/local/bin"
  echo "  --force        Overwrite existing installation"
  echo "  --dry-run      Show what would be done, but don’t execute"
  exit 0
}

log()  { echo "💬 $*"; }
warn() { echo "⚠️ $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) print_usage ;;
    *) warn "Unknown argument: $1"; print_usage ;;
  esac
done

if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep tag_name | cut -d '"' -f4)
  [ -z "$VERSION" ] && echo "❌ Failed to fetch latest version." && exit 1
fi

URL="https://github.com/$REPO/releases/download/$VERSION/context-for-ai.tar.gz"
TMP_DIR=$(mktemp -d)
DEST="$PREFIX/context-for-ai"

log "Detected latest version: $VERSION"
log "Downloading: $URL"
$DRY_RUN || curl -sL "$URL" -o "$TMP_DIR/archive.tar.gz"

log "Extracting..."
$DRY_RUN || tar -xzf "$TMP_DIR/archive.tar.gz" -C "$TMP_DIR"

log "Searching for binary..."
SRC=$($DRY_RUN || find "$TMP_DIR" -type f -name context-for-ai -perm -u+x | head -n 1)

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "❌ context-for-ai binary not found in archive"
  echo "📦 Archive contents:"
  tar -tzf "$TMP_DIR/archive.tar.gz"
  exit 1
fi

if [[ -f "$DEST" && "$FORCE" != true ]]; then
  warn "$DEST already exists. Use --force to overwrite."
  exit 1
fi

log "Installing to: $DEST"
$DRY_RUN || mkdir -p "$PREFIX"
$DRY_RUN || cp "$SRC" "$DEST"
$DRY_RUN || chmod +x "$DEST"

log "✅ Installed context-for-ai to $DEST"
$DRY_RUN || "$DEST" --version
