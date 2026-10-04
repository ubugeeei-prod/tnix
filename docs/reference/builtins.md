---
title: Builtins and Registry
description: The built-in type constructors, the names in scope by default, how to type Nix builtins, and the declaration packs shipped in the registry.
---

# Builtins and Registry

## Built-in type constructors

These names are always available in types. Any other capitalized name must be
an alias or comes from a declaration file.

| Name | Kind | Meaning |
| --- | --- | --- |
| `String` | `Type` | strings; string literals such as `"web"` are subtypes |
| `Int` | `Type` | integers |
| `Nat` | `Type` | non-negative integers; `Nat <: Int` |
| `Float` | `Type` | floating-point numbers |
| `Number` | `Type` | any number; `Int <: Number`, `Float <: Number` |
| `Bool` | `Type` | booleans; `true` and `false` are literal subtypes |
| `Null` | `Type` | the type of `null` |
| `Path` | `Type` | path literals such as `./src` |
| `List` | `Type -> Type` | homogeneous lists |
| `Tuple` | `Type -> Type` | fixed heterogeneous lists, written `Tuple [ A B ]` |
| `Vec` | `Type -> Type -> Type` | `Vec n a`: lists of length `n` |
| `Matrix` | `Type -> Type -> Type -> Type` | `Matrix r c a`: rectangular nested lists |
| `Tensor` | `Type -> Type -> Type` | `Tensor [ d1 d2 ... ] a`: rank-n shapes |
| `Range` | `Type -> Type -> Type -> Type` | `Range lo hi base`: inclusive numeric bounds |
| `Unit` | `Type -> Type -> Type` | `Unit "label" base`: phantom units of measure |

The keywords `dynamic`, `unknown` and `any` are types too; see
[gradual typing](../tutorial/gradual.md). Literal types (`"web"`, `8080`, `1.5`,
`true`, `false`) can appear anywhere a type can.

## Names in scope in expressions

Every `.tnix` file starts with two names in scope:

| Name | Default type | Becomes |
| --- | --- | --- |
| `builtins` | `dynamic` | the declared record, once a `declare "builtins" { ... }` block is loaded |
| `import` | `Path -> dynamic` | the declared scheme of the target, when the argument is a path or string literal with a declaration |

Everything else must be bound by `let`, a lambda, `rec`, or a `with` scope.

> [!NOTE]
> **Upcoming.** Nix's global builtins that do not need the `builtins.` prefix
> (`toString`, `map`, `throw`, `derivation`, `baseNameOf`, `isNull`, and
> friends) are being added to the default scope. Until then, write
> `builtins.toString` and so on.

## Typing `builtins`

`builtins` stays `dynamic` until a declaration says otherwise:

```tnix [types/builtins.d.tnix]
declare "builtins" {
  head :: forall a. List a -> a;
  length :: forall a. List a -> Int;
  map :: forall a b. (a -> b) -> List a -> List b;
  toString :: dynamic -> String;
};
```

This is the starter file that `tnix init` writes. Once any declaration for
`"builtins"` is visible in the workspace, `builtins` is a **closed** record:
members that are not declared are `TC0009` errors rather than `dynamic`. Either
declare everything you use, or start from the full pack below.

The target string `"builtins"` is special-cased; it does not name a file. Like
any other target, it may be declared only once per workspace.

## The registry

The repository's [`registry/`](https://github.com/ubugeeei-prod/tnix/tree/main/registry)
directory contains curated declaration packs, in the spirit of DefinitelyTyped.
Copy the files you need into your project, or vendor the directory and list it
in [`declarationPacks`](./config.md#declarationpacks).

### `registry/workspace/`

Declarations for files every project has. These are rebased onto your project
root when loaded through `declarationPacks`.

| File | Declares |
| --- | --- |
| [`builtins.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/builtins.d.tnix) | about 100 Nix builtins, from `abort` to `zipAttrsWith`, plus helper aliases such as `Predicate a` and `Fold b a` |
| [`flake.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/flake.d.tnix) | a minimal `flake.nix` shape: `description`, `inputs`, and `outputs :: ResolvedFlakeInputs -> FlakeOutputs` |
| [`tnix.config.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/tnix.config.d.tnix) | `TnixProjectConfig` for `tnix.config.tnix` |

### `registry/ecosystem/`

Alias-only packs for common upstream APIs. They declare **types**, not files,
so you connect them to your imports with your own `declare` blocks:

```tnix
declare "./nix/flake-utils.nix" { default :: NixFlakeUtilsFlake; };
```

| File | Main aliases |
| --- | --- |
| [`nixpkgs-lib.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/nixpkgs-lib.d.tnix) | `NixpkgsLib` with `lists`, `strings`, `attrsets`, `trivial`, `modules`, `systems`; `NixpkgsMeta`, `NixpkgsLicense`, `NixpkgsSystem` |
| [`nixpkgs-pkgs.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/nixpkgs-pkgs.d.tnix) | `NixpkgsPkgs`, `NixpkgsStdenv`, `NixpkgsDerivation`, `NixpkgsMkDerivationArgs`, `NixpkgsMkShellArgs`, fetcher arguments, `NixpkgsImport` |
| [`flake-ecosystem.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/flake-ecosystem.d.tnix) | `NixFlakeInputSpec`, `NixFlakeSystemOutputs a`, `NixpkgsFlake`, `NixFlakeUtilsFlake`, `HomeManagerFlake`, `NixDarwinFlake`, `FlakePartsLib` |
| [`community-flakes.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/community-flakes.d.tnix) | `DevenvFlake`, `TreefmtNixFlake`, `PreCommitHooksFlake`, `CraneFlake`, `FenixFlake`, `DeployRsFlake`, `NixvimFlake`, `SopsNixFlake`, `AgenixFlake`, `DiskoFlake`, `ColmenaFlake` |

> [!WARNING]
> tnix records have no optional fields, so a registry argument type such as
> `NixpkgsMkDerivationArgs` requires *every* field it lists (fields like
> `buildInputs :: List dynamic | Null` must be present, possibly as `null`).
> When that is too strict for your call sites, define a narrower alias with
> only the fields you pass, as the
> [flake tutorial](../tutorial/flakes-and-packages.md) does.

## Writing your own pack

- Put aliases and `declare` blocks in `.d.tnix` files. A declaration file must
  not contain an expression: one that does breaks analysis for the whole
  workspace with `TD0007`.
- Prefix alias names with the library's name (`Nixpkgs...`, `HomeManager...`).
  All aliases share one namespace per workspace.
- Prefer `dynamic` for parts you have not modeled over guessing; a wrong type is
  worse than an honest `dynamic`.
- Use `forall` for polymorphic members (`map :: forall a b. ...`), and let
  higher-kinded parameters be inferred (`type Functor f = { ... f a ... };`).
