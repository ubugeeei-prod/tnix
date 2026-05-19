# Changelog

## Unreleased

### Added

- Stable diagnostic-code system: every parser, kind-checker, type-checker, and driver error is now tagged with a `[TPxxxx]` / `[TKxxxx]` / `[TCxxxx]` / `[TDxxxx]` prefix, catalogued in [`docs/diagnostics.md`](./docs/diagnostics.md).
- Full EBNF grammar reference in [`docs/grammar.md`](./docs/grammar.md), cross-checked against the parser sources.
- Project governance documentation in [`GOVERNANCE.md`](./GOVERNANCE.md) and platform-support tiers in [`docs/support-matrix.md`](./docs/support-matrix.md).
- Structured parser errors via `Parser.parseProgramDetailed` returning a `ParseError` with 1-based `(line, column, message)` so editors can attach diagnostics to the exact span.
- Workspace-wide analysis cache (`AnalysisCache`) that memoizes driver results by `(path, content)` with bounded FIFO eviction; cached entries are reused across `workspace/symbol`, `definition`, `references`, and `hover` requests.
- VS Code extension surfaces LSP startup failures and exposes a `tnix.restartServer` command plus a status bar indicator (running / starting / error / stopped).
- CycloneDX SBOMs published alongside every tagged release archive (`*-linux-x64.cdx.json`, `*-macos-arm64.cdx.json`, `tnix-vscode-*.cdx.json`) and attested with `actions/attest`.
- Release smoke step now exercises packaged `tnix` against the in-tree `examples/` and `dogfood/` corpora and drives a minimal JSON-RPC handshake against packaged `tnix-lsp`.

### Changed

- `Session.hs` (1191 LOC) split into eight focused modules (`SessionTypes`, `SessionWorkspace`, `SessionText`, `SessionSymbols`, `SessionReferences`, `SessionDocuments`, `SessionSemanticTokens`, `SessionDiagnostics`) — Session.hs is now ~397 LOC of handler dispatchers.
- Diagnostics are rendered through `Pretty` instead of `show`, so type / kind errors show surface syntax instead of internal AST constructors.
- Every previously invariant-guarded partial function in `tnix-core` (`Map.!`, `foldl1`, `foldr1`) is replaced with a total form.
- `tnix init` / `tnix scaffold` write scaffolded files via atomic tmp + rename so a crash mid-write cannot leave a half-populated `.tnix` / `.d.tnix` on disk.

### Fixed

- `tnix check-project` no longer hangs on directory symlink loops; the walker is cycle-safe and depth-bounded.
- LSP-side `didSave` notifications are now handled instead of dropped, and JSON-RPC framing errors are logged.
- `pnpm --filter tnix fmt` is no longer broken by including `.vscodeignore` (which has no prettier parser).

### CI / Tooling

- New `Lint (formatters)` CI job that runs prettier on the VS Code extension and `cargo fmt --check` on the Zed extension.
- New `Docs` CI workflow that runs `markdownlint-cli2` and `lycheeverse/lychee-action` (offline) on every `.md` change.
- Dependabot configuration covers GitHub Actions, the VS Code extension (npm), and the Zed extension (cargo).
- `.github/CODEOWNERS` routes review requests automatically.
- TypeScript bumped to 6.x; prettier to 3.8.3; `@vscode/vsce` to 3.9.1.

### Tests

- New unit suites for `Alias`, `Emit`, `AnalysisCache`, `SessionText`, `SessionWorkspace`, and `SessionDiagnostics` — `cabal test all` now runs 16 suites.

## v0.4.0 - 2026-05-18

- Harden GitHub Actions with pinned third-party actions, least-privilege
  permissions, checkout credential isolation, explicit timeouts, and release
  artifact attestations.
- Split CI into focused metadata, flake, Haskell, fixture, VS Code, Zed, and
  Neovim checks with a summary status for branch protection.
- Add release support documentation, CI/CD hardening notes, contribution and
  security policies, and conventional root `pnpm` scripts.
- Fix CLI JSON failure output and scaffolded string escaping, and make the
  Neovim integration detect `tnix.config.tnix` as a workspace root marker.

## v0.3.1 - 2026-04-06

- Support quoted attribute names, dynamic `${...}` selections, attrset lambda binders, and indented `'' ... ''` strings in executable `tnix`.
- Extend the checker, compiler, and pretty-printer so flake-oriented source shapes round-trip instead of falling out of the reliable subset.
- Add regression coverage for flake-style parsing, typing, and compile/emit behavior, including quoted selectors and dynamic package lookups.

## v0.3.0 - 2026-04-02

- Add project-aware CLI workflows for `check-project`, `build`, and `emit-project`, together with stronger config decoding and absolute root handling.
- Expand the LSP surface with richer editor features, cached analyzed documents, and better workspace-scale behavior.
- Ship a curated `examples/` showcase project and wire it into repeatable verification so sample code stays healthy in CI.
- Support `declarationPacks` in `tnix.config.tnix`, including direct consumption of upstream ecosystem packs and rebased `registry/workspace` packs without copying.
- Harden release and CI behavior with version sync validation, packaged binary smoke tests, and fixture lookup fixes for package builds.
- Extend core regression coverage with compile/emit golden tests and broader registry/config support tests.

## v0.2.0 - 2026-04-01

- Ship the first end-to-end `tnix` toolchain release with a Haskell core, CLI, LSP, and editor integrations for VS Code, Zed, and Neovim.
- Compile `.tnix` to `.nix`, type-check source files, and emit `.d.tnix` declaration files without adding any runtime layer.
- Add gradual typing primitives centered on `dynamic`, structural subtyping, ambient declarations for existing `.nix`, and declaration loading from workspace support files.
- Add type-level expressiveness including `forall`, conditional types, `infer`, higher-kinded aliases, and indexed container types for `Vec`, `Matrix`, `Tensor`, and `Tuple`.
- Infer exact container and sequence shapes from ordinary Nix list literals, including heterogeneous tuple inference and tensor widening back to structural list views when shapes diverge.
- Expand the regression suite across parser, checker, subtyping, compile/emit, CLI, LSP, VS Code, Zed, and Neovim validation.
