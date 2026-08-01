#!/bin/sh
set -eu

REPOSITORY="${CODEX_I686_RELEASE_REPOSITORY:-andy5090/codex-for-i686-linux}"
RELEASE_TAG="${CODEX_I686_RELEASE_TAG:-i686-latest}"
ARCHIVE="codex-i686-unknown-linux-musl.tar.gz"
DEFAULT_BASE_URL="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
BASE_URL="${CODEX_I686_RELEASE_BASE_URL:-$DEFAULT_BASE_URL}"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-i686-install.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

curl -fL --retry 3 \
    "$BASE_URL/$ARCHIVE" \
    -o "$TEMP_DIR/$ARCHIVE"
curl -fL --retry 3 \
    "$BASE_URL/$ARCHIVE.sha256" \
    -o "$TEMP_DIR/$ARCHIVE.sha256"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$TEMP_DIR" && sha256sum -c "$ARCHIVE.sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$TEMP_DIR" && shasum -a 256 -c "$ARCHIVE.sha256")
else
    echo "sha256sum or shasum is required to verify the download." >&2
    exit 1
fi

PACKAGE_DIR_NAME=$(tar -tzf "$TEMP_DIR/$ARCHIVE" | sed -n '1s|/.*||p')
case "$PACKAGE_DIR_NAME" in
    codex-i686-unknown-linux-musl-*)
        ;;
    *)
        echo "The downloaded archive has an unexpected layout." >&2
        exit 1
        ;;
esac

tar -xzf "$TEMP_DIR/$ARCHIVE" -C "$TEMP_DIR"
PACKAGE_DIR="$TEMP_DIR/$PACKAGE_DIR_NAME"
if [ ! -x "$PACKAGE_DIR/install.sh" ]; then
    echo "The downloaded Codex i686 package is incomplete." >&2
    exit 1
fi

"$PACKAGE_DIR/install.sh"
