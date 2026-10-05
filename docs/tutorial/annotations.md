---
title: "3. Annotations and inference"
description: Learn where tynix needs annotations, what it infers on its own, and how literal types, numbers, functions and polymorphism behave.
---

# 3. Annotations and inference

tynix infers most types. Annotations are how you state intent, and the checker
holds the code to it. This step shows the three places annotations go and what
inference does everywhere else.

## Three places for types

```tynix [annotations.tynix]
let
  port :: Int;
  port = 8080;

  name = "web";

  double = (x :: Int): x * 2;

  label :: String -> Int -> String;
  label = prefix: n: "${prefix}-${toString n}";

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
tynix check annotations.tynix
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

`toString` is one of the builtins that Nix puts in scope without the
`builtins.` prefix. tynix ships typed declarations for all of them, and for
every `builtins.*` member, so `toString n` is checked like any other call
(`toString :: unknown -> String`). Step 6 explains where those types come from.

## Literal types and widening

Look at `name :: "web"`. Without a signature, a string literal keeps its exact
**literal type** `"web"`, which is a subtype of `String`. The same goes for
integers (`8080`), floats (`1.5`) and booleans (`true`). Literal types let
unions of literals act as enumerations:

```tynix [levels.tynix]
let
  level :: "debug" | "info" | "warn";
  level = "debug";

  other :: "debug" | "info";
  other = "trace";
in level
```

```text
6:11: [TC0013] type mismatch: "trace" vs "debug" | "info"
```

A signature widens: `port :: Int` makes `port` an `Int` even though its value is
the literal `8080`. Use a signature whenever you want a binding's type to be the
general one.

## Numbers

Numbers form a small tower: `Nat <: Int <: Number` and `Float <: Number`.
Arithmetic (`+`, `-`, `*`, `/`) picks the narrowest family that is still
correct:

```tynix [numbers.tynix]
let
  count :: Nat;
  count = 3;

  offset = count - 5;
  scaled = count * 2;
  half = count / 2;
  ratio = 1.5 * 2;
  add = a: b: a + b;
in { inherit offset scaled half ratio add; }
```

```text
root: {
  add :: Number %1 -> Number %1 -> Number;
  half :: Int;
  offset :: Int;
  ratio :: Number;
  scaled :: Int;
}
add :: Number %1 -> Number %1 -> Number
count :: Nat
half :: Int
offset :: Int
ratio :: Number
scaled :: Int
```

Subtracting from a `Nat` can go negative, so `offset` widens to `Int`. Mixing a
float with an integer gives `Number`. An unannotated `a + b` has nothing to go
on, so it defaults to `Number`. Integer division stays an integer, as in Nix.
A negative literal is rejected where a `Nat` is expected: `count = -1;` reports
`[TC0013] type mismatch: -1 vs Nat`.

## Functions and the `%1` arrow

`double` was inferred as `Int %1 -> Int`, not `Int -> Int`. tynix tracks
**multiplicity**: a lambda that uses its argument exactly once gets the linear
arrow `%1 ->`. A linear function may be used anywhere an ordinary function is
expected (`%1 ->` is a subtype of `->`), so you can mostly ignore it. It shows
up in hovers and `check` output, and you can write it in signatures when you
want to require a function that consumes its argument once.

A function signature checks the whole body. Here the body returns a string
where the signature promises an `Int`:

```tynix [bad-fn.tynix]
let
  bad :: Int -> Int;
  bad = x: "${toString x}";
in bad
```

```text
3:9: [TC0013] type mismatch: String vs Int
```

The `3:9:` prefix is the line and column of the offending expression, here the
body of `bad`. Editors underline exactly that span. Calling something that is
not a function is caught too: `let a = 1; in a 2` reports
`1:15: [TC0018] cannot call an integer as a function`.

## Polymorphism

`id :: forall a. a -> a` is polymorphic: each use picks its own `a`, which is
why `id true` returned `true`. You rarely need to write the `forall` yourself,
though. tynix infers **principal polymorphic types** for unannotated `let`
bindings, the way Haskell and OCaml do (Hindley-Milner let-polymorphism):

```tynix [poly.tynix]
let
  id = x: x;
  compose = f: g: x: f (g x);

  n = id 1;
  s = id "one";
  inc = compose (x: x + 1) (x: x * 2);
in { inherit n s inc; }
```

```text
root: {
  inc :: Int %1 -> Int;
  n :: 1;
  s :: "one";
}
compose :: forall t0 t1 t2. (t1 -> t2) %1 -> (t0 -> t1) %1 -> t0 %1 -> t2
id :: forall t0. t0 %1 -> t0
inc :: Int %1 -> Int
n :: 1
s :: "one"
```

`id` is used at `1` and at `"one"` in the same `let`, and each use gets a fresh
instance. Inferred type variables are named `t0`, `t1`, ... in output; variables
you write yourself keep their names.

The bindings of one `let` may refer to each other in any order. tynix sorts them
by their dependencies, infers each group of mutually recursive bindings
together, and generalizes a group as soon as it is solved. Mutual recursion
works without annotations:

```tynix [even-odd.tynix]
let
  isEven = n: if n == 0 then true else isOdd (n - 1);
  isOdd = n: if n == 0 then false else isEven (n - 1);
in isEven 10
```

```text
root: Bool
isEven :: Int -> Bool
isOdd :: Int -> Bool
```

### Signatures are promises

A `forall` signature is **rigid**: the body must work for *every* choice of the
type variables, not just for one. A body that only works for some `a` is
rejected:

```tynix [rigid.tynix]
let
  id :: forall a. a -> a;
  id = x: 1;
in id
```

```text
3:8: [TC0013] type mismatch: 1 vs a
```

Inside the body, `a` is an opaque type that only equals itself, so `1` does not
fit. This is what makes a signature trustworthy: callers may rely on `id`
returning exactly what they passed in.

## Recap

- Annotate `let` bindings with `name :: Type;` and lambda binders with
  `(x :: Type):`.
- Literals keep literal types until a signature or a join widens them.
- `%1 ->` marks a function that uses its argument once; it is accepted wherever
  `->` is expected.
- Unannotated `let` bindings get principal polymorphic types, so one helper
  can be used at several types. `forall` signatures are rigid: the body must
  work for every instantiation.

<div class="tx-pager">

[← 2. Your first file](./first-file.md) [4. Attribute sets →](./attrsets.md)

</div>
