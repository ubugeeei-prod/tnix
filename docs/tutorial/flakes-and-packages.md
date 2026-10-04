---
title: "9. Typing a flake and a package.nix"
description: Apply tnix to the two most common Nix files, a callPackage-style package and a flake, with small hand-written nixpkgs types.
---

# 9. Typing a flake and a package.nix

Time to type real Nix shapes. You will describe the slice of nixpkgs that you
use, write a `callPackage`-style package in tnix, and author a flake whose
outputs are checked.

## Describe the nixpkgs you use

You do not need a type for all of nixpkgs. Describe the handful of attributes
your files touch:

```tnix [types/nixpkgs.d.tnix]
type Derivation = {
  name :: String;
  outPath :: String;
};

type MkDerivationArgs = {
  pname :: String;
  version :: String;
  src :: Path | Derivation;
};

type Stdenv = {
  mkDerivation :: MkDerivationArgs -> Derivation;
};

type FetchUrl = { url :: String; hash :: String; } -> Path;

type Pkgs = {
  stdenv :: Stdenv;
  fetchurl :: FetchUrl;
  hello :: Derivation;
  mkShell :: { packages :: List Derivation; } -> Derivation;
};

type NixpkgsInput = {
  legacyPackages :: {
    x86_64-linux :: Pkgs;
    aarch64-darwin :: Pkgs;
  };
};
```

This file only contains aliases, and aliases from workspace declaration files
are visible to every file in the workspace. Records are structural, so the real
nixpkgs values, which have far more attributes, fit these narrow types.

> [!TIP]
> The repository ships much larger alias packs for nixpkgs, `lib`, and popular
> flakes in [`registry/ecosystem/`](https://github.com/ubugeeei-prod/tnix/tree/main/registry/ecosystem).
> They are a good source to copy from. See
> [builtins and the registry](../reference/builtins.md).

## A package

`callPackage` inspects a function's attribute-set pattern to decide which
arguments to pass, so a package must keep the `{ stdenv, fetchurl }:` shape.
Pattern-bound names start out untyped, so give them their types with a cast at
the point of use:

```tnix [package.tnix]
{ stdenv, fetchurl }:
(stdenv as Stdenv).mkDerivation {
  pname = "hello";
  version = "2.12.1";
  src = (fetchurl as FetchUrl) {
    url = "mirror://gnu/hello/hello-2.12.1.tar.gz";
    hash = "sha256-jZkUKv2SV28wsM18tCqNxoCZmLxdYH2Idh9RLibH2yA=";
  };
  meta = { description = "A program that produces a familiar, friendly greeting"; };
}
```

```bash
tnix check package.tnix
```

```text
root: {
  fetchurl :: FetchUrl;
  stdenv :: Stdenv;
} -> {
  name :: String;
  outPath :: String;
}
```

The casts did more than allow the field access: they fixed the types of the
pattern's fields, so the whole file now has the type "a function from
`{ stdenv; fetchurl; }` to a derivation". Forget `version` and the check
fails, naming exactly what was expected:

```text
[TC0013] type mismatch: {
  pname :: "hello";
  src :: Path;
} vs {
  pname :: String;
  src :: Path | {
    name :: String;
    outPath :: String;
  };
  version :: String;
}
```

Compile it to the `package.nix` that `callPackage` will load:

```bash
tnix compile package.tnix -o package.nix
```

```nix [package.nix]
{ stdenv, fetchurl }: stdenv.mkDerivation {
  pname = "hello";
  version = "2.12.1";
  src = fetchurl {
    url = "mirror://gnu/hello/hello-2.12.1.tar.gz";
    hash = "sha256-jZkUKv2SV28wsM18tCqNxoCZmLxdYH2Idh9RLibH2yA=";
  };
  meta = {
    description = "A program that produces a familiar, friendly greeting";
  };
}
```

> [!NOTE]
> **Upcoming syntax.** Default arguments and `@` binders
> (`{ stdenv, fetchurl, withDocs ? false, ... }@args:`), `inherit (lib) licenses;`,
> nested attribute paths (`meta.license = ...;`), and `<nixpkgs>` lookups
> (`import <nixpkgs> { }`) are being added to the parser. Until they land,
> list pattern fields without defaults, write `meta = { license = ...; };`, and
> pass nixpkgs in explicitly.

## A flake

A flake's `outputs` is a function from the resolved inputs to an attribute set.
Annotate the function parameter and every `inputs.nixpkgs...` lookup is
checked:

```tnix [flake.tnix]
type FlakeInputs = {
  self :: dynamic;
  nixpkgs :: NixpkgsInput;
};

{
  description = "hello, typed with tnix";

  inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-unstable"; };
  };

  outputs = (inputs :: FlakeInputs):
    let
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages = {
        x86_64-linux = {
          default = pkgs.hello;
        };
      };
      devShells = {
        x86_64-linux = {
          default = pkgs.mkShell { packages = [ pkgs.hello ]; };
        };
      };
    };
}
```

```bash
tnix check flake.tnix
tnix compile flake.tnix -o flake.nix
```

`outputs = inputs: ...` is a valid flake: Nix passes the inputs as one attribute
set, whether or not you destructure it. Mistakes that would otherwise surface
only during `nix flake check` on a specific system are now immediate. Ask for a
system that `NixpkgsInput` does not list:

```text
[TC0009] missing field `riscv64-linux` on {
  aarch64-darwin :: {
  ...
```

Put something that is not a derivation into `mkShell`'s `packages`, such as the
string `"git"`, and the list no longer matches `List Derivation`.

> [!TIP]
> Commit both `flake.tnix` and the generated `flake.nix`. Nix reads only
> `flake.nix`, and flakes see only files tracked by Git.

## Alternative: type an existing flake without converting it

If you would rather keep `flake.nix` as hand-written Nix, describe it with a
declaration and check a small typed *projection* of it instead. tnix does this
for its own flake in
[`dogfood/flake-surface.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/dogfood/flake-surface.tnix):

```tnix [types/flake.d.tnix]
type FlakeOutputs = {
  packages :: { x86_64-linux :: { default :: Derivation; }; };
};

declare "../flake.nix" {
  description :: String;
  outputs :: dynamic -> FlakeOutputs;
};
```

```tnix [flake-surface.tnix]
let
  flake = import ./flake.nix;
in flake.description
```

The declaration's target path is relative to the `.d.tnix` file, hence
`../flake.nix` from `types/`.

## Recap

- Describe only the nixpkgs surface you use; structural records make narrow
  types fit.
- Keep `callPackage` patterns and type pattern-bound names with `as`.
- Annotate `outputs`' parameter to check every input lookup.
- Generate `flake.nix` from `flake.tnix`, or keep `flake.nix` and declare it.

<div class="tx-pager">

[← 8. Conditional types](./conditional-types.md) [10. Editor setup →](./editor.md)

</div>
