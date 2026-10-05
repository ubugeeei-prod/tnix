---`:checkhealth tnix`
local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

local function first_line(text)
  return (vim.split(vim.trim(text or ""), "\n", { plain = true })[1] or "")
end

local function command_version(argv)
  local output = vim.fn.system(argv)
  if vim.v.shell_error ~= 0 then
    return nil, first_line(output)
  end
  return first_line(output)
end

local function check_neovim()
  start("Neovim")
  local version = vim.version()
  local rendered = string.format("%d.%d.%d", version.major, version.minor, version.patch)
  if vim.fn.has("nvim-0.11") == 1 then
    ok("Neovim " .. rendered .. " (native vim.lsp.config / vim.lsp.enable)")
  elseif vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. rendered .. " (using the vim.lsp.start fallback; 0.11+ recommended)")
  else
    warn("Neovim " .. rendered .. " is older than 0.10; tnix is tested on 0.10+", {
      "Upgrade Neovim to 0.11 or newer for the best experience.",
    })
  end
end

local function check_setup()
  start("Plugin setup")
  local tnix = require("tnix")
  if tnix.options == nil then
    warn('require("tnix").setup() has not been called', {
      'Call require("tnix").setup() from your config (lazy.nvim: `opts = {}`).',
    })
  else
    ok("setup() called")
  end

  local filetype = vim.filetype.match({ filename = "example.d.tnix" })
  if filetype == "tnix" then
    ok("`.tnix` / `.d.tnix` files use the `tnix` filetype")
  else
    error("`.d.tnix` is detected as " .. tostring(filetype) .. " instead of `tnix`")
  end
end

local function check_executables()
  start("Executables")
  local opts = require("tnix").options or {}
  local cmd = require("tnix.config").normalize_cmd(opts.cmd)
  local server = cmd[1]

  if vim.fn.executable(server) == 1 then
    local version, err = command_version({ server, "--version" })
    if version then
      ok(string.format("%s: %s (%s)", server, version, vim.fn.exepath(server)))
    else
      warn(string.format("%s is on PATH but `--version` failed: %s", server, err or "unknown error"))
    end
  else
    error(server .. " was not found on PATH", {
      "Install with: curl -fsSL https://tnix.dev/install.sh | sh",
      "Or via Nix: nix profile install github:ubugeeei/tnix#tnix-lsp",
      'Or point `cmd` at the binary: require("tnix").setup({ cmd = { "/path/to/tnix-lsp" } })',
    })
  end

  if vim.fn.executable("tnix") == 1 then
    local version = command_version({ "tnix", "--version" })
    ok("tnix CLI: " .. (version or "available"))
  else
    info("tnix CLI not found on PATH (optional; used for `tnix check` / `tnix doctor`)")
  end
end

local function check_treesitter()
  start("Tree-sitter")
  local treesitter = require("tnix.treesitter")

  if treesitter.parser_available() then
    ok("tnix parser is installed")
  else
    warn("tnix parser is not installed (falling back to no tree-sitter highlighting)", {
      'With nvim-treesitter: call require("tnix").setup() and run :TSInstall tnix',
      'Or build editors/tree-sitter-tnix and pass setup({ treesitter = { parser_path = "/path/to/tnix.so" } })',
    })
  end

  local queries = vim.api.nvim_get_runtime_file("queries/tnix/highlights.scm", true)
  if #queries > 0 then
    ok("highlight queries: " .. queries[1])
  else
    error("queries/tnix/highlights.scm not found on 'runtimepath'", {
      "Make sure editors/neovim from the tnix repository is on 'runtimepath'.",
    })
  end

  if pcall(require, "nvim-treesitter") then
    ok("nvim-treesitter is available")
  else
    info("nvim-treesitter not found (optional; only needed for :TSInstall tnix)")
  end
end

local function check_clients()
  start("Language server")
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  local attached = {}
  for _, client in ipairs(get_clients()) do
    if client.name == "tnix" or client.name == "tnix-lsp" then
      table.insert(attached, string.format("%s (id %d, root %s)", client.name, client.id, client.config.root_dir or "?"))
    end
  end
  if #attached > 0 then
    for _, line in ipairs(attached) do
      ok("running: " .. line)
    end
  else
    info("no tnix-lsp client is running (open a .tnix file to start one)")
  end
end

function M.check()
  check_neovim()
  check_setup()
  check_executables()
  check_treesitter()
  check_clients()
end

return M
