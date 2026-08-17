#!/usr/bin/env python3
import os
import sys


def main() -> None:
    filtered_args = []
    for argument in sys.argv[1:]:
        if argument in {"-mavx512f", "-mavx512vl"}:
            # Zig's Clang accepts these flags during feature detection but
            # cannot compile the BLAKE3 AVX-512 intrinsics for the i686 target.
            # Report them as unsupported so BLAKE3 uses its other x86 paths.
            sys.exit(1)
        if argument in {"--target=i686-unknown-linux-musl", "-Wl,-melf_i386"}:
            continue
        if argument == "-Wp,-U_FORTIFY_SOURCE":
            filtered_args.append("-U_FORTIFY_SOURCE")
        else:
            filtered_args.append(argument)
    os.execvp(
        "zig",
        ["zig", "cc", "-target", "x86-linux-musl", *filtered_args],
    )


if __name__ == "__main__":
    main()
