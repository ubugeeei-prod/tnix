# Releasing

`tynix` is currently published primarily through GitHub Releases.

## What ships today

- `tynix` CLI binary
- `tynix-lsp` language server binary
- SHA-256 checksum files for each archive
- VS Code `.vsix` extension package
- GitHub artifact attestations for release archives, checksum files, and the
  VS Code extension package
- Optional VS Code Marketplace publish when `VSCE_PAT` is configured
- Optional Open VSX publish when `OVSX_PAT` is configured
- Nix flake packages and apps exposed as `#tynix` and `#tynix-lsp`

Artifacts are built for:

- Linux x64 and Linux arm64 (fully static, musl)
- macOS arm64 and macOS x64 (only system libraries)

Users install them with `curl -fsSL https://tynix.dev/install.sh | sh`, which
downloads from `https://tynix.dev/download/<tag>/<file>` (a Cloudflare Pages
redirect to the GitHub release asset) and verifies the checksum.

## Release flow

1. Make sure `main` is green in CI.
2. Run `nix flake check --accept-flake-config` locally to verify the published
   flake outputs, package tests, and dogfood/example fixtures.
3. Update versioned files as needed.
4. Create and push a semver tag such as `v1.0.0`.
5. Wait for the `Release` GitHub Actions workflow to finish.
6. Verify the generated release notes and uploaded assets on GitHub.
7. If `VSCE_PAT` and/or `OVSX_PAT` are configured, confirm the new extension
   version is visible on the corresponding marketplace.

## Commands

```bash
git checkout main
git pull --ff-only origin main
git tag v1.0.0
git push origin v1.0.0
```

To validate a release archive checksum locally, keep the archive next to its
`.sha256` file and run:

```bash
node --experimental-strip-types ./scripts/package-release.ts verify-checksum tynix-v1.0.0-linux-x64.sha256
```

To verify release artifact provenance, use GitHub's attestation verifier:

```bash
gh attestation verify tynix-v1.0.0-linux-x64.tar.gz -R ubugeeei-prod/tynix
gh attestation verify tynix-v1.0.0-linux-x64.sha256 -R ubugeeei-prod/tynix
```

## Notes

- `nix flake check` is the canonical release-grade validation entrypoint for
  the flake itself. It now covers version metadata sync, packaged binary smoke
  tests, Haskell package test suites, and dogfood/example fixture checks.
- The release workflow verifies each generated checksum with Node before
  uploading the archive and checksum file, so the check is portable across
  Linux and macOS runners.
- The release workflow generates artifact attestations before uploading release
  assets so users can verify provenance with the GitHub CLI.
- CI now primes the Cabal package index explicitly so clean runners can resolve Haskell dependencies reliably.
- The release workflow always creates a GitHub Release. Marketplace publishing is layered on top and only runs when the corresponding repository secrets are present.
- Configure `VSCE_PAT` with a Visual Studio Marketplace publisher token and `OVSX_PAT` with an Open VSX token to enable automatic extension publishing on tag pushes.
