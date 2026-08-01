Codex CLI for 32-bit x86 Linux
================================

Install:

    tar -xzf codex-i686-unknown-linux-musl-*.tar.gz
    cd codex-i686-unknown-linux-musl-*
    ./install.sh

If the archive extracts directly into the current directory, run ./install.sh
there instead.

The default install is per-user:

    executable: ~/.local/bin/codex
    package:    ~/.local/share/codex-i686/releases/<build-id>

After installation:

    codex login --device-auth
    codex

This package is statically linked and includes 32-bit builds of ripgrep and
bubblewrap. JavaScript Code Mode is disabled because rusty_v8 does not support
32-bit Linux. Normal Codex chat, direct tools, file editing, and shell execution
remain available.

On i686, bubblewrap enforces filesystem restrictions and network namespace
isolation. The additional seccomp syscall filter used on x86_64 and aarch64 is
not available because seccompiler does not support AUDIT_ARCH_I386.

The Rust i686 target requires an SSE2-capable processor.

When testing this package through linux/386 user-mode emulation on a non-x86
host, /proc/cpuinfo describes the host CPU rather than the emulated CPU. In
that case only, run CODEX_I686_SKIP_CPU_CHECK=1 ./install.sh.
