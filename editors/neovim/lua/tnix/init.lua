local M = {}
local config = require("tnix.config")

function M.setup(opts)
  opts = opts or {}

  vim.filetype.add({
    extension = { tnix = "tnix" },
    pattern = { [".*%.d%.tnix"] = "tnix" },
  })

  -- Attach to `.tnix` and, by default, plain `.nix` files so tnix-lsp provides
  -- ambient typing/diagnostics on existing Nix code (matching the VS Code
  -- extension, which activates on `nix`). Override with `filetypes` to opt out
  -- of `.nix`, e.g. `require("tnix").setup({ filetypes = { "tnix" } })`.
  local filetypes = opts.filetypes
  if type(filetypes) ~= "table" or vim.tbl_isempty(filetypes) then
    filetypes = { "tnix", "nix" }
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = filetypes,
    callback = function(ev)
      vim.lsp.start(config.server_config(ev.buf, opts))
    end,
  })
end

return M
