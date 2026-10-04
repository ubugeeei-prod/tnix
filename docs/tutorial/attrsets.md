---
title: "4. Attribute sets and structural typing"
description: Type Nix attribute sets as structural records, with width subtyping, field errors, updates, unions and dynamic keys.
---

# 4. Attribute sets and structural typing

Attribute sets are the backbone of Nix, and tnix types them **structurally**: a
record type lists the fields it needs, and any attribute set that has at least
those fields, with compatible types, fits. There are no class names and no
nominal declarations to line up.

## Record types and type aliases

```tnix [describe.tnix]
type Package = { pname :: String; version :: String; };

let
  describe = (pkg :: Package): "${pkg.pname}-${pkg.version}";

  hello = {
    pname = "hello";
    version = "2.12.1";
    meta = { license = "GPL-3.0-or-later"; };
  };

  patched = hello // { version = "2.12.2"; };
in {
  name = describe hello;
  patchedName = describe patched;
  hasMeta = hello ? meta;
  license = hello.meta.license;
}
```

```bash
tnix check describe.tnix
```

```text
root: {
  hasMeta :: Bool;
  license :: "GPL-3.0-or-later";
  name :: String;
  patchedName :: String;
}
describe :: Package -> String
hello :: {
  meta :: {
    license :: "GPL-3.0-or-later";
  };
  pname :: "hello";
  version :: "2.12.1";
}
patched :: {
  meta :: {
    license :: "GPL-3.0-or-later";
  };
  pname :: "hello";
  version :: "2.12.2";
}
```

A few things happened here:

- `type Package = { ... };` declares a **type alias**. Aliases are top-level
  declarations and must come before the file's expression.
- `hello` has an extra `meta` field, yet `describe hello` is accepted. This is
  **width subtyping**: a record with more fields is a subtype of a record with
  fewer.
- `hello // { version = "2.12.2"; }` is typed field by field. The right-hand side
  wins, exactly like Nix's `//`.
- `hello ? meta` has type `Bool`, and `hello.meta.license` keeps its literal
  type.

## Missing fields

Leave out a required field and the call is rejected:

```tnix [package-missing.tnix]
type Package = { pname :: String; version :: String; };

let
  describe = (pkg :: Package): "${pkg.pname}-${pkg.version}";
in describe { pname = "hello"; }
```

```text
[TC0013] type mismatch: {
  pname :: "hello";
} vs {
  pname :: String;
  version :: String;
}
```

Selecting a field that is not there is its own diagnostic:

```tnix [typo.tnix]
let
  hello = { pname = "hello"; version = "2.12.1"; };
in hello.license
```

```text
[TC0009] missing field `license` on {
  pname :: "hello";
  version :: "2.12.1";
}
```

## Annotate parameters you select from

Notice that `describe` annotates its parameter, `(pkg :: Package):`. The checker
infers a function body before it compares the function against its signature,
so inside an unannotated `pkg: ...` the parameter's type is still an unknown
inference variable and `pkg.pname` has nothing to look up:

```text
[TC0009] missing field `pname` on ?0
```

Whenever a function selects fields from a parameter, annotate that parameter.
A `let` signature on the function alone is not enough today.

## Attribute-set patterns

Nix's destructuring lambdas work, and the checker infers a record type for the
argument:

```tnix [pattern.tnix]
let
  mk = { pname, version, ... }: "${pname}-${version}";
in mk { pname = "hello"; version = "2.12.1"; extra = true; }
```

```text
root: String
mk :: forall t0 t1. {
  pname :: t0;
  version :: t1;
} -> String
```

The pattern's fields are not annotated, so each gets a type variable. Interpolating
them is fine; selecting fields *from* them is not, for the reason above. Step 9
shows how to give pattern-bound names a type with `as`.

> [!NOTE]
> **Upcoming syntax.** Default values and an `@` binder, as in
> `{ pname, version ? "0.1.0", ... }@args:`, are being added to the parser.
> Today a pattern lists bare names and an optional `...`.

## `rec`, `inherit` and `with`

```tnix [rec.tnix]
let
  base = { a = 1; };
in rec {
  inherit base;
  greeting = "hi";
  loud = "${greeting}!";
  fromWith = with base; a + 1;
}
```

```text
root: {
  base :: {
    a :: 1;
  };
  fromWith :: Int;
  greeting :: "hi";
  loud :: String;
}
base :: {
  a :: 1;
}
```

Inside `rec { ... }` the fields can see each other. `with base;` brings the
fields of a *known* record into scope. If the scope's type is not a known record
(for example an untyped import), names in the body that tnix cannot resolve are
treated as `dynamic` instead of being reported as unbound.

> [!NOTE]
> **Upcoming syntax.** `inherit (base) a;` and nested attribute paths such as
> `meta.license = "MIT";` are being added. Today, write
> `a = base.a;` and `meta = { license = "MIT"; };`.

## Unions of records

A union type `A | B` accepts values of either shape. Selecting a field from a
union works only when **every** member has that field, and the result joins the
members' field types:

```tnix [source.tnix]
type Source =
  { kind :: "git"; url :: String; rev :: String; }
  | { kind :: "path"; url :: String; };

let
  src :: Source;
  src = { kind = "path"; url = "./vendor"; };
in { u = src.url; k = src.kind; }
```

```text
root: {
  k :: "git" | "path";
  u :: String;
}
src :: Source
```

`src.rev` would be rejected with `` [TC0009] missing field `rev` on Source ``
because the `path` variant has no `rev`. The checker does not narrow unions by
inspecting `kind` in an `if`. When you have established the variant yourself,
say so with a cast (step 5).

## Dynamic keys

`attrs.${key}` is checked when the key's type is a string literal or a union of
string literals:

```tnix [shells.tnix]
let
  shells = {
    x86_64-linux = "bash";
    aarch64-darwin = "zsh";
  };

  system :: "x86_64-linux" | "aarch64-darwin";
  system = "aarch64-darwin";
in shells.${system}
```

```text
root: "bash" | "zsh"
shells :: {
  aarch64-darwin :: "zsh";
  x86_64-linux :: "bash";
}
system :: "x86_64-linux" | "aarch64-darwin"
```

Remove `aarch64-darwin` from `shells` and you get
`[TC0010] missing field selected by dynamic key of type "x86_64-linux" | "aarch64-darwin"`.
A key of plain type `String` is allowed too, but then the result is `dynamic`,
since the checker cannot know which field you meant.

## Recap

- Record types are structural; extra fields are fine (width subtyping).
- `//`, `?`, `rec`, `inherit` and `with` are all typed.
- Annotate a parameter before selecting fields from it.
- Unions of records allow only the fields every member shares.
- Literal-typed keys make `attrs.${key}` checkable.

<div class="tx-pager">

[← 3. Annotations and inference](./annotations.md) [5. Gradual typing →](./gradual.md)

</div>
