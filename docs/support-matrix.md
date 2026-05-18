# Support Matrix

This page documents the support targets that should be kept green before a
release is considered production-ready.

## Platform Support Tiers

Platforms fall into one of three tiers:

| Tier | Meaning |
| --- | --- |
| **Tier 1: officially supported** | CI gates every PR for this platform and tagged releases publish prebuilt archives. Bugs on Tier 1 platforms block a release. |
| **Tier 2: best effort** | Builds from source through the Nix flake. Issues are accepted and triaged but not guaranteed to block a release. |
| **Tier 3: unsupported** | tnix is not known to work and the project has no plans to support it today. Reports may be educational but will not be prioritized. |

| Platform | Tier | Notes |
| --- | --- | --- |
| Linux x64 (`x86_64-linux`) | Tier 1 | Release archive published per tag; CI runs the full matrix on `ubuntu-latest`. |
| macOS arm64 (Apple Silicon) | Tier 1 | Release archive published per tag; CI runs the full matrix on `macos-latest`. |
| Linux arm64 (`aarch64-linux`) | Tier 2 | Flake produces working `tnix` / `tnix-lsp` derivations; no prebuilt archive ships today. |
| macOS x64 (Intel) | Tier 2 | Flake builds locally on Intel Macs; CI does not exercise this target, no prebuilt archive ships today. |
| Windows | Tier 3 | The CLI and language server are not tested on Windows. Use [WSL2](https://learn.microsoft.com/windows/wsl/install) with the Linux x64 instructions, or build from source through the flake on a Linux/macOS host. |

Adding a new target to Tier 1 requires:

1. A CI job that builds, tests, and smoke-checks the binary for the target,
2. A release-pipeline entry that produces a prebuilt archive + checksum, and
3. An installation entry in [`getting-started.md`](./getting-started.md).

## Release Artifacts

GitHub Releases publish prebuilt CLI/LSP archives for the Tier 1 targets:

- Linux x64: `tnix-<version>-linux-x64.tar.gz`
- macOS arm64: `tnix-<version>-macos-arm64.tar.gz`

Tier 2 platforms should build through the flake until a release job is added
for that target (see the checklist above).

## Runtime Support

| Surface | Supported range |
| --- | --- |
| Nix | Flake-enabled Nix capable of running `nix develop` and `nix flake check` |
| CLI | Latest released `tnix` and `tnix-lsp` binaries |
| VS Code | `^1.110.0`, matching `editors/vscode/package.json` |
| Zed | Extension API `0.5.0`, matching `editors/zed/Cargo.toml` |
| Neovim | Neovim with `vim.fs.root` and `vim.lsp.start` support |

## Development Toolchain

The repository flake is the source of truth for contributor tooling. CI and the
development shell currently provide:

- GHC, Cabal, and Haskell Language Server from `nixpkgs` `haskellPackages`.
- Node.js 24 and pnpm for editor packaging and release scripts.
- Rust, Cargo, and rust-analyzer for the Zed extension.
- Neovim for plugin smoke tests.

Run the full workspace verification before release:

```bash
nix develop
pnpm install --frozen-lockfile
vp run check
nix flake check --accept-flake-config
```

## Release Support Policy

Security and critical correctness fixes target the latest release first. Older
release lines may receive patches when the fix is low-risk and the affected
surface is still actively used, but users should plan to upgrade to the latest
release.

## CI Coverage

The default CI matrix verifies the full workspace on:

- `ubuntu-latest`
- `macos-latest`

Release asset builds cover Linux x64 and macOS arm64. Adding a new production
target should include CI verification, release packaging, and installation docs
for that target.
