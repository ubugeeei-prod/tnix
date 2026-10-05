# tnix for Zed

A [Zed](https://zed.dev) extension for tnix: tree-sitter syntax highlighting
for `.tnix` / `.d.tnix` files (via [`tree-sitter-tnix`](../tree-sitter-tnix))
plus the `tnix-lsp` language server for diagnostics, hover, completion, and
navigation.

## Features

- Highlighting for full Nix syntax and the tnix type layer: `type` aliases,
  `declare` blocks, `name :: Type;` signatures, `(x :: T):` binders,
  `expr as T` casts, type constructors / variables / literal types, and
  `# @tnix-ignore` / `# @tnix-expected` directives
- Bracket matching (including `${ }`, `"..."`, `''...''`), auto-indent,
  outline (type aliases, declarations, bindings), and text objects
- Bash injection inside `buildPhase`/`installPhase`/`shellHook`/... and
  `writeShellScript` strings
- `tnix-lsp` attached to `.tnix` / `.d.tnix` and to plain `.nix` buffers owned
  by Zed's Nix extension

## Requirements

Install `tnix-lsp` and make sure it is on your `PATH`:

```bash
curl -fsSL https://tnix.dev/install.sh | sh
# or
nix profile install github:ubugeeei/tnix#tnix-lsp
tnix-lsp --version
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
(`[grammars.tnix]`, `path = "editors/tree-sitter-tnix"`). The pin must point
at a commit that contains `editors/tree-sitter-tnix`; bump `rev` whenever the
grammar changes. To build against a local checkout, temporarily set:

```toml
[grammars.tnix]
repository = "file:///absolute/path/to/tnix"
rev = "<local commit sha>"
path = "editors/tree-sitter-tnix"
```

## Settings

```jsonc
// ~/.config/zed/settings.json
{
  "lsp": {
    "tnix-lsp": {
      "binary": { "path": "/path/to/tnix-lsp", "arguments": [] },
      // forwarded as LSP initializationOptions
      "initialization_options": {},
      // answered for workspace/configuration (wrapped as { "tnix": ... }
      // unless already namespaced)
      "settings": {}
    }
  }
}
```

## File association

The `tnix` language owns the `tnix` suffix (so `.d.tnix` is included). Plain
`.nix` files keep using Zed's Nix extension for highlighting, and `tnix-lsp`
attaches to them as an additional language server. To stop that, remove
`"Nix"` from `language_servers.tnix-lsp.languages` in a local build, or
disable the server for Nix in your settings:

```jsonc
{ "languages": { "Nix": { "language_servers": ["!tnix-lsp", "..."] } } }
```

## Building / developing

```bash
cargo build --manifest-path editors/zed/Cargo.toml
cargo test  --manifest-path editors/zed/Cargo.toml
# validate the Zed queries against the grammar (needs the tree-sitter CLI)
node editors/tree-sitter-tnix/scripts/check-queries.mjs
```

Queries live in `languages/tnix/*.scm` and use Zed capture names
(`@keyword`, `@type`, `@type.builtin`, `@property`, `@string.special`,
`@preproc`, `@embedded`, ...). Later patterns take precedence over earlier
ones.

## Troubleshooting

- Confirm `tnix-lsp --version` runs in your shell.
- Check Zed's language-server logs (**dev: open language server logs**).
- If highlighting is missing, check **zed: open log** for grammar compilation
  errors (usually a `rev` that does not contain the grammar).

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
