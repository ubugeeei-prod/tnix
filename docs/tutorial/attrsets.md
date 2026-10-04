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

Leave out a required field and the call is rejected. The diagnostic points at
the argument and names the field that is missing:

```tnix [package-missing.tnix]
type Package = { pname :: String; version :: String; };

let
  describe = (pkg :: Package): "${pkg.pname}-${pkg.version}";
in describe { pname = "hello"; }
```

```text
5:13: [TC0009] missing field `version`: expected { pname :: String; version :: String; } but got { pname :: "hello"; }
```

Selecting a field that is not there is the same diagnostic, pointing at the
selection:

```tnix [typo.tnix]
let
  hello = { pname = "hello"; version = "2.12.1"; };
in hello.license
```

```text
3:4: [TC0009] missing field `license` on { pname :: "hello"; version :: "2.12.1"; }
```

## Inferred record parameters

You do not have to annotate a parameter before selecting from it. When a
function selects fields from a value whose type is not known yet, tnix infers an
**open record**: "at least these fields, plus possibly others". This is *row
polymorphism*:

```tnix [rows.tnix]
let
  describe = pkg: "${pkg.pname}-${pkg.version}";
  withSuffix = pkg: pkg // { suffix = "-dev"; };
in {
  name = describe { pname = "hello"; version = "2.12.1"; extra = true; };
  dev = withSuffix { pname = "hello"; };
}
```

```text
root: {
  dev :: {
    pname :: "hello";
    suffix :: "-dev";
  };
  name :: String;
}
describe :: forall t0 t1. {
  pname :: t0;
  version :: t1;
  ...
} -> String
withSuffix :: forall t0. {
  ...t0
} %1 -> {
  suffix :: "-dev";
  ...t0
}
```

- `{ pname :: t0; version :: t1; ... }` is an open record type. The `...` stands
  for the fields the function does not care about, so `describe` accepts the
  extra `extra = true` field.
- `...t0` names those remaining fields. `withSuffix` returns *the same* other
  fields it received, plus `suffix`: `//` is row-aware.
- You can write open records in annotations too: `{ pname :: String; ... }`.

A call that does not provide a selected field is still an error:
`describe { pname = "hello"; }` reports
`` 3:13: [TC0009] missing field `version` required by { pname :: ?6; version :: ?7; } ``,
where `?6` and `?7` are field types that were not solved yet.

`x.a or default` selects with a fallback. It never makes `a` a required
field, so it is the way to read an attribute that may be absent.

## Attribute-set patterns

Nix's destructuring lambdas work in full, including default values and the `@`
binder, and the checker infers a record type for the argument:

```tnix [pattern.tnix]
let
  mk = { pname, version ? "0.1.0", doCheck ? null, ... }@args:
    "${pname}-${version}";
in {
  a = mk { pname = "hello"; };
  b = mk { pname = "hello"; version = "2.12.1"; extra = true; };
}
```

```text
root: {
  a :: String;
  b :: String;
}
mk :: forall t0 t1. {
  doCheck? :: t1;
  pname :: t0;
  version? :: String;
  ...
} -> String
```

- A field with a default becomes an **optional field**, written `name? :: T`.
  Callers may leave it out. The type comes from the default, widened to its
  base type: `version ? "0.1.0"` accepts any `String`, not just `"0.1.0"`.
- `doCheck ? null` is Nix's idiom for "optional, no default", so the default
  says nothing about the type of a value a caller passes.
- `...` makes the argument record open, and `@args` binds the whole argument.
  `args@{ ... }:` works too.
- Leaving out a field that has no default is an error:
  `mk { version = "1.0"; }` reports
  `` 3:7: [TC0009] missing field `pname` required by { pname :: ?4; version? :: String; } ``.

Pattern fields can carry an annotation, which is erased like every other type:
`{ pname :: String, version ? "0.1.0" }:`. Step 9 uses this to type a
`callPackage`-style package.

## `rec`, `inherit` and `with`

```tnix [rec.tnix]
let
  base = { a = 1; b = "two"; };
in rec {
  inherit (base) a b;
  greeting = "hi";
  loud = "${greeting}!";
  meta.license = "MIT";
  meta.homepage = "https://example.org";
  fromWith = with base; a + 1;
}
```

```text
root: {
  a :: 1;
  b :: "two";
  fromWith :: Int;
  greeting :: "hi";
  loud :: String;
  meta :: {
    homepage :: "https://example.org";
    license :: "MIT";
  };
}
base :: {
  a :: 1;
  b :: "two";
}
```

Inside `rec { ... }` the fields can see each other. `inherit (base) a b;`
copies fields out of another attribute set, and nested attribute paths such as
`meta.license = "MIT";` are merged into one `meta` record, exactly as Nix does.
`with base;` brings the fields of a *known* record into scope. If the scope's
type is not a known record (for example an untyped import), names in the body
that tnix cannot resolve are treated as `dynamic` instead of being reported as
unbound.

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

Computed keys also work when *building* an attribute set. Because the names are
not known statically, a set built only from computed keys is a dictionary,
`AttrsOf T`:

```tnix [computed.tnix]
let
  forSystem = system: { ${system} = "bash"; };
  cfg = { port = 80; };
in {
  one = forSystem "x86_64-linux";
  port = cfg.port or 8080;
  host = cfg.host or "localhost";
}
```

```text
root: {
  host :: "localhost";
  one :: AttrsOf "bash";
  port :: 80 | 8080;
}
cfg :: {
  port :: 80;
}
forSystem :: String %1 -> AttrsOf "bash"
```

A record whose fields all fit `T` is a subtype of `AttrsOf T`, which is how
builtins such as `builtins.mapAttrs` and `builtins.attrValues` accept ordinary
records. A set mixing static and computed keys keeps its static fields and is
open for the rest: `{ a = 1; ${k} = 2; }` is `{ a :: 1; ... }`.

## Recap

- Record types are structural; extra fields are fine (width subtyping).
- Selecting from an unannotated parameter infers an open record
  (`{ a :: T; ... }`); `//` keeps the other fields.
- Pattern defaults produce optional fields (`name? :: T`).
- `//`, `?`, `or`, `rec`, `inherit (src)`, nested paths and `with` are all
  typed.
- Unions of records allow only the fields every member shares.
- Literal-typed keys make `attrs.${key}` checkable; computed keys build
  `AttrsOf T` dictionaries.

<div class="tx-pager">

[← 3. Annotations and inference](./annotations.md) [5. Gradual typing →](./gradual.md)

</div>
