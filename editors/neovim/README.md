# tnix for Neovim

A Neovim plugin for tnix:

- `tnix` filetype for `.tnix` and `.d.tnix` (`ftdetect/`), with an
  `ftplugin` (`commentstring = "# %s"`, 2-space indent, `-`/`'` in keywords)
- `tnix-lsp` setup through `vim.lsp.config` / `vim.lsp.enable` on Neovim 0.11+,
  falling back to `vim.lsp.start` on 0.10 (and best-effort on older releases)
- tree-sitter highlighting, folds, indents, injections, locals, and
  textobjects via [`tree-sitter-tnix`](../tree-sitter-tnix)
- `:checkhealth tnix`

## Requirements

- Neovim 0.10+ (0.11+ recommended).
- The `tnix-lsp` binary on your `PATH`:

  ```bash
  curl -fsSL https://tnix.dev/install.sh | sh
  # or
  nix profile install github:ubugeeei/tnix#tnix-lsp
  tnix-lsp --version
  ```

- Optional: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
  to install the parser with `:TSInstall tnix`.

## Install

The plugin lives in the `editors/neovim` directory of the repository.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ubugeeei/tnix",
  config = function(plugin)
    vim.opt.rtp:append(plugin.dir .. "/editors/neovim")
    require("tnix").setup()
  end,
}
```

Or manually:

```lua
vim.opt.runtimepath:append("/path/to/tnix/editors/neovim")
require("tnix").setup()
```

## Tree-sitter

`setup()` registers the `tnix` parser with nvim-treesitter (both the `master`
and `main` branches) and starts tree-sitter highlighting for `tnix` buffers
once the parser is installed. Queries ship in this plugin's `queries/tnix/`.

```vim
:TSInstall tnix
```

Without nvim-treesitter, compile the parser yourself and point the plugin at
it:

```bash
cd /path/to/tnix/editors/tree-sitter-tnix
cc -shared -fPIC -O2 -I src src/parser.c src/scanner.c -o tnix.so
```

```lua
require("tnix").setup({ treesitter = { parser_path = "/path/to/tnix.so" } })
```

Use `require("tnix").setup_treesitter()` to register only the parser, or
`setup({ treesitter = false })` to skip it.

## Configuration

`setup` accepts an options table:

```lua
require("tnix").setup({
  -- Filetypes the server attaches to. Defaults to { "tnix", "nix" }.
  -- Use { "tnix" } to leave plain .nix files to another Nix LSP.
  filetypes = { "tnix", "nix" },

  -- Override the server command (string or argv list).
  cmd = { "tnix-lsp" },

  -- Extra environment for the server process.
  cmd_env = {},

  -- Project-root markers, or a string / function for custom layouts.
  -- Defaults to flake.nix, cabal.project, pnpm-workspace.yaml,
  -- tnix.config.tnix, and .git.
  root_markers = { "flake.nix", "tnix.config.tnix", ".git" },

  -- LSP initializationOptions and workspace/configuration settings.
  init_options = {},
  settings = { tnix = {} },

  -- false: use the FileType + vim.lsp.start path even on 0.11+.
  native_lsp = true,

  -- false: skip LSP setup (e.g. when another plugin manages tnix-lsp).
  lsp = true,

  -- false to skip, or { parser_path = "...", highlight = true }.
  treesitter = {},
})
```

On 0.11+ the server is registered as `vim.lsp.config.tnix`, so you can also
tweak it with `vim.lsp.config("tnix", { ... })` after `setup()`.

## Health check

```vim
:checkhealth tnix
```

reports the Neovim version, whether `tnix-lsp` / `tnix` are on `PATH` (with
their versions), parser and query availability, and running clients.

## Tests

From the repository root:

```bash
nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/config_spec.lua

# parser + query smoke test (needs a compiled parser)
cc -shared -fPIC -O2 -I editors/tree-sitter-tnix/src \
  editors/tree-sitter-tnix/src/parser.c editors/tree-sitter-tnix/src/scanner.c -o "$TMPDIR/tnix.so"
TNIX_PARSER="$TMPDIR/tnix.so" nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/treesitter_spec.lua
```

`queries/tnix/*.scm` are generated from `editors/tree-sitter-tnix/queries`;
run `node editors/tree-sitter-tnix/scripts/sync-queries.mjs` after editing
those.

## Troubleshooting

- Run `:checkhealth tnix`.
- Confirm `tnix-lsp --version` works in the shell Neovim inherits.
- Check `:LspInfo` (or `:checkhealth vim.lsp`) and `:messages` for the
  resolved command and any start error.
- If another Nix language server already owns `.nix`, set
  `filetypes = { "tnix" }` to avoid attaching two servers.

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
