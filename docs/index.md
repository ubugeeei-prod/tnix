---
layout: entry
title: TypeScript-grade types for Nix
description: tnix adds a gradual, structural type system to Nix. Write .tnix, check it, and ship plain .nix with every type erased.
hero:
  name: tnix
  text: TypeScript-grade types for Nix. Zero runtime.
  tagline: Annotate the Nix you already write. tnix checks records, functions, generics and gradual boundaries, then erases every type and hands your toolchain plain .nix.
  image:
    src: /brand/tnix-mark.svg
    alt: The tnix mark, a blue hexagon with a lowercase t and a mint colon
  actions:
    - theme: brand
      text: Start the tutorial
      link: /tutorial
    - theme: alt
      text: Read the reference
      link: /language-reference
features:
  - icon: /brand/icons/erase.svg
    title: Zero runtime
    details: Types, aliases, declarations and casts are erased at build time. The output is ordinary Nix with the same layout and the same semantics.
    link: /reference/type-system-internals
  - icon: /brand/icons/records.svg
    title: Structural records
    details: Attribute sets are compared by shape, with width subtyping, literal types, unions and precise field errors.
    link: /tutorial/attrsets
  - icon: /brand/icons/gradual.svg
    title: Gradual by design
    details: dynamic, unknown and any give you three different escape hatches. Adopt one file at a time and tighten as you go.
    link: /tutorial/gradual
  - icon: /brand/icons/declare.svg
    title: Type existing .nix
    details: Describe modules you will not rewrite with .d.tnix declarations, the same way DefinitelyTyped describes JavaScript.
    link: /tutorial/declarations
  - icon: /brand/icons/generics.svg
    title: Generics, HKT and conditional types
    details: forall, higher-kinded aliases, extends / infer and Vec, Matrix and Tensor shapes, checked by a kind-aware engine.
    link: /tutorial/generics
  - icon: /brand/icons/editor.svg
    title: Editor and CI ready
    details: A language server with hover, inlay hints and diagnostics, plus stable diagnostic codes and JSON reports for CI.
    link: /tutorial/editor
---

<p class="tx-section-label">Install</p>

<div class="tx-install">
<div>

One-line installer (Linux x64 and macOS arm64)

```bash
curl -fsSL https://tnix.dev/install.sh | sh
```

</div>
<div>

From the flake, on any Nix-enabled host

```bash
nix profile install github:ubugeeei-prod/tnix
```

</div>
</div>

<p class="tx-section-label">Write .tnix, ship .nix</p>

<div class="tx-compare">
<div>
<p class="tx-file">greet.tnix: what you write</p>

```tnix
type User = { name :: String; admin :: Bool; };

let
  greet :: User -> String;
  greet = (user :: User):
    if user.admin
    then "Welcome back, ${user.name}."
    else "Hello, ${user.name}!";
in greet { name = "Ada"; admin = true; }
```

</div>
<div class="tx-arrow"><strong>→</strong>tnix compile</div>
<div>
<p class="tx-file">greet.nix: what Nix evaluates</p>

```nix
let
  greet = user: if user.admin
  then "Welcome back, ${user.name}."
  else "Hello, ${user.name}!";
in greet {
  name = "Ada";
  admin = true;
}
```

</div>
</div>

<p class="tx-caption">Everything in <span class="tx-amber">amber</span> is type-only syntax. tnix checks it, then removes it. Misspell <code>user.nmae</code> and you get <code>[TC0009] missing field `nmae`</code> before Nix ever evaluates the file.</p>

<p class="tx-section-label">Why tnix</p>

Nix is a lazy, dynamically typed language, so a typo in an attribute name only
surfaces when that branch is evaluated, sometimes deep inside a build. tnix
borrows the adoption model that made TypeScript work: the type layer is
optional, gradual and structural, and it never changes what runs.

- **Familiar surface.** `.tnix` is Nix plus annotations. `let`, attribute sets,
  lambdas, `with`, `rec`, `inherit`, interpolation and imports work as they do in
  Nix.
- **Precise where it helps.** Literal types, unions, `Range`, `Unit`, and
  `Vec` / `Matrix` / `Tensor` shapes record what the code actually proves.
- **Honest about the unknown.** Untyped imports are `dynamic`, not silently
  trusted. Narrow them with a declaration or an `as` cast when you are ready.

<div class="tx-cta">
<div>

## Ready in fifteen minutes

Install tnix, type your first file, and finish with a checked flake.

</div>

[Start the tutorial →](./tutorial/index.md)

</div>
