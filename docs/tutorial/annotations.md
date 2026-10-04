---
title: "3. Annotations and inference"
description: Learn where tnix needs annotations, what it infers on its own, and how literal types, numbers, functions and polymorphism behave.
---

# 3. Annotations and inference

tnix infers most types. Annotations are how you state intent, and the checker
holds the code to it. This step shows the three places annotations go and what
inference does everywhere else.

## Three places for types

```tnix [annotations.tnix]
let
  port :: Int;
  port = 8080;

  name = "web";

  double = (x :: Int): x * 2;

  label :: String -> Int -> String;
  label = prefix: n: "${prefix}-${builtins.toString n}";

  id :: forall a. a -> a;
  id = x: x;
in {
  inherit port name;
  doubled = double port;
  tag = label name port;
  same = id true;
}
```

```bash
tnix check annotations.tnix
```

```text
root: {
  doubled :: Int;
  name :: "web";
  port :: Int;
  same :: true;
  tag :: String;
}
double :: Int %1 -> Int
id :: forall a. a -> a
label :: String -> Int -> String
name :: "web"
port :: Int
```

1. **`let` signatures** (`port :: Int;`) are checking boundaries. The binding
   must satisfy the signature, and every later use sees the signature, not the
   inferred type.
2. **Lambda parameters** (`(x :: Int): ...`) annotate one binder. The
   parentheses are required.
3. **Casts** (`expr as Type`) assert a type at an expression. They are the
   subject of [step 5](./gradual.md).

`builtins` is untyped (`dynamic`) unless you declare it, so
`builtins.toString n` is accepted without complaint. Step 6 shows how to give
`builtins` real types.

## Literal types and widening

Look at `name :: "web"`. Without a signature, a string literal keeps its exact
**literal type** `"web"`, which is a subtype of `String`. The same goes for
integers (`8080`), floats (`1.5`) and booleans (`true`). Literal types let
unions of literals act as enumerations:

```tnix [levels.tnix]
let
  level :: "debug" | "info" | "warn";
  level = "debug";

  other :: "debug" | "info";
  other = "trace";
in level
```

```text
[TC0013] type mismatch: "trace" vs "debug" | "info"
```

A signature widens: `port :: Int` makes `port` an `Int` even though its value is
the literal `8080`. Use a signature whenever you want a binding's type to be the
general one.

## Numbers

Numbers form a small tower: `Nat <: Int <: Number` and `Float <: Number`.
Arithmetic picks the narrowest family that is still correct:

```tnix [numbers.tnix]
let
  count :: Nat;
  count = 3;

  offset = count - 5;
  scaled = count * 2;
  ratio = 1.5 * 2;
  add = a: b: a + b;
in { inherit offset scaled ratio add; }
```

```text
root: {
  add :: Number %1 -> Number %1 -> Number;
  offset :: Int;
  ratio :: Number;
  scaled :: Int;
}
add :: Number %1 -> Number %1 -> Number
count :: Nat
offset :: Int
ratio :: Number
scaled :: Int
```

Subtracting from a `Nat` can go negative, so `offset` widens to `Int`. Mixing a
float with an integer gives `Number`. An unannotated `a + b` has nothing to go
on, so it defaults to `Number`. A negative literal is rejected where a `Nat` is
expected: `count = -1;` reports `[TC0013] type mismatch: -1 vs Nat`.

> [!NOTE]
> **Upcoming syntax.** Division (`a / b`) is being added to the parser. Until it
> lands, use `builtins.div a b`.

## Functions and the `%1` arrow

`double` was inferred as `Int %1 -> Int`, not `Int -> Int`. tnix tracks
**multiplicity**: a lambda that uses its argument exactly once gets the linear
arrow `%1 ->`. A linear function may be used anywhere an ordinary function is
expected (`%1 ->` is a subtype of `->`), so you can mostly ignore it. It shows
up in hovers and `check` output, and you can write it in signatures when you
want to require a function that consumes its argument once.

A function signature checks the whole body. Here the body returns a string
where the signature promises an `Int`:

```tnix [bad-fn.tnix]
let
  bad :: Int -> Int;
  bad = x: "${builtins.toString x}";
in bad
```

```text
[TC0013] type mismatch: String vs Int
```

Calling something that is not a function is caught too: `let a = 1; in a 2`
reports `[TC0018] cannot call an integer as a function`.

## Polymorphism

`id :: forall a. a -> a` is polymorphic: each use picks its own `a`, which is
why `id true` returned `true`. tnix also generalizes unannotated bindings, but
only *after* the `let` group that defines them, because the bindings of one
`let` may refer to each other recursively. So this fails:

```tnix [poly.tnix]
let
  id = x: x;
  n = id 1;
  s = id "one";
in { inherit n s; }
```

```text
[TC0013] type mismatch: "one" vs 1
```

Inside the group, `id` is still being inferred, and its first use fixes the
parameter to `1`. There are two fixes:

- give it a polymorphic signature, `id :: forall a. a -> a;` (as in
  `annotations.tnix`), or
- define it in an outer `let`, so it is generalized before the inner group uses
  it:

```tnix [poly-nested.tnix]
let
  id = x: x;
in
let
  n = id 1;
  s = id "one";
in { inherit n s; }
```

```text
root: {
  n :: 1;
  s :: "one";
}
id :: forall t0. t0 %1 -> t0
```

Inferred type variables are named `t0`, `t1`, ... in output. Variables you
write yourself keep their names.

## Recap

- Annotate `let` bindings with `name :: Type;` and lambda binders with
  `(x :: Type):`.
- Literals keep literal types until a signature or a join widens them.
- `%1 ->` marks a function that uses its argument once; it is accepted wherever
  `->` is expected.
- Unannotated bindings are generalized after their `let` group. Use
  `forall` signatures for helpers that are used at several types in the same
  group.

<div class="tx-pager">

[← 2. Your first file](./first-file.md) [4. Attribute sets →](./attrsets.md)

</div>
