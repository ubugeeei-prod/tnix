# tnix-lsp

Language server for tnix. Speaks LSP 3.17 over stdio (`tnix-lsp --stdio`,
optionally `--log-file PATH`).

## Architecture

| Layer | Module(s) | Role |
| --- | --- | --- |
| Protocol | `ServerProtocol`, `ServerUri`, `app/Main.hs` | framing, URIs, reader thread + worker queue, cancellation, debounce |
| Documents | `SessionDocuments`, `AnalysisCache` | open buffers, last good analysis, LRU analysis cache |
| Scanner | `SessionScan` | error-tolerant tokens, brackets, binders, scopes, references, doc comments |
| Resolver | `SessionResolve` | types for names in scope (signatures, owning function, `import` + `declare`, registry aliases) |
| Features | `SessionCompletion`, `SessionHover`, `SessionNavigation`, `SessionPublish`, `SessionSemanticTokens`, … | individual LSP features |
| Handlers | `Session` | request → feature glue, with the earlier text-based implementations kept as fallbacks |

The scanner does not depend on the core AST, so positional features keep
working while the buffer does not parse and are unaffected by AST changes in
`tnix-core`. Type information comes from the checker's `Analysis` (the last
successful one is reused while the buffer is broken).

## Capabilities

### Completion (`textDocument/completion`, `completionItem/resolve`)

Context-aware; triggered on `.` and `/`.

- **Member access** `expr.` lists the fields of the expression's record type,
  with the field type as `detail`. Works for `builtins.`, for names bound to
  `import ./file.nix` (typed by a `declare "./file.nix" { … }` block anywhere
  in the workspace), for lambda parameters and destructured pattern fields
  (typed from the signature of the function they belong to), and for
  `lib` / `pkgs` / `stdenv` arguments when the registry aliases `NixpkgsLib` /
  `NixpkgsPkgs` / `NixpkgsStdenv` are loaded. Without a type, the keys of an
  attrset literal are offered.
- **Names in scope**: `let` bindings, lambda parameters, pattern fields and
  `rec` fields visible at the cursor (innermost first), then root bindings,
  `builtins`, `import`, keywords, and snippets (`let … in`,
  `if … then … else`, `{ … }:` lambda, package skeleton, `declare` block,
  `type` alias, signature + binding).
- **Type positions** (after `::`, `as`, inside `type X = …`, `declare` blocks):
  builtin type constructors, aliases (local and from declaration files),
  type parameters in scope, and `forall` / `infer` / `dynamic` / `any` / `unknown`.
- **Expected-record keys**: inside `{ }` passed to a function with a record
  parameter, bound to a name with a record signature, or used as a lambda
  pattern for a typed function, the missing fields are offered (`name = $1;`
  for attrsets, bare names for patterns).
- **Paths**: inside `./`, `../`, `/`, `~/` literals, directory entries.
- Items carry `detail` (type), `labelDetails`, markdown `documentation` from
  `#` comments above the declaration (or the `declare` entry), a relevance
  `sortText`, and a `textEdit` covering exactly the identifier being typed.
  Lists larger than 150 items omit documentation; `completionItem/resolve`
  fills it in.

### Diagnostics

- Published on open/save immediately and on change after a 200 ms debounce
  (one analysis per typing burst). Clients that declare
  `textDocument.diagnostic` get `diagnosticProvider` instead and pull via
  `textDocument/diagnostic`.
- Every diagnostic has `source: "tnix"`, the stable `code`, and
  `codeDescription.href = https://tnix.dev/reference/diagnostics#<code>`
  (lower-case code). Severity: errors, except `TC0006` (unused
  `@tnix-expected`) which is a warning.
- Ranges are token-accurate: parser/checker `line:col` coordinates when the
  message has them, otherwise the token the message names (an unbound
  reference, the `.field` of a missing field, the duplicate key), otherwise the
  smallest binding value whose replacement by `(null as any)` makes the error
  go away (re-checked in the background).
- `relatedInformation`: the declaration of a "did you mean" suggestion, the
  declaration of the selected value for missing fields, and the signature that
  set the expected type for type mismatches. Suggestions are appended to the
  message (`Did you mean \`greet\`?`).
- Lint hints from the scanner (work even when analysis fails):

  | Code | Meaning | Tags |
  | --- | --- | --- |
  | `TL0001` | unused `let` binding, `inherit`, lambda parameter, pattern field, or `@` alias (names starting with `_` are exempt) | `Unnecessary` |
  | `TL0002` | use of a binding or `builtins` member whose doc comment contains `@deprecated [reason]` | `Deprecated` |

  These `TLxxxx` codes belong to the language server and are documented in the
  "Language Server Lints" section of `docs/diagnostics.md`.

### Code actions

- `# @tnix-ignore` / `# @tnix-expected` above the offending line.
- "Did you mean …?" for unbound names (scope-aware candidates) and missing
  fields (fields of the record in the message), best match preferred.
- Add a missing field to a local attrset literal.
- Remove an unused `let` binding (and its signature), prefix an unused
  parameter with `_`, remove an unused pattern field.
- `refactor.rewrite`: insert the inferred type signature above an
  unannotated `let` binding.

### Navigation

- **Hover**: markdown card with kind, name, and type, followed by the
  documentation comment; keywords, type aliases, type parameters, builtin
  types, and path literals are explained too.
- **Signature help** for curried calls with active parameter, parameter
  names (from `f = a: b: …`), and documentation.
- **Definition**: scope-aware for locals (including lambda parameters and
  shadowing), path literals open the file (`default.nix` for directories),
  `m.name` for `m = import ./file.nix` jumps to the `declare` entry or the
  binding in the imported file, `builtins.x` jumps into `builtins.d.tnix`,
  then workspace symbols.
- **References / highlights / rename / prepareRename**: scope-aware for local
  symbols and type aliases (field selections, attribute keys, strings, and
  comments are never touched); member names fall back to workspace-wide
  text search.
- **Document symbols**: hierarchical (`DocumentSymbol[]` with type details)
  when the client supports it — aliases, `declare` blocks and entries, `let`
  bindings, nested attribute fields; flat otherwise. **Workspace symbols**
  across `.tnix` / `.d.tnix` files.
- **Selection ranges**, **folding ranges**, **document links**.

### Semantic tokens (`full` and `range`)

Legend (indices are stable): `keyword type function variable property string
number operator parameter typeParameter comment namespace decorator`;
modifiers `declaration readonly defaultLibrary deprecated`. Type names vs. type
parameters inside annotations, functions by inferred/declared type, parameters,
attribute keys and selected fields as properties, `builtins` / `import` as
default-library, `# @tnix-…` directives as decorators. Multi-line strings and
comments are split per line.

### Other

- **Inlay hints**: inferred types after unannotated root `let` bindings.
- **Formatting**: whole-document re-render through the core pretty printer,
  applied only when it round-trips and the document has no comments (the AST
  does not keep them); otherwise a no-op.
- **Robustness**: one crashing handler answers with an internal error and the
  server keeps running; `$/cancelRequest` cancels queued requests
  (`RequestCancelled`); edits to unparsable buffers keep completion, hover, and
  navigation working from the scanner and the last good analysis.

## Development

```sh
cabal build tnix-lsp
cabal test tnix-lsp
```

`test/SessionFeatures.spec.hs` drives the feature handlers end to end
against the real checker on temporary workspaces.
