# Adopting tnix in an Existing Project

`tnix` is built for incremental adoption, the same way TypeScript was added to
existing JavaScript codebases. You do **not** rewrite your `.nix` files. You add
types alongside them, type-check the surfaces you care about, and grow coverage
over time. Erased output is ordinary Nix, so adoption never changes runtime
behavior.

This guide walks an existing flake-based repository from zero to a checked
surface.

## 1. Add tnix to the toolchain

Install the CLI (and language server) from the flake, or vendor the repository
and run through the dev shell:

```bash
nix profile install github:ubugeeei/tnix#tnix
nix profile install github:ubugeeei/tnix#tnix-lsp
```

Verify it runs:

```bash
tnix --version
```

## 2. Create a project config

From the repository root:

```bash
tnix init
```

This writes a `tnix.config.tnix` plus starter files. Point `sourceDir`/`entries`
at the directories where your typed `.tnix` files will live, and set
`declarationDir` to where you'll keep ambient `.d.tnix` declarations.

## 3. Type your first existing module — don't rewrite it

Keep the runtime implementation in `.nix`. Describe its public API in a
`.d.tnix` (or an inline `declare`) and consume it from typed `.tnix`:

```tnix
declare "./legacy/default.nix" {
  default :: { name :: String; version :: String; };
};

import ./legacy/default.nix
```

This is the core bridge:

- the implementation stays in `.nix`,
- its surface is described once in a declaration,
- typed code consumes that surface and is checked against it.

## 4. Type the flake surface

For flakes, keep the full implementation in `flake.nix` and write a typed
*projection* over the parts you want checked. The pattern (adapted from
[`dogfood/flake-surface.tnix`](../dogfood/flake-surface.tnix)):

```tnix
let
  flake = import ../flake.nix;

  inputs :: ResolvedFlakeInputs;
  inputs = { self = builtins; nixpkgs = builtins; };

  outputs :: FlakeOutputs;
  outputs = flake.outputs inputs;
in {
  description = flake.description;
  devShell = outputs.devShells.aarch64-darwin.default;
}
```

You stay on a stable, checked surface while the real flake logic remains
untouched.

## 5. Reuse bundled ecosystem declarations

Instead of hand-writing ambient types for common dependencies, reuse the packs
under `registry/`. Either copy them in, or reference them without vendoring by
listing them in `declarationPacks` in `tnix.config.tnix`:

```tnix
{
  declarationPacks = [
    ../vendor/tnix/registry/ecosystem
    ../vendor/tnix/registry/workspace
  ];
}
```

Packs cover `nixpkgs.lib`, `pkgs` / `import nixpkgs`, `flake-utils`,
`home-manager`, `nix-darwin`, `flake-parts`, `devenv`, and more — see
[getting-started.md](./getting-started.md#bundled-ecosystem-declarations).

## 6. Check the project and wire it into CI

```bash
tnix check-project ./. --format json
```

This exits non-zero on type errors, so it gates a build directly. A typical CI
step runs the same command; see [ci-cd.md](./ci-cd.md) for hardening notes and
the JSON output contract.

## 7. Grow coverage incrementally

- Start with the highest-value surfaces (your flake outputs, shared libraries).
- Use `dynamic` / `unknown` / `any` at gradual boundaries and tighten them later
  (see [type-system.md](./type-system.md)).
- Use `expr as Type` casts at boundaries you can't yet prove, and
  `# @tnix-ignore` to defer individual diagnostics without blocking the rest.
- Generate declaration files for typed modules with `tnix emit` /
  `tnix emit-project` so downstream consumers get a checked surface.

## What not to migrate (yet)

Executable `.tnix` targets a Nix-like subset, not full parser parity. For
modules that use constructs outside that subset, prefer ambient typing
(steps 3–4) over rewriting them as `.tnix`. The supported subset and its current
exclusions are documented in [grammar.md](./grammar.md) and the
[README](../README.md).
