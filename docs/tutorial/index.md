---
title: Tutorial
description: A hands-on, step-by-step tour of tnix, from installing the CLI to type-checking a flake in CI.
---

# Tutorial

This tutorial takes you from an empty directory to a type-checked flake that
runs in CI. Each step builds on the previous one and every example is a real
file that you can check with `tnix check`.

You should be comfortable reading Nix. No TypeScript or Haskell knowledge is
required, though readers who know either will recognize the ideas.

## What you will build

You start with a single `hello.tnix` file. Along the way you will type a small
package description, describe an untyped `.nix` module with a declaration file,
write generic helpers, author a `flake.tnix`, and finally turn the directory into
a tnix project that `tnix check-project` verifies on every pull request.

## Steps

<div class="tx-steps">

1. [Install](./install.md): get the `tnix` CLI and language server.
2. [Your first .tnix file](./first-file.md): check it, compile it, read an error.
3. [Annotations and inference](./annotations.md): signatures, literal types, functions and polymorphism.
4. [Attribute sets and structural typing](./attrsets.md): records, width subtyping, unions and dynamic keys.
5. [Gradual typing](./gradual.md): `dynamic`, `unknown`, `any`, `as` casts and directives.
6. [Typing existing .nix](./declarations.md): `.d.tnix` files, `declare` blocks and `tnix emit`.
7. [Generics and higher-kinded types](./generics.md): `forall`, generic aliases and kinds.
8. [Conditional types and infer](./conditional-types.md): type-level pattern matching.
9. [Typing a flake and a package.nix](./flakes-and-packages.md): real-world Nix shapes.
10. [Editor setup](./editor.md): `tnix ide install`, `tnix doctor` and the language server.
11. [Projects](./projects.md): `tnix init`, `tnix.config.tnix`, `check-project` and `build`.
12. [CI integration](./ci.md): gate pull requests on the checker.

</div>

## Conventions

- Code blocks titled with a file name, such as `hello.tnix`, are files you
  create. Blocks without a title are terminal sessions or fragments.
- The output shown under `tnix check` is copied from the real CLI. Bindings are
  listed alphabetically after the `root:` line, and diagnostics start with the
  `line:column` of the offending expression.
- Everything is ordinary Nix syntax plus type annotations. Default arguments,
  `@` binders, `inherit (x)`, nested attribute paths, `<nixpkgs>`, every
  operator and the global builtins such as `toString` all work, so examples are
  written the way you would write Nix.

> [!TIP]
> Already know the basics and want the rules instead of a walkthrough? Jump to
> the [language reference](../language-reference.md) or to
> [how checking works](../reference/type-system-internals.md).

<div class="tx-pager">

[Start: 1. Install →](./install.md)

</div>
