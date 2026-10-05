# tynix for Neovim

A Neovim plugin for tynix:

- `tynix` filetype for `.tynix` and `.d.tynix` (`ftdetect/`), with an
  `ftplugin` (`commentstring = "# %s"`, 2-space indent, `-`/`'` in keywords)
- `tynix-lsp` setup through `vim.lsp.config` / `vim.lsp.enable` on Neovim 0.11+,
  falling back to `vim.lsp.start` on 0.10 (and best-effort on older releases)
- tree-sitter highlighting, folds, indents, injections, locals, and
  textobjects via [`tree-sitter-tynix`](../tree-sitter-tynix)
- `:checkhealth tynix`

## Requirements

- Neovim 0.10+ (0.11+ recommended).
- The `tynix-lsp` binary on your `PATH`:

  ```bash
  curl -fsSL https://tynix.dev/install.sh | sh
  # or
  nix profile install github:ubugeeei/tynix#tynix-lsp
  tynix-lsp --version
  ```

- Optional: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
  to install the parser with `:TSInstall tynix`.

## Install

The plugin lives in the `editors/neovim` directory of the repository.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ubugeeei/tynix",
  config = function(plugin)
    vim.opt.rtp:append(plugin.dir .. "/editors/neovim")
    require("tynix").setup()
  end,
}
```

Or manually:

```lua
vim.opt.runtimepath:append("/path/to/tynix/editors/neovim")
require("tynix").setup()
```

## Tree-sitter

`setup()` registers the `tynix` parser with nvim-treesitter (both the `master`
and `main` branches) and starts tree-sitter highlighting for `tynix` buffers
once the parser is installed. Queries ship in this plugin's `queries/tynix/`.

```vim
:TSInstall tynix
```

Without nvim-treesitter, compile the parser yourself and point the plugin at
it:

```bash
cd /path/to/tynix/editors/tree-sitter-tynix
cc -shared -fPIC -O2 -I src src/parser.c src/scanner.c -o tynix.so
```

```lua
require("tynix").setup({ treesitter = { parser_path = "/path/to/tynix.so" } })
```

Use `require("tynix").setup_treesitter()` to register only the parser, or
`setup({ treesitter = false })` to skip it.

## Configuration

`setup` accepts an options table:

```lua
require("tynix").setup({
  -- Filetypes the server attaches to. Defaults to { "tynix", "nix" }.
  -- Use { "tynix" } to leave plain .nix files to another Nix LSP.
  filetypes = { "tynix", "nix" },

  -- Override the server command (string or argv list).
  cmd = { "tynix-lsp" },

  -- Extra environment for the server process.
  cmd_env = {},

  -- Project-root markers, or a string / function for custom layouts.
  -- Defaults to flake.nix, cabal.project, pnpm-workspace.yaml,
  -- tynix.config.tynix, and .git.
  root_markers = { "flake.nix", "tynix.config.tynix", ".git" },

  -- LSP initializationOptions and workspace/configuration settings.
  init_options = {},
  settings = { tynix = {} },

  -- false: use the FileType + vim.lsp.start path even on 0.11+.
  native_lsp = true,

  -- false: skip LSP setup (e.g. when another plugin manages tynix-lsp).
  lsp = true,

  -- false to skip, or { parser_path = "...", highlight = true }.
  treesitter = {},
})
```

On 0.11+ the server is registered as `vim.lsp.config.tynix`, so you can also
tweak it with `vim.lsp.config("tynix", { ... })` after `setup()`.

## Health check

```vim
:checkhealth tynix
```

reports the Neovim version, whether `tynix-lsp` / `tynix` are on `PATH` (with
their versions), parser and query availability, and running clients.

## Tests

From the repository root:

```bash
nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/config_spec.lua

# parser + query smoke test (needs a compiled parser)
cc -shared -fPIC -O2 -I editors/tree-sitter-tynix/src \
  editors/tree-sitter-tynix/src/parser.c editors/tree-sitter-tynix/src/scanner.c -o "$TMPDIR/tynix.so"
TYNIX_PARSER="$TMPDIR/tynix.so" nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/treesitter_spec.lua
```

`queries/tynix/*.scm` are generated from `editors/tree-sitter-tynix/queries`;
run `node editors/tree-sitter-tynix/scripts/sync-queries.mjs` after editing
those.

## Troubleshooting

- Run `:checkhealth tynix`.
- Confirm `tynix-lsp --version` works in the shell Neovim inherits.
- Check `:LspInfo` (or `:checkhealth vim.lsp`) and `:messages` for the
  resolved command and any start error.
- If another Nix language server already owns `.nix`, set
  `filetypes = { "tynix" }` to avoid attaching two servers.

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
