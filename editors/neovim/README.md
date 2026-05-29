# tnix for Neovim

A small Neovim plugin that starts the `tnix-lsp` language server for `.tnix`,
`.d.tnix`, and (by default) `.nix` files, giving you diagnostics, hover, and
completion on top of existing Nix code.

## Requirements

- Neovim with `vim.lsp.start` and `vim.fs.root` (Neovim 0.10+).
- The `tnix-lsp` binary on your `PATH`:

  ```bash
  nix profile install github:ubugeeei/tnix#tnix-lsp
  tnix-lsp --version
  ```

## Install

Add the `editors/neovim` directory to your `runtimepath` and call `setup`.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ubugeeei/tnix",
  config = function()
    require("tnix").setup()
  end,
}
```

Or manually:

```lua
vim.opt.runtimepath:append("/path/to/tnix/editors/neovim")
require("tnix").setup()
```

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
})
```

## Troubleshooting

- Confirm `tnix-lsp --version` works in the shell Neovim inherits.
- Check `:LspInfo` and `:messages` for the resolved command and any start error.
- If another Nix language server already owns `.nix`, set
  `filetypes = { "tnix" }` to avoid attaching two servers.

See [docs/troubleshooting.md](../../docs/troubleshooting.md) for more.
