---
title: "5. Gradual typing"
description: Use dynamic, unknown and any at the edges of typed code, assert types with as, and manage expected failures with directives.
---

# 5. Gradual typing

Real Nix code imports untyped modules, parses JSON and calls functions nobody
has described yet. tnix does not make you type all of that before you can type
anything. It gives you three types for the unknown, each with different rules,
and an explicit cast to cross between them.

| Type | Meaning | Use a value as `String`? | Select fields? |
| --- | --- | --- | --- |
| `dynamic` | "not typed yet". The gradual boundary. | yes | yes, result is `dynamic` |
| `unknown` | "could be anything, check before use". The top type. | no, cast first | no, cast first |
| `any` | "trust me". The unsound escape hatch. | yes | yes, result is `any` |

## `dynamic`: untyped code

An `import` of a file that tnix has no declaration for is `dynamic`:

```tnix [dynamic.tnix]
let
  config = import ./config.nix;

  port :: Int;
  port = config.port;
in port
```

```text
root: Int
config :: dynamic
port :: Int
```

`dynamic` is *consistent* with every type: you can pass it where an `Int` is
expected, select fields from it, and call it. That is what lets typed code sit
next to untyped code. The price is that nothing about `config.port` was
actually checked. `dynamic` is a marker of where the types stop, and step 6
shows how to replace it with a declaration.

Note that `tnix check` does not even need `config.nix` to exist: without a
declaration it never reads the file.

## `unknown`: check before use

`unknown` is the safe counterpart. Every value can be *assigned* to `unknown`,
but an `unknown` cannot be used as anything more specific:

```tnix [unknown.tnix]
let
  raw :: unknown;
  raw = builtins.fromJSON "{}";
in raw.port
```

```text
[TC0008] cannot select field `port` from unknown
```

Assigning `raw` to a `String` binding fails the same way, with `[TC0013] type
mismatch: unknown vs String`. To use an `unknown` value, assert what it is.

## `as`: explicit casts

`expr as Type` is a checked assertion. It is accepted when the two types are
related: one is a subtype of the other, or a gradual type (`dynamic`,
`unknown`, `any`) sits on one side.

```tnix [cast.tnix]
let
  raw :: unknown;
  raw = builtins.fromJSON ''{"port": 8080}'';

  settings = raw as { port :: Int; };
in settings.port
```

```text
root: Int
raw :: unknown
settings :: {
  port :: Int;
}
```

Casts can also widen (`1 as Number`) or narrow a record to the fields you care
about (`{ name = "x"; extra = true; } as { name :: String; }`). What they cannot
do is relate two unrelated concrete types:

```text
$ tnix check bad-cast.tnix     # contains: 1 as String
[TC0015] invalid cast: 1 as String
```

Like every other piece of type syntax, `as` is erased: `raw as { port :: Int; }`
compiles to `raw`. A cast is a promise you make to the checker, not a runtime
conversion.

## `any`: the escape hatch

`any` turns checking off for a value. It flows into every type and every type
flows into it, and anything you derive from it is `any` too:

```tnix [any.tnix]
let
  escape :: any;
  escape = 1;

  s :: String;
  s = escape;

  n :: Int;
  n = escape;

  deep = escape.whatever.you.like;
in { inherit s n deep; }
```

```text
root: {
  deep :: any;
  n :: Int;
  s :: String;
}
deep :: any
escape :: any
n :: Int
s :: String
```

Prefer `dynamic` for "not typed yet" and `unknown` for "must be checked".
Reach for `any` only when you deliberately want the checker out of the way.

## Directives: `@tnix-ignore` and `@tnix-expected`

Sometimes the right move is to acknowledge an error and keep going. Two comment
directives apply to the next `let` binding (or signature) or to the root
expression:

```tnix [directives.tnix]
let
  # @tnix-ignore
  legacyPort :: Int;
  legacyPort = "8080";

  # @tnix-expected
  mustFail :: Int;
  mustFail = "not an int";
in { inherit legacyPort mustFail; }
```

```text
root: {
  legacyPort :: Int;
  mustFail :: Int;
}
legacyPort :: Int
mustFail :: Int
```

- `# @tnix-ignore` suppresses an error on the targeted binding. The binding
  keeps its declared type, so the rest of the file is still checked against
  `Int`.
- `# @tnix-expected` *requires* an error. If the binding starts checking
  cleanly, tnix reports `` [TC0006] unused @tnix-expected directive on binding `mustFail` ``, so a fixed bug cannot hide behind a stale suppression.

A directive must be followed by code; a directive at the end of a file is a
parse error (`TP0001`).

## Recap

- `dynamic` marks untyped boundaries and is consistent with everything.
- `unknown` accepts everything but must be cast before use.
- `any` disables checking for a value and everything derived from it.
- `as` asserts a related type and is erased at compile time.
- `@tnix-ignore` and `@tnix-expected` scope suppressions to one binding.

<div class="tx-pager">

[← 4. Attribute sets](./attrsets.md) [6. Typing existing .nix →](./declarations.md)

</div>
