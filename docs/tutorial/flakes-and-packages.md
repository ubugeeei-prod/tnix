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
nixpkgs values, which have far more attributes, fit these narrow types. The
built-in prelude already defines a complete `Derivation`; a workspace alias
with the same name takes precedence, which keeps this example small.

> [!TIP]
> The repository ships much larger alias packs for nixpkgs, `lib`, and popular
> flakes in [`registry/ecosystem/`](https://github.com/ubugeeei-prod/tnix/tree/main/registry/ecosystem).
> They are a good source to copy from. See
> [builtins and the registry](../reference/builtins.md).

## A package

`callPackage` inspects a function's attribute-set pattern to decide which
arguments to pass, so a package keeps the usual `{ stdenv, fetchurl }:` shape.
Annotate the pattern fields you want checked. The annotations are erased, so
`callPackage` still sees exactly the pattern it expects:

```tnix [package.tnix]
{ stdenv :: Stdenv, fetchurl :: FetchUrl, doCheck ? true }:
stdenv.mkDerivation {
  pname = "hello";
  version = "2.12.1";
  src = fetchurl {
    url = "mirror://gnu/hello/hello-2.12.1.tar.gz";
    hash = "sha256-jZkUKv2SV28wsM18tCqNxoCZmLxdYH2Idh9RLibH2yA=";
  };
  inherit doCheck;
  meta.description = "A program that produces a familiar, friendly greeting";
}
```

```bash
tnix check package.tnix
```

```text
root: {
  doCheck? :: Bool;
  fetchurl :: FetchUrl;
  stdenv :: Stdenv;
} -> {
  name :: String;
  outPath :: String;
}
```

The file now has the type "a function from `{ stdenv; fetchurl; doCheck?; }` to
a derivation". `doCheck ? true` became an optional `Bool` field. Forget
`version` and the check fails at the `mkDerivation` argument, naming the
missing field:

```text
2:21: [TC0009] missing field `version`: expected { pname :: String; src :: Path | { name :: String; outPath :: String; }; version :: String; } but got { doCheck :: Bool; meta :: { description :: "A program that produces a familiar, friendly greeting"; }; pname :: "hello"; src :: Path; }
```

Compile it to the `package.nix` that `callPackage` will load:

```bash
tnix compile package.tnix -o package.nix
```

```nix [package.nix]
{ stdenv, fetchurl, doCheck ? true }: stdenv.mkDerivation {
  pname = "hello";
  version = "2.12.1";
  src = fetchurl {
    url = "mirror://gnu/hello/hello-2.12.1.tar.gz";
    hash = "sha256-jZkUKv2SV28wsM18tCqNxoCZmLxdYH2Idh9RLibH2yA=";
  };
  inherit doCheck;
  meta.description = "A program that produces a familiar, friendly greeting";
}
```

### Unannotated dependencies stay gradual

You can also leave the pattern unannotated. tnix then treats the injected
dependencies as *gradual*: it records which fields you select, but calling one
of them does not fix its type from that single call site.

```tnix [package-untyped.tnix]
{ stdenv, fetchurl }:
stdenv.mkDerivation {
  pname = "hello";
  version = "2.12.1";
  src = fetchurl { url = "mirror://gnu/hello/hello-2.12.1.tar.gz"; };
}
```

```text
root: {
  fetchurl :: dynamic -> dynamic;
  stdenv :: {
    mkDerivation :: dynamic -> dynamic;
    ...
  };
} -> dynamic
```

That is why unannotated nixpkgs code type-checks out of the box: functions such
as `lib.mkOption` or `fetchFromGitHub` are polymorphic or overloaded in
practice, and pinning them to their first use would produce false errors. Add
annotations where you want real checking.

The rest of the Nix language works as you would expect: `inherit (lib)
licenses;`, `meta.license = ...;`, `import <nixpkgs> { }`, `x.a or default`,
`|>` pipes and the other operators all parse and type-check.

## A flake

A flake's `outputs` is a function from the resolved inputs to an attribute set.
Annotate the inputs you use and every lookup through them is checked:

```tnix [flake.tnix]
{
  description = "hello, typed with tnix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs :: NixpkgsInput, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.default = pkgs.hello;
      devShells.x86_64-linux.default = pkgs.mkShell { packages = [ pkgs.hello ]; };
    };
}
```

```bash
tnix check flake.tnix
tnix compile flake.tnix -o flake.nix
```

Mistakes that would otherwise surface only during `nix flake check` on a
specific system are now immediate. Ask for a system that `NixpkgsInput` does
not list:

```text
8:14: [TC0009] missing field `riscv64-linux` on { aarch64-darwin :: { ...
```

Put something that is not a derivation into `mkShell`'s `packages`, such as the
string `"git"`, and the error names the field:

```text
11:53: [TC0013] type mismatch in field `packages`: Vec 1 "git" vs List { name :: String; outPath :: String; }
```

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
- Keep `callPackage` patterns and annotate their fields
  (`{ stdenv :: Stdenv, ... }:`); unannotated dependencies stay gradual.
- Annotate the flake inputs you use to check every lookup through them.
- Generate `flake.nix` from `flake.tnix`, or keep `flake.nix` and declare it.

<div class="tx-pager">

[← 8. Conditional types](./conditional-types.md) [10. Editor setup →](./editor.md)

</div>
