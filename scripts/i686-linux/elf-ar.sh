#!/bin/sh
set -eu

if command -v gar >/dev/null 2>&1; then
    exec gar "$@"
fi

if command -v brew >/dev/null 2>&1; then
    binutils_prefix=$(brew --prefix binutils 2>/dev/null || true)
    if [ -x "$binutils_prefix/bin/ar" ]; then
        exec "$binutils_prefix/bin/ar" "$@"
    fi
fi

if ar --version 2>/dev/null | grep -q 'GNU ar'; then
    exec ar "$@"
fi

echo "GNU ar is required to create ELF static libraries." >&2
exit 1
