# Support Matrix

This page documents the support targets that should be kept green before a
release is considered production-ready.

## Release Artifacts

GitHub Releases publish prebuilt CLI/LSP archives for:

- Linux x64: `tnix-<version>-linux-x64.tar.gz`
- macOS arm64: `tnix-<version>-macos-arm64.tar.gz`

Other platforms should use the flake outputs until a release job is added for
that target.

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
