---
layout: entry
hero:
  name: tnix
  text: Typed tooling for Nix
  tagline: Gradually add static checking, editor feedback, and declaration files to Nix projects without changing runtime semantics.
  image:
    src: /tnix-logo.svg
    alt: tnix logo
  actions:
    - theme: brand
      text: Get started
      link: /getting-started
    - theme: alt
      text: Language reference
      link: /language-reference
features:
  - icon: "mdi:code-braces"
    title: Nix-compatible surface
    details: Write ordinary Nix-shaped expressions and erase type annotations at compile time.
    link: /grammar
  - icon: "mdi:shield-check"
    title: Gradual static checks
    details: Use structural types, ambient declarations, and checker directives to adopt tnix incrementally.
    link: /type-system
  - icon: "mdi:tools"
    title: Tooling-first workflow
    details: CLI, LSP, editor extensions, diagnostics, and CI checks are documented together.
    link: /getting-started
---

# tnix documentation

`tnix` is a gradual type system and tooling stack for Nix. It compiles `.tnix`
to `.nix`, provides static checking, and emits `.d.tnix` declaration files.

## Read next

- [Getting Started](./getting-started.md)
- [Language Reference](./language-reference.md)
- [Type System](./type-system.md)
- [Diagnostics](./diagnostics.md)
- [CI/CD Hardening](./ci-cd.md)
