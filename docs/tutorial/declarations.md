---
title: "6. Typing existing .nix"
description: Describe untyped .nix modules with .d.tnix declaration files and declare blocks, type builtins, and generate declarations with tnix emit.
---

# 6. Typing existing .nix

You will not rewrite a whole Nix codebase in `.tnix`, and you do not need to.
**Declarations** describe the type of a `.nix` file without touching it, the way
`.d.ts` files describe JavaScript libraries. Typed code that imports the file
then sees real types instead of `dynamic`.

## A module to describe

Create an ordinary Nix file. tnix will never compile or modify it:

```nix [lib/strings.nix]
{
  shout = s: "${s}!";
  join = sep: xs: builtins.concatStringsSep sep xs;
  version = "1.4.0";
}
```

## Write a `.d.tnix` file

Next to it, create a declaration file:

```tnix [lib/strings.d.tnix]
declare "./strings.nix" {
  shout :: String -> String;
  join :: String -> List String -> String;
  version :: String;
};
```

A `declare` block names a target path, resolved relative to the file that
contains the block, and lists the module's members. A declaration file may
contain `type` aliases and `declare` blocks but no expression.

Now import the module from typed code:

```tnix [main.tnix]
let
  strings = import ./lib/strings.nix;
in {
  loud = strings.shout "hello";
  csv = strings.join "," [ "a" "b" ];
  version = strings.version;
}
```

```bash
tnix check main.tnix
```

```text
root: {
  csv :: String;
  loud :: String;
  version :: String;
}
strings :: {
  join :: String -> List String -> String;
  shout :: String -> String;
  version :: String;
}
```

`strings` is no longer `dynamic`, so mistakes surface: `strings.shout 42`
reports `[TC0013] type mismatch: 42 vs String`.

> [!NOTE]
> **Upcoming syntax.** `inherit (strings) version;` is being added. Until then
> write `version = strings.version;`.

### How declaration files are found

You did not tell `main.tnix` where `strings.d.tnix` lives. tnix finds the
**workspace root** (the nearest ancestor directory with `.git`, `flake.nix`,
`tnix.config.tnix`, `cabal.project` or `pnpm-workspace.yaml`; this is why you ran
`git init` in step 1) and loads **every** `.d.tnix` file under it. Each
`declare` block is keyed by the absolute path of its target, and `import` looks
that path up. Where the `.d.tnix` file lives is therefore up to you: next to the
module, or in a `types/` directory.

Two consequences:

- Each target may be declared only once in a workspace. A second `declare` for
  the same file is `[TD0002] duplicate ambient declarations`, and it fails
  every check in the workspace until you remove one.
- A nested directory that has its own workspace marker (say, a vendored repo
  with its own `.git`) is skipped.

## Default exports

If a module evaluates to something other than an attribute set, such as a
function or a string, declare a single member called `default`:

```tnix [greeting.tnix]
declare "./mk-greeting.nix" {
  default :: String -> String;
};

(import ./mk-greeting.nix) "tnix"
```

```text
root: String
```

This example also shows that a `declare` block can sit at the top of a regular
`.tnix` file, before its expression. Inline declarations are handy for one-off
imports; shared ones belong in a `.d.tnix` file.

## Typing `builtins`

`builtins` is `dynamic` until you declare it. A declaration target of
`"builtins"` (a string, not a path) describes it:

```tnix [types/builtins.d.tnix]
declare "builtins" {
  head :: forall a. List a -> a;
  length :: forall a. List a -> Int;
  map :: forall a b. (a -> b) -> List a -> List b;
  toString :: dynamic -> String;
};
```

```tnix [lists.tnix]
let
  n = builtins.length [ 1 2 3 ];
  inc = (x :: Int): x + 1;
  xs = builtins.map inc [ 1 2 ];
in { inherit n xs; }
```

```text
root: {
  n :: Int;
  xs :: List Int;
}
inc :: Int %1 -> Int
n :: Int
xs :: List Int
```

Once `builtins` is declared, it is a closed record: using a builtin that your
declaration does not list, such as `builtins.readFile`, is
`` [TC0009] missing field `readFile` ``. You do not have to write the full list
yourself. The repository ships a complete declaration of the Nix builtins in
[`registry/workspace/builtins.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/builtins.d.tnix),
and `tnix init` (step 11) scaffolds a starter file. See
[builtins and the registry](../reference/builtins.md).

> [!NOTE]
> **Upcoming.** Global builtins such as `toString`, `map`, `throw` and
> `derivation`, which Nix exposes without the `builtins.` prefix, are being
> added to the checker's environment. Today, spell them `builtins.toString` and
> so on.

## Generate declarations with `tnix emit`

For files you *do* write in tnix, there is no need to hand-write declarations.
`tnix emit` derives one from the checked source:

```tnix [greetings.tnix]
type Greeting = { text :: String; loud :: Bool; };

{
  mk = (text :: String): { inherit text; loud = false; };
  default = { text = "hi"; loud = true; };
}
```

```bash
tnix emit greetings.tnix -o greetings.d.tnix
```

```tnix [greetings.d.tnix]
type Greeting  = {
  loud :: Bool;
  text :: String;
};
declare "./greetings.nix" {
  default :: {
    loud :: true;
    text :: "hi";
  };
  mk :: String %1 -> {
    loud :: false;
    text :: String;
  };
};
```

When the root expression is an attribute set, each field becomes a member;
otherwise the whole value becomes `default`. The file's type aliases are copied
along so the declaration stays readable. The target is the compiled `.nix`
path, which is what other modules will import at runtime.

> [!TIP]
> Emitted declarations record what was *inferred*, literal types included. If
> you want a stable, wider public API, add signatures (or `as` casts) to the
> exported fields before emitting.

## Recap

- `declare "./file.nix" { member :: Type; };` describes an existing module.
- All `.d.tnix` files under the workspace root are loaded automatically.
- Use `default` for modules that are not attribute sets.
- `declare "builtins" { ... }` types the builtins.
- `tnix emit` writes declarations for your own `.tnix` files.

<div class="tx-pager">

[← 5. Gradual typing](./gradual.md) [7. Generics and HKT →](./generics.md)

</div>
