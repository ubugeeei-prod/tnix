# tree-sitter-tnix

A [tree-sitter](https://tree-sitter.github.io/) grammar for **tnix**: full Nix
syntax plus the tnix type layer. It powers syntax highlighting, folding,
indentation, outlines, and text objects in Zed and Neovim.

## Coverage

Nix (node names follow
[nix-community/tree-sitter-nix](https://github.com/nix-community/tree-sitter-nix)
where possible, so existing Nix queries are easy to port):

- comments (`#`, `/* */`), integers, floats, URIs
- `"..."` and `''...''` strings with `${}` interpolation and every escape
  (`\x`, `\$`, `$${`, `'''`, `''$`, `''\x`)
- paths: `./a`, `../a`, `/a`, `a/b`, `~/a`, `<nixpkgs>`, `./dir/${name}.nix`
- `let ... in`, `let { }`, `rec { }`, `with`, `assert`, `if`, `inherit`,
  `inherit (e) ...`, attrpath bindings (`a.b."c".${d} = ...;`)
- lambdas: `x: ...`, `{ a, b ? 1, ... }@args: ...`, `args@{ ... }: ...`
- every operator, including `//`, `++`, `->`, `?`, `|>` and `<|`, and
  `a.b or default`

tnix additions:

- `type Name params = Type;` aliases and `declare "path" { name :: Type; };`
  blocks (string or path literal)
- `name :: Type;` signatures inside `let` and attribute sets
- typed binders `(x :: Type): body` and `expr as Type` casts
- types: `forall a b. T`, `Ctx a => T`, `A -> B`, `A %1 -> B`, unions,
  record types, string / number / boolean literal types, conditional types
  `A extends B ? C : D` with `infer x`, type application, type lists
  (`Tuple [Int String]`, `Tensor [2 3] Float`), and `any` / `dynamic` /
  `unknown`
- `# @tnix-ignore` / `# @tnix-expected` directive comments are a separate
  `directive` node so they can be highlighted differently from comments

## Layout

```
grammar.js            grammar definition
src/scanner.c         external scanner (string fragments and paths)
src/parser.c          generated parser (committed; ABI 14)
queries/*.scm         canonical queries (nvim-treesitter capture names)
test/corpus/*.txt     corpus tests for `tree-sitter test`
examples/             extra parse samples
scripts/              corpus / query maintenance helpers
```

The Zed extension keeps its own queries in `editors/zed/languages/tnix/`
(Zed capture names). Neovim uses copies of `queries/` under
`editors/neovim/queries/tnix/`.

## Development

Requires the [`tree-sitter` CLI](https://github.com/tree-sitter/tree-sitter/tree/master/cli)
(any version from 0.20.7 works; `src/` is generated with ABI 14 so Zed and
Neovim 0.9+ can load it).

```bash
cd editors/tree-sitter-tnix
tree-sitter generate --no-bindings   # after editing grammar.js
tree-sitter test                     # corpus tests
node scripts/parse-corpus.mjs        # parse every .tnix/.nix file in the repo, fail on ERROR
node scripts/check-queries.mjs       # compile grammar, Neovim, and Zed queries against the grammar
node scripts/sync-queries.mjs        # copy queries/ to editors/neovim/queries/tnix
node scripts/sync-queries.mjs --check
```

The same commands are available as `npm run generate|test|parse-corpus|sync-queries|check-queries`.

To try the parser in Neovim without nvim-treesitter:

```bash
cc -shared -fPIC -O2 -I src src/parser.c src/scanner.c -o tnix.so
```

then `require("tnix").setup({ treesitter = { parser_path = "/path/to/tnix.so" } })`.

## Releasing

Zed fetches the grammar by commit: after changing `grammar.js` (and
regenerating `src/`), bump `rev` under `[grammars.tnix]` in
`editors/zed/extension.toml` to a commit that contains the change.
