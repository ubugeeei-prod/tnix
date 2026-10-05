# tynix for Zed

A [Zed](https://zed.dev) extension for tynix: tree-sitter syntax highlighting
for `.tynix` / `.d.tynix` files (via [`tree-sitter-tynix`](../tree-sitter-tynix))
plus the `tynix-lsp` language server for diagnostics, hover, completion, and
navigation.

## Features

- Highlighting for full Nix syntax and the tynix type layer: `type` aliases,
  `declare` blocks, `name :: Type;` signatures, `(x :: T):` binders,
  `expr as T` casts, type constructors / variables / literal types, and
  `# @tynix-ignore` / `# @tynix-expected` directives
- Bracket matching (including `${ }`, `"..."`, `''...''`), auto-indent,
  outline (type aliases, declarations, bindings), and text objects
- Bash injection inside `buildPhase`/`installPhase`/`shellHook`/... and
  `writeShellScript` strings
- `tynix-lsp` attached to `.tynix` / `.d.tynix` and to plain `.nix` buffers owned
  by Zed's Nix extension

## Requirements

Install `tynix-lsp` and make sure it is on your `PATH`:

```bash
curl -fsSL https://tynix.dev/install.sh | sh
# or
nix profile install github:ubugeeei/tynix#tynix-lsp
tynix-lsp --version
```

The extension also checks common Nix profile locations
(`~/.nix-profile/bin`, `/run/current-system/sw/bin`, ...).

## Install (dev extension)

1. Open Zed.
2. Run **zed: install dev extension** from the command palette.
3. Select the `editors/zed` directory in this repository.

Zed compiles the extension (Rust to WebAssembly) and the tree-sitter grammar
referenced in `extension.toml`.

### Grammar pin

`extension.toml` fetches the grammar from this repository at a pinned commit
(`[grammars.tynix]`, `path = "editors/tree-sitter-tynix"`). The pin must point
at a commit that contains `editors/tree-sitter-tynix`; bump `rev` whenever the
grammar changes. To build against a local checkout, temporarily set:

```toml
[grammars.tynix]
repository = "file:///absolute/path/to/tynix"
rev = "<local commit sha>"
path = "editors/tree-sitter-tynix"
```

## Settings

```jsonc
// ~/.config/zed/settings.json
{
  "lsp": {
    "tynix-lsp": {
      "binary": { "path": "/path/to/tynix-lsp", "arguments": [] },
      // forwarded as LSP initializationOptions
      "initialization_options": {},
      // answered for workspace/configuration (wrapped as { "tynix": ... }
      // unless already namespaced)
      "settings": {}
    }
  }
}
```

## File association

The `tynix` language owns the `tynix` suffix (so `.d.tynix` is included). Plain
`.nix` files keep using Zed's Nix extension for highlighting, and `tynix-lsp`
attaches to them as an additional language server. To stop that, remove
`"Nix"` from `language_servers.tynix-lsp.languages` in a local build, or
disable the server for Nix in your settings:

```jsonc
{ "languages": { "Nix": { "language_servers": ["!tynix-lsp", "..."] } } }
```

## Building / developing

```bash
cargo build --manifest-path editors/zed/Cargo.toml
cargo test  --manifest-path editors/zed/Cargo.toml
# validate the Zed queries against the grammar (needs the tree-sitter CLI)
node editors/tree-sitter-tynix/scripts/check-queries.mjs
```

Queries live in `languages/tynix/*.scm` and use Zed capture names
(`@keyword`, `@type`, `@type.builtin`, `@property`, `@string.special`,
`@preproc`, `@embedded`, ...). Later patterns take precedence over earlier
ones.

## Troubleshooting

- Confirm `tynix-lsp --version` runs in your shell.
- Check Zed's language-server logs (**dev: open language server logs**).
- If highlighting is missing, check **zed: open log** for grammar compilation
  errors (usually a `rev` that does not contain the grammar).

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
