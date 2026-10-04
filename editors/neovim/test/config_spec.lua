local config = require("tnix.config")
local plugin = require("tnix")

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

assert_equal(config.normalize_cmd(nil), { "tnix-lsp" }, "normalize_cmd falls back to tnix-lsp")
assert_equal(config.normalize_cmd(" custom-lsp "), { "custom-lsp" }, "normalize_cmd trims string commands")
assert_equal(config.normalize_cmd({ "custom-lsp", "", " --stdio " }), { "custom-lsp", "--stdio" }, "normalize_cmd compacts argv lists")
assert_equal(config.root_markers(nil), { "flake.nix", "cabal.project", "pnpm-workspace.yaml", "tnix.config.tnix", ".git" }, "root_markers exposes the default workspace markers")
assert_equal(config.root_markers({ "", "flake.nix", "custom.marker" }), { "flake.nix", "custom.marker" }, "root_markers drops blank entries")

with_temp_tree({
  ["flake.nix"] = "{}",
  ["packages/app/main.tnix"] = "1",
  ["custom.marker"] = "",
}, function(root)
  local nested = root .. "/packages/app/main.tnix"
  assert_equal(config.resolve_root_dir(nested, {}), root, "resolve_root_dir finds workspace markers")
  assert_equal(config.resolve_root_dir(nested, { root_markers = { "custom.marker" } }), root, "resolve_root_dir honors custom markers")
  assert_equal(config.resolve_root_dir(nested, { root_dir = root .. "/packages" }), root .. "/packages", "resolve_root_dir honors explicit roots")
  assert_equal(config.resolve_root_dir(nested, { root_dir = function() return root .. "/via-callback" end }), root .. "/via-callback", "resolve_root_dir honors callback roots")

  assert_equal(
    config.server_config(nested, { cmd = { "tnix-lsp", "--stdio" }, cmd_env = { TNIX_ENV = "1" }, name = "tnix-custom" }),
    {
      name = "tnix-custom",
      cmd = { "tnix-lsp", "--stdio" },
      cmd_env = { TNIX_ENV = "1" },
      root_dir = root,
    },
    "server_config assembles lsp.start options"
  )
end)

with_temp_tree({
  ["tnix.config.tnix"] = "{}",
  ["src/main.tnix"] = "1",
}, function(root)
  assert_equal(config.resolve_root_dir(root .. "/src/main.tnix", {}), root, "resolve_root_dir treats tnix.config.tnix as a workspace marker")
end)

assert_equal(config.filetypes(nil), { "tnix", "nix" }, "filetypes defaults to tnix and nix")
assert_equal(config.filetypes({ "tnix", " " }), { "tnix" }, "filetypes drops blank entries")

with_temp_tree({
  ["flake.nix"] = "{}",
  ["src/main.tnix"] = "1",
}, function(root)
  local lsp = config.lsp_config({ cmd = "custom-lsp", settings = { tnix = { inlayHints = false } } })
  assert_equal(lsp.cmd, { "custom-lsp" }, "lsp_config normalizes cmd")
  assert_equal(lsp.filetypes, { "tnix", "nix" }, "lsp_config uses default filetypes")
  assert_equal(lsp.settings, { tnix = { inlayHints = false } }, "lsp_config passes settings through")
  local resolved
  lsp.root_dir(root .. "/src/main.tnix", function(dir)
    resolved = dir
  end)
  assert_equal(resolved, root, "lsp_config root_dir callback resolves workspace markers")

  local server = config.server_config(root .. "/src/main.tnix", { init_options = { a = 1 } })
  assert_equal(server.init_options, { a = 1 }, "server_config forwards init_options")
end)

local result = plugin.setup({})
assert_equal(vim.filetype.match({ filename = "demo.tnix" }), "tnix", "setup registers the .tnix filetype")
assert_equal(vim.filetype.match({ filename = "demo.d.tnix" }), "tnix", "setup registers the .d.tnix filetype")

if vim.fn.has("nvim-0.11") == 1 then
  assert_equal(result.lsp, "native", "setup uses vim.lsp.config on 0.11+")
  assert_equal(vim.lsp.config.tnix.cmd, { "tnix-lsp" }, "setup registers the native tnix config")
  assert_equal(vim.lsp.config.tnix.filetypes, { "tnix", "nix" }, "native config carries filetypes")
else
  assert_equal(result.lsp, "autocmd", "setup falls back to vim.lsp.start before 0.11")
end

local fallback = plugin.setup({ native_lsp = false, filetypes = { "tnix" } })
assert_equal(fallback.lsp, "autocmd", "native_lsp = false forces the autocmd path")
local autocmds = vim.api.nvim_get_autocmds({ group = "tnix-lsp", event = "FileType" })
assert_equal(#autocmds, 1, "autocmd path registers exactly one FileType autocmd")
assert_equal(autocmds[1].pattern, "tnix", "autocmd path honors filetypes")

local treesitter = require("tnix.treesitter")
assert_equal(treesitter.install_info.location, "editors/tree-sitter-tnix", "parser install_info points at the grammar")
assert_equal(treesitter.install_info.files, { "src/parser.c", "src/scanner.c" }, "parser install_info lists the sources")
assert_equal(#vim.api.nvim_get_runtime_file("queries/tnix/highlights.scm", true) > 0, true, "highlight queries ship on the runtimepath")

-- Detach the language server before opening tnix buffers so the spec does not
-- require tnix-lsp on PATH.
if vim.fn.has("nvim-0.11") == 1 then
  vim.lsp.enable("tnix", false)
end
pcall(vim.api.nvim_del_augroup_by_name, "tnix-lsp")

-- ftplugin
vim.cmd("filetype plugin on")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "tnix"
assert_equal(vim.bo[buf].commentstring, "# %s", "ftplugin sets commentstring")
assert_equal(vim.bo[buf].shiftwidth, 2, "ftplugin sets shiftwidth")

-- :checkhealth tnix
if vim.fn.has("nvim-0.10") == 1 then
  vim.cmd("checkhealth tnix")
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert_equal(report:find("Executables", 1, true) ~= nil, true, "checkhealth tnix renders the executables section")
  assert_equal(report:find("Tree-sitter", 1, true) ~= nil, true, "checkhealth tnix renders the tree-sitter section")
  assert_equal(report:find("ERROR: Failed to run healthcheck", 1, true), nil, "checkhealth tnix runs without crashing")
end

print("tnix neovim config_spec: ok")
