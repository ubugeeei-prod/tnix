# tnix for Zed

A [Zed](https://zed.dev) extension that runs the `tnix-lsp` language server for
tnix, providing diagnostics, hover, and completion.

## Requirements

The extension launches `tnix-lsp` from your `PATH`. Install it first:

```bash
nix profile install github:ubugeeei/tnix#tnix-lsp
tnix-lsp --version
```

## Install

This extension is built as a dev extension from the repository:

1. Open Zed.
2. Run **zed: install dev extension** from the command palette.
3. Select the `editors/zed` directory in this repository.

Zed compiles the extension (Rust → WebAssembly) and registers the `tnix`
language and the `tnix-lsp` language server.

## File association

The extension registers the `tnix` language for both `.tnix` and `.nix`
suffixes (see `languages/tnix/config.toml`) and uses the tree-sitter Nix
grammar for syntax highlighting. If you already use another Nix extension in
Zed, the language association for `.nix` is resolved by Zed's extension
precedence; scope tnix to `.tnix` by editing `path_suffixes` in a local build
if you prefer to keep `.nix` on the other extension.

## Building / developing

```bash
cargo build --manifest-path editors/zed/Cargo.toml
cargo test  --manifest-path editors/zed/Cargo.toml
```

The extension version tracks the tnix toolchain release (currently `0.5.0`) in
both `extension.toml` and `Cargo.toml`.

## Troubleshooting

- Confirm `tnix-lsp --version` runs in your shell.
- Check Zed's language-server logs (**dev: open language server logs**).

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
