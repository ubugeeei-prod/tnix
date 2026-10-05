# tynix Grammar

This is the executable surface grammar of `.tynix` and `.d.tynix` files as
implemented by the parser in
[`packages/tynix-core/src/ParserExpr.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/ParserExpr.hs),
[`packages/tynix-core/src/ParserType.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/ParserType.hs),
and [`packages/tynix-core/src/ParserLexer.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/ParserLexer.hs).

The notation is EBNF with these conventions:

| Form | Meaning |
| --- | --- |
| `X Y` | `X` followed by `Y` |
| `` X \| Y `` | `X` or `Y` |
| `X*` | zero or more `X` |
| `X+` | one or more `X` |
| `X?` | optional `X` |
| `"..."` | literal terminal text |
| `<name>` | named terminal (see [Lexical Structure](#lexical-structure)) |

Whitespace and comments are skipped between every non-trivial token by the
lexer (`sc`). All productions below assume that implicit skipping.

## Program Structure

A tynix file is a sequence of declarations followed by an optional root
expression. Declaration-only files (`.d.tynix`) end after the declarations.

```ebnf
program     = declaration* root_expression?
declaration = alias_decl | ambient_decl
root_expression = expression
```

### Type alias declarations

```ebnf
alias_decl = "type" type_identifier type_identifier* "=" type ";"
```

### Ambient declarations

`declare` blocks describe externally-defined Nix surfaces.

```ebnf
ambient_decl  = "declare" ( path | string_literal ) "{" ambient_entry* "}" ";"
ambient_entry = attr_name "::" type ";"
```

## Expressions

The expression grammar follows Nix. It is layered from loosest binding to
tightest:
`expression < pipe < implication < or < and < equality < relational < update <
not < addition < multiplication < concat < has_attr < negation < cast <
application < select < atom`.

```ebnf
expression       = if_expr
                 | let_expr
                 | assert_expr
                 | with_expr
                 | lambda_expr
                 | pipe_expr
```

### Control flow

```ebnf
if_expr  = "if" expression "then" expression "else" expression

assert_expr = "assert" expression ";" expression

with_expr   = "with" expression ";" expression

let_expr = "let" let_item* "in" expression
let_item = let_signature | let_binding | inherit_clause
let_signature = binding_identifier "::" type ";"
let_binding   = let_key ("." attr_key)* "=" expression ";"
let_key       = binding_identifier | "${" expression "}" | string_literal
```

The first key of a `let` item is parsed once; if it is a plain name followed
by `::`, the item is a signature, otherwise a binding. A binding may use a
nested path (`a.b.c = 1;`). A dynamic first key (`${k} = v;`) parses but is
rejected by the checker with `TC0022`, as Nix rejects it.

### Lambdas and patterns

```ebnf
lambda_expr  = pattern ":" expression        -- the ":" must not start "::"
pattern      = "(" binding_identifier "::" type ")"
             | binding_identifier "@" attr_set_pattern
             | attr_set_pattern ("@" binding_identifier)?
             | binding_identifier

attr_set_pattern = "{" (pattern_item ("," pattern_item)* ","?)? "}"
pattern_item     = "..."
                 | binding_identifier ("::" type)? ("?" expression)?
```

Only the `pattern :` prefix is speculative: once it is recognized, the parser
commits to the lambda, so an error inside the body is reported where it occurs.
A pattern field may carry an erased annotation and a default:
`{ name :: String, version ? "1", ... }@args:`.

### Operators

```ebnf
pipe_expr        = impl_expr ("|>" impl_expr)*          -- left-associative
                 | impl_expr ("<|" impl_expr)*          -- right-associative
impl_expr        = or_expr ("->" impl_expr)?
or_expr          = and_expr ("||" and_expr)*
and_expr         = equality_expr ("&&" equality_expr)*
equality_expr    = relational_expr (("==" | "!=") relational_expr)*
relational_expr  = update_expr (("<=" | ">=" | "<" | ">") update_expr)*
update_expr      = not_expr ("//" update_expr)?
not_expr         = "!" not_expr | addition_expr
addition_expr    = multiplication_expr (("+" | "-") multiplication_expr)*
multiplication_expr = concat_expr (("*" | "/") concat_expr)*
concat_expr      = has_attr_expr ("++" concat_expr)?
has_attr_expr    = negation_expr ("?" attr_key ("." attr_key)*)?
negation_expr    = "-" negation_expr | cast_expr
cast_expr        = application_expr ("as" type)*
application_expr = select_expr+
select_expr      = atom ("." attr_key)* ("or" select_expr)?
attr_key         = field_name | string_literal | "${" expression "}"
```

`|>` and `<|` cannot be mixed in one chain without parentheses, as in Nix. A
negated numeric literal folds into a negative literal (`-1` keeps the
singleton type `-1`). `or` is only meaningful after a selection:
`x.a.b or default`.

Single-character operators never swallow a longer one: `-` is not followed by
`>`, `/` not by `/`, `<` not by `|`, and `+` not by `+`.

### Atoms

```ebnf
atom = "(" expression ")"
     | rec_attr_set
     | attr_set
     | list
     | string
     | path
     | search_path
     | float_literal
     | int_literal
     | "true" | "false" | "null"
     | uri_literal
     | identifier
     | "as"                     -- the variable `as`, when no type follows

attr_set        = "{" attr_item* "}"
rec_attr_set    = "rec" "{" attr_item* "}"
attr_item       = inherit_clause | attr_field
inherit_clause  = "inherit" ("(" expression ")")? attr_name* ";"
attr_field      = attr_key ("." attr_key)* "=" expression ";"

list            = "[" list_item* "]"
list_item       = if_expr | let_expr | lambda_expr | list_cast
list_cast       = select_expr ("as" type)*
```

List elements are selection-level expressions, as in Nix, so `[ f x ]` is a
two-element list. tynix additionally accepts casts and a few compound forms
inside lists that would otherwise need parentheses.

## Types

```ebnf
type             = forall_type
                 | context? conditional_type

forall_type      = "forall" type_identifier+ "." type
context          = "(" application_type ("," application_type)* ")" "=>"
                 | application_type "=>"
function_type    = union_type ( ("->" | "%1" "->") function_type )?
union_type       = application_type ("|" application_type)*
application_type = atom_type+
```

A constraint context (`Functor f =>`, `(Eq a, Show a) =>`) may open a type or
follow a `forall`. It is parsed and then dropped: tynix has no type classes yet,
so contexts are documentation only.

Function arrows are right-associative: `A -> B -> C` parses as `A -> (B -> C)`.

### Conditional types

```ebnf
conditional_type = function_type ("extends" function_type "?" type ":" type)?
```

### Atomic types

```ebnf
atom_type = "(" type ")"
          | record_type
          | type_list
          | string_literal     -- becomes a TLit (LString ...)
          | float_literal      -- becomes a TLit (LFloat ...)
          | int_literal        -- becomes a TLit (LInt ...)
          | "true" | "false"   -- TLit (LBool ...)
          | "any" | "dynamic" | "unknown"
          | "infer" identifier
          | type_ref

record_type  = "{" record_field* row_tail? "}"
record_field = attr_name "?"? "::" type ";"
row_tail     = "..." type_identifier? ";"?

type_list = "[" shape_item* "]"
shape_item = atom_type
```

`name? :: T;` is an optional field. A trailing `...` makes the record open,
and `...r` names its row variable.

A bare identifier in a type position becomes `TVar` if it starts with a
lowercase letter, otherwise `TCon`. This is how `List a` and `Vec n a` parse
as `TApp (TCon "List") (TVar "a")` and so on without dedicated keywords.

## Lexical Structure

```ebnf
identifier      = ident_start ident_char*
                  -- minus the term keywords below
binding_identifier = identifier | "as"
type_identifier = ident_start ident_char*
                  -- minus the type keywords below
field_name      = ident_start ident_char*      -- keywords allowed
ident_start     = letter | "_"
ident_char      = letter | digit | "_" | "'" | "-"

attr_name       = field_name | string_literal

int_literal     = digit+                      -- types also accept a leading "-"
float_literal   = digit* "." digit+ ( ("e"|"E") ["+"|"-"] digit+ )?

string          = double_quoted | indented
double_quoted   = '"' ( interpolation | "$$" | escape_seq | double_quoted_char )* '"'
indented        = "''" ( interpolation | indented_escape | indented_char )* "''"
escape_seq      = "\\" any_char      -- \n \r \t decode; any other char is literal
indented_escape = "''$" | "''${" | "'''" | "''\\" any_char
interpolation   = "${" expression "}"

path            = path_prefix path_part+
path_prefix     = "./" | "../" | "~/" | "/"
path_part       = path_chars | interpolation    -- e.g. ./${name}.nix
path_chars      = (letter | digit | "." | "_" | "-" | "+")+ ("/" path_chars)*
search_path     = "<" search_segment ("/" search_segment)* ">"   -- <nixpkgs/lib>
uri_literal     = letter (letter | digit | "+" | "-" | ".")+ ":" uri_char+
```

`attr_name` and `attr_key` accept string literals to support quoted keys such
as `"aarch64-darwin"`. A path needs at least one segment after its prefix, so
`//` and a lone `/` remain operators. Unquoted URIs are only reachable in
argument position, because a bare `scheme:` at the start of an expression is
read as a lambda; quote URIs elsewhere.

## Comments

```ebnf
comment           = line_comment | block_comment
line_comment      = "#" ... <end-of-line>
block_comment     = "/*" ... "*/"
```

Block comments do not nest. Line comments that begin with `# @tynix-ignore`
or `# @tynix-expected` are also picked up by the directive scanner — they
remain ordinary comments to the parser but are attached to the next root
expression or `let` item as a `DiagnosticDirective`. See
[Language Reference: Diagnostic Directives](./language-reference.md#diagnostic-directives).

## Operator Precedence and Associativity

From loosest to tightest binding, matching Nix:

| Level | Form | Associativity |
| --- | --- | --- |
| 1 | `if`, `let`, `with`, `assert`, lambda `pattern :` | (non-applicable) |
| 2 | `\|>` and `<\|` (pipes) | left and right |
| 3 | `->` (logical implication) | right |
| 4 | `\|\|` (boolean or) | left |
| 5 | `&&` (boolean and) | left |
| 6 | `==`, `!=` (equality) | left |
| 7 | `<`, `>`, `<=`, `>=` (relational) | left |
| 8 | `//` (attribute-set update) | right |
| 9 | `!` (boolean not) | prefix |
| 10 | `+`, `-` (additive) | left |
| 11 | `*`, `/` (multiplicative) | left |
| 12 | `++` (list concatenation) | right |
| 13 | `e ? attrpath` (has-attr) | (non-associative) |
| 14 | `-e` (arithmetic negation) | prefix |
| 15 | `expr as Type` (cast) | left |
| 16 | function application `f x` | left |
| 17 | `.field`, `.${expr}`, `or` default (select) | left |

So `a + 1 < limit && ok || done` parses as `(((a + 1) < limit) && ok) || done`,
and `xs |> map f |> length` as `(xs |> map f) |> length`.

Type-level precedence, from loosest to tightest:

| Level | Form | Associativity |
| --- | --- | --- |
| 1 | `forall vars. T`, `C =>` context | (binds tightest body) |
| 1 | `T extends P ? A : B` | right |
| 2 | `A -> B`, `A %1 -> B` | right |
| 3 | `` A \| B `` (union) | left |
| 4 | `F X` (type application) | left |
| 5 | `(T)`, record / type-list / literal atoms | — |

## Reserved Words

In expressions, only the Nix keywords are reserved: `if`, `then`, `else`,
`let`, `in`, `rec`, `with`, `assert`, `inherit`, `or`, and the constants
`true`, `false` and `null`. `as` is reserved as a variable reference only where
a type can follow it; it is an ordinary name in binding positions (lambda
binders, pattern fields, `let` keys), so `as: as.x` parses as in Nix.

In types, tynix's own keywords are reserved as well: `type`, `declare`,
`import`, `forall`, `extends`, `infer`, `any`, `dynamic`, `unknown`, `Tuple`
and `as`. This is why `type`, `any`, `import` and `declare` can be bound and
used as ordinary names in expressions.

Attribute names (field names, selections, record fields, `declare` entries)
accept every identifier, keywords included, so declaration packs can mirror
real APIs such as `lib.or` or `lib.any`.

## Whitespace and Newlines

Whitespace, line comments, and block comments are skipped between every
token by `sc`. Newlines have no syntactic role outside of comments —
expressions, declarations, and lists can all span multiple lines freely.

## Conformance Notes

- The grammar is implemented with [Megaparsec](https://hackage.haskell.org/package/megaparsec)
  and uses `try` for productions that share a common prefix (`alias_decl`
  vs `ambient_decl`, the lambda `pattern :` prefix, the typed-pattern vs
  attrset-pattern split).
- Every expression node records its source span, which is how diagnostics
  report `line:col` positions and editors underline the exact range.
- `programParser` requires the input to end with `eof`, so unterminated
  expressions are rejected with a structured `ParseError` (see
  [`Parser.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/Parser.hs)).
- The integration tests in
  [`Parser.spec.hs`](https://github.com/ubugeeei-prod/tynix/blob/main/packages/tynix-core/src/Parser.spec.hs) double as
  executable examples for every production in this document; if you change
  the grammar, mirror the change there first.

## Nix Parity

The parser accepts every expression form of the Nix language. Erasing a file
without type syntax gives back the same program: over a sample of 4000
nixpkgs files, `tynix compile` output parses to the same AST as the source
under `nix-instantiate --parse`, up to how equal strings are split into
segments. The known differences from Nix's lexer are:

- unquoted URIs are recognized only in argument position (see above);
- `x:x` without a space is a lambda, where Nix would read it as a URI.
