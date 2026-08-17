#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
DIST_DIR="$REPO_ROOT/dist"
TARGET="i686-unknown-linux-musl"
TARGET_DIR="${CODEX_I686_ZIG_TARGET_DIR:-$REPO_ROOT/codex-rs/target/i686-zig}"
BUILD_JOBS="${CODEX_I686_BUILD_JOBS:-2}"
RIPGREP_VERSION="15.2.0"
LIBCAP_VERSION="2.78"
LIBCAP_SHA256="0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11"
ZIG_CC="$SCRIPT_DIR/zig-cc-i686.py"
ZIG_LINKER="$SCRIPT_DIR/zig-linker-i686.sh"
ELF_AR="$SCRIPT_DIR/elf-ar.sh"
ELF_RANLIB="$SCRIPT_DIR/elf-ranlib.sh"
ELF_STRIP="$SCRIPT_DIR/elf-strip.sh"

TOOLCHAIN=$(sed -n \
    's/^channel = "\([^"]*\)"/\1/p' \
    "$REPO_ROOT/codex-rs/rust-toolchain.toml")
if [ -z "$TOOLCHAIN" ]; then
    echo "Could not determine the Rust toolchain." >&2
    exit 1
fi

for tool in cargo cargo-zigbuild curl git make pkg-config python3 rustup tar zig; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required build tool not found: $tool" >&2
        exit 1
    fi
done

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d " " -f 1
    else
        shasum -a 256 "$1" | cut -d " " -f 1
    fi
}

strip_binary() {
    input=$1
    "$ELF_STRIP" --strip-all "$input"
}

zigbuild_binary() {
    binary=$1
    shift
    rm -f "$binary"
    if cargo "+$TOOLCHAIN" zigbuild "$@"; then
        return
    fi
    if [ -x "$binary" ]; then
        echo "cargo-zigbuild reported a post-processing error; using the newly linked ELF binary." >&2
        return
    fi
    echo "cargo-zigbuild did not produce the expected binary: $binary" >&2
    exit 1
}

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
mkdir -p "$DIST_DIR" "$TARGET_DIR"
rustup target add --toolchain "$TOOLCHAIN" "$TARGET"

LIBCAP_ROOT="$TARGET_DIR/i686-libcap-$LIBCAP_VERSION"
if [ ! -f "$LIBCAP_ROOT/lib/libcap.a" ]; then
    LIBCAP_BUILD=$(mktemp -d)
    trap 'rm -rf "$LIBCAP_BUILD"' EXIT HUP INT TERM
    cd "$LIBCAP_BUILD"
    LIBCAP_ARCHIVE="libcap-$LIBCAP_VERSION.tar.xz"
    for libcap_url in \
        "https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/$LIBCAP_ARCHIVE" \
        "https://deb.debian.org/debian/pool/main/libc/libcap2/libcap2_${LIBCAP_VERSION}.orig.tar.xz"
    do
        if curl -fsSL \
            --connect-timeout 30 \
            --retry 2 \
            --retry-all-errors \
            "$libcap_url" \
            -o "$LIBCAP_ARCHIVE.tmp"; then
            mv "$LIBCAP_ARCHIVE.tmp" "$LIBCAP_ARCHIVE"
            break
        fi
    done
    rm -f "$LIBCAP_ARCHIVE.tmp"
    if [ ! -f "$LIBCAP_ARCHIVE" ]; then
        echo "Could not download $LIBCAP_ARCHIVE." >&2
        exit 1
    fi
    if [ "$(sha256_file "$LIBCAP_ARCHIVE")" != "$LIBCAP_SHA256" ]; then
        echo "libcap checksum verification failed." >&2
        exit 1
    fi
    tar -xf "$LIBCAP_ARCHIVE"
    python3 - \
        "libcap-$LIBCAP_VERSION/libcap/include/uapi/linux/capability.h" \
        "libcap-$LIBCAP_VERSION/libcap/cap_names.list.h" <<'PY'
import re
import sys

source, destination = sys.argv[1:]
pattern = re.compile(r"^#define\s+CAP_(\S+)\s+(\d+)\s*$")
with open(source, encoding="utf-8") as input_file, open(
    destination, "w", encoding="utf-8"
) as output_file:
    for line in input_file:
        if match := pattern.match(line):
            name, number = match.groups()
            output_file.write(f'{{"{name.lower()}",{number}}},\n')
PY
    make \
        -C "libcap-$LIBCAP_VERSION/libcap" \
        AR="$ELF_AR" \
        BUILD_CC=cc \
        CC="$ZIG_CC" \
        GOLANG=no \
        PAM_CAP=no \
        RANLIB="$ELF_RANLIB" \
        SHARED=no \
        USE_GPERF=no
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
    sed \
        -e "s|@PREFIX@|$LIBCAP_ROOT|g" \
        "$SCRIPT_DIR/libcap.pc.in" \
        >"$LIBCAP_ROOT/lib/pkgconfig/libcap.pc"
    rm -rf "$LIBCAP_BUILD"
    trap - EXIT HUP INT TERM
fi

export AR_i686_unknown_linux_musl="$ELF_AR"
export CARGO_BUILD_JOBS="$BUILD_JOBS"
export CARGO_PROFILE_RELEASE_DEBUG=none
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_TARGET_DIR="$TARGET_DIR"
export CFLAGS_i686_unknown_linux_musl="-O2 -fPIC"
export CC_i686_unknown_linux_musl="$ZIG_CC"
export CRATE_CC_NO_DEFAULTS=1
export LIBCAP_STATIC=1
export OPENSSL_STATIC=1
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_PATH="$LIBCAP_ROOT/lib/pkgconfig"
export RANLIB_i686_unknown_linux_musl="$ELF_RANLIB"
export RUSTFLAGS="-C target-cpu=pentium4"
export SOURCE_DATE_EPOCH
export TARGET_PKG_CONFIG_ALLOW_CROSS=1
export TARGET_PKG_CONFIG_LIBDIR="$LIBCAP_ROOT/lib/pkgconfig"
export TARGET_PKG_CONFIG_PATH="$LIBCAP_ROOT/lib/pkgconfig"
export TARGET_PKG_CONFIG_SYSROOT_DIR=/

cd "$REPO_ROOT/codex-rs"
BINARY_DIR="$TARGET_DIR/$TARGET/release"
zigbuild_binary "$BINARY_DIR/bwrap" \
    --locked \
    --target "$TARGET" \
    --profile release \
    --bin bwrap

strip_binary "$BINARY_DIR/bwrap"
BWRAP_SHA256=$(sha256_file "$BINARY_DIR/bwrap")
export CODEX_BWRAP_SHA256="$BWRAP_SHA256"

zigbuild_binary "$BINARY_DIR/codex" \
    --locked \
    --target "$TARGET" \
    --profile release \
    --bin codex

RG_ROOT="$TARGET_DIR/i686-ripgrep-$RIPGREP_VERSION"
if [ ! -x "$RG_ROOT/bin/rg" ]; then
    CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_LINKER="$ZIG_LINKER" \
        cargo "+$TOOLCHAIN" install ripgrep \
        --locked \
        --version "$RIPGREP_VERSION" \
        --target "$TARGET" \
        --root "$RG_ROOT"
fi

STAGE_ROOT=$(mktemp -d)
PACKAGE_NAME="codex-$TARGET-$BUILD_ID"
STAGE="$STAGE_ROOT/$PACKAGE_NAME"
trap 'rm -rf "$STAGE_ROOT"' EXIT HUP INT TERM
mkdir -p \
    "$STAGE/bin" \
    "$STAGE/codex-path" \
    "$STAGE/codex-resources"

install -m 0755 "$BINARY_DIR/codex" "$STAGE/bin/codex"
install -m 0755 "$BINARY_DIR/bwrap" "$STAGE/codex-resources/bwrap"
install -m 0755 "$RG_ROOT/bin/rg" "$STAGE/codex-path/rg"
strip_binary "$STAGE/bin/codex"
strip_binary "$STAGE/codex-path/rg"

install -m 0755 \
    "$SCRIPT_DIR/update.sh" \
    "$STAGE/bin/codex-i686-update"
install -m 0755 "$SCRIPT_DIR/install.sh" "$STAGE/install.sh"
install -m 0644 "$SCRIPT_DIR/README.txt" "$STAGE/README.txt"
printf '%s\n' "$BUILD_ID" >"$STAGE/BUILD-ID"

VERSION=$(sed -n \
    's/^version = "\([^"]*\)"/\1/p' \
    "$REPO_ROOT/codex-rs/Cargo.toml" | head -n 1)
python3 - "$STAGE/codex-package.json" "$VERSION" "$TARGET" "$BUILD_ID" <<'PY'
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

ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
if command -v gtar >/dev/null 2>&1; then
    gtar \
        --sort=name \
        --mtime="@$SOURCE_DATE_EPOCH" \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        -C "$STAGE_ROOT" \
        -czf "$ARCHIVE" \
        "$PACKAGE_NAME"
else
    COPYFILE_DISABLE=1 tar \
        --no-xattrs \
        -C "$STAGE_ROOT" \
        -czf "$ARCHIVE" \
        "$PACKAGE_NAME"
fi
printf '%s  %s\n' \
    "$(sha256_file "$ARCHIVE")" \
    "$ARCHIVE_NAME" \
    >"$ARCHIVE.sha256"

rm -rf "$STAGE_ROOT"
trap - EXIT HUP INT TERM

printf 'Built %s\n' "$ARCHIVE"
printf 'Checksum %s\n' "$ARCHIVE.sha256"
