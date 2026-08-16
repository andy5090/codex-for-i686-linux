# Codex CLI for i686 Linux

This repository provides an unofficial, community-maintained build of
[OpenAI Codex CLI](https://github.com/openai/codex) for 32-bit x86 Linux.
It targets Debian-based distributions running on `i686` hardware.

The upstream project does not publish an i686 binary. This fork adds the
target-specific compatibility changes, packaging scripts, and release assets
needed to install Codex on supported 32-bit x86 systems.

## Install

Run this as the user who will use Codex; root privileges are not required:

```sh
curl -fsSL \
  https://github.com/andy5090/codex-for-i686-linux/releases/download/i686-latest/install-codex-i686.sh \
  | sh
```

The installer downloads the statically linked i686 package, verifies its
SHA-256 checksum, and installs it under:

- executable: `~/.local/bin/codex`
- release files: `~/.local/share/codex-i686/releases/<build-id>`

Make sure `~/.local/bin` is in `PATH`, then sign in and start Codex:

```sh
codex login --device-auth
codex
```

To update an existing installation to the latest i686 release:

```sh
codex-i686-update
```

The update command downloads the current `i686-latest` installer, verifies the
package checksum through that installer, installs the new build alongside the
previous release, and switches `~/.local/bin/codex` to the new build.

If you prefer to inspect the installer before running it:

```sh
curl -fLO \
  https://github.com/andy5090/codex-for-i686-linux/releases/download/i686-latest/install-codex-i686.sh
less install-codex-i686.sh
sh install-codex-i686.sh
```

## Platform support

- Debian-based 32-bit x86 Linux (`i386` through `i686`)
- SSE2-capable processor
- Tested on antiX Linux running on real i686 hardware
- statically linked musl binaries for Codex, ripgrep, and bubblewrap
- per-user installation without replacing distribution packages

JavaScript Code Mode is unavailable because `rusty_v8` does not publish a
32-bit Linux host binary. When a model requests `CodeModeOnly`, this build
falls back to direct tools so shell execution, file editing, and normal Codex
workflows remain available.

You may see a warning that Code Mode is unavailable and direct tools are being
used. That warning is expected. A warning that Code Mode "will fail closed"
usually means an older build is still being executed.

## Test shell execution

```sh
codex exec -m gpt-5.6-sol --skip-git-repo-check \
  "Use the shell to run uname -m and pwd, then show the results."
```

If the shell tool is available but bubblewrap fails, repeat the test only in a
trusted directory with sandboxing disabled:

```sh
codex exec -m gpt-5.6-sol \
  --dangerously-bypass-approvals-and-sandbox \
  "Use the shell to run uname -m and pwd, then show the results."
```

If only the second command works, report the bubblewrap error and the output of
`uname -a`; that is a kernel sandbox compatibility issue rather than a Code
Mode issue.

## Codex Apps MCP

`codex_apps` is a remote HTTPS MCP service and is independent of the i686
binary format. If it is not needed, it can be disabled in
`~/.codex/config.toml`:

```toml
[features]
apps = false
```

For connection failures, include the complete
`MCP client for codex_apps failed to start: ...` message in a bug report.

## Build locally

The native macOS cross-build path uses Zig:

```sh
./scripts/i686-linux/build-package-zig.sh
```

A Docker or Podman build path is also available:

```sh
./scripts/i686-linux/build-package.sh
```

Packages and checksum files are written to `dist/`. The scripts assign dirty
local builds a source-state build ID so installing a rebuilt package does not
silently reuse an older release directory.

## Upstream and support status

This is not an official OpenAI distribution. General Codex documentation and
non-i686 development happen in [openai/codex](https://github.com/openai/codex).
Changes in this repository focus on maintaining the i686 Linux build and may
need adjustment as upstream evolves.

The project remains licensed under the [Apache-2.0 License](LICENSE), with the
upstream notices retained in [NOTICE](NOTICE).
