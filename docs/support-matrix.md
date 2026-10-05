# Support Matrix

This page documents the support targets that should be kept green before a
release is considered production-ready.

## Platform Support Tiers

Platforms fall into one of three tiers:

| Tier | Meaning |
| --- | --- |
| **Tier 1: officially supported** | CI gates every PR for this platform and tagged releases publish prebuilt archives. Bugs on Tier 1 platforms block a release. |
| **Tier 2: best effort** | Builds from source through the Nix flake. Issues are accepted and triaged but not guaranteed to block a release. |
| **Tier 3: unsupported** | tynix is not known to work and the project has no plans to support it today. Reports may be educational but will not be prioritized. |

| Platform | Tier | Notes |
| --- | --- | --- |
| Linux x64 (`x86_64-linux`) | Tier 1 | Fully static (musl) release archive per tag; CI runs the full matrix on `ubuntu-latest`. |
| Linux arm64 (`aarch64-linux`) | Tier 1 | Fully static (musl) release archive per tag, built and smoke-tested on `ubuntu-24.04-arm` by the release workflow (PR CI does not cover this target yet). |
| macOS arm64 (Apple silicon) | Tier 1 | Release archive per tag (links only `/usr/lib` and `/System`); CI runs the full matrix on `macos-latest`. |
| macOS x64 (Intel) | Tier 1 | Release archive per tag (links only `/usr/lib` and `/System`), built and smoke-tested on `macos-15-intel` by the release workflow (PR CI does not cover this target yet). |
| Other Nix-supported systems | Tier 2 | Build from source through the flake (`nix profile install github:ubugeeei-prod/tynix`). |
| Windows | Tier 3 | The CLI and language server are not tested on Windows. Use [WSL2](https://learn.microsoft.com/windows/wsl/install) and install the Linux build with `curl -fsSL https://tynix.dev/install.sh \| sh`. |

Adding a new target to Tier 1 requires:

1. A CI job that builds, tests, and smoke-checks the binary for the target,
2. A release-pipeline entry that produces a prebuilt archive + checksum, and
3. An installation entry in [`getting-started.md`](./getting-started.md).

## Release Artifacts

GitHub Releases publish prebuilt CLI/LSP archives for the Tier 1 targets,
each with a `.sha256` checksum, a CycloneDX SBOM, and a build provenance
attestation:

- Linux x64: `tynix-<version>-linux-x64.tar.gz`
- Linux arm64: `tynix-<version>-linux-arm64.tar.gz`
- macOS arm64: `tynix-<version>-macos-arm64.tar.gz`
- macOS x64: `tynix-<version>-macos-x64.tar.gz`

The archives are built from the flake's `release-bundle` output on a native
runner for each target. Linux binaries are statically linked against musl, so
they run on any distribution. macOS binaries link GMP statically and use the
system `libiconv` / `libffi`, so they need nothing outside `/usr/lib` and
`/System`. The release workflow fails if a binary still references
`/nix/store`, then installs every archive with `install.sh` on a runner
without Nix and smoke-tests the CLI and language server before publishing.

`https://tynix.dev/install.sh` (source: `docs/public/install.sh`) installs these
archives; `https://tynix.dev/download/<tag>/<file>` redirects to the matching
GitHub release asset.

## Runtime Support

| Surface | Supported range |
| --- | --- |
| Nix | Flake-enabled Nix capable of running `nix develop` and `nix flake check` |
| CLI | Latest released `tynix` and `tynix-lsp` binaries |
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
vp run workspace:check
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

Release asset builds cover Linux x64, Linux arm64, macOS arm64, and macOS
x64. Adding a new production target should include CI verification, release
packaging, and installation docs for that target.

## Binary Cache

The release workflow can push build results to the Cachix cache `tynix`
(https://tynix.cachix.org). It is enabled only when the repository secret
`CACHIX_AUTH_TOKEN` is set; without it, builds fall back to
`cache.nixos.org` and compile the rest. The cold Linux static build includes
the musl GHC cross compiler and can take a few hours, so a warm cache matters.
Flake users can opt in with `cachix use tynix`; the flake does not set
`nixConfig` for it.
