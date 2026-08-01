#!/bin/sh
set -eu

exec cargo-zigbuild zig cc -- \
    -g \
    -fno-sanitize=all \
    -mcpu=pentium4 \
    -target x86-linux-musl \
    "$@"
