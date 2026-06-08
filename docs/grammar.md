# tnix Grammar

This is the executable surface grammar of `.tnix` and `.d.tnix` files as
implemented by the parser in
[`packages/tnix-core/src/ParserExpr.hs`](../packages/tnix-core/src/ParserExpr.hs),
[`packages/tnix-core/src/ParserType.hs`](../packages/tnix-core/src/ParserType.hs),
and [`packages/tnix-core/src/ParserLexer.hs`](../packages/tnix-core/src/ParserLexer.hs).

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

A tnix file is a sequence of declarations followed by an optional root
expression. Declaration-only files (`.d.tnix`) end after the declarations.

```ebnf
program     = declaration* root_expression?
declaration = alias_decl | ambient_decl
root_expression = expression
```

### Type alias declarations

```ebnf
alias_decl = "type" identifier identifier* "=" type ";"
```

### Ambient declarations

`declare` blocks describe externally-defined Nix surfaces.

```ebnf
ambient_decl  = "declare" ( path_literal | string_literal ) "{" ambient_entry* "}" ";"
ambient_entry = attr_name "::" type ";"
```

## Expressions

The expression grammar is layered from loosest binding to tightest:
`expression < or < and < equality < relational < not < addition <
multiplication < concat < cast < application < postfix < atom`.

```ebnf
expression       = if_expr
                 | let_expr
                 | lambda_expr
                 | or_expr
```

### Control flow

```ebnf
if_expr  = "if" expression "then" expression "else" expression

let_expr = "let" let_item* "in" expression
let_item = let_signature | let_binding
let_signature = identifier "::" type ";"
let_binding   = identifier "=" expression ";"
```

`let_item` is parsed as `try let_signature <|> let_binding`, so signatures
take precedence over bindings when the same identifier could match both.

### Lambdas and patterns

```ebnf
lambda_expr  = pattern ":" expression
pattern      = typed_pattern
             | attr_set_pattern
             | identifier

typed_pattern = "(" identifier "::" type ")"
attr_set_pattern = "{" attr_set_pattern_items "}"
attr_set_pattern_items = ( identifier ("," identifier)* ("," "...")? | "..." )?
```

Open attribute-set patterns (`{ self, nixpkgs, ... }`) and typed binders
(`(x :: Int)`) compose with ordinary identifier binders.

### Operators

Operators bind looser than application/selection and casts, but tighter than
control flow.

```ebnf
or_expr          = and_expr ("||" and_expr)*
and_expr         = equality_expr ("&&" equality_expr)*
equality_expr    = relational_expr (("==" | "!=") relational_expr)*
relational_expr  = not_expr (("<=" | ">=" | "<" | ">") not_expr)*
not_expr            = "!" not_expr | addition_expr
addition_expr       = multiplication_expr (("+" | "-") multiplication_expr)*
multiplication_expr = concat_expr ("*" concat_expr)*
concat_expr         = cast_expr ("++" concat_expr)?

cast_expr        = application_expr ("as" type)*
application_expr = postfix_expr+
postfix_expr     = atom select_step*
select_step      = "." (attr_name | "${" expression "}")
```

All binary operators are left-associative except list concatenation `++`,
which is right-associative. Precedence runs (loosest to tightest)
`||` < `&&` < `==`/`!=` < relational < prefix `!` < `+`/`-` < `*` < `++`, so
`a + 1 < limit && ok || done` parses as
`(((a + 1) < limit) && ok) || done`. `cast_expr` is left-associative:
`expr as A as B` desugars to `(expr as A) as B`. `application_expr` is also
left-associative.

### Atoms

```ebnf
atom = "(" expression ")"
     | attr_set
     | list
     | string_literal
     | float_literal
     | int_literal
     | "true" | "false" | "null"
     | path_literal
     | identifier

attr_set        = "{" attr_item* "}"
attr_item       = inherit_clause | attr_field
inherit_clause  = "inherit" identifier+ ";"
attr_field      = attr_name "=" expression ";"

list            = "[" list_item* "]"
list_item       = if_expr | let_expr | lambda_expr | list_addition
list_addition   = list_cast ("+" list_cast)*
list_cast       = postfix_expr ("as" type)*
```

The list-internal `list_addition` / `list_cast` productions exist because
the outer `expression` cannot be used directly inside `[ ... ]` without
breaking Nix-style space-separated list elements.

## Types

```ebnf
type             = forall_type
                 | conditional_type
                 | function_type

forall_type      = "forall" identifier+ "." type
function_type    = union_type ( ("->" | "%1" "->") type )?
union_type       = application_type ("|" application_type)*
application_type = atom_type+
```

Function arrows are right-associative: `A -> B -> C` parses as `A -> (B -> C)`.

### Conditional types

```ebnf
conditional_type = application_type "extends" application_type
                   "?" type ":" type
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

record_type = "{" record_field* "}"
record_field = attr_name "::" type ";"

type_list = "[" shape_item* "]"
shape_item = atom_type
```

A bare identifier in a type position becomes `TVar` if it starts with a
lowercase letter, otherwise `TCon`. This is how `List a` and `Vec n a` parse
as `TApp (TCon "List") (TVar "a")` and so on without dedicated keywords.

## Lexical Structure

```ebnf
identifier      = ascii_letter (ascii_alphanum | "_" | "'" | "-")*
                  -- minus the reserved words below

attr_name       = identifier | string_literal

reserved        = "true" | "false" | "null" | "let" | "in"
                | "if" | "then" | "else" | "inherit"
                | "type" | "declare" | "import"
                | "as" | "forall" | "extends" | "infer"
                | "any" | "dynamic" | "unknown"
                | "Tuple"

int_literal     = ["-"] digit+
float_literal   = ["-"] digit+ "." digit+ ( ("e"|"E") ["+"|"-"] digit+ )?

string_literal  = double_quoted | indented
double_quoted   = '"' double_quoted_char* '"'
indented        = "''" indented_char* "''"
double_quoted_char = escape_seq | any character except '"' and '\'
escape_seq      = "\\" ( '"' | '\\' | 'n' | 't' | '$' | '/' | other_char )

path_literal    = relative_path | absolute_path | parent_path
relative_path   = "./" path_body
parent_path     = "../" path_body
absolute_path   = "/" path_body
path_body       = path_segment ("/" path_segment)*
path_segment    = (ascii_alphanum | "_" | "-" | ".")+ -- minus ".." alone
```

`attr_name` accepts string literals to support quoted keys such as
`"aarch64-darwin"`. Dynamic keys (`packages.${system}`) are part of the
expression grammar (`select_step`), not the lexer.

## Comments

```ebnf
comment           = line_comment | block_comment
line_comment      = "#" ... <end-of-line>
block_comment     = "/*" ... "*/"
```

Block comments do not nest. Line comments that begin with `# @tnix-ignore`
or `# @tnix-expected` are also picked up by the directive scanner — they
remain ordinary comments to the parser but are attached to the next root
expression or `let` item as a `DiagnosticDirective`. See
[Language Reference: Diagnostic Directives](./language-reference.md#diagnostic-directives).

## Operator Precedence and Associativity

From loosest to tightest binding:

| Level | Form | Associativity |
| --- | --- | --- |
| 1 | `if`, `let`, lambda `pattern :` | (non-applicable) |
| 2 | `\|\|` (boolean or) | left |
| 3 | `&&` (boolean and) | left |
| 4 | `==`, `!=` (equality) | left |
| 5 | `<`, `>`, `<=`, `>=` (relational) | left |
| 6 | `!` (boolean not) | prefix |
| 7 | `+`, `-` (additive) | left |
| 8 | `*` (multiplicative) | left |
| 9 | `++` (list concatenation) | right |
| 10 | `expr as Type` (cast) | left |
| 11 | function application `f x` | left |
| 12 | `.field` and `.${expr}` (postfix select) | left |

Type-level precedence, from loosest to tightest:

| Level | Form | Associativity |
| --- | --- | --- |
| 1 | `forall vars. T` | (binds tightest body) |
| 1 | `T extends P ? A : B` | right |
| 2 | `A -> B`, `A %1 -> B` | right |
| 3 | `` A \| B `` (union) | left |
| 4 | `F X` (type application) | left |
| 5 | `(T)`, record / type-list / literal atoms | — |

## Reserved Words

`true`, `false`, `null`, `let`, `in`, `if`, `then`, `else`, `inherit`,
`type`, `declare`, `import`, `as`, `forall`, `extends`, `infer`, `any`,
`dynamic`, `unknown`, `Tuple`.

Identifiers in the lexer match `identifier` above but are rejected when
they equal one of these. The same set is reserved inside `let`-bindings,
attribute names (where keywords are allowed only when quoted), and
declarations.

## Whitespace and Newlines

Whitespace, line comments, and block comments are skipped between every
token by `sc`. Newlines have no syntactic role outside of comments —
expressions, declarations, and lists can all span multiple lines freely.

## Conformance Notes

- The grammar is implemented with [Megaparsec](https://hackage.haskell.org/package/megaparsec)
  and uses `try` for productions that share a common prefix (`alias_decl`
  vs `ambient_decl`, `let_signature` vs `let_binding`, the typed-pattern
  vs attrset-pattern split).
- `programParser` requires the input to end with `eof`, so unterminated
  expressions are rejected with a structured `ParseError` (see
  [`Parser.hs`](../packages/tnix-core/src/Parser.hs)).
- The integration tests in
  [`Parser.spec.hs`](../packages/tnix-core/src/Parser.spec.hs) double as
  executable examples for every production in this document; if you change
  the grammar, mirror the change there first.

## Not Yet Supported

The parser intentionally accepts a production-ready Nix-shaped subset instead
of the full Nix language. These forms are still outside the supported surface:

- string interpolation in double-quoted and indented strings, including
  `"${expr}"` and `''${expr}''`
- recursive attribute sets with `rec { ... }`
- `with scope; expr`
- attribute-set merging with `//`
- attribute-presence tests with `?`
- assertions with `assert condition; expr`
- nested attribute-path declarations such as `a.b.c = value;`
- Nix's full indented-string indentation stripping and escape rules
