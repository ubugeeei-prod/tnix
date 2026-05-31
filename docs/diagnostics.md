# Diagnostic Codes

Every user-visible error produced by `tnix` is tagged with a stable code so
editors, CI logs, and this documentation can refer to the same diagnostic
without depending on the exact wording. Messages have the shape:

```
[Tnnnnn] human-readable message
```

The leading prefix encodes the phase:

| Prefix | Phase |
| --- | --- |
| `TPxxxx` | parser |
| `TKxxxx` | kind checker |
| `TCxxxx` | type checker / semantic analysis |
| `TDxxxx` | driver / project / IO |

Codes are considered stable once assigned. To retire a code, leave its entry
here and stop emitting it — never reuse the number.

## Parser (`TPxxxx`)

### `TP0001` — dangling tnix diagnostic directive

A `# @tnix-ignore` or `# @tnix-expected` directive appears as the very last
non-blank line of the file. Directives attach to the next root expression or
`let` binding, so a trailing directive has nothing to label.

**Fix:** delete the directive, or move it above the line it should affect.

### `TP0002` — multiple directives target the same next line

Two consecutive `# @tnix-*` directives sit between code lines. Only one
directive can be attached to any single target.

**Fix:** keep one directive or split them across separate targets.

### `TP0003` — duplicate directives for the same line

A previous directive already attached to the line a new directive is now
trying to target.

**Fix:** consolidate the directives or move them to distinct targets.

### `TP0004` — parse error

A Megaparsec-level syntax error. The accompanying message contains the
exact unexpected token and the production that was being parsed; see
[`docs/grammar.md`](./grammar.md) for the full surface grammar.

## Kind Checker (`TKxxxx`)

### `TK0001` — kind mismatch

Two type expressions reached kind unification with incompatible kinds
(e.g. applying a `Type -> Type` constructor to another `Type -> Type`).

**Fix:** check the arity of the type constructor and the kinds of the
arguments.

### `TK0002` — kind occurs check failed

A kind metavariable was being instantiated with a kind that contains
itself.

**Fix:** usually indicates a malformed higher-kinded alias body. Add or
simplify alias parameters to avoid the recursive instantiation.

### `TK0003` — annotation must resolve to `Type`

A type annotation in a term position (function binder, signature, ambient
entry) resolved to a higher kind instead of `Type`.

**Fix:** fully apply the constructor (`List Int` rather than `List`).

### `TK0004` — internal: missing alias placeholder

An internal invariant in the alias-kind inference pass was broken. Please
file a bug report with the offending program.

## Type Checker (`TCxxxx`)

### `TC0001` — unbound name

A name was referenced but never bound in scope.

### `TC0002` — duplicate attribute

The same attribute name appears twice in a single attribute set.

### `TC0003` — duplicate signatures

A `let` group contains the same `name :: T;` signature more than once.

### `TC0004` — duplicate bindings

A `let` group contains the same `name = expr;` binding more than once.

### `TC0005` — missing binding for signature

A `let` group declared `name :: T;` but never bound `name`.

### `TC0006` — unused `@tnix-expected` directive

A `# @tnix-expected` directive was attached to a binding whose body did not
produce a checker failure.

**Fix:** remove the directive, or change the body so the expected failure
actually occurs.

### `TC0007` — duplicate pattern bindings

An attribute-set lambda pattern (`{ a, b, a }`) repeats a binder.

### `TC0008` — cannot select field from unknown

A field was selected from a value whose type is `unknown`. The checker
treats `unknown` as a true top type: nothing structural is provable.

**Fix:** narrow the value with an explicit `expr as Type` cast before
selecting.

### `TC0009` — missing field

A field was selected that does not exist on the inferred record type. The
message includes the available record so the typo is easy to spot.

### `TC0010` — missing field from dynamic key

A dynamic-key selection (`pkgs.${system}`) resolved to a string-literal
union that includes a member missing from the record.

### `TC0011` — dynamic key is `unknown`

`unknown` keys cannot be used with dynamic selection because the set of
possible field names is unrestricted.

### `TC0012` — dynamic key is not string-like

The expression inside `${ ... }` resolved to a non-string type.

### `TC0013` — type mismatch

Two types could not be unified or related by subtyping. The message includes
both sides rendered via `Pretty`.

### `TC0014` — record mismatch

Two record types failed unification because their field sets do not have a
subset relationship.

### `TC0015` — invalid cast

An `expr as Type` cast was rejected because the actual and asserted types
have no overlapping structure.

### `TC0016` — occurs check failed

A type metavariable was being instantiated with a type that contains
itself.

### `TC0017` — internal: missing placeholder

An internal invariant in the recursive-let placeholder allocation was
broken. Please file a bug.

### `TC0018` — value is not callable

A value of a concrete non-function type (an attribute set, list, string,
number, boolean, or other base type) was applied as if it were a function.

**Fix:** apply only functions, or correct the expression so the callee is a
function. Gradual types (`dynamic`, `unknown`, `any`) are still callable.

## Driver / Project (`TDxxxx`)

### `TD0001` — failed to read

`tnix` could not open a file. The message includes the OS-level
`displayException` so the underlying cause (missing path, permission
denied, etc.) is preserved.

### `TD0002` — duplicate ambient declarations

A single source has two `declare "..."` blocks for the same target path.

### `TD0003` — duplicate ambient entry

A single `declare` block has two entries for the same attribute name.

### `TD0004` — config decode error

`tnix.config.tnix` failed to parse or did not evaluate to an attribute
set.

### `TD0005` — config bad list

A list-valued config field (e.g. `declarationPacks`) was not a list.

### `TD0006` — config bad item

An entry inside a list-valued config field was not a path-like value, or
pointed at a file that does not exist / is not a `.d.tnix` file.

### `TD0007` — compiling a declaration-only file

`tnix compile`/`tnix.compile` was asked to lower a `.d.tnix` file.
Declaration-only files have no executable root expression.

### `TD0008` — emitting from a declaration-only file

`tnix emit`/`tnix.emit` was asked to emit declarations from a file that
has no root expression.

## Listing Codes Programmatically

The canonical list lives in
[`packages/tnix-core/src/Diagnostics.hs`](../packages/tnix-core/src/Diagnostics.hs).
The `DiagnosticCode` data type is exposed alongside `diagnosticCodeText` and
`withCode`, so downstream tooling can pattern match on stable variants
rather than parsing the prefix back out of the message.
