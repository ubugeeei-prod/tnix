# Diagnostic Codes

Every user-visible error produced by `tynix` is tagged with a stable code so
editors, CI logs, and this documentation can refer to the same diagnostic
without depending on the exact wording. Messages have the shape:

```
line:col: [Tnnnnn] human-readable message
```

`line:col` (1-based) is the start of the source span the diagnostic belongs
to: the offending expression for checker errors, the unexpected token for
parse errors. Editors underline the whole span. Diagnostics that are not tied
to one expression (kind errors, driver errors, and a few checker errors such
as `TC0022`) omit the position.

The leading prefix of the code encodes the phase:

| Prefix | Phase |
| --- | --- |
| `TPxxxx` | parser |
| `TKxxxx` | kind checker |
| `TCxxxx` | type checker / semantic analysis |
| `TDxxxx` | driver / project / IO |
| `TLxxxx` | language-server lints (editor only, see [below](#language-server-lints-tlxxxx)) |

Codes are considered stable once assigned. To retire a code, leave its entry
here and stop emitting it — never reuse the number.

## Parser (`TPxxxx`)

### `TP0001` — dangling tynix diagnostic directive

A `# @tynix-ignore` or `# @tynix-expected` directive appears as the very last
non-blank line of the file. Directives attach to the next root expression or
`let` binding, so a trailing directive has nothing to label.

**Fix:** delete the directive, or move it above the line it should affect.

### `TP0002` — multiple directives target the same next line

Two consecutive `# @tynix-*` directives sit between code lines. Only one
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

### `TC0006` — unused `@tynix-expected` directive

A `# @tynix-expected` directive was attached to a binding whose body did not
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

A record lacks a field that is required. There are three shapes:

- a selection names a field the value does not have:
  `` missing field `license` on { pname :: "hello"; version :: "2.12.1"; } ``,
  reported at the selection;
- a record passed to a function or a signature lacks a required field:
  `` missing field `version`: expected { ... } but got { ... } ``, reported at
  the argument or binding;
- a call does not provide a field that the callee's inferred (open) record or
  attribute-set pattern requires:
  `` missing field `pname` required by { pname :: ?4; version? :: String; } ``.

Optional fields (`name? :: T`, from pattern defaults) never trigger it, and
neither does `x.a or default`.

**Fix:** add the field, fix the typo, or give the pattern field a default.

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
both sides rendered via `Pretty`, actual first. A call mismatch is reported at
the argument, a signature mismatch at the binding's body. When both sides are
records, the message names the first field that does not fit:
`` type mismatch in field `packages`: Vec 1 "git" vs List Derivation ``.

A `forall` signature is rigid, so a body that only works for some
instantiation reports the type variable itself: `type mismatch: 1 vs a`.

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

### `TC0019` — operands are not comparable

An ordered comparison (`<`, `>`, `<=`, `>=`) was applied to operands that are
not both numeric or both string-like. Structural equality (`==`, `!=`) accepts
any operands; only ordered comparisons require comparable types.

**Fix:** compare numbers with numbers or strings with strings. A gradual
boundary (`dynamic`, `any`) on either side suppresses the error.

### `TC0020` — operands are not concatenable

List concatenation (`++`) was applied to operands that are not both list-like.
Fixed-shape sequences (vectors, tuples) and plain `List a` values all count as
list-like; the result is a plain `List` joining both element types.

**Fix:** concatenate lists with lists. A gradual boundary (`dynamic`, `any`)
on either side suppresses the error.

### `TC0021` — operands are not updatable

The attribute-set update operator (`//`) was applied to operands that are not
both records. The result merges the two field maps, with the right-hand side
overriding fields present on both.

**Fix:** update an attribute set with another attribute set. A gradual
boundary (`dynamic`, `any`) on either side suppresses the error.

### `TC0022` — dynamic attribute in `let`

A `let` binding used a dynamic key such as `${name} = value;`. Nix rejects
dynamic attributes in `let` blocks because the bound names must be known
statically.

**Fix:** bind a static name, or build an attribute set with the dynamic key
and select from it.

## Driver / Project (`TDxxxx`)

### `TD0001` — failed to read

`tynix` could not open a file. The message includes the OS-level
`displayException` so the underlying cause (missing path, permission
denied, etc.) is preserved.

### `TD0002` — duplicate ambient declarations

A single source has two `declare "..."` blocks for the same target path.

### `TD0003` — duplicate ambient entry

A single `declare` block has two entries for the same attribute name.

### `TD0004` — config decode error

`tynix.config.tynix` failed to parse or did not evaluate to an attribute
set.

### `TD0005` — config bad list

A list-valued config field (e.g. `declarationPacks`) was not a list.

### `TD0006` — config bad item

An entry inside a list-valued config field was not a path-like value, or
pointed at a file that does not exist / is not a `.d.tynix` file.

### `TD0007` — compiling a declaration-only file

`tynix compile`/`tynix.compile` was asked to lower a `.d.tynix` file.
Declaration-only files have no executable root expression.

### `TD0008` — emitting from a declaration-only file

`tynix emit`/`tynix.emit` was asked to emit declarations from a file that
has no root expression.

## Language Server Lints (`TLxxxx`)

These diagnostics come from `tynix-lsp` only; `tynix check` and
`check-project` never report them, and they never fail a build. They are
computed from the source text, so they keep working while the file has type
errors. Their codes are owned by the language server, not by
`Diagnostics.hs`.

**TL0001: unused binding** (severity: hint, tag: `Unnecessary`, so editors
render the name faded). A `let` binding, `inherit`ed name, lambda parameter,
attribute-set pattern field, or `@` alias is never used, for example
`` `x` is a parameter but never used. `` Names starting with `_` are exempt.

**Fix:** remove the binding, or prefix the name with `_` to keep it on
purpose. Code actions do either.

**TL0002: use of a deprecated declaration** (severity: hint, tag:
`Deprecated`, so editors strike the name through). The code uses a binding or
`builtins` member whose documentation comment (the `#` lines directly above
it) contains `@deprecated`, optionally followed by a reason that is appended to
the message, as in `` `hello` is deprecated: use `greet` instead ``:

```tynix
let
  # Old spelling.
  # @deprecated use `greet` instead
  hello = name: "hello ${name}";
  greet = name: "hello ${name}";
in hello "tynix"
```

**Fix:** switch to the replacement named in the reason.

## Listing Codes Programmatically

The canonical list lives in
[`packages/tynix-core/src/Diagnostics.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/Diagnostics.hs).
The `DiagnosticCode` data type is exposed alongside `diagnosticCodeText` and
`withCode`, so downstream tooling can pattern match on stable variants
rather than parsing the prefix back out of the message.
