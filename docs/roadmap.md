# Roadmap

Status legend: ✅ shipped · 🚧 in progress.

Phases 0–4 shipped in the integrated `0.5.0` toolchain release. Phase 5 hardening
is largely shipped; the remaining production-readiness work is tracked under the
[**Production Ready (v1.0)**](https://github.com/ubugeeei/tnix/milestone/1)
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

- `.tnix -> .nix`
- `tnix check`
- `tnix emit`

## Phase 2: Ambient + Workspace ✅

- `.d.tnix` parser
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
[**Production Ready (v1.0)**](https://github.com/ubugeeei/tnix/milestone/1)
milestone, organized as epics:

- Nix-language parity (string interpolation, operators, nested attr paths)
- Checker soundness & structured, span-carrying diagnostics
- LSP robustness (crash isolation, JSON-RPC errors) and features (formatting,
  signature help)
- CLI output contract, exit codes, and watch mode
- Release/cross-platform packaging and CI hardening (lint, security scan,
  coverage)
- Property-based, integration, golden, and benchmark tests

## Shipping Criteria

- erased `.nix` preserves source semantics
- existing `.nix` files can be typed with `.d.tnix` alone
- hover and diagnostics are practically useful
- the main type-puzzle examples are expressible
