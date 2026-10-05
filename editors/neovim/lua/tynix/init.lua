local M = {}
local config = require("tynix.config")

---Options passed to the most recent `setup()` call (read by `:checkhealth tynix`).
M.options = nil

---Register the `tynix` filetype for `.tynix` and `.d.tynix` files.
---
---`ftdetect/tynix.lua` does the same at startup; calling it again from `setup`
---keeps `-u NONE` / manual runtimepath setups working.
function M.register_filetype()
  vim.filetype.add({
    extension = { tynix = "tynix" },
    pattern = { [".*%.d%.tynix"] = "tynix" },
  })
end

---Whether the native `vim.lsp.config` / `vim.lsp.enable` API (Neovim 0.11+)
---should be used.
---@param opts table
---@return boolean
function M.use_native_lsp(opts)
  if opts.native_lsp == false then
    return false
  end
  return type(vim.lsp.config) ~= "nil" and type(vim.lsp.enable) == "function"
end

local function setup_lsp(opts)
  if M.use_native_lsp(opts) then
    local name = opts.name or "tynix"
    vim.lsp.config(name, config.lsp_config(opts))
    vim.lsp.enable(name)
    return "native"
  end

  -- Neovim < 0.11 (or `native_lsp = false`): start the client per buffer.
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("tynix-lsp", { clear = true }),
    pattern = config.filetypes(opts.filetypes),
    callback = function(ev)
      vim.lsp.start(config.server_config(ev.buf, opts))
    end,
  })
  return "autocmd"
end

---Configure tynix for Neovim.
---
---Options:
---  filetypes     string[]   filetypes tynix-lsp attaches to (default { "tynix", "nix" })
---  cmd           string|string[]  server command (default { "tynix-lsp" })
---  cmd_env       table      extra environment for the server
---  root_markers  string[]   project-root markers
---  root_dir      string|fun(source): string  explicit root
---  init_options  table      LSP initializationOptions
---  settings      table      workspace/configuration settings (e.g. { tynix = { ... } })
---  name          string     client/config name (default "tynix" natively, "tynix-lsp" otherwise)
---  native_lsp    boolean    set false to force the pre-0.11 autocmd path
---  lsp           boolean    set false to skip language-server setup entirely
---  treesitter    boolean|table  false to skip; table is passed to
---                           `require("tynix.treesitter").register` ({ parser_path, highlight })
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.options = opts

  M.register_filetype()

  local result = { lsp = nil, treesitter = nil }

  if opts.lsp ~= false then
    result.lsp = setup_lsp(opts)
  end

  if opts.treesitter ~= false then
    local ts_opts = type(opts.treesitter) == "table" and opts.treesitter or {}
    result.treesitter = require("tynix.treesitter").register(ts_opts)
  end

  return result
end

---Register the tree-sitter parser without touching LSP configuration.
---@param opts table|nil
function M.setup_treesitter(opts)
  M.register_filetype()
  return require("tynix.treesitter").register(opts)
end

return M
