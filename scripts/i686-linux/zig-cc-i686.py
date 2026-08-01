#!/usr/bin/env python3
import os
import sys


def main() -> None:
    filtered_args = []
    for argument in sys.argv[1:]:
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
