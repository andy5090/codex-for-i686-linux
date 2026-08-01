#!/bin/sh
set -eu

if command -v granlib >/dev/null 2>&1; then
    exec granlib "$@"
fi

if command -v brew >/dev/null 2>&1; then
    binutils_prefix=$(brew --prefix binutils 2>/dev/null || true)
    if [ -x "$binutils_prefix/bin/ranlib" ]; then
        exec "$binutils_prefix/bin/ranlib" "$@"
    fi
fi

if ranlib --version 2>/dev/null | grep -q 'GNU ranlib'; then
    exec ranlib "$@"
fi

echo "GNU ranlib is required to index ELF static libraries." >&2
exit 1
