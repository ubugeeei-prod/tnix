# Getting Started

## What `tynix` Is

`tynix` is a static type layer for Nix.

- `.tynix` keeps ordinary Nix value syntax
- types are used for checking, hover, and declaration emit
- generated `.nix` erases all type syntax

If you already know Nix, the goal is that `tynix` feels like "Nix plus a type surface", not a different runtime language.

## Installation

### Install script (Linux, macOS)

```bash
curl -fsSL https://tynix.dev/install.sh | sh
```

The script detects your OS and CPU, downloads the matching release archive,
verifies its SHA-256 checksum, and installs `tynix` and `tynix-lsp` into
`~/.tynix/bin` (it prints the line to add to your shell profile if that
directory is not on `PATH`). The binaries do not need Nix: Linux builds are
fully static, and macOS builds only link system libraries.

Options can be passed after `sh -s --`, or as environment variables:

```bash
# A specific release
curl -fsSL https://tynix.dev/install.sh | sh -s -- --version 0.5.0   # or TYNIX_VERSION=0.5.0
# A custom install directory
curl -fsSL https://tynix.dev/install.sh | TYNIX_INSTALL_DIR="$HOME/.local/bin" sh
# Uninstall
curl -fsSL https://tynix.dev/install.sh | sh -s -- --uninstall
```

Re-running the script upgrades to the latest release.

### Nix flake

```bash
# Install tynix and tynix-lsp into your profile
nix profile install github:ubugeeei-prod/tynix

# Or run without installing
nix run github:ubugeeei-prod/tynix -- check ./main.tynix
```

The flake also exports `overlays.default` (adds `pkgs.tynix`, `pkgs.tynix-lsp`
and `pkgs.tynix-toolchain`) and modules that install the toolchain with
`programs.tynix.enable = true;`:

```nix
# flake.nix: inputs.tynix.url = "github:ubugeeei-prod/tynix";

# NixOS (use tynix.darwinModules.default for nix-darwin)
{ inputs, ... }:
{
  imports = [ inputs.tynix.nixosModules.default ];
  programs.tynix.enable = true;
}

# Home Manager
{ inputs, ... }:
{
  imports = [ inputs.tynix.homeManagerModules.default ];
  programs.tynix.enable = true;
}
```

### Supported platforms

Prebuilt `tynix` and `tynix-lsp` archives ship for Linux x64, Linux arm64, macOS
arm64 (Apple silicon), and macOS x64 (Intel). Other platforms can build from
source through the Nix flake. Windows is not tested today. Use WSL2 and the
Linux install script there. See [support-matrix.md](./support-matrix.md) for
the full per-platform tier table.

Check the install:

```bash
tynix --version
tynix-lsp --version
```

## First Commands

From the repository root:

```bash
nix develop
```

Typical CLI entry points:

```bash
tynix init .
tynix scaffold .
tynix check ./examples/main.tynix
tynix compile ./examples/main.tynix -o ./dist/main.nix
tynix emit ./examples/main.tynix -o ./dist/main.d.tynix
```

If you are using the published flake directly:

```bash
nix run github:ubugeeei-prod/tynix#tynix -- check ./main.tynix
nix run github:ubugeeei-prod/tynix#tynix -- compile ./main.tynix -o ./main.nix
nix run github:ubugeeei-prod/tynix#tynix -- emit ./main.tynix -o ./main.d.tynix
```

To set up an editor, run `tynix ide install vscode` (or `cursor`, `vscodium`,
`zed`, `neovim`, `helix`), then `tynix doctor`. See [Editor Setup](./editors.md).

## Scaffolding A Project

`tynix init` creates a starter project in the target directory:

- `tynix.config.tynix`
- `tynix.config.d.tynix`
- `src/main.tynix`
- `types/builtins.d.tynix`

`builtins` and the global builtins (`toString`, `map`, `throw`, ...) are typed
out of the box by a prelude embedded in the binary. A workspace
`declare "builtins"` block replaces that prelude, so delete the scaffolded
`types/builtins.d.tynix` unless you want to restrict the builtins, and set
`builtins = false;` to keep `tynix scaffold` from recreating it.

The generated config is ordinary tynix syntax:

```tynix
{
  name = "demo";
  sourceDir = ./src;
  entry = ./src/main.tynix;
  declarationDir = ./types;
  declarationPacks = [];
  buildDir = ./dist;
  generatedDeclarationDir = ./dist/types;
  entries = [];
  include = [];
  exclude = [];
  builtins = true;
}
```

You can later re-run:

```bash
tynix scaffold .
```

to materialize any missing scaffold files without overwriting existing ones.

The generated `tynix.config.d.tynix` lets other typed files import the project
config with a stable declaration instead of treating it as untyped.

## Your First `.tynix` File

```tynix
let
  greeting :: String;
  greeting = "hello";
in greeting
```

Checking this file validates the annotation and infers the root type.

Compiling it produces ordinary Nix:

```nix
let
  greeting = "hello";
in greeting
```

## Records And Field Access

`tynix` uses structural typing for attribute sets.

```tynix
let
  pkg :: { name :: String; version :: String; };
  pkg = { name = "tynix"; version = "0.1.0"; };
in pkg.name
```

The checker understands the field projection and infers the root type as `String`.

## Ambient Typing For Existing `.nix`

You can type legacy `.nix` modules without rewriting them.

```tynix
declare "./legacy/default.nix" {
  default :: { name :: String; version :: String; };
};

import ./legacy/default.nix
```

This is the main bridge for incremental adoption:

- keep the runtime implementation in `.nix`
- describe its public API in `.d.tynix` or inline `declare`
- use that API from typed `.tynix`

## Nix Syntax

`.tynix` accepts the whole Nix expression language, so existing code can be
renamed to `.tynix` and annotated gradually. For example:

```tynix
{ lib ? null, name ? "demo", version, ... }@args:
let
  base = { meta.license = "MIT"; meta.homepage = "https://example.org"; };
  inherit (base.meta) license;
  greeting = "${name}-${version}";
in base // {
  inherit greeting license;
  half = 7 / 2;
  safe = args.extra.port or 8080;
  piped = [ 1 2 3 ] |> builtins.length;
  implied = true -> false;
  src = ./${name}.nix;
}
```

Attribute-set patterns with defaults and `@` binders, `inherit (src)`, nested
(`a.b.c = 1;`) and dynamic (`${k} = v;`) attribute paths, `x.a or default`,
`x ? ${k}`, every operator (including `/`, `->`, `|>` and `<|`), `<nixpkgs>`,
`~/` and interpolated paths, and `$$` string escapes all parse and type-check.
Only Nix keywords are reserved: `type`, `any`, `import` and `declare` are
ordinary names in expressions, and `as` is an ordinary name except in the
`expr as Type` cast. See the [language reference](./language-reference.md#nix-compatibility).

## Flake Workflow

A flake can be written directly as `flake.tynix` and compiled to `flake.nix`;
the [flake tutorial](./tutorial/flakes-and-packages.md#a-flake) walks through
it. Annotate the inputs you use, `{ self, nixpkgs :: NixpkgsInput, ... }:`, and
every lookup through them is checked.

If you would rather keep `flake.nix` hand-written, describe it with a
declaration and check a typed *projection* of the parts you care about:

```tynix
declare "./flake.nix" {
  description :: String;
  outputs :: dynamic -> {
    packages :: { x86_64-linux :: { default :: Derivation; }; };
  };
};

let
  flake = import ./flake.nix;
  outputs = flake.outputs { };
in {
  description = flake.description;
  package = outputs.packages.x86_64-linux.default;
}
```

`Derivation` is one of the aliases the built-in prelude provides.

## Bundled Ecosystem Declarations

The repository ships curated declaration packs under `registry/` for both local
workspace files and common Nix ecosystem surfaces. They are meant to be copied
or vendored into your project when you want a DefinitelyTyped-style starting
point instead of handwriting every ambient declaration.

Directory layout:

- `registry/workspace/` for `builtins`, `flake.nix`, and `tynix.config.tynix`
- `registry/ecosystem/` for reusable alias packs such as `nixpkgs` and popular flakes

Available packs currently cover:

- `nixpkgs.lib`
- `pkgs` / `import nixpkgs`
- `flake-utils`, `home-manager`, `nix-darwin`, `flake-parts`
- `devenv`, `treefmt-nix`, `pre-commit-hooks.nix`, `crane`, `deploy-rs`, `nixvim`, `sops-nix`, `agenix`, `disko`, `colmena`

Example:

```tynix
declare "./flake-utils.nix" { default :: NixFlakeUtilsFlake; };
declare "./devenv.nix" { default :: DevenvFlake; };
declare "./pre-commit-hooks.nix" { default :: PreCommitHooksFlake; };
```

This keeps the runtime import path local to your project while reusing stable
alias names from the bundled registry packs.

If you want to consume the upstream packs without copying them into your
repository, list them in `declarationPacks`:

```tynix
{
  declarationPacks = [
    ../vendor/tynix/registry/ecosystem
    ../vendor/tynix/registry/workspace
  ];
}
```

`registry/workspace/` packs are rebased onto your current project root, so
their ambient declarations still target your local `flake.nix` and
`tynix.config.tynix`.

## Lists, Vectors, And Matrices

Plain Nix list syntax can infer more precise indexed shapes.

```tynix
{
  pair = [1 2];
  grid = [[1 2] [3 4]];
  ragged = [[1] [2 3]];
}
```

```text
root: {
  grid :: Matrix 2 2 (1 | 2 | 3 | 4);
  pair :: Vec 2 (1 | 2);
  ragged :: List (Vec (1 | 2) (1 | 2 | 3));
}
```

You can also write shape annotations directly:

```tynix
let
  xs :: Vec 3 Int;
  xs = [1 2 3];
in xs
```

Bounded lengths are supported too:

```tynix
let
  xs :: Vec (Range 2 4 Nat) Int;
  xs = [1 2 3];
in xs
```

## Numeric Validation

`tynix` includes a small refinement surface for numeric values.

```tynix
let
  ratio :: Range 0.0 1.0 Float;
  ratio = 0.5;
in ratio
```

This passes, while:

```tynix
let
  ratio :: Range 0.0 1.0 Float;
  ratio = 1.5;
in ratio
```

is rejected.

## Units

Units are phantom wrappers that survive checking but disappear at runtime.

```tynix
let
  timeout :: Unit "ms" (Range 0 5000 Nat);
  timeout = 2500;
in timeout
```

Different labels stay distinct:

```tynix
let
  timeoutMs :: Unit "ms" Nat;
  timeoutMs = 1;
  timeoutS :: Unit "s" Nat;
  timeoutS = timeoutMs;
in timeoutS
```

The assignment to `timeoutS` is rejected.

## Casts

`tynix` also supports explicit `as` casts for the places where you want to
assert a more useful static view.

```tynix
let
  value :: unknown;
  value = 1;
in value as Int
```

This is accepted because the cast is explicit. Widening casts work too:

```tynix
1 as Number
```

Concrete unrelated casts are still rejected:

```tynix
1 as String
```

At compile time the cast disappears, so the generated `.nix` still contains
only the original runtime expression.

## Diagnostic Directives

`tynix` supports TypeScript-style line comments for intentional checker failures.

Ignore the next line's checker error:

```tynix
let
  # @tynix-ignore
  value = missing;
in value
```

Expect the next line to fail and report an error if it does not:

```tynix
let
  # @tynix-expected
  value :: Int;
  value = "oops";
in value
```

These directives apply to the root expression or to one `let` item.

## Declaration Emit

`tynix emit` turns a `.tynix` file into a `.d.tynix` API surface.

Source (`user.tynix`):

```tynix
type User = { name :: String; };

{
  make = (name :: String): { inherit name; } as User;
}
```

Emitted declaration:

```tynix
type User  = {
  name :: String;
};
declare "./user.nix" {
  make :: String %1 -> User;
};
```

The `declare` target is not a literal string: `tynix emit` derives it from the
source path by replacing the `.tynix` extension with `.nix`, expressed relative
to the emitted `.d.tynix` file's directory. So emitting `widget.tynix` produces
`declare "./widget.nix" { … }`. The `%1 ->` arrow marks a function that uses its
argument exactly once; see [Annotations and inference](./tutorial/annotations.md#functions-and-the-1-arrow).

## Suggested Learning Path

1. Start by renaming a file to `.tynix` and running `tynix check`; inference and
   the builtins prelude cover a lot without any annotations.
2. Add annotations on `let` bindings and function parameters where you want
   to state intent.
3. Add ambient declarations for existing `.nix` imports.
4. Use `emit` to stabilize public APIs between files.
5. Add `tynix.config.tynix` and `tynix scaffold` once the project layout is settling.
6. Reach for `Vec` / `Matrix` / `Tensor`, `Range`, and `Unit` when the shape or numeric contract actually matters.

## Next Docs

- [Tutorial](./tutorial/index.md)
- [Editor Setup](./editors.md)
- [Language Reference](./language-reference.md)
- [Type System](./type-system.md)
- [Language Design](./language-design.md)
- [Architecture](./architecture.md)
