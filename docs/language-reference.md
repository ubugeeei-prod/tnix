# Language Reference

## Overview

`tnix` keeps Nix value syntax and adds type-only syntax for checking and
tooling.

The runtime model is simple:

- parse `.tnix`
- type-check it
- erase type syntax
- emit ordinary `.nix`

## Files

- `.tnix`: implementation files with value-level Nix syntax plus types
- `.d.tnix`: declaration-only files that describe existing `.nix` surfaces
- `.nix`: erased runtime output

## Nix Compatibility

The expression grammar covers the whole Nix language. Every construct the
reference implementation accepts also parses as `.tnix`, and erasing a file
without type syntax gives back the same program: over a sample of 4000 nixpkgs
files, the compiled output parses to an AST identical to the source's under
`nix-instantiate --parse` (up to how equal strings are split into segments).

Only Nix keywords are reserved in expressions: `if`, `then`, `else`, `let`,
`in`, `rec`, `with`, `assert`, `inherit`, `or`, plus `true`, `false` and `null`.
tnix's own keywords are reserved only inside types, so `type`, `any`,
`import`, `declare`, `forall` and friends are ordinary names in expressions.
`as` is contextual: it is an ordinary binder and variable (`as: as.x` works),
and `e as T` is a cast only where a type can follow.

Unquoted URIs (`https://example.org/x.tar.gz`), which Nix itself deprecates,
are accepted in argument position. Quote them anywhere else, since a bare
`name:` at the start of an expression is read as a lambda.

## Expressions

### Literals

```tnix
{
  string = "hello";
  indented = ''
    echo "$out"
  '';
  int = 1;
  float = 1.5;
  negative = -3;
  bool = true;
  nothing = null;
  relative = ../path.nix;
  home = ~/.config;
  searchPath = <nixpkgs>;
  interpolated = ./${"default"}.nix;
}
```

Strings support `${...}` interpolation and Nix's escapes, including `$$` and
`''$` for a literal dollar sign. Paths may be interpolated too.

### Variables and builtins

```tnix
let
  value = 1;
in {
  inherit value;
  text = toString value;
  count = builtins.length [ 1 2 ];
}
```

`builtins` and the globals Nix exposes without the prefix (`toString`, `map`,
`throw`, `abort`, `import`, `derivation`, `baseNameOf`, `dirOf`,
`fetchTarball`, `isNull`, `removeAttrs`, `placeholder`, ...) are in scope and
typed by the built-in prelude. See [builtins and the registry](./reference/builtins.md).

### Lambdas

```tnix
{
  plain = x: x;
  annotated = (x :: Int): x;
  pattern = { a, b ? 2, ... }: a + b;
  named = { a, ... }@args: args;
  namedFirst = args@{ a, ... }: a;
  typedFields = { name :: String, version ? "1" }: "${name}-${version}";
}
```

Attribute-set patterns accept defaults (`b ? 2`), `...`, and an `@` binder on
either side. A pattern field may carry an annotation (`name :: String`), which
is erased like every other type. A field with a default makes that argument
optional: the pattern above has type `{ a :: Int; b? :: Int; ... } -> Int`.

### Application

```tnix
let
  f = x: x + 1;
  xs = [ { name = "a"; } ];
in {
  one = f 1;
  names = map (x: x.name) xs;
}
```

### `let`

```tnix
let
  value :: Int;
  value = 1;

  meta.license = "MIT";
  meta.homepage = "https://example.org";

  source = { pname = "hello"; version = "1"; };
  inherit (source) pname version;
in "${pname}-${version}-${meta.license}"
```

A `let` item is a signature (`name :: Type;`), a binding, a nested binding
path (`meta.license = ...;`), or `inherit` / `inherit (source)`. Dynamic
attribute names are not allowed in `let`, as in Nix (`TC0022`).

`let` items are also where the diagnostic directives are most useful:

```tnix
let
  # @tnix-expected
  value :: Int;
  value = "oops";
in value
```

### Attribute Sets

```tnix
let
  name = "tnix";
  key = "computed";
  src = { url = "https://example.org"; rev = "abc"; };
in {
  inherit name;
  inherit (src) url rev;
  version = "0.1.0";
  nested.enabled = true;
  nested.level = 2;
  "quoted-name" = 1;
  ${key} = "value";
}
```

Nested paths are merged into one record, exactly as Nix does. A computed key
(`${key} = ...;`) makes the result an open record (`{ name :: ...; ... }`), or an
`AttrsOf T` dictionary when every key is computed. `rec { ... }` lets fields
refer to each other.

### Selection, defaults and presence tests

```tnix
let
  cfg = { server = { port = 80; }; };
  key = "server";
in {
  port = cfg.server.port;
  dynamic = cfg.${key}.port;
  host = cfg.server.host or "localhost";
  hasTls = cfg ? server.tls;
  hasKey = cfg ? ${key};
}
```

`x.a.b or default` never requires `a` or `b` to exist, and `?` always yields
`Bool`.

### Lists

```tnix
[ 1 2 3 ]
```

Nested lists infer shapes such as `Matrix 2 2 Int`; see
[list shape inference](#list-shape-inference).

### Operators

```tnix
let
  n = 7;
in {
  arithmetic = n + 1 - 2 * 3 / 4;
  negated = -n;
  text = "a" + "b";
  path = ./dir + "/file.nix";
  lists = [ 1 ] ++ [ 2 ];
  merged = { a = 1; } // { b = 2; };
  logic = !(n > 1) || (n <= 9 && n != 3);
  implication = true -> false;
  piped = [ 1 2 3 ] |> builtins.length;
  pipedLeft = builtins.length <| [ 1 2 ];
}
```

`+` adds numbers and concatenates strings and paths (a path plus a string is a
`Path`). Precedence and associativity follow Nix; see the
[grammar](./grammar.md#operator-precedence-and-associativity).

### Conditionals, `with` and `assert`

```tnix
let
  cond = true;
  lib = { version = "1"; };
in
assert cond;
with lib;
if cond then version else "none"
```

### Import

```tnix
declare "./lib.nix" { default :: { value :: Int; }; };

{
  lib = import ./lib.nix;
  value = (import ./lib.nix).value;
  untyped = import ./other.nix;
}
```

`import` of a path with a declaration has the declared type; anything else is
`dynamic`.

## Type Annotations

Signatures go next to `let` bindings, annotations on lambda binders and pattern
fields:

```tnix
let
  name :: String;
  name = "x";

  f :: Int -> Int;
  f = x: x + 1;

  g = (x :: String): x;
  h = { port :: Int, host ? "localhost" }: "${host}:${toString port}";
in { inherit name f g h; }
```

A `forall` signature is **rigid**: the body must work for every instantiation
of its type variables, so `id :: forall a. a -> a; id = x: 1;` is rejected
with `type mismatch: 1 vs a`.

A type may carry a Haskell-style constraint context such as `Functor f =>` or
`(Eq a, Show a) =>`, at the start of the type or right after its `forall`
(`forall f a b. Functor f => (a -> b) -> f a -> f b`). Contexts are parsed for
documentation but not enforced, because tnix has no type classes yet.

## Casts

```tnix
let
  value :: unknown;
  value = 1;
in value as Int
```

`as` is a value-level cast. It changes the static type of the expression when
the source and target overlap in one of the ways `tnix` allows:

- normal widening (`1 as Number`)
- structural narrowing (`value as { name :: String; }`)
- explicit gradual assertions across `any`, `unknown`, or `dynamic`

Concrete unrelated casts such as `1 as String` are rejected (`TC0015`).

## Diagnostic Directives

`tnix` recognizes two line-comment directives modeled after TypeScript.

### `# @tnix-ignore`

Suppress the next root-expression or `let`-item checker failure.

```tnix
let
  # @tnix-ignore
  value = missing;
in value
```

### `# @tnix-expected`

Suppress the next failure, but raise an error if that line does not fail.

```tnix
# @tnix-expected
missing
```

This is useful for regression tests and documentation examples where a failure
is the expected outcome.

## Type Forms

The snippets in this section are types; write them after `::`, in `type`
aliases, or in `declare` blocks.

### Primitive Constructors

```tnix
String
Int
Float
Number
Nat
Bool
Path
Null
any
dynamic
unknown
```

### Literal Singleton Types

```tnix
"tnix"
1
1.5
true
false
```

### Function Types

```tnix
Int -> Int
String -> { name :: String; }
Int %1 -> Int
```

`%1 ->` is the linear arrow, inferred for lambdas that use their argument
exactly once. It may be used wherever `->` is expected.

### Record Types

```tnix
{ name :: String; version :: String; }
{ name :: String; version? :: String; }
{ name :: String; ... }
{ name :: String; ...rest }
```

- A closed record lists its fields; values may still have more fields (width
  subtyping).
- `name? :: T` is an **optional field**: it may be absent, and when present it
  has type `T`.
- `...` makes the record **open**: "these fields, plus possibly others". A named
  tail such as `...rest` is a row variable, so a signature can say that a
  function returns the same other fields it received:
  `forall r. { ...r } -> { tag :: String; ...r }`.

### Dictionaries

```tnix
AttrsOf Int
AttrsOf (List String)
```

`AttrsOf T` is an attribute set with arbitrary names whose values all have type
`T`. A record is a subtype of `AttrsOf T` when every field fits `T`, so
`{ a = 1; b = 2; }` can be passed to `builtins.mapAttrs` or
`builtins.attrValues`.

### Union Types

```tnix
String | Int
{ ok :: true; value :: a; } | { ok :: false; error :: e; }
```

### Parametric Polymorphism

```tnix
forall a. a -> a
forall f a. f a -> f a
forall f a b. Functor f => (a -> b) -> f a -> f b
```

### Type Aliases

```tnix
type Box a = { value :: a; };
type Pair = Tuple [Int String];
```

### Higher-Kinded Application

```tnix
type Apply f a = f a;
type Id f = f;
type ListOfInt = Apply (Id List) Int;
```

### Conditional Types

```tnix
type Element t = t extends List (infer a) ? a : t;
type ReturnOf f = f extends (infer a -> infer r) ? r : dynamic;
```

### Tuple Types

`Tuple` is the heterogeneous fixed-length sequence form.

```tnix
Tuple [Int String]
Tuple [1 "x" true]
```

### Indexed Containers

```tnix
Vec 3 Int
Matrix 2 4 Float
Tensor [2 3 4] Number
Vec (2 | 3 | Range 4 8 Nat) Int
Tensor [2 (Range 1 2 Nat) 1] Int
```

### Numeric Validators

```tnix
Nat
Range 0 10 Int
Range 0 5000 Nat
Range 0.0 1.0 Float
```

A numeric literal is a subtype of a validator when it satisfies it: `3` fits
`Range 0 10 Nat`, `0.5` fits `Range 0.0 1.0 Float`, and `11` does not fit
`Range 0 10 Nat`.

### Units

```tnix
Unit "ms" Nat
Unit "ms" (Range 0 5000 Nat)
Unit "MiB" Int
```

A bare literal may enter a unit (`1` fits `Unit "ms" Nat`), but different
labels never mix: `Unit "ms" Nat` is not a subtype of `Unit "s" Nat`.

## Declarations

Ambient declarations attach types to existing runtime files.

```tnix
declare "./legacy/default.nix" {
  value :: Int;
  mkPkg :: { name :: String; } -> Derivation;
};
```

A block whose only member is `default` declares the module's whole value; any
other block declares an attribute set of its members. The target `"builtins"`
replaces the built-in prelude for the whole workspace.

### Bundled Registry Packs

The repository also ships curated `.d.tnix` packs under `registry/`. These
packs are split into two groups:

- `registry/workspace/` for root-adjacent files such as `builtins`,
  `flake.nix`, and `tnix.config.tnix`
- `registry/ecosystem/` for alias-oriented ecosystem packs reused from local
  `declare` blocks

Current packs include:

- `NixpkgsLib`, `NixpkgsPkgs`, and related aliases for `nixpkgs`
- `NixFlakeUtilsFlake`, `HomeManagerFlake`, `NixDarwinFlake`, `FlakePartsLib`
- `DevenvFlake`, `TreefmtNixFlake`, `PreCommitHooksFlake`, `CraneFlake`
- `DeployRsFlake`, `NixvimFlake`, `SopsNixFlake`, `AgenixFlake`, `DiskoFlake`, `ColmenaFlake`

Example:

```tnix
declare "./nixpkgs.nix" { default :: NixpkgsImport; };
declare "./home-manager.nix" { default :: HomeManagerFlake; };
declare "./treefmt-nix.nix" { default :: TreefmtNixFlake; };
```

You can also register external pack paths from `tnix.config.tnix`:

```tnix
{
  declarationPacks = [
    ../vendor/tnix/registry/ecosystem
    ../vendor/tnix/registry/workspace
  ];
}
```

Configured `registry/workspace/` packs are resolved against the current project
root, so upstream workspace declarations still describe your local
`tnix.config.tnix` and `flake.nix`.

The checker resolves those aliases exactly like aliases written in your own
`.d.tnix` files.

## Inference Notes

### Let-polymorphism

Unannotated `let` bindings get principal polymorphic types. Bindings are
grouped by their dependencies, each group of mutually recursive bindings is
inferred together, and the group is generalized before later groups use it:

```tnix
let
  id = x: x;
  compose = f: g: x: f (g x);
in {
  n = id 1;
  s = id "one";
  inc = compose (x: x + 1) (x: x * 2);
}
```

Here `compose` is inferred as
`forall t0 t1 t2. (t1 -> t2) %1 -> (t0 -> t1) %1 -> t0 %1 -> t2`.

### Records and rows

Selecting from a value whose type is not known yet infers an open record:
`x: x.a + x.b` has type `{ a :: Number; b :: Number; ... } -> Number`, and
`x: x // { y = 1; }` has type `forall t0. { ...t0 } %1 -> { y :: 1; ...t0 }`.
Pattern fields with defaults become optional fields. `x.a or d` never makes
`a` required.

Width subtyping still applies to closed records: a value with more fields fits
a record type with fewer.

```tnix
let
  pkg :: { name :: String; };
  pkg = { name = "a"; version = "1"; };
in pkg
```

### Gradual Compatibility

The three gradual escape hatches have different roles:

- `any` is assignable to and from every type.
- `unknown` is a top type. Every value can be viewed as `unknown`, but `unknown` does not flow back into concrete types without an annotation or narrowing.
- `dynamic` keeps the existing tnix gradual-consistency behavior. It is consistent with every type, but not a concrete subtype of every type.

Unannotated code is accepted gradually where strict inference would produce
false errors:

- Dependencies injected through an attribute-set pattern
  (`{ lib, fetchFromGitHub, ... }:`) and fields selected from values of unknown
  shape are *soft*: calling one gives `dynamic -> dynamic` instead of fixing
  its type from the first call site. Plain lambda binders keep full
  Hindley-Milner principal types.
- Literals are widened where precision would only cause errors: in pattern
  defaults (`b ? 2` accepts any `Int`), in arguments to callees whose type is
  unknown, and in `if` branches whose other side is still unknown.

### List Shape Inference

```tnix
{
  empty = [];
  pair = [1 2];
  mixed = [1 "x"];
  grid = [[1 2] [3 4]];
  ragged = [[1] [2 3]];
}
```

```text
root: {
  empty :: Vec 0 dynamic;
  grid :: Matrix 2 2 (1 | 2 | 3 | 4);
  mixed :: Tuple [ 1 "x" ];
  pair :: Vec 2 (1 | 2);
  ragged :: List (Vec (1 | 2) (1 | 2 | 3));
}
```

## Erasure

The following syntax is erased during `.tnix -> .nix` compilation:

- `::` annotations on `let` bindings, lambda binders and pattern fields
- `as` casts
- `type` aliases
- `declare` blocks

Everything else is value-level Nix and is kept, with the same structure and
names.

## Common Patterns

### Typing A Legacy Import

```tnix
declare "./lib.nix" {
  default :: { value :: Int; };
};

(import ./lib.nix).value
```

### Narrowing A Gradual Boundary

```tnix
let
  payload = import ./opaque.nix;
in payload as { value :: String; }
```

### A Typed `callPackage` Function

```tnix
{ name :: String, version ? "1.0", doCheck ? true }:
{
  pname = name;
  inherit version doCheck;
}
```

### Bounded Sequence Contracts

```tnix
let
  xs :: Vec (Range 2 4 Nat) Int;
  xs = [1 2 3];
in xs
```

### Unit-Safe Numeric Contracts

```tnix
let
  timeout :: Unit "ms" (Range 0 5000 Nat);
  timeout = 2500;
in timeout
```

## Related Docs

- [Getting Started](./getting-started.md)
- [Grammar](./grammar.md)
- [Type System](./type-system.md)
- [How Checking Works](./reference/type-system-internals.md)
- [Language Design](./language-design.md)
