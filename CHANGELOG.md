# Changelog

## Unreleased

### Fixed

- Compiled `.nix` output no longer breaks on strings that contain a quote, a backslash, or an antiquotation marker. `Pretty` renders string literals verbatim, so a source such as `message = "he said \"hi\""` compiled to `"he said "hi""`, which Nix rejects outright. Double-quoted text now escapes `"`, `\`, newline/CR/tab, and a `$` that would open an antiquotation; indented text escapes `${` and the single quotes that would pair with a delimiter. The same escaping applies inside interpolation segments, attribute names, type-level string literals, and `declare` paths.
- Indented strings no longer absorb the indentation of the block they sit in. Because the parser reads the body back verbatim, the extra whitespace compounded on every recompile and `tnix compile` was not idempotent for any file with a multi-line `''` string.
- `ParserExpr` accepts the two Nix escapes it was missing inside indented strings, `''$` and `''\<char>`. Both were previously unparseable, so this only widens what the frontend accepts.
- The parser and kind checker now emit the diagnostic codes `docs/diagnostics.md` already documented: `TP0001`-`TP0004` and `TK0004`. They were catalogued but never produced.

### Performance

- `tnix check-project` on a 60-source project with 25 declaration packs: **0.96 s -> 0.15 s**. `analyzeText` re-discovered and re-parsed every `.d.tnix` file in the workspace once per source file; `Driver` now exposes a `SupportCache` keyed by workspace root. `check-project`, `build`, and `emit-project` create one per command, and the language server creates one per request so it can never serve a declaration file the client has since edited.
- Type-layer hot paths, measured over the checker's own operations:
  - `joinTypes` on 200-member unions: **6.4 ms -> 0.69 ms**. `flattenUnion` deduplicated with a linear `elem` scan.
  - `isSubtype` on 200-member unions: **1.32 ms -> 0.19 ms**. Union-vs-union subtyping now consults a set of the right-hand members before falling back to the quadratic scan.
  - `resolveType` on a depth-14 record: **6.5 us -> 1.0 us**. Alias expansion and indexed normalization are whole-tree walks that were being re-run at every node.
  - `substituteMetas` with an empty substitution: **323 ns -> 18 ns**. Instantiating a monomorphic scheme and zonking before the first solved meta both rebuilt the whole type to produce an identical copy.
- `expandAliases` charges its recursion budget for expansions rather than for structural descent. Past 32 levels of nesting it silently stopped expanding aliases, which also made the result non-idempotent.
- `SessionText.wordSpans` no longer calls the O(n) `Text.index` once per match, and `collapseParentSegments` no longer rebuilds its accumulator per segment.

### Changed

- `Driver` exports `SupportCache`, `newSupportCache`, and the `...With` analysis entry points. The existing functions are unchanged and create a private cache per call.
- `Check` exports `resolvePath` and `collapseParentSegments`; the driver kept a second copy that had to stay in sync with the checker's for ambient declarations to keep matching the imports they describe.
- `Diagnostics` exports `allDiagnosticCodes`, so tooling and tests enumerate the catalogue instead of restating it.

### Tests

- `cabal test all` runs 25 suites and 600 examples, up from 20 suites and 447.
- New suites: `Pretty.spec` (render/parse round-trip, including 300 generated cases over an alphabet of quotes, backslashes, and antiquotation markers), `Type.spec` (substitution and meta-closure laws), `Diagnostics.spec` (every code is uniquely identified, documented, and actually emitted by some non-test source), and `Check.spec` (import path resolution).
- Compiled output is now asserted to be a fixed point over a corpus covering the executable grammar: compiling twice must produce the same text, and the result must contain no type-only syntax.
- Property coverage for the algorithms replaced above: `flattenUnion` is idempotent and duplicate-free, `expandAliases` and `resolveType` reach a fixed point, `joinTypes` is an upper bound of both sides, union subtyping agrees with its member-by-member definition, and `wordSpans` agrees with a direct scan over every offset.
- `Kind.spec` grew from 5 examples to 19 and `Indexed.spec` from 12 to 25; `Cli.spec` covers project discovery filters, config decoding errors, and the JSON report contract.

### CI / Tooling

- The workspace builds warning-free under `-Wall`. Removed redundant imports, a missing top-level signature, a partial `head`, and the `other-modules` entries several LSP test suites were missing.

## v0.5.0 - 2026-05-19

### Added

- Stable diagnostic-code system: every parser, kind-checker, type-checker, and driver error is now tagged with a `[TPxxxx]` / `[TKxxxx]` / `[TCxxxx]` / `[TDxxxx]` prefix, catalogued in [`docs/diagnostics.md`](./docs/diagnostics.md).
- Full EBNF grammar reference in [`docs/grammar.md`](./docs/grammar.md), cross-checked against the parser sources.
- Project governance documentation in [`GOVERNANCE.md`](./GOVERNANCE.md) and platform-support tiers in [`docs/support-matrix.md`](./docs/support-matrix.md).
- Structured parser errors via `Parser.parseProgramDetailed` returning a `ParseError` with 1-based `(line, column, message)` so editors can attach diagnostics to the exact span.
- Workspace-wide analysis cache (`AnalysisCache`) that memoizes driver results by `(path, content)` with bounded FIFO eviction; cached entries are reused across `workspace/symbol`, `definition`, `references`, and `hover` requests.
- VS Code extension surfaces LSP startup failures and exposes a `tnix.restartServer` command plus a status bar indicator (running / starting / error / stopped).
- CycloneDX SBOMs published alongside every tagged release archive (`*-linux-x64.cdx.json`, `*-macos-arm64.cdx.json`, `tnix-vscode-*.cdx.json`) and attested with `actions/attest`.
- Release smoke step now exercises packaged `tnix` against the in-tree `examples/` and `dogfood/` corpora and drives a minimal JSON-RPC handshake against packaged `tnix-lsp`.
- LSP folding-range provider (`textDocument/foldingRange`) that folds `let-in` blocks, attribute sets, list and parenthesised literals, multi-line indented strings, and runs of consecutive `#` comment lines. The scan is text-driven, so it keeps producing useful folds even when the buffer has type errors. Covered by `tnix-lsp-session-folding-spec`.
- LSP document-highlight provider (`textDocument/documentHighlight`) that paints every occurrence of the identifier under the cursor inside the active buffer. Symbol resolution goes through the same machinery as `references` and `rename`, so dotted selections light up the same matches editors would jump or rebind to.
- LSP document-link provider (`textDocument/documentLink`) that turns every `import ./path` path literal and `declare "./path"` string literal into a clickable link. Relative paths are resolved against the source file's directory. The scan is text-driven so it keeps producing links even when the buffer fails to type-check. Covered by `tnix-lsp-session-links-spec`.
- LSP inlay-hint provider (`textDocument/inlayHint`) that surfaces inferred `:: Scheme` annotations next to top-level `let` bindings whose author has not written an explicit signature. Pretty-printed through the shared `renderScheme`, so the displayed text matches hover. Covered by `tnix-lsp-session-inlay-hints-spec`.

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
