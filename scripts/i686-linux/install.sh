#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_ID=$(sed -n '1p' "$PACKAGE_DIR/BUILD-ID")
DATA_ROOT="${CODEX_I686_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/codex-i686}"
BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
RELEASES_DIR="$DATA_ROOT/releases"
RELEASE_DIR="$RELEASES_DIR/$BUILD_ID"
CODEX_LINK="$BIN_DIR/codex"

case "$(uname -m)" in
    i386 | i486 | i586 | i686 | x86_64)
        ;;
    *)
        echo "This package requires a 32-bit x86-compatible Linux kernel." >&2
        exit 1
        ;;
esac

if [ "${CODEX_I686_SKIP_CPU_CHECK:-0}" != 1 ] &&
    [ -r /proc/cpuinfo ] &&
    ! grep -qi '\bsse2\b' /proc/cpuinfo; then
    echo "This Codex build requires an SSE2-capable processor." >&2
    exit 1
fi

if [ ! -x "$PACKAGE_DIR/bin/codex" ] ||
    [ ! -x "$PACKAGE_DIR/codex-path/rg" ] ||
    [ ! -x "$PACKAGE_DIR/codex-resources/bwrap" ]; then
    echo "The Codex i686 package is incomplete." >&2
    exit 1
fi

mkdir -p "$RELEASES_DIR" "$BIN_DIR"
if [ ! -d "$RELEASE_DIR" ]; then
    STAGE_DIR=$(mktemp -d "$RELEASES_DIR/.staging.XXXXXX")
    trap 'rm -rf "$STAGE_DIR"' EXIT HUP INT TERM
    cp -R \
        "$PACKAGE_DIR/bin" \
        "$PACKAGE_DIR/codex-path" \
        "$PACKAGE_DIR/codex-resources" \
        "$PACKAGE_DIR/codex-package.json" \
        "$PACKAGE_DIR/BUILD-ID" \
        "$PACKAGE_DIR/README.txt" \
        "$STAGE_DIR/"
    mv "$STAGE_DIR" "$RELEASE_DIR"
    trap - EXIT HUP INT TERM
fi

if [ ! -x "$RELEASE_DIR/bin/codex" ]; then
    echo "The installed release is incomplete: $RELEASE_DIR" >&2
    exit 1
fi

if [ -e "$CODEX_LINK" ] && [ ! -L "$CODEX_LINK" ]; then
    echo "Refusing to replace the existing non-symlink: $CODEX_LINK" >&2
    echo "Set CODEX_INSTALL_DIR to another directory and run install.sh again." >&2
    exit 1
fi

ln -sfn "$RELEASE_DIR/bin/codex" "$CODEX_LINK"

"$CODEX_LINK" --version
echo "Installed Codex i686 at $CODEX_LINK"
case ":$PATH:" in
    *":$BIN_DIR:"*)
        echo "Run: codex login --device-auth"
        ;;
    *)
        echo "Add this directory to PATH: $BIN_DIR"
        echo "Then run: codex login --device-auth"
        ;;
esac
