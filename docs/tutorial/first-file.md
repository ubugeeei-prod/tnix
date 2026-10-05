---
title: "2. Your first .tnix file"
description: Write a .tnix file, type-check it, compile it to .nix, and read your first diagnostic.
---

# 2. Your first .tnix file

A `.tnix` file is a Nix expression that may also contain type syntax. In this
step you write one, check it, and compile it.

## Write it

Inside the `tnix-tour` directory, create `hello.tnix`:

```tnix [hello.tnix]
let
  greeting :: String;
  greeting = "Hello, tnix!";
in greeting
```

The only new line compared with Nix is `greeting :: String;`. It is a **type
signature**: it promises that the binding with the same name has type `String`.
Signatures sit next to their binding inside `let`, in the same way Haskell
writes them.

## Check it

```bash
tnix check hello.tnix
```

```text
root: String
greeting :: String
```

`tnix check` prints the type of the file's root expression and of every
`let`-bound name. Nothing was written to disk; `check` only analyzes.

## Compile it

```bash
tnix compile hello.tnix -o hello.nix
cat hello.nix
```

```nix [hello.nix]
let
  greeting = "Hello, tnix!";
in greeting
```

The signature is gone. This is **erasure**: tnix removes every piece of type
syntax and emits ordinary Nix that keeps your layout and names. Nix never sees a
type, so there is nothing to evaluate at runtime and nothing to slow it down.

```bash
nix eval --file hello.nix
```

```text
"Hello, tnix!"
```

Without `-o`, `tnix compile` prints the generated Nix to standard output.

> [!NOTE]
> `tnix compile` type-checks first and refuses to write output for a file that
> does not check. You never ship `.nix` generated from an ill-typed `.tnix`.

## Break it

Change the value so it no longer matches the signature:

```tnix [hello.tnix]
let
  greeting :: String;
  greeting = 42;
in greeting
```

```bash
tnix check hello.tnix
```

```text
3:14: [TC0013] type mismatch: 42 vs String
```

The command exits with status `1`. A diagnostic starts with the line and column
of the offending expression (`3:14` is the `42`), followed by a stable code in
brackets. The first letters of the code tell you which phase found the problem:

| Prefix | Phase |
| --- | --- |
| `TP` | parser |
| `TK` | kind checker (types applied to the wrong number of arguments) |
| `TC` | type checker |
| `TD` | driver: files, declarations and project config |

Look any code up in the [diagnostics reference](../diagnostics.md). Notice also
that the checker reports `42`, not `Int`: integer and string literals keep their
exact *literal type* until something forces them to widen. You will use that in
the next step.

A syntax error comes from the parser, which also prints an excerpt of the line
and what it expected to find:

```tnix [broken.tnix]
let
  greeting :: String
  greeting = "Hello";
in greeting
```

```text
3:12: [TP0004] broken.tnix:3:12:
  |
3 |   greeting = "Hello";
  |            ^
unexpected '='
expecting "%1", "->", "Tuple", "any", "dynamic", "extends", "false", "infer", "true", "unknown", '"', '(', '-', ';', '[', '{', '|', digit, or integer
```

The signature on line 2 is missing its `;`, so the parser kept reading a type
and tripped over the `=` on line 3.

Put `"Hello, tnix!"` back before moving on.

## Emit a declaration

One more command completes the loop. `tnix emit` writes the *public type
surface* of a file as a declaration (`.d.tnix`) file:

```bash
tnix emit hello.tnix
```

```tnix
declare "./hello.nix" {
  default :: String;
};
```

This says "the module at `./hello.nix` evaluates to a `String`". Other typed
files that `import ./hello.nix` will see that type. Step 6 covers declarations
in depth.

## Recap

- `.tnix` = Nix + type syntax. Signatures look like `name :: Type;`.
- `tnix check` analyzes, `tnix compile` erases types and emits `.nix`, and
  `tnix emit` writes a `.d.tnix` declaration.
- Diagnostics carry a `line:column` position and a stable code such as
  `TC0013`.

<div class="tx-pager">

[← 1. Install](./install.md) [3. Annotations and inference →](./annotations.md)

</div>
