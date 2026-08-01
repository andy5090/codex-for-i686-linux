#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
DIST_DIR="$REPO_ROOT/dist"
BUILD_IMAGE="${CODEX_I686_BUILD_IMAGE:-docker.io/messense/rust-musl-cross:i686-musl}"
TARGET="i686-unknown-linux-musl"
TARGET_VOLUME="${CODEX_I686_TARGET_VOLUME:-codex-i686-musl-target}"
CARGO_VOLUME="${CODEX_I686_CARGO_VOLUME:-codex-i686-musl-cargo}"
BUILD_JOBS="${CODEX_I686_BUILD_JOBS:-2}"
RIPGREP_VERSION="15.2.0"
LIBCAP_VERSION="2.78"
LIBCAP_SHA256="0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11"

CONTAINER_ENGINE="${CODEX_I686_CONTAINER_ENGINE:-}"
if [ -z "$CONTAINER_ENGINE" ]; then
    DOCKER_SERVER_VERSION=""
    if command -v docker >/dev/null 2>&1; then
        DOCKER_SERVER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
    fi
    if [ -n "$DOCKER_SERVER_VERSION" ]; then
        CONTAINER_ENGINE="docker"
    elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        CONTAINER_ENGINE="podman"
    else
        echo "A running Docker or Podman engine is required." >&2
        exit 1
    fi
elif ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
    echo "Container engine not found: $CONTAINER_ENGINE" >&2
    exit 1
fi

ENGINE_AUTH_FILE=""
if [ "$CONTAINER_ENGINE" = "podman" ]; then
    ENGINE_AUTH_FILE=$(mktemp)
    trap 'rm -f "$ENGINE_AUTH_FILE"' EXIT HUP INT TERM
    printf '{"auths": {}}\n' >"$ENGINE_AUTH_FILE"
    export REGISTRY_AUTH_FILE="$ENGINE_AUTH_FILE"
fi

COMMIT=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)
SOURCE_DATE_EPOCH=$(git -C "$REPO_ROOT" show -s --format=%ct HEAD)
if [ -n "$(git -C "$REPO_ROOT" status --short)" ]; then
    SOURCE_STATE_HASH=$(
        {
            git -C "$REPO_ROOT" diff --binary --no-ext-diff HEAD
            git -C "$REPO_ROOT" ls-files --others --exclude-standard |
                LC_ALL=C sort |
                while IFS= read -r source_path; do
                    printf '%s\n' "$source_path"
                    git -C "$REPO_ROOT" hash-object "$source_path"
                done
        } | git hash-object --stdin | cut -c 1-12
    )
    BUILD_ID="${COMMIT}-local-${SOURCE_STATE_HASH}"
else
    BUILD_ID="$COMMIT"
fi

ARCHIVE_NAME="codex-${TARGET}-${BUILD_ID}.tar.gz"
mkdir -p "$DIST_DIR"

printf 'Using container engine: %s\n' "$CONTAINER_ENGINE"
"$CONTAINER_ENGINE" run --rm --platform linux/amd64 \
    -e "BUILD_ID=$BUILD_ID" \
    -e "CARGO_BUILD_JOBS=$BUILD_JOBS" \
    -e "CARGO_HOME=/cargo" \
    -e "CARGO_PROFILE_RELEASE_DEBUG=none" \
    -e "CARGO_PROFILE_RELEASE_LTO=false" \
    -e "CARGO_TARGET_DIR=/target" \
    -e "LIBCAP_SHA256=$LIBCAP_SHA256" \
    -e "LIBCAP_VERSION=$LIBCAP_VERSION" \
    -e "RIPGREP_VERSION=$RIPGREP_VERSION" \
    -e "RUSTUP_TOOLCHAIN=stable" \
    -e "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" \
    -e "TARGET=$TARGET" \
    -v "$REPO_ROOT:/work:ro" \
    -v "$DIST_DIR:/out" \
    -v "$TARGET_VOLUME:/target" \
    -v "$CARGO_VOLUME:/cargo" \
    "$BUILD_IMAGE" \
    sh -lc '
set -eu

cd /work/codex-rs
export RUSTFLAGS="-C target-cpu=pentium4"

if ! command -v pkg-config >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq pkg-config >/dev/null
fi

LIBCAP_ROOT="/target/i686-libcap-$LIBCAP_VERSION"
if [ ! -f "$LIBCAP_ROOT/lib/libcap.a" ]; then
    LIBCAP_BUILD=$(mktemp -d)
    trap "rm -rf \"$LIBCAP_BUILD\"" EXIT HUP INT TERM
    cd "$LIBCAP_BUILD"
    LIBCAP_ARCHIVE="libcap-$LIBCAP_VERSION.tar.xz"
    curl -fsSLO \
        "https://mirrors.edge.kernel.org/pub/linux/libs/security/linux-privs/libcap2/$LIBCAP_ARCHIVE"
    printf "%s  %s\n" "$LIBCAP_SHA256" "$LIBCAP_ARCHIVE" | sha256sum -c -
    tar -xf "$LIBCAP_ARCHIVE"
    make \
        -C "libcap-$LIBCAP_VERSION/libcap" \
        CROSS_COMPILE=i686-unknown-linux-musl- \
        BUILD_CC=gcc \
        SHARED=no \
        PAM_CAP=no \
        GOLANG=no
    mkdir -p \
        "$LIBCAP_ROOT/include/linux" \
        "$LIBCAP_ROOT/include/sys" \
        "$LIBCAP_ROOT/lib/pkgconfig"
    install -m 0644 \
        "libcap-$LIBCAP_VERSION/libcap/libcap.a" \
        "$LIBCAP_ROOT/lib/libcap.a"
    install -m 0644 \
        "libcap-$LIBCAP_VERSION/libcap/include/sys/capability.h" \
        "$LIBCAP_ROOT/include/sys/capability.h"
    install -m 0644 \
        "libcap-$LIBCAP_VERSION/libcap/include/uapi/linux/capability.h" \
        "$LIBCAP_ROOT/include/linux/capability.h"
    cat >"$LIBCAP_ROOT/lib/pkgconfig/libcap.pc" <<PC
prefix=$LIBCAP_ROOT
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libcap
Description: POSIX capabilities library
Version: $LIBCAP_VERSION
Libs: -L\${libdir} -lcap
Cflags: -I\${includedir}
PC
    rm -rf "$LIBCAP_BUILD"
    trap - EXIT HUP INT TERM
    cd /work/codex-rs
fi

export LIBCAP_STATIC=1
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_PATH="$LIBCAP_ROOT/lib/pkgconfig"
export TARGET_PKG_CONFIG_ALLOW_CROSS=1
export TARGET_PKG_CONFIG_LIBDIR="$LIBCAP_ROOT/lib/pkgconfig"
export TARGET_PKG_CONFIG_PATH="$LIBCAP_ROOT/lib/pkgconfig"
export TARGET_PKG_CONFIG_SYSROOT_DIR=/

cargo build \
    --locked \
    --target "$TARGET" \
    --profile release \
    --bin bwrap

STRIP=i686-unknown-linux-musl-strip
BINARY_DIR="/target/$TARGET/release"
"$STRIP" "$BINARY_DIR/bwrap"
BWRAP_SHA256=$(sha256sum "$BINARY_DIR/bwrap" | cut -d " " -f 1)
export CODEX_BWRAP_SHA256="$BWRAP_SHA256"

cargo build \
    --locked \
    --target "$TARGET" \
    --profile release \
    --bin codex

RG_ROOT="/target/i686-ripgrep-$RIPGREP_VERSION"
if [ ! -x "$RG_ROOT/bin/rg" ]; then
    cargo install ripgrep \
        --locked \
        --version "$RIPGREP_VERSION" \
        --target "$TARGET" \
        --root "$RG_ROOT"
fi

STAGE_ROOT=$(mktemp -d)
PACKAGE_NAME="codex-$TARGET-$BUILD_ID"
STAGE="$STAGE_ROOT/$PACKAGE_NAME"
trap "rm -rf \"$STAGE_ROOT\"" EXIT HUP INT TERM
mkdir -p \
    "$STAGE/bin" \
    "$STAGE/codex-path" \
    "$STAGE/codex-resources"

install -m 0755 "$BINARY_DIR/codex" "$STAGE/bin/codex"
install -m 0755 "$BINARY_DIR/bwrap" "$STAGE/codex-resources/bwrap"
install -m 0755 "$RG_ROOT/bin/rg" "$STAGE/codex-path/rg"
"$STRIP" "$STAGE/bin/codex" "$STAGE/codex-path/rg"

install -m 0755 /work/scripts/i686-linux/install.sh "$STAGE/install.sh"
install -m 0644 /work/scripts/i686-linux/README.txt "$STAGE/README.txt"
printf "%s\n" "$BUILD_ID" >"$STAGE/BUILD-ID"

VERSION=$(sed -n \
    "s/^version = \"\\([^\"]*\\)\"/\\1/p" \
    /work/codex-rs/Cargo.toml | head -n 1)
python3 - "$STAGE/codex-package.json" "$VERSION" "$TARGET" "$BUILD_ID" <<'"'"'PY'"'"'
import json
import sys

path, version, target, build_id = sys.argv[1:]
metadata = {
    "layoutVersion": 1,
    "version": version,
    "target": target,
    "variant": "codex",
    "entrypoint": "bin/codex",
    "resourcesDir": "codex-resources",
    "pathDir": "codex-path",
    "buildId": build_id,
    "unsupportedFeatures": ["code_mode", "code_mode_host"],
}
with open(path, "w", encoding="utf-8") as output:
    json.dump(metadata, output, indent=2)
    output.write("\n")
PY

"$STAGE/bin/codex" --version
"$STAGE/codex-path/rg" --version | head -n 1
"$STAGE/codex-resources/bwrap" --version

ARCHIVE="/out/codex-$TARGET-$BUILD_ID.tar.gz"
tar \
    --sort=name \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -C "$STAGE_ROOT" \
    -czf "$ARCHIVE" \
    "$PACKAGE_NAME"
(
    cd /out
    sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256"
)
'

printf 'Built %s\n' "$DIST_DIR/$ARCHIVE_NAME"
printf 'Checksum %s\n' "$DIST_DIR/$ARCHIVE_NAME.sha256"
if [ -n "$ENGINE_AUTH_FILE" ]; then
    rm -f "$ENGINE_AUTH_FILE"
    trap - EXIT HUP INT TERM
fi
