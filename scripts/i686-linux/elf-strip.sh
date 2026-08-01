#!/bin/sh
set -eu

if command -v gstrip >/dev/null 2>&1; then
    exec gstrip "$@"
fi

if command -v brew >/dev/null 2>&1; then
    binutils_prefix=$(brew --prefix binutils 2>/dev/null || true)
    if [ -x "$binutils_prefix/bin/strip" ]; then
        exec "$binutils_prefix/bin/strip" "$@"
    fi
fi

if strip --version 2>/dev/null | grep -q 'GNU strip'; then
    exec strip "$@"
fi

echo "GNU strip is required to strip ELF binaries." >&2
exit 1
