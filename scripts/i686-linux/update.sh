#!/bin/sh
set -eu

REPOSITORY="${CODEX_I686_RELEASE_REPOSITORY:-andy5090/codex-for-i686-linux}"
RELEASE_TAG="${CODEX_I686_RELEASE_TAG:-i686-latest}"
INSTALLER_URL="${CODEX_I686_INSTALLER_URL:-https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG/install-codex-i686.sh}"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-i686-update.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

curl -fL --retry 3 \
    "$INSTALLER_URL" \
    -o "$TEMP_DIR/install-codex-i686.sh"

sh "$TEMP_DIR/install-codex-i686.sh"
