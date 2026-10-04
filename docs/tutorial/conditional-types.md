---
title: "8. Conditional types and infer"
description: Compute types from other types with extends ? : and pull pieces out of a type with infer.
---

# 8. Conditional types and infer

Sometimes the type you want is a function of another type: "the element type of
this list", "the return type of that function", "the type of the `port` field
of this config". tnix borrows TypeScript's **conditional types** for this.

```text
Checked extends Pattern ? WhenMatched : Otherwise
```

If `Checked` matches `Pattern`, the type reduces to `WhenMatched`, otherwise to
`Otherwise`. Inside `Pattern`, `infer x` captures part of the matched type so
that `WhenMatched` can use it.

## A small toolbox

```tnix [conditional.tnix]
type ElementOf t = t extends List (infer a) ? a : t;
type ReturnOf f = f extends (infer a -> infer r) ? r : dynamic;
type ArgOf f = f extends (infer a -> infer r) ? a : dynamic;
type FieldOf r = r extends { value :: infer v; } ? v : unknown;
type IsString t = t extends String ? true : false;

let
  item :: ElementOf (List String);
  item = "hello";

  same :: ElementOf Int;
  same = 3;

  result :: ReturnOf (String -> Int);
  result = 42;

  arg :: ArgOf (String -> Int);
  arg = "input";

  field :: FieldOf { value :: Bool; label :: String; };
  field = true;

  yes :: IsString "nix";
  yes = true;
in { inherit item same result arg field yes; }
```

```bash
tnix check conditional.tnix
```

Every binding checks. Output keeps the alias spelling (`item :: ElementOf (List
String)`) because that is what you wrote, but the checker compares values
against the *reduced* type:

| Annotation | Reduces to | Why |
| --- | --- | --- |
| `ElementOf (List String)` | `String` | `List String` matches `List (infer a)` with `a = String` |
| `ElementOf Int` | `Int` | no match, so the `else` branch returns `t` |
| `ReturnOf (String -> Int)` | `Int` | the function pattern binds `a = String`, `r = Int` |
| `ArgOf (String -> Int)` | `String` | same match, other variable |
| `FieldOf { value :: Bool; label :: String; }` | `Bool` | record patterns match by field; extra fields are fine |
| `IsString "nix"` | `true` | no `infer`, so tnix falls back to subtyping: `"nix" <: String` |

Change `result = 42;` to a string and the reduced type shows its teeth:

```text
[TC0013] type mismatch: "forty-two" vs ReturnOf (String -> Int)
```

## How matching works

tnix reduces a conditional type in two stages:

1. **Pattern match.** If the pattern contains `infer`, tnix matches the checked
   type against it structurally: functions against functions, records field by
   field, applications such as `List a` argument by argument. Each `infer x`
   binds the part it lines up with. Using the same `infer x` twice requires
   both occurrences to bind the same type.
2. **Subtype test.** If the pattern does not match structurally, tnix asks
   whether `Checked` is a subtype of `Pattern` and picks the branch from the
   answer. This is how `IsString "nix"` works.

Two practical rules follow:

- **Conditional types do not distribute over unions.** `ElementOf (List Int |
  String)` does not become `Int | String`. The union as a whole does not match
  `List (infer a)`, so the result is the `else` branch, the union itself.
- **Function patterns match the arrow exactly.** A pattern written with `->`
  does not match a linear `%1 ->` function type and vice versa. Write the
  pattern with the arrow you expect to receive.

> [!WARNING]
> Keep conditional aliases non-recursive. A conditional alias that refers to
> itself in a branch, such as `Unwrap t = t extends { value :: infer v; } ?
> Unwrap v : t`, is cut off by tnix's reduction budget and does not reduce the
> way you would expect. Unroll the recursion to the depth you need instead.

## Combining with real types

Conditional types are most useful on top of record types you already have.
Here a config's port type is extracted once and reused, refinement and all:

```tnix [port.tnix]
type PortOf c = c extends { port :: infer p; } ? p : Int;
type Config = { port :: Range 1 65535 Int; host :: String; };

let
  port :: PortOf Config;
  port = 8080;
in port
```

`PortOf Config` reduces to `Range 1 65535 Int`, a numeric refinement: integers
from 1 to 65535. `port = 70000;` is rejected with
`[TC0013] type mismatch: 70000 vs PortOf Config`. The
[language reference](../language-reference.md#numeric-validators) covers `Range`,
`Unit`, and the `Vec` / `Matrix` / `Tensor` shape types.

## Recap

- `A extends B ? C : D` picks a branch at the type level.
- `infer x` inside `B` captures a piece of `A` for use in `C`.
- Without `infer`, the test is plain subtyping.
- No distribution over unions, exact arrow matching, and no recursion.

<div class="tx-pager">

[← 7. Generics and HKT](./generics.md) [9. Flakes and packages →](./flakes-and-packages.md)

</div>
