---
title: "7. Generics and higher-kinded types"
description: Write polymorphic functions with forall, parameterize type aliases, and describe higher-kinded APIs that the kind checker validates.
---

# 7. Generics and higher-kinded types

Nix code is full of helpers that work for any element type: `map`, `filter`,
`foldl'`. tynix expresses them with **parametric polymorphism**, and goes one
level further with **higher-kinded types**, where the thing you abstract over
is itself a type constructor such as `List`.

This step continues in the `tynix-tour` workspace. `builtins.head` below is
typed by the built-in prelude from step 6 (`forall a. List a -> a`).

## Generic functions and aliases

```tynix [generics.tynix]
type Pair a b = { fst :: a; snd :: b; };
type Maybe a = a | Null;

let
  first :: forall a. List a -> a;
  first = xs: builtins.head xs;

  mkPair :: forall a b. a -> b -> Pair a b;
  mkPair = a: b: { fst = a; snd = b; };

  swap :: forall a b. Pair a b -> Pair b a;
  swap = (p :: Pair a b): { fst = p.snd; snd = p.fst; };

  lookupPort :: Maybe Int;
  lookupPort = null;
in {
  head = first [ "x" "y" ];
  pair = swap (mkPair 1 "one");
  port = lookupPort;
}
```

```text
root: {
  head :: "x" | "y";
  pair :: Pair "one" 1;
  port :: Maybe Int;
}
first :: forall a. List a -> a
lookupPort :: Maybe Int
mkPair :: forall a b. a -> b -> Pair a b
swap :: forall a b. Pair a b -> Pair b a
```

- `forall a b.` introduces type variables. Type variables are lowercase; type
  constructors and aliases are capitalized.
- Aliases take parameters: `type Pair a b = ...`. `Maybe a = a | Null` is just
  a union with a friendly name.
- Each call instantiates the variables afresh, so `swap (mkPair 1 "one")`
  returns the swapped literal types.

Instantiation is checked as you would expect:

```tynix [generics-bad.tynix]
let
  first :: forall a. List a -> a;
  first = xs: builtins.head xs;

  n :: Int;
  n = first [ "x" "y" ];
in n
```

```text
6:7: [TC0013] type mismatch: "x" | "y" vs Int
```

## Abstracting over type constructors

`List` on its own is not a type; it is a **type constructor** that becomes a
type once you apply it: `List Int`. tynix lets type parameters stand for type
constructors. The classic example is a functor, a record that knows how to map
over some container `f`:

```tynix [functor.d.tynix]
type Functor f = {
  map :: forall a b. (a -> b) -> f a -> f b;
};

type Box a = { value :: a; };

declare "./functors.nix" {
  list :: Functor List;
  box :: Functor Box;
};
```

In `Functor f`, `f` is applied to arguments (`f a`), so tynix infers that `f`
has kind `Type -> Type`. Both `List` and `Box` have that kind, so
`Functor List` and `Functor Box` are well-formed.

The implementation is plain Nix:

```nix [functors.nix]
{
  list = { map = builtins.map; };
  box = { map = f: box: { value = f box.value; }; };
}
```

And typed code uses it generically:

```tynix [hkt.tynix]
let
  functors = import ./functors.nix;
  inc = (x :: Int): x + 1;
in {
  xs = functors.list.map inc [ 1 2 3 ];
  boxed = functors.box.map inc { value = 41; };
}
```

```text
root: {
  boxed :: Box Int;
  xs :: List Int;
}
functors :: {
  box :: Functor Box;
  list :: Functor List;
}
inc :: Int %1 -> Int
```

The same `map` signature, written once, produced `List Int` for one functor and
`{ value :: Int; }` for the other. Passing `{ value = "41"; }` to the box
functor's `map inc` is rejected, because `inc` expects an `Int`.

> [!IMPORTANT]
> Declaring and *using* values with polymorphic fields, as above, is fully
> supported. *Implementing* a record whose fields carry their own `forall`
> (for example writing `boxFunctor :: Functor Box; boxFunctor = { map = ...; };`
> in a `.tynix` file) is not yet accepted by the checker. Keep such instances in
> `.nix` and describe them with a declaration, as this step does.

## Composing type constructors

Aliases can take constructors as arguments and apply them:

```tynix [compose.tynix]
type Compose f g a = f (g a);

let
  boxes :: Compose List Box Int;
  boxes = [ { value = 1; } { value = 2; } ];
in boxes
```

```text
root: Compose List Box Int
boxes :: Compose List Box Int
```

`Compose List Box Int` expands to `List (Box Int)`, that is, a list of
`{ value :: Int; }`. `Box` comes from `functor.d.tynix`: aliases declared in
workspace declaration files are visible everywhere in the workspace. A list of
`{ value = "one"; }` records is rejected.

## Kinds keep you honest

Because tynix infers kinds, it catches type-level mistakes before checking any
value:

```tynix [kinds.tynix]
let
  x :: Int String;
  x = 1;
in x
```

```text
[TK0001] kind mismatch: Type vs Type -> ?0
```

`Int` has kind `Type`; applying it to `String` would require `Type -> ...`.
Under-applying a constructor in an annotation is caught as well:

```tynix [twice.tynix]
type Twice f a = f (f a);

let
  x :: Twice List;
  x = [ ];
in x
```

```text
[TK0003] term annotation must resolve to Type, but got Type -> Type for Twice List
```

`Twice List Int` (a list of lists of `Int`) is the fully applied, valid form.

## Recap

- `forall a.` makes a signature generic; each use instantiates it.
- Aliases take parameters, including constructor parameters such as `f`.
- Kinds (`Type`, `Type -> Type`, ...) are inferred and checked; `TK` diagnostics
  report misuse.
- Higher-kinded APIs are best declared in `.d.tynix` and implemented in `.nix`
  today.

<div class="tx-pager">

[← 6. Typing existing .nix](./declarations.md) [8. Conditional types →](./conditional-types.md)

</div>
