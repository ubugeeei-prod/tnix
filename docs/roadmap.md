# Roadmap

Status legend: ✅ shipped · 🚧 in progress.

Phases 0–4 shipped in the integrated `0.5.0` toolchain release. Phase 5 hardening
is largely shipped; the remaining production-readiness work is tracked under the
[**Production Ready (v1.0)**](https://github.com/ubugeeei-prod/tynix/milestone/1)
milestone.

## Phase 0: Spec First ✅

- document the language design
- lock down the core type-system concepts
- define monorepo package responsibilities

## Phase 1: Core ✅

- parser
- AST
- pretty printer
- type representation
- subtype and consistency
- basic inference

Deliverables:

- `.tynix -> .nix`
- `tynix check`
- `tynix emit`

## Phase 2: Ambient + Workspace ✅

- `.d.tynix` parser
- workspace declaration discovery
- `import` declaration resolution
- declaration emitter stabilization

## Phase 3: Type Puzzle Features ✅

- conditional types
- `infer`
- higher-kinded type application
- improved solver diagnostics

## Phase 4: Tooling ✅

- Haskell LSP server
- VS Code extension
- Zed extension
- neovim helper

## Phase 5: Hardening 🚧

- larger fixture corpus ✅
- golden tests ✅
- regression suite ✅
- performance tuning 🚧
- incremental cache ✅ (LSP analysis cache)

## Toward v1.0: Production Ready 🚧

Tracked under the
[**Production Ready (v1.0)**](https://github.com/ubugeeei-prod/tynix/milestone/1)
milestone, organized as epics:

- Nix-language parity ✅: attrset patterns with defaults and `@` binders,
  `inherit (src)`, nested and dynamic attribute paths, `or` defaults, every
  operator (`/`, `->`, `|>`, `<|`, prefix `-`), `<nixpkgs>`, `~/` and
  interpolated paths, string escapes. Compiled output of 4000 sampled nixpkgs
  files parses to the same AST as the source under `nix-instantiate --parse`.
- Span-carrying diagnostics ✅: `line:col` in the CLI, exact underlines in
  editors, argument-level call mismatches, field-level record errors
- Checker soundness ✅: Hindley-Milner let-polymorphism with per-SCC
  generalization, rigid (skolemized) signatures, row-polymorphic open
  records, optional fields, `AttrsOf` dictionaries
- Gradual adoption of unannotated Nix ✅: soft injected dependencies, literal
  widening, a typed prelude for every builtin; about 98% of a sample of 800
  unannotated nixpkgs files type-check
- LSP features ✅: scope- and type-aware completion, rich diagnostics with
  related information, unused-binding and deprecation lints, code actions,
  signature help, navigation
- Editor setup and distribution ✅: `tynix ide install`, `tynix doctor`, the
  `tynix.dev` installer, flake packages, overlay and NixOS / nix-darwin / Home
  Manager modules
- CLI output contract and exit codes ✅; watch mode 🚧
- Release/cross-platform packaging and CI hardening (lint, security scan,
  coverage) 🚧
- Property-based, integration, golden, and benchmark tests 🚧

## Next: Type System

Planned after v1.0, roughly in priority order:

- type classes, so that constraint contexts such as `Functor f =>` (already
  parsed) are enforced
- flow-sensitive narrowing through guards: `isAttrs x`, `x ? a`,
  `x._tag == "some"` and `x != null` refining `x` inside the branch
- `config`-aware typing of NixOS, nix-darwin and Home Manager modules, with
  option declarations driving the type of `config`
- implementing records whose fields carry their own `forall` (instances of
  `Functor`-style dictionaries) in `.tynix`
- reporting more than one diagnostic per file
- kind annotations

## Shipping Criteria

- erased `.nix` preserves source semantics
- existing `.nix` files can be typed with `.d.tynix` alone
- hover and diagnostics are practically useful
- the main type-puzzle examples are expressible
