# CI/CD Hardening

The GitHub Actions workflows follow these rules so CI and release automation are
predictable, reviewable, and safer to run on public pull requests.

## Security

- Workflows default `GITHUB_TOKEN` to read-only contents access.
- Jobs request write permissions only where they need them, such as publishing a
  GitHub Release or generating artifact attestations.
- Third-party actions are pinned to full commit SHAs with the intended upstream
  version left as a comment for maintainability.
- `actions/checkout` disables persisted credentials because no job pushes back
  to the repository.
- CI cancels superseded pull request runs but does not cancel `main` or tag
  validations.

## Caching

CI caches Cabal, pnpm, and Cargo dependency stores using lockfile and manifest
hashes. The workflows intentionally do not cache `/nix/store` with
`actions/cache`: Nix store paths are large, platform-specific, and better served
by a dedicated binary cache if the project later configures one.

## Check Layout

CI is split by responsibility instead of running the whole monorepo in one
opaque job. Metadata, Nix flake checks, Haskell packages, repository fixtures,
VS Code, Zed, and Neovim each report their own status so failures point at the
affected surface area. A small summary job depends on every split check and can
be used as the single required branch protection status.

## Release Provenance

Release archives, checksum files, and the VS Code extension package are attested
with GitHub artifact attestations before upload. Consumers can verify release
assets with:

```bash
gh attestation verify <artifact> -R ubugeeei/tnix
```

## Dependency Updates

[`.github/dependabot.yml`](../.github/dependabot.yml) opens weekly update PRs for
three ecosystems:

- `github-actions` across every workflow
- `npm` for the VS Code extension under `editors/vscode`
- `cargo` for the Zed extension under `editors/zed`

GHC, cabal, and `nixpkgs` versions are tracked through the flake; bump them by
updating `flake.lock` rather than waiting on Dependabot.

## Code Owners and Branch Protection

[`.github/CODEOWNERS`](../.github/CODEOWNERS) requests reviewers automatically
based on the changed paths. The recommended branch protection rule for `main`
is:

- Require pull request reviews from code owners.
- Require status checks to pass before merging, with `CI Summary` selected as
  the required check (it depends on every split job and represents the full
  pipeline).
- Require branches to be up to date before merging, and dismiss stale review
  approvals when new commits are pushed.
