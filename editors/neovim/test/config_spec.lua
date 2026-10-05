local config = require("tynix.config")
local plugin = require("tynix")

local function assert_equal(actual, expected, label)
  if not vim.deep_equal(actual, expected) then
    error(string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function with_temp_tree(files, run)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  for relative, content in pairs(files) do
    local path = root .. "/" .. relative
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
  end

  local ok, result = pcall(run, root)
  vim.fn.delete(root, "rf")
  if not ok then
    error(result)
  end
  return result
end

assert_equal(config.normalize_cmd(nil), { "tynix-lsp" }, "normalize_cmd falls back to tynix-lsp")
assert_equal(config.normalize_cmd(" custom-lsp "), { "custom-lsp" }, "normalize_cmd trims string commands")
assert_equal(config.normalize_cmd({ "custom-lsp", "", " --stdio " }), { "custom-lsp", "--stdio" }, "normalize_cmd compacts argv lists")
assert_equal(config.root_markers(nil), { "flake.nix", "cabal.project", "pnpm-workspace.yaml", "tynix.config.tynix", ".git" }, "root_markers exposes the default workspace markers")
assert_equal(config.root_markers({ "", "flake.nix", "custom.marker" }), { "flake.nix", "custom.marker" }, "root_markers drops blank entries")

with_temp_tree({
  ["flake.nix"] = "{}",
  ["packages/app/main.tynix"] = "1",
  ["custom.marker"] = "",
}, function(root)
  local nested = root .. "/packages/app/main.tynix"
  assert_equal(config.resolve_root_dir(nested, {}), root, "resolve_root_dir finds workspace markers")
  assert_equal(config.resolve_root_dir(nested, { root_markers = { "custom.marker" } }), root, "resolve_root_dir honors custom markers")
  assert_equal(config.resolve_root_dir(nested, { root_dir = root .. "/packages" }), root .. "/packages", "resolve_root_dir honors explicit roots")
  assert_equal(config.resolve_root_dir(nested, { root_dir = function() return root .. "/via-callback" end }), root .. "/via-callback", "resolve_root_dir honors callback roots")

  assert_equal(
    config.server_config(nested, { cmd = { "tynix-lsp", "--stdio" }, cmd_env = { TYNIX_ENV = "1" }, name = "tynix-custom" }),
    {
      name = "tynix-custom",
      cmd = { "tynix-lsp", "--stdio" },
      cmd_env = { TYNIX_ENV = "1" },
      root_dir = root,
    },
    "server_config assembles lsp.start options"
  )
end)

with_temp_tree({
  ["tynix.config.tynix"] = "{}",
  ["src/main.tynix"] = "1",
}, function(root)
  assert_equal(config.resolve_root_dir(root .. "/src/main.tynix", {}), root, "resolve_root_dir treats tynix.config.tynix as a workspace marker")
end)

assert_equal(config.filetypes(nil), { "tynix", "nix" }, "filetypes defaults to tynix and nix")
assert_equal(config.filetypes({ "tynix", " " }), { "tynix" }, "filetypes drops blank entries")

with_temp_tree({
  ["flake.nix"] = "{}",
  ["src/main.tynix"] = "1",
}, function(root)
  local lsp = config.lsp_config({ cmd = "custom-lsp", settings = { tynix = { inlayHints = false } } })
  assert_equal(lsp.cmd, { "custom-lsp" }, "lsp_config normalizes cmd")
  assert_equal(lsp.filetypes, { "tynix", "nix" }, "lsp_config uses default filetypes")
  assert_equal(lsp.settings, { tynix = { inlayHints = false } }, "lsp_config passes settings through")
  local resolved
  lsp.root_dir(root .. "/src/main.tynix", function(dir)
    resolved = dir
  end)
  assert_equal(resolved, root, "lsp_config root_dir callback resolves workspace markers")

  local server = config.server_config(root .. "/src/main.tynix", { init_options = { a = 1 } })
  assert_equal(server.init_options, { a = 1 }, "server_config forwards init_options")
end)

local result = plugin.setup({})
assert_equal(vim.filetype.match({ filename = "demo.tynix" }), "tynix", "setup registers the .tynix filetype")
assert_equal(vim.filetype.match({ filename = "demo.d.tynix" }), "tynix", "setup registers the .d.tynix filetype")

if vim.fn.has("nvim-0.11") == 1 then
  assert_equal(result.lsp, "native", "setup uses vim.lsp.config on 0.11+")
  assert_equal(vim.lsp.config.tynix.cmd, { "tynix-lsp" }, "setup registers the native tynix config")
  assert_equal(vim.lsp.config.tynix.filetypes, { "tynix", "nix" }, "native config carries filetypes")
else
  assert_equal(result.lsp, "autocmd", "setup falls back to vim.lsp.start before 0.11")
end

local fallback = plugin.setup({ native_lsp = false, filetypes = { "tynix" } })
assert_equal(fallback.lsp, "autocmd", "native_lsp = false forces the autocmd path")
local autocmds = vim.api.nvim_get_autocmds({ group = "tynix-lsp", event = "FileType" })
assert_equal(#autocmds, 1, "autocmd path registers exactly one FileType autocmd")
assert_equal(autocmds[1].pattern, "tynix", "autocmd path honors filetypes")

local treesitter = require("tynix.treesitter")
assert_equal(treesitter.install_info.location, "editors/tree-sitter-tynix", "parser install_info points at the grammar")
assert_equal(treesitter.install_info.files, { "src/parser.c", "src/scanner.c" }, "parser install_info lists the sources")
assert_equal(#vim.api.nvim_get_runtime_file("queries/tynix/highlights.scm", true) > 0, true, "highlight queries ship on the runtimepath")

-- Detach the language server before opening tynix buffers so the spec does not
-- require tynix-lsp on PATH.
if vim.fn.has("nvim-0.11") == 1 then
  vim.lsp.enable("tynix", false)
end
pcall(vim.api.nvim_del_augroup_by_name, "tynix-lsp")

-- ftplugin
vim.cmd("filetype plugin on")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "tynix"
assert_equal(vim.bo[buf].commentstring, "# %s", "ftplugin sets commentstring")
assert_equal(vim.bo[buf].shiftwidth, 2, "ftplugin sets shiftwidth")

-- :checkhealth tynix
if vim.fn.has("nvim-0.10") == 1 then
  vim.cmd("checkhealth tynix")
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert_equal(report:find("Executables", 1, true) ~= nil, true, "checkhealth tynix renders the executables section")
  assert_equal(report:find("Tree-sitter", 1, true) ~= nil, true, "checkhealth tynix renders the tree-sitter section")
  assert_equal(report:find("ERROR: Failed to run healthcheck", 1, true), nil, "checkhealth tynix runs without crashing")
end

print("tynix neovim config_spec: ok")
